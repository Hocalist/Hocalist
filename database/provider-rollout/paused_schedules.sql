-- Apply only after approved worker-token copies exist in Supabase Vault.
-- Both jobs are created and paused in one transaction; no worker is invoked.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $guard$
DECLARE
  job_id bigint;
  item record;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Run as approved postgres deployment role';
  END IF;
  PERFORM pg_advisory_xact_lock(723801921);
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname IN
    ('hocalist-stripe-test-reconcile', 'hocalist-android-push')) THEN
    RAISE EXCEPTION 'Hocalist jobs already exist; inspect instead of overwriting';
  END IF;
  FOR item IN SELECT * FROM (VALUES
    ('hocalist-stripe-test-reconcile', 'hocalist_stripe_test_worker_secret'),
    ('hocalist-android-push', 'hocalist_push_worker_secret')
  ) AS expected(job_name, secret_name)
  LOOP
    IF (SELECT count(*) FROM vault.decrypted_secrets
        WHERE name = item.secret_name
          AND decrypted_secret ~ '^[a-f0-9]{64}$') <> 1 THEN
      RAISE EXCEPTION 'Missing or invalid approved Vault credential: %', item.secret_name;
    END IF;
  END LOOP;
  job_id := cron.schedule('hocalist-stripe-test-reconcile', '* * * * *', $command$
SELECT net.http_post(
  url := 'https://icqwbzswokoulatomgql.supabase.co/functions/v1/hocalist-stripe-test-reconcile',
  headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
    'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets
      WHERE name = 'hocalist_stripe_test_worker_secret')),
  body := '{}'::jsonb,
  timeout_milliseconds := 10000
);
$command$);
  PERFORM cron.alter_job(job_id, active := false);
  job_id := cron.schedule('hocalist-android-push', '* * * * *', $command$
SELECT net.http_post(
  url := 'https://icqwbzswokoulatomgql.supabase.co/functions/v1/hocalist-push-worker',
  headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
    'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets
      WHERE name = 'hocalist_push_worker_secret')),
  body := '{}'::jsonb,
  timeout_milliseconds := 10000
);
$command$);
  PERFORM cron.alter_job(job_id, active := false);
  IF (SELECT count(*) FROM cron.job WHERE jobname IN
      ('hocalist-stripe-test-reconcile', 'hocalist-android-push')
      AND active = false AND schedule = '* * * * *' AND username = 'postgres') <> 2 THEN
    RAISE EXCEPTION 'Paused scheduler postcondition failed';
  END IF;
END;
$guard$;
COMMIT;
SELECT jobname, schedule, active FROM cron.job
WHERE jobname IN ('hocalist-stripe-test-reconcile', 'hocalist-android-push')
ORDER BY jobname;

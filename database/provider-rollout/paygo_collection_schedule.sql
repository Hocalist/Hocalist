-- Install only after the dedicated approved credential is present in Vault
-- and in the collection endpoint. Installation does not enable collection.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='15s';
DO $guard$
DECLARE job_id bigint;
BEGIN
  PERFORM pg_advisory_xact_lock(723801922);
  IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='hocalist-paygo-test-collect') THEN
    RAISE EXCEPTION 'Collection job already exists; inspect before changing it';
  END IF;
  IF (SELECT count(*) FROM vault.decrypted_secrets
      WHERE name='hocalist_paygo_worker_secret'
      AND decrypted_secret ~ '^[a-f0-9]{64}$')<>1 THEN
    RAISE EXCEPTION 'Dedicated collection credential missing or invalid';
  END IF;
  job_id:=cron.schedule('hocalist-paygo-test-collect','* * * * *',$command$
SELECT net.http_post(
 url:='https://icqwbzswokoulatomgql.supabase.co/functions/v1/hocalist-paygo-collect',
 headers:=jsonb_build_object('Content-Type','application/json','Authorization',
 'Bearer '||(SELECT decrypted_secret FROM vault.decrypted_secrets
 WHERE name='hocalist_paygo_worker_secret')),
 body:='{}'::jsonb,timeout_milliseconds:=10000
)
WHERE (SELECT enabled FROM hocalist.paygo_collection_policy WHERE singleton);
$command$);
  PERFORM cron.alter_job(job_id,active:=false);
  IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=job_id AND NOT active) THEN
    RAISE EXCEPTION 'Collection job was not installed paused';
  END IF;
END;
$guard$;
COMMIT;

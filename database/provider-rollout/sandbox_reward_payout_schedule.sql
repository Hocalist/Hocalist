-- Hocalist's existing Stripe sandbox. An idle queue sends no HTTP request.
BEGIN;
DO $check$
BEGIN
  IF (hocalist.sandbox_payout_execution_guard()->>'ready')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'Sandbox payout guard is not ready';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name='hocalist_commercial_worker_secret') THEN
    RAISE EXCEPTION 'Sandbox payout worker credential is missing';
  END IF;
END $check$;

SELECT cron.schedule('hocalist-sandbox-reward-payout', '* * * * *', $job$
  SELECT net.http_post(
    url := 'https://icqwbzswokoulatomgql.supabase.co/functions/v1/hocalist-commercial-worker',
    headers := jsonb_build_object('Content-Type','application/json','Authorization',
      'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='hocalist_commercial_worker_secret')),
    body := '{}'::jsonb, timeout_milliseconds := 30000
  )
  WHERE EXISTS (
    SELECT 1 FROM hocalist.withdrawal_requests w JOIN hocalist.sandbox_reward_credits c ON c.buyer_id=w.user_id
    WHERE w.provider='stripe_global_sandbox' AND w.status='processing'
  ) AND (hocalist.sandbox_payout_execution_guard()->>'ready')::boolean;
$job$);
COMMIT;

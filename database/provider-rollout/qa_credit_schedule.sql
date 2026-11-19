-- Reuse the credit reconciliation worker and its dedicated Vault credential.
SELECT cron.schedule('hocalist-qa-credit-reconcile','* * * * *',$job$
  SELECT net.http_post(
    url:='https://icqwbzswokoulatomgql.supabase.co/functions/v1/hocalist-stripe-test-reconcile?queue=qa-credits',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization',
      'Bearer '||(SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='hocalist_stripe_test_worker_secret')),
    body:='{}'::jsonb,timeout_milliseconds:=30000
  ) WHERE EXISTS(SELECT 1 FROM hocalist.stripe_test_checkouts WHERE qa_credit AND state='open');
$job$);

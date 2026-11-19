SELECT cron.schedule('hocalist-qa-subscriptions','* * * * *',$job$
  SELECT net.http_post(
    url:='https://icqwbzswokoulatomgql.supabase.co/functions/v1/hocalist-stripe-test-reconcile?queue=qa-subscriptions',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization',
      'Bearer '||(SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='hocalist_stripe_test_worker_secret')),
    body:='{}'::jsonb,timeout_milliseconds:=30000
  ) WHERE EXISTS (
    SELECT 1 FROM hocalist.stripe_test_checkouts c LEFT JOIN hocalist.stripe_test_subscriptions s ON s.verified_checkout_id=c.id
    WHERE c.qa_subscription AND c.session_id IS NOT NULL AND (c.state='open' OR
      (c.state='complete' AND s.provider_status NOT IN ('canceled','incomplete_expired')))
      AND (c.qa_checked_at IS NULL OR c.qa_checked_at < now() -
        CASE WHEN c.state='open' THEN interval '30 seconds' ELSE interval '3 minutes' END)
  );
$job$);

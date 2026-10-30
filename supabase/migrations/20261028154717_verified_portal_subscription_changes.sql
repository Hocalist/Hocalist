-- Portal plan changes retain the original checkout as an ownership anchor.
-- Current pricing is separately verified against the server-owned catalogue.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
ALTER TABLE hocalist.stripe_test_subscriptions
 ADD COLUMN verified_price_id text,
 ADD COLUMN verified_amount_minor integer CHECK(verified_amount_minor>0),
 ADD COLUMN verified_billing_interval text CHECK(verified_billing_interval IN ('month','year'));
UPDATE hocalist.stripe_test_subscriptions s SET
 verified_price_id=c.price_id,verified_amount_minor=c.amount_minor,
 verified_billing_interval=c.billing_interval
 FROM hocalist.stripe_test_checkouts c
 WHERE c.id=s.verified_checkout_id AND c.membership_id=s.membership_id;
DO $repair$
DECLARE d text; old_guard text; new_guard text; marker text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.website_checkout_context(text)')) INTO d;
 IF d IS NULL OR strpos(d,'''membership_id'', c.membership_id,')=0 THEN
  RAISE EXCEPTION 'Website context definition drift'; END IF;
 d:=replace(d,'''membership_id'', c.membership_id,',$context$
 'price_options',(SELECT coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) FROM hocalist.subscription_price_options p),
 'subscription',(SELECT jsonb_build_object('subscription_id',s.subscription_id,
   'provider_status',s.provider_status,'paid_until',s.paid_until,'requires_review',s.requires_review,
   'amount_minor',s.verified_amount_minor) FROM hocalist.stripe_test_subscriptions s WHERE s.membership_id=c.membership_id),
 'membership_id',c.membership_id,
 $context$);
 EXECUTE d;
 SELECT pg_get_functiondef(to_regprocedure('hocalist.stripe_test_finish(uuid,text,text,jsonb,text)')) INTO d;
 old_guard:='AND c.id::text=p_snapshot->>''checkout_id'' AND c.plan_code=p_snapshot->>''plan_code'')';
 new_guard:=$guard$AND c.id::text=p_snapshot->>'checkout_id' AND (
  (c.plan_code=p_snapshot->>'plan_code' AND (NOT(p_snapshot ? 'price_id') OR c.price_id=p_snapshot->>'price_id'))
  OR (EXISTS(SELECT 1 FROM hocalist.stripe_test_subscriptions s WHERE s.membership_id=m
       AND s.subscription_id=p_snapshot->>'subscription_id')
      AND EXISTS(SELECT 1 FROM hocalist.subscription_price_options p WHERE p.enabled
       AND p.code=p_snapshot->>'plan_code' AND p.price_id=p_snapshot->>'price_id'
       AND p.amount_minor=(p_snapshot->>'amount_minor')::integer
       AND p.billing_interval=p_snapshot->>'billing_interval'))))$guard$;
 IF d IS NULL OR strpos(d,old_guard)=0 THEN RAISE EXCEPTION 'Subscription guard definition drift'; END IF;
 d:=replace(d,old_guard,new_guard);
 marker:='UPDATE hocalist.stripe_test_checkouts SET state=''complete'' WHERE membership_id=m AND id=(p_snapshot->>''checkout_id'')::uuid;';
 IF strpos(d,marker)=0 THEN RAISE EXCEPTION 'Subscription completion definition drift'; END IF;
 d:=replace(d,marker,marker||$price$
 UPDATE hocalist.stripe_test_subscriptions SET
   verified_price_id=p_snapshot->>'price_id',
   verified_amount_minor=(p_snapshot->>'amount_minor')::integer,
   verified_billing_interval=p_snapshot->>'billing_interval'
 WHERE membership_id=m AND subscription_id=p_snapshot->>'subscription_id' AND p_snapshot ? 'price_id';
 $price$);
 EXECUTE d;
 SELECT pg_get_functiondef(to_regprocedure('hocalist.website_purchase_status(uuid)')) INTO d;
 marker:='''amount_minor'',c.amount_minor,''currency'',''usd'',''billing_interval'',c.billing_interval';
 IF d IS NULL OR strpos(d,marker)=0 THEN RAISE EXCEPTION 'Subscription presentation definition drift'; END IF;
 EXECUTE replace(d,marker,'''amount_minor'',coalesce(s.verified_amount_minor,c.amount_minor),''currency'',''usd'',''billing_interval'',coalesce(s.verified_billing_interval,c.billing_interval)');
END $repair$;
NOTIFY pgrst,'reload schema';
COMMIT;

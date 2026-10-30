-- Authenticated billing presentation from verified entitlement and checkout
-- records. Older subscriptions are not assigned a guessed billing period.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE hocalist.stripe_test_subscriptions ADD COLUMN verified_checkout_id uuid REFERENCES hocalist.stripe_test_checkouts(id);
DO $verified$
DECLARE d text; marker text:='UPDATE hocalist.stripe_test_checkouts SET state=''complete'' WHERE membership_id=m AND id=(p_snapshot->>''checkout_id'')::uuid;';
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.stripe_test_finish(uuid,text,text,jsonb,text)')) INTO d;
 IF d IS NULL OR strpos(d,marker)=0 THEN RAISE EXCEPTION 'Verified subscription definition drift'; END IF;
 EXECUTE replace(d,marker,marker||' UPDATE hocalist.stripe_test_subscriptions SET verified_checkout_id=(p_snapshot->>''checkout_id'')::uuid WHERE membership_id=m AND subscription_id=p_snapshot->>''subscription_id'';');
 SELECT pg_get_functiondef(to_regprocedure('hocalist.website_purchase_status(uuid)')) INTO d;
 IF d IS NULL OR strpos(d,'''account'', jsonb_build_object(')=0 THEN RAISE EXCEPTION 'Billing presentation definition drift'; END IF;
 d:=replace(d,'''account'', jsonb_build_object(',
 '''entitlement'',hocalist.account_entitlement(),''subscription_price'',(SELECT jsonb_build_object(''amount_minor'',c.amount_minor,''currency'',''usd'',''billing_interval'',c.billing_interval) FROM hocalist.stripe_test_subscriptions s JOIN hocalist.stripe_test_checkouts c ON c.id=s.verified_checkout_id AND c.membership_id=s.membership_id WHERE s.membership_id=m.id AND NOT s.requires_review),''account'', jsonb_build_object(');
 IF to_regclass('hocalist.paygo_plan_rates') IS NOT NULL THEN
   d:=replace(d,'''account'', jsonb_build_object(','''standard_rates'',(SELECT jsonb_agg(to_jsonb(r)) FROM hocalist.paygo_plan_rates r WHERE r.plan_code=hocalist.marketplace_seller_plan(u)),''account'', jsonb_build_object(');
 END IF;
 EXECUTE d;
END $verified$;
NOTIFY pgrst,'reload schema';
COMMIT;

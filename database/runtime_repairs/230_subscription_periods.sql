-- Provider prices remain server configuration, never browser supplied.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE hocalist.subscription_price_options (
 code text NOT NULL REFERENCES hocalist.stripe_test_plans(code),
 billing_interval text NOT NULL CHECK(billing_interval IN ('month','year')),
 price_id text UNIQUE CHECK(price_id ~ '^price_[A-Za-z0-9]+$'),
 amount_minor integer NOT NULL CHECK(amount_minor>0),
 currency text NOT NULL DEFAULT 'usd' CHECK(currency='usd'),
 enabled boolean NOT NULL DEFAULT false,
 PRIMARY KEY(code,billing_interval),CHECK(NOT enabled OR price_id IS NOT NULL)
);
INSERT INTO hocalist.subscription_price_options(code,billing_interval,price_id,amount_minor,currency,enabled)
 SELECT code,'month',price_id,amount_minor,currency,enabled FROM hocalist.stripe_test_plans;
INSERT INTO hocalist.subscription_price_options(code,billing_interval,amount_minor)
 VALUES('pro','year',12000),('elite','year',30000);
CREATE TABLE hocalist.subscription_trials (
 user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id),
 subscription_id text UNIQUE NOT NULL,started_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.subscription_price_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.subscription_trials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.subscription_price_options,hocalist.subscription_trials FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE hocalist.stripe_test_checkouts ADD COLUMN billing_interval text NOT NULL DEFAULT 'month' CHECK(billing_interval IN ('month','year'));
ALTER TABLE hocalist.stripe_test_checkouts ADD COLUMN trial_days integer NOT NULL DEFAULT 0 CHECK(trial_days IN (0,14));

DO $begin$
DECLARE d text;
BEGIN
 SELECT prosrc INTO d FROM pg_proc WHERE oid=to_regprocedure('hocalist.stripe_test_checkout_begin(uuid,text,uuid)');
 IF strpos(d,'SELECT * INTO p FROM hocalist.stripe_test_plans WHERE code=p_plan AND enabled;')=0
 OR strpos(d,'(membership_id,request_key,plan_code,price_id,amount_minor)')=0 THEN RAISE EXCEPTION 'Subscription begin definition drift'; END IF;
 d:=replace(d,'p hocalist.stripe_test_plans%ROWTYPE;','p record; v_trial integer;');
 d:=replace(d,'SELECT * INTO p FROM hocalist.stripe_test_plans WHERE code=p_plan AND enabled;',
 'SELECT * INTO p FROM hocalist.subscription_price_options WHERE code=p_plan AND billing_interval=p_interval AND enabled AND (p_interval=''month'' OR (SELECT annual_enabled FROM hocalist.entitlement_policy WHERE singleton));');
 d:=replace(d,'IF c.plan_code<>p_plan','IF c.billing_interval IS DISTINCT FROM p_interval OR c.plan_code<>p_plan');
 d:=replace(d,'INSERT INTO hocalist.stripe_test_checkouts(membership_id,request_key,plan_code,price_id,amount_minor)',
 'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM hocalist.subscription_trials WHERE user_id=p_user) AND NOT EXISTS(SELECT 1 FROM hocalist.stripe_test_subscriptions WHERE membership_id=m.id) THEN coalesce(trial_days,0) ELSE 0 END INTO v_trial FROM hocalist.entitlement_policy WHERE singleton;
 INSERT INTO hocalist.stripe_test_checkouts(membership_id,request_key,plan_code,price_id,amount_minor,billing_interval,trial_days)');
 d:=replace(d,'VALUES(m.id,p_key,p.code,p.price_id,p.amount_minor)','VALUES(m.id,p_key,p.code,p.price_id,p.amount_minor,p_interval,coalesce(v_trial,0))');
 d:=replace(d,'''price_id'',c.price_id,','''billing_interval'',c.billing_interval,''trial_days'',c.trial_days,''price_id'',c.price_id,');
 EXECUTE 'CREATE FUNCTION hocalist.stripe_test_subscription_begin(p_user uuid,p_plan text,p_key uuid,p_interval text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='''' AS '||quote_literal(d);
END $begin$;
REVOKE ALL ON FUNCTION hocalist.stripe_test_subscription_begin(uuid,text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.stripe_test_subscription_begin(uuid,text,uuid,text) TO service_role;

DO $reads$
DECLARE d text; f text;
BEGIN
 FOREACH f IN ARRAY ARRAY['hocalist.stripe_test_customer_context(text)','hocalist.stripe_test_pending_checkout(uuid)','hocalist.website_checkout_context(text)'] LOOP
  SELECT pg_get_functiondef(to_regprocedure(f)) INTO d;
  IF d IS NULL THEN RAISE EXCEPTION 'Missing billing prerequisite: %',f; END IF;
  IF f='hocalist.stripe_test_customer_context(text)' THEN
   d:=replace(d,'''price_id'',price_id,','''billing_interval'',billing_interval,''trial_days'',trial_days,''price_id'',price_id,');
   -- Only checkouts carry trial days; preserve the separate plan catalogue.
   d:=replace(d,'FROM hocalist.stripe_test_plans)', 'FROM (SELECT p.*,''month''::text AS billing_interval,0 AS trial_days FROM hocalist.stripe_test_plans p) p)');
  ELSIF f='hocalist.website_checkout_context(text)' THEN
   IF strpos(d,'''price_id'', x.price_id,')=0 THEN RAISE EXCEPTION 'Website context definition drift'; END IF;
   d:=replace(d,'''price_id'', x.price_id,','''billing_interval'',x.billing_interval,''trial_days'',x.trial_days,''price_id'', x.price_id,');
  ELSE
   d:=replace(d,'''checkout_id'',c.id,','''billing_interval'',c.billing_interval,''trial_days'',c.trial_days,''checkout_id'',c.id,');
  END IF;
  EXECUTE d;
 END LOOP;
 SELECT pg_get_functiondef(to_regprocedure('hocalist.website_purchase_status(uuid)')) INTO d;
 d:=replace(d,'''plan_code'', c.plan_code,','''billing_interval'',c.billing_interval,''plan_code'', c.plan_code,');
 d:=replace(d,'''code'', code, ''amount_minor'', amount_minor,','''code'', code, ''billing_interval'',billing_interval,''amount_minor'', amount_minor,');
 d:=replace(d,'FROM hocalist.stripe_test_plans)', 'FROM hocalist.subscription_price_options)');
 d:=replace(d,'''account'', jsonb_build_object(','''effective_plan'',hocalist.marketplace_seller_plan(u),''trial_days'',CASE WHEN EXISTS(SELECT 1 FROM hocalist.subscription_trials WHERE user_id=u) OR EXISTS(SELECT 1 FROM hocalist.stripe_test_subscriptions WHERE membership_id=m.id) THEN 0 ELSE coalesce((SELECT trial_days FROM hocalist.entitlement_policy WHERE singleton),0) END,''account'', jsonb_build_object(');
 EXECUTE d;
END $reads$;

-- A verified provider trial is access until its verified end, never a payment.
DO $trial$
DECLARE d text; f text;
BEGIN
 FOREACH f IN ARRAY ARRAY['hocalist.entitlement_readings_internal(uuid)','hocalist.stripe_test_billing_status()'] LOOP
  SELECT pg_get_functiondef(to_regprocedure(f)) INTO d;
  EXECUTE replace(d,'s.provider_status=''active''','s.provider_status IN (''active'',''trialing'')');
 END LOOP;
 SELECT pg_get_functiondef(to_regprocedure('hocalist.stripe_test_finish(uuid,text,text,jsonb,text)')) INTO d;
 IF strpos(d,'INSERT INTO hocalist.stripe_test_subscriptions(')=0 THEN RAISE EXCEPTION 'Subscription finish definition drift'; END IF;
 d:=replace(d,'INSERT INTO hocalist.stripe_test_subscriptions(',$trialclaim$
 IF p_snapshot->>'status'='trialing' THEN
   IF NOT EXISTS(SELECT 1 FROM hocalist.stripe_test_checkouts WHERE id=(p_snapshot->>'checkout_id')::uuid AND trial_days=14) THEN RAISE EXCEPTION 'invalid_trial'; END IF;
   INSERT INTO hocalist.subscription_trials(user_id,subscription_id)
     SELECT user_id,p_snapshot->>'subscription_id' FROM hocalist.memberships WHERE id=m
     ON CONFLICT(user_id) DO NOTHING;
   IF NOT EXISTS(SELECT 1 FROM hocalist.subscription_trials t JOIN hocalist.memberships x ON x.user_id=t.user_id WHERE x.id=m AND t.subscription_id=p_snapshot->>'subscription_id') THEN RAISE EXCEPTION 'trial_already_used'; END IF;
 END IF;
 INSERT INTO hocalist.stripe_test_subscriptions(
 $trialclaim$);
 EXECUTE d;
END $trial$;
NOTIFY pgrst,'reload schema';
COMMIT;

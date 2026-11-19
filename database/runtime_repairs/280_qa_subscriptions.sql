BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE hocalist.subscription_price_options ADD COLUMN IF NOT EXISTS qa_price_id text UNIQUE;
UPDATE hocalist.subscription_price_options p SET qa_price_id=v.price
FROM (VALUES
 ('pro','month',1500,'price_1UZGNeDsZD1mZ3BBQJtc7FTE'),
 ('pro','year',12000,'price_1UZGNqDsZD1mZ3BBfSxmjzeV'),
 ('elite','month',3000,'price_1UZGNuDsZD1mZ3BBMfSsM4IB'),
 ('elite','year',30000,'price_1UZGNyDsZD1mZ3BBwzPdmK3v')
) v(code,period,amount,price)
WHERE p.code=v.code AND p.billing_interval=v.period AND p.amount_minor=v.amount AND p.currency='usd';
ALTER TABLE hocalist.stripe_test_checkouts ADD COLUMN IF NOT EXISTS qa_subscription boolean NOT NULL DEFAULT false;
CREATE OR REPLACE FUNCTION hocalist.qa_subscription_begin(p_user uuid,p_plan text,p_key uuid,p_interval text DEFAULT 'month')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; existing uuid; c hocalist.stripe_test_checkouts%ROWTYPE; price text;
BEGIN
  PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
  SELECT s.id INTO existing FROM hocalist.stripe_test_checkouts s JOIN hocalist.memberships m ON m.id=s.membership_id
    WHERE m.user_id=p_user AND m.role='seller' AND s.request_key=p_key;
  result:=hocalist.stripe_test_subscription_begin(p_user,p_plan,p_key,p_interval);
  SELECT * INTO STRICT c FROM hocalist.stripe_test_checkouts WHERE id=(result->>'checkout_id')::uuid;
  IF existing IS NULL THEN
    SELECT qa_price_id INTO STRICT price FROM hocalist.subscription_price_options WHERE code=p_plan
      AND billing_interval=p_interval AND amount_minor=c.amount_minor AND enabled;
    IF price IS NULL THEN RAISE EXCEPTION 'configuration_unavailable'; END IF;
    UPDATE hocalist.stripe_test_checkouts SET qa_subscription=true,price_id=price,
      qa_customer=(SELECT x.qa_customer FROM hocalist.stripe_test_checkouts x WHERE x.membership_id=c.membership_id
        AND x.qa_subscription AND x.qa_customer IS NOT NULL ORDER BY x.created_at DESC LIMIT 1)
      WHERE id=c.id RETURNING * INTO c;
  END IF;
  IF c.qa_subscription THEN RETURN result||jsonb_build_object('qa_subscription',true,'customer_id',c.qa_customer,'price_id',c.price_id); END IF;
  RETURN result;
END $$;

DO $patch$
DECLARE d text; a text; b text;
BEGIN
  SELECT pg_get_functiondef('hocalist.stripe_test_checkout_bind(uuid,text,text,text)'::regprocedure) INTO d;
  IF strpos(d,'c.qa_subscription')=0 THEN
    a:='INSERT INTO hocalist.stripe_test_customers'; b:='IF p_session IS NOT NULL THEN';
    IF strpos(d,a)=0 OR strpos(d,b)=0 THEN RAISE EXCEPTION 'Subscription binding drift'; END IF;
    EXECUTE replace(replace(d,a,'IF c.qa_subscription THEN
      IF c.qa_customer IS NOT NULL AND c.qa_customer<>p_customer THEN RAISE EXCEPTION ''customer_conflict''; END IF;
      UPDATE hocalist.stripe_test_checkouts SET qa_customer=p_customer WHERE id=c.id;
      ELSE '||a),b,'END IF; '||b);
  END IF;
  SELECT pg_get_functiondef('hocalist.stripe_test_pending_checkout(uuid)'::regprocedure) INTO d;
  IF strpos(d,'c.qa_subscription')=0 THEN
    EXECUTE replace(replace(d,'''qa_credit'',c.qa_credit','''qa_credit'',c.qa_credit,''qa_subscription'',c.qa_subscription'),
      'CASE WHEN c.qa_credit THEN','CASE WHEN c.qa_credit OR c.qa_subscription THEN');
  END IF;
  SELECT pg_get_functiondef('hocalist.stripe_test_checkout_expire(uuid,text,text)'::regprocedure) INTO d;
  IF strpos(d,'c.qa_subscription')=0 THEN EXECUTE replace(d,'CASE WHEN c.qa_credit THEN','CASE WHEN c.qa_credit OR c.qa_subscription THEN'); END IF;
END $patch$;

CREATE OR REPLACE FUNCTION hocalist.qa_subscription_due()
RETURNS SETOF jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  WITH due AS (
    SELECT c.id FROM hocalist.stripe_test_checkouts c LEFT JOIN hocalist.stripe_test_subscriptions s
      ON s.verified_checkout_id=c.id
    WHERE c.qa_subscription AND c.session_id IS NOT NULL AND
      (c.state='open' OR (c.state='complete' AND s.provider_status NOT IN ('canceled','incomplete_expired')))
      AND (c.qa_checked_at IS NULL OR c.qa_checked_at < now() -
        CASE WHEN c.state='open' THEN interval '30 seconds' ELSE interval '3 minutes' END)
    ORDER BY c.qa_checked_at NULLS FIRST,c.created_at LIMIT 8 FOR UPDATE OF c SKIP LOCKED
  ) UPDATE hocalist.stripe_test_checkouts c SET qa_checked_at=clock_timestamp() FROM due WHERE c.id=due.id
  RETURNING jsonb_build_object('checkout',c.id,'membership_id',c.membership_id,'customer_id',c.qa_customer,
    'session_id',c.session_id,'checked_at',c.qa_checked_at,'checkouts',jsonb_build_array(to_jsonb(c)),
    'plans',(SELECT jsonb_agg(jsonb_build_object('code',code)) FROM hocalist.stripe_test_plans),
    'price_options',(SELECT jsonb_agg(to_jsonb(p)||jsonb_build_object('price_id',p.qa_price_id)) FROM hocalist.subscription_price_options p),
    'subscription',(SELECT to_jsonb(s)||jsonb_build_object('amount_minor',s.verified_amount_minor) FROM hocalist.stripe_test_subscriptions s WHERE s.membership_id=c.membership_id))
$$;

-- Share the reviewed snapshot validation, trial consumption and entitlement
-- write from the signed-event worker. Lock and fence each polling generation.
DO $install$
DECLARE body text; section text;
BEGIN
  SELECT prosrc INTO body FROM pg_proc WHERE oid='hocalist.stripe_test_finish(uuid,text,text,jsonb,text)'::regprocedure;
  section:=substring(body FROM 'IF m IS NOT NULL AND p_snapshot IS NOT NULL THEN(.*)UPDATE hocalist.stripe_test_inbox SET status=''processed''');
  IF section IS NULL OR strpos(section,'verified_checkout_id')=0 THEN RAISE EXCEPTION 'Subscription settlement drift'; END IF;
  body:='DECLARE m uuid; BEGIN SELECT membership_id INTO m FROM hocalist.stripe_test_checkouts
    WHERE id=p_checkout AND qa_subscription AND qa_customer=p_customer AND qa_checked_at=p_generation
      AND id::text=p_snapshot->>''checkout_id'' AND state IN (''open'',''complete'') FOR UPDATE;
    IF m IS NOT NULL AND p_snapshot IS NOT NULL THEN '||section||' END;';
  EXECUTE 'CREATE OR REPLACE FUNCTION hocalist.qa_subscription_apply(p_checkout uuid,p_customer text,p_generation timestamptz,p_snapshot jsonb)
    RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='''' AS '||quote_literal(body);
END $install$;
REVOKE ALL ON FUNCTION hocalist.qa_subscription_begin(uuid,text,uuid,text),hocalist.qa_subscription_due(),
  hocalist.qa_subscription_apply(uuid,text,timestamptz,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION hocalist.qa_subscription_begin(uuid,text,uuid,text),hocalist.qa_subscription_due(),
  hocalist.qa_subscription_apply(uuid,text,timestamptz,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
DO $portal$
DECLARE d text; a text:='RETURN jsonb_build_object(';
BEGIN
  SELECT pg_get_functiondef('hocalist.stripe_test_portal_access(uuid)'::regprocedure) INTO d;
  IF strpos(d,'qa_subscription')=0 THEN
    IF strpos(d,a)=0 THEN RAISE EXCEPTION 'Portal definition drift'; END IF;
    EXECUTE replace(d,a,'IF EXISTS(SELECT 1 FROM hocalist.stripe_test_subscriptions s JOIN hocalist.stripe_test_checkouts c
      ON c.id=s.verified_checkout_id WHERE s.membership_id=m.id AND c.qa_subscription) THEN
      RETURN (SELECT jsonb_build_object(''qa_subscription'',true,''membership_id'',m.id,''customer_id'',c.qa_customer,
        ''requires_review'',s.requires_review OR coalesce(v_review,false)) FROM hocalist.stripe_test_subscriptions s
        JOIN hocalist.stripe_test_checkouts c ON c.id=s.verified_checkout_id WHERE s.membership_id=m.id); END IF; '||a);
  END IF;
END $portal$;
COMMIT;

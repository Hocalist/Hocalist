-- DRAFT. Requires reviewed/applied 003 and 005. No live migration permission implied.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE hocalist.stripe_test_plans (
 code text PRIMARY KEY CHECK(code IN ('pro','elite')),
 price_id text UNIQUE NOT NULL,
 amount_minor integer NOT NULL CHECK(amount_minor>0),
 currency text NOT NULL CHECK(currency='usd'),
 enabled boolean NOT NULL DEFAULT false
);
INSERT INTO hocalist.stripe_test_plans VALUES
 ('pro','price_1UHQfsDmHEV44E5Y7mV2Vd0T',1500,'usd',false),
 ('elite','price_1UHQgTDmHEV44E5YnvAxiHlH',3000,'usd',false);
CREATE TABLE hocalist.stripe_test_customers (
 membership_id uuid PRIMARY KEY REFERENCES hocalist.memberships(id),
 customer_id text UNIQUE NOT NULL CHECK(customer_id ~ '^cus_[A-Za-z0-9]+$'),
 requires_review boolean NOT NULL DEFAULT false
);
CREATE TABLE hocalist.stripe_test_checkouts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 membership_id uuid NOT NULL REFERENCES hocalist.memberships(id),
 request_key uuid NOT NULL,
 plan_code text NOT NULL REFERENCES hocalist.stripe_test_plans(code),
 price_id text NOT NULL,
 amount_minor integer NOT NULL,
 state text NOT NULL DEFAULT 'creating' CHECK(state IN ('creating','open','complete','expired')),
 session_id text UNIQUE,
 session_url text,
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT (now()+interval '1 hour'),
 UNIQUE(membership_id,request_key)
);
CREATE UNIQUE INDEX stripe_test_one_checkout ON hocalist.stripe_test_checkouts(membership_id)
 WHERE state IN ('creating','open');
CREATE TABLE hocalist.stripe_test_subscriptions (
 membership_id uuid PRIMARY KEY REFERENCES hocalist.memberships(id),
 subscription_id text UNIQUE NOT NULL,
 plan_code text REFERENCES hocalist.stripe_test_plans(code),
 provider_status text NOT NULL,
 paid_until timestamptz,
 cancel_at_period_end boolean NOT NULL,
 requires_review boolean NOT NULL DEFAULT false,
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE hocalist.stripe_test_worker_lock (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 token uuid, event_id text, expires_at timestamptz
);
INSERT INTO hocalist.stripe_test_worker_lock(singleton) VALUES(true);
ALTER TABLE hocalist.stripe_test_inbox ADD COLUMN attempts integer NOT NULL DEFAULT 0,
 ADD COLUMN available_at timestamptz NOT NULL DEFAULT now(), ADD COLUMN last_error text;
ALTER TABLE hocalist.stripe_test_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.stripe_test_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.stripe_test_checkouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.stripe_test_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.stripe_test_worker_lock ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.stripe_test_plans,hocalist.stripe_test_customers,
 hocalist.stripe_test_checkouts,hocalist.stripe_test_subscriptions,hocalist.stripe_test_worker_lock
 FROM PUBLIC,anon,authenticated,service_role;

-- Trusted server only. p_user must come from Supabase Auth /user, never request JSON.
CREATE FUNCTION hocalist.stripe_test_checkout_begin(p_user uuid,p_plan text,p_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m hocalist.memberships%ROWTYPE; c hocalist.stripe_test_checkouts%ROWTYPE;
 p hocalist.stripe_test_plans%ROWTYPE; customer text;
BEGIN
 PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO m FROM hocalist.memberships WHERE user_id=p_user AND role='seller' FOR UPDATE;
 IF NOT FOUND OR m.status<>'active' OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO p FROM hocalist.stripe_test_plans WHERE code=p_plan AND enabled;
 IF NOT FOUND OR p_key IS NULL THEN RAISE EXCEPTION 'invalid_plan_or_key' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM hocalist.stripe_test_customers WHERE membership_id=m.id AND requires_review) THEN
  RAISE EXCEPTION 'billing_review_required' USING ERRCODE='P0001'; END IF;
 SELECT * INTO c FROM hocalist.stripe_test_checkouts WHERE membership_id=m.id AND request_key=p_key;
 IF FOUND AND c.plan_code<>p_plan THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
 IF FOUND AND c.state IN ('complete','expired') THEN RAISE EXCEPTION 'checkout_closed' USING ERRCODE='P0001'; END IF;
 IF EXISTS(SELECT 1 FROM hocalist.stripe_test_subscriptions WHERE membership_id=m.id AND (provider_status NOT IN ('canceled','incomplete_expired') OR requires_review)) THEN
  RAISE EXCEPTION 'subscription_exists' USING ERRCODE='P0001'; END IF;
 -- Never expire a session solely from our clock: it could have completed before expiry.
 IF c.id IS NULL THEN
  IF EXISTS(SELECT 1 FROM hocalist.stripe_test_checkouts WHERE membership_id=m.id AND state IN ('creating','open')) THEN
   RAISE EXCEPTION 'checkout_pending' USING ERRCODE='P0001'; END IF;
  INSERT INTO hocalist.stripe_test_checkouts(membership_id,request_key,plan_code,price_id,amount_minor)
   VALUES(m.id,p_key,p.code,p.price_id,p.amount_minor) RETURNING * INTO c;
 END IF;
 -- Beyond this window Stripe may no longer accept the original expires_at. Reconcile, never blindly create again.
 IF c.state='creating' AND c.created_at<now()-interval '25 minutes' THEN
  RAISE EXCEPTION 'checkout_reconciliation_required' USING ERRCODE='P0001'; END IF;
 SELECT customer_id INTO customer FROM hocalist.stripe_test_customers WHERE membership_id=m.id;
 RETURN jsonb_build_object('checkout_id',c.id,'membership_id',m.id,'customer_id',customer,
  'price_id',c.price_id,'amount_minor',c.amount_minor,'plan_code',c.plan_code,
  'session_id',c.session_id,'session_url',c.session_url,'expires_at',floor(extract(epoch FROM c.expires_at)), 'state',c.state);
END; $$;

CREATE FUNCTION hocalist.stripe_test_checkout_bind(p_checkout uuid,p_customer text,p_session text DEFAULT NULL,p_url text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c hocalist.stripe_test_checkouts%ROWTYPE; current_customer text;
BEGIN
 SELECT * INTO STRICT c FROM hocalist.stripe_test_checkouts WHERE id=p_checkout FOR UPDATE;
 IF c.state NOT IN ('creating','open') THEN RAISE EXCEPTION 'checkout_closed'; END IF;
 IF p_customer IS NULL OR p_customer !~ '^cus_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'invalid_customer'; END IF;
 INSERT INTO hocalist.stripe_test_customers(membership_id,customer_id) VALUES(c.membership_id,p_customer) ON CONFLICT(membership_id) DO NOTHING;
 SELECT customer_id INTO current_customer FROM hocalist.stripe_test_customers WHERE membership_id=c.membership_id;
 IF current_customer<>p_customer THEN RAISE EXCEPTION 'customer_conflict'; END IF;
 IF p_session IS NOT NULL THEN
  IF p_session !~ '^cs_test_[A-Za-z0-9]+$' OR p_url IS NULL OR p_url !~ '^https://checkout[.]stripe[.]com/' THEN RAISE EXCEPTION 'invalid_session'; END IF;
  IF c.session_id IS NOT NULL AND c.session_id<>p_session THEN RAISE EXCEPTION 'session_conflict'; END IF;
  UPDATE hocalist.stripe_test_checkouts SET session_id=p_session,session_url=p_url,
   state=CASE WHEN state='creating' THEN 'open' ELSE state END WHERE id=c.id;
 END IF;
END; $$;

-- Caller must have retrieved this exact session and verified Stripe reports expired.
CREATE FUNCTION hocalist.stripe_test_checkout_expire(p_checkout uuid,p_session text,p_customer text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 UPDATE hocalist.stripe_test_checkouts c SET state='expired'
 WHERE c.id=p_checkout AND c.session_id=p_session AND c.state='open'
 AND EXISTS(SELECT 1 FROM hocalist.stripe_test_customers x WHERE x.membership_id=c.membership_id AND x.customer_id=p_customer);
 IF NOT FOUND THEN RAISE EXCEPTION 'checkout_reconciliation_required'; END IF;
END; $$;

-- One global worker lease deliberately serializes reconciliation across this small test environment.
-- Fence is checked again on commit; a stale worker can never overwrite a newer refresh.
CREATE FUNCTION hocalist.stripe_test_claim()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE l hocalist.stripe_test_worker_lock%ROWTYPE; e hocalist.stripe_test_inbox%ROWTYPE; t uuid:=gen_random_uuid();
BEGIN
 SELECT * INTO l FROM hocalist.stripe_test_worker_lock WHERE singleton FOR UPDATE;
 IF l.expires_at>clock_timestamp() THEN RETURN NULL; END IF;
 UPDATE hocalist.stripe_test_inbox SET status='quarantined',last_error='attempt_limit'
 WHERE status='pending' AND attempts>=10;
 SELECT * INTO e FROM hocalist.stripe_test_inbox WHERE status='pending' AND available_at<=now()
 ORDER BY received_at,event_id LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 UPDATE hocalist.stripe_test_worker_lock SET token=t,event_id=e.event_id,expires_at=clock_timestamp()+interval '2 minutes' WHERE singleton;
 UPDATE hocalist.stripe_test_inbox SET attempts=attempts+1 WHERE account_id=e.account_id AND event_id=e.event_id;
 RETURN jsonb_build_object('token',t,'event_id',e.event_id,'event_type',e.event_type,'object_id',e.object_id);
END; $$;

CREATE FUNCTION hocalist.stripe_test_customer_context(p_customer text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('membership_id',c.membership_id,'plans',
  (SELECT jsonb_agg(jsonb_build_object('code',code,'price_id',price_id,'amount_minor',amount_minor)) FROM hocalist.stripe_test_plans),
  'checkouts',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'session_id',session_id,'plan_code',plan_code,'price_id',price_id,'amount_minor',amount_minor)), '[]'::jsonb)
    FROM hocalist.stripe_test_checkouts WHERE membership_id=c.membership_id))
 FROM hocalist.stripe_test_customers c WHERE c.customer_id=p_customer;
$$;

CREATE FUNCTION hocalist.stripe_test_finish(p_token uuid,p_event text,p_customer text,p_snapshot jsonb,p_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE l hocalist.stripe_test_worker_lock%ROWTYPE; e hocalist.stripe_test_inbox%ROWTYPE; m uuid;
BEGIN
 SELECT * INTO l FROM hocalist.stripe_test_worker_lock WHERE singleton FOR UPDATE;
 IF p_token IS NULL OR l.token IS DISTINCT FROM p_token OR l.event_id IS DISTINCT FROM p_event
  OR l.expires_at IS NULL OR l.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'worker_lease_lost'; END IF;
 SELECT * INTO STRICT e FROM hocalist.stripe_test_inbox WHERE account_id='acct_1Le6hqDmHEV44E5Y' AND event_id=p_event FOR UPDATE;
 IF p_error IS NOT NULL THEN
  -- Fail closed for an owned customer even when an ambiguous provider snapshot cannot be applied.
  IF p_error='review_required' THEN
   UPDATE hocalist.stripe_test_customers SET requires_review=true WHERE customer_id=p_customer;
   UPDATE hocalist.stripe_test_subscriptions SET requires_review=true,updated_at=now()
   WHERE membership_id=(SELECT membership_id FROM hocalist.stripe_test_customers WHERE customer_id=p_customer);
  END IF;
  UPDATE hocalist.stripe_test_inbox SET status=CASE WHEN attempts>=10 OR p_error='review_required' THEN 'quarantined' ELSE 'pending' END,
   available_at=now()+make_interval(secs=>least(3600,30*power(2,least(attempts,7)))::integer),
   last_error=CASE WHEN p_error='review_required' THEN p_error ELSE 'provider_or_storage_unavailable' END
   WHERE account_id=e.account_id AND event_id=e.event_id;
 ELSE
  SELECT membership_id INTO m FROM hocalist.stripe_test_customers WHERE customer_id=p_customer;
  IF m IS NOT NULL AND p_snapshot IS NOT NULL THEN
   IF jsonb_typeof(p_snapshot) IS DISTINCT FROM 'object' OR coalesce(p_snapshot->>'subscription_id','') !~ '^sub_[A-Za-z0-9]+$'
    OR coalesce(p_snapshot->>'status','') NOT IN ('active','trialing','past_due','canceled','incomplete','incomplete_expired','unpaid','paused')
    OR jsonb_typeof(p_snapshot->'cancel_at_period_end') IS DISTINCT FROM 'boolean'
    OR jsonb_typeof(p_snapshot->'requires_review') IS DISTINCT FROM 'boolean'
    OR NOT EXISTS(SELECT 1 FROM hocalist.stripe_test_checkouts c WHERE c.membership_id=m
      AND c.id::text=p_snapshot->>'checkout_id' AND c.plan_code=p_snapshot->>'plan_code')
    THEN RAISE EXCEPTION 'invalid_subscription_snapshot'; END IF;
   INSERT INTO hocalist.stripe_test_subscriptions(membership_id,subscription_id,plan_code,provider_status,paid_until,cancel_at_period_end,requires_review)
   VALUES(m,p_snapshot->>'subscription_id',p_snapshot->>'plan_code',p_snapshot->>'status',
    (p_snapshot->>'paid_until')::timestamptz,(p_snapshot->>'cancel_at_period_end')::boolean,(p_snapshot->>'requires_review')::boolean)
   ON CONFLICT(membership_id) DO UPDATE SET subscription_id=excluded.subscription_id,plan_code=excluded.plan_code,
    provider_status=excluded.provider_status,paid_until=excluded.paid_until,cancel_at_period_end=excluded.cancel_at_period_end,
    requires_review=excluded.requires_review OR hocalist.stripe_test_subscriptions.requires_review,updated_at=now();
   UPDATE hocalist.stripe_test_checkouts SET state='complete' WHERE membership_id=m AND id=(p_snapshot->>'checkout_id')::uuid;
  END IF;
  UPDATE hocalist.stripe_test_inbox SET status='processed',last_error=NULL WHERE account_id=e.account_id AND event_id=e.event_id;
 END IF;
 UPDATE hocalist.stripe_test_worker_lock SET token=NULL,event_id=NULL,expires_at=NULL WHERE singleton;
END; $$;

CREATE FUNCTION hocalist.stripe_test_billing_status()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('membership_id',m.id,'plan',CASE WHEN m.status='active'
  AND NOT EXISTS(SELECT 1 FROM hocalist.memberships other WHERE other.user_id=m.user_id AND other.status IN ('restricted','disabled'))
  AND NOT EXISTS(SELECT 1 FROM hocalist.stripe_test_customers c WHERE c.membership_id=m.id AND c.requires_review)
  AND s.provider_status='active' AND s.plan_code IS NOT NULL AND s.paid_until>now() AND NOT s.requires_review THEN s.plan_code ELSE 'free' END,
  'provider_status',s.provider_status,'paid_until',s.paid_until,'cancel_at_period_end',s.cancel_at_period_end,
  'requires_review',coalesce(s.requires_review,false) OR EXISTS(SELECT 1 FROM hocalist.stripe_test_customers c WHERE c.membership_id=m.id AND c.requires_review),'updated_at',s.updated_at)
 FROM hocalist.memberships m LEFT JOIN hocalist.stripe_test_subscriptions s ON s.membership_id=m.id
 WHERE m.user_id=(SELECT auth.uid()) AND m.role='seller';
$$;
REVOKE ALL ON FUNCTION hocalist.stripe_test_checkout_begin(uuid,text,uuid),
 hocalist.stripe_test_checkout_bind(uuid,text,text,text),hocalist.stripe_test_claim(),
 hocalist.stripe_test_checkout_expire(uuid,text,text),
 hocalist.stripe_test_customer_context(text),hocalist.stripe_test_finish(uuid,text,text,jsonb,text),
 hocalist.stripe_test_billing_status() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.stripe_test_checkout_begin(uuid,text,uuid),
 hocalist.stripe_test_checkout_bind(uuid,text,text,text),hocalist.stripe_test_claim(),
 hocalist.stripe_test_checkout_expire(uuid,text,text),
 hocalist.stripe_test_customer_context(text),hocalist.stripe_test_finish(uuid,text,text,jsonb,text) TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.stripe_test_billing_status() TO authenticated;
COMMIT;

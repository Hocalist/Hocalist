-- TEST pay-as-you-go card authorisation. No charge is created here.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE hocalist.paygo_payment_setups (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 membership_id uuid NOT NULL REFERENCES hocalist.memberships(id),
 request_key uuid NOT NULL,
 customer_id text NOT NULL CHECK(customer_id ~ '^cus_[A-Za-z0-9]+$'),
 session_id text UNIQUE CHECK(session_id ~ '^cs_test_[A-Za-z0-9]+$'),
 session_url text,
 state text NOT NULL DEFAULT 'creating' CHECK(state IN ('creating','open','complete','expired')),
 consent_version text NOT NULL CHECK(consent_version='paygo-v1'),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(user_id,request_key)
);
CREATE UNIQUE INDEX paygo_one_pending_setup ON hocalist.paygo_payment_setups(user_id) WHERE state IN ('creating','open');
CREATE TABLE hocalist.paygo_payment_methods (
 user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id),
 setup_id uuid NOT NULL UNIQUE REFERENCES hocalist.paygo_payment_setups(id),
 customer_id text NOT NULL,
 payment_method_id text NOT NULL CHECK(payment_method_id ~ '^pm_[A-Za-z0-9]+$'),
 consent_version text NOT NULL CHECK(consent_version='paygo-v1'),
 authorised_at timestamptz NOT NULL DEFAULT now(),
 revoked_at timestamptz
);
ALTER TABLE hocalist.paygo_payment_setups ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.paygo_payment_methods ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.paygo_payment_setups,hocalist.paygo_payment_methods FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION hocalist.paygo_setup_begin(p_user uuid,p_key uuid,p_consent text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m hocalist.memberships%ROWTYPE; s hocalist.paygo_payment_setups%ROWTYPE; customer text;
BEGIN
 PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
 SELECT * INTO m FROM hocalist.memberships WHERE user_id=p_user AND role='seller' AND status='active';
 IF NOT FOUND OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status IN ('restricted','disabled')) THEN RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
 IF p_key IS NULL OR p_consent IS DISTINCT FROM 'paygo-v1' THEN RAISE EXCEPTION 'consent_required' USING ERRCODE='22023'; END IF;
 SELECT customer_id INTO customer FROM hocalist.stripe_test_customers WHERE membership_id=m.id AND NOT requires_review;
 IF customer IS NULL THEN RAISE EXCEPTION 'billing_customer_required'; END IF;
 SELECT * INTO s FROM hocalist.paygo_payment_setups WHERE user_id=p_user AND request_key=p_key FOR UPDATE;
 IF NOT FOUND THEN
   -- A page reload may lose its browser retry key. Resume this seller's one
   -- pending setup rather than permanently blocking setup or making duplicates.
   SELECT * INTO s FROM hocalist.paygo_payment_setups WHERE user_id=p_user AND state IN ('creating','open') FOR UPDATE;
   IF NOT FOUND THEN
     INSERT INTO hocalist.paygo_payment_setups(user_id,membership_id,request_key,customer_id,consent_version)
     VALUES(p_user,m.id,p_key,customer,p_consent) RETURNING * INTO s;
   END IF;
 END IF;
 IF s.state IN ('complete','expired') THEN RAISE EXCEPTION 'setup_closed'; END IF;
 IF s.customer_id<>customer THEN RAISE EXCEPTION 'customer_conflict'; END IF;
 RETURN jsonb_build_object('setup_id',s.id,'customer_id',s.customer_id,'membership_id',s.membership_id,'session_id',s.session_id,'session_url',s.session_url,'created_at',s.created_at);
END $$;
CREATE FUNCTION hocalist.paygo_customer(p_user uuid,p_customer text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m uuid; c text;
BEGIN
 PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
 SELECT id INTO m FROM hocalist.memberships WHERE user_id=p_user AND role='seller' AND status='active';
 IF m IS NULL OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status IN ('restricted','disabled')) THEN RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM hocalist.stripe_test_customers WHERE membership_id=m AND requires_review) THEN RAISE EXCEPTION 'billing_review_required'; END IF;
 IF p_customer IS NOT NULL THEN
  IF p_customer !~ '^cus_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'invalid_customer'; END IF;
  INSERT INTO hocalist.stripe_test_customers(membership_id,customer_id) VALUES(m,p_customer) ON CONFLICT(membership_id) DO NOTHING;
 END IF;
 SELECT customer_id INTO c FROM hocalist.stripe_test_customers WHERE membership_id=m;
 IF p_customer IS NOT NULL AND c IS DISTINCT FROM p_customer THEN RAISE EXCEPTION 'customer_conflict'; END IF;
 RETURN jsonb_build_object('membership_id',m,'customer_id',c);
END $$;
CREATE FUNCTION hocalist.paygo_setup_bind(p_setup uuid,p_customer text,p_session text,p_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s hocalist.paygo_payment_setups%ROWTYPE;
BEGIN
 SELECT * INTO s FROM hocalist.paygo_payment_setups WHERE id=p_setup FOR UPDATE;
 IF NOT FOUND OR s.customer_id IS DISTINCT FROM p_customer OR s.state NOT IN ('creating','open')
 OR p_session IS NULL OR p_session !~ '^cs_test_[A-Za-z0-9]+$' OR p_url IS NULL OR p_url !~ '^https://checkout[.]stripe[.]com/' THEN RAISE EXCEPTION 'invalid_setup_binding'; END IF;
 IF s.session_id IS NOT NULL AND s.session_id<>p_session THEN RAISE EXCEPTION 'session_conflict'; END IF;
 UPDATE hocalist.paygo_payment_setups SET session_id=p_session,session_url=p_url,state='open' WHERE id=s.id;
END $$;
CREATE FUNCTION hocalist.paygo_setup_context(p_user uuid,p_setup uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT to_jsonb(s) FROM hocalist.paygo_payment_setups s WHERE s.id=p_setup AND s.user_id=p_user
 AND EXISTS(SELECT 1 FROM hocalist.memberships m WHERE m.id=s.membership_id AND m.user_id=p_user AND m.status='active')
 AND NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status IN ('restricted','disabled'))
$$;
CREATE FUNCTION hocalist.paygo_setup_finish(p_setup uuid,p_customer text,p_session text,p_method text,p_expired boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s hocalist.paygo_payment_setups%ROWTYPE;
BEGIN
 PERFORM 1 FROM hocalist.profiles WHERE id=(SELECT user_id FROM hocalist.paygo_payment_setups WHERE id=p_setup) FOR UPDATE;
 SELECT * INTO s FROM hocalist.paygo_payment_setups WHERE id=p_setup FOR UPDATE;
 IF NOT FOUND OR s.customer_id IS DISTINCT FROM p_customer OR s.session_id IS DISTINCT FROM p_session THEN RAISE EXCEPTION 'setup_identity_mismatch'; END IF;
 IF p_expired THEN
   IF s.state='complete' THEN RAISE EXCEPTION 'setup_closed'; END IF;
   UPDATE hocalist.paygo_payment_setups SET state='expired' WHERE id=s.id; RETURN;
 END IF;
 IF s.state NOT IN ('open','complete') OR p_method IS NULL OR p_method !~ '^pm_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
 IF s.state='complete' THEN
   IF NOT EXISTS(SELECT 1 FROM hocalist.paygo_payment_methods WHERE setup_id=s.id AND payment_method_id=p_method) THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
   RETURN;
 END IF;
 INSERT INTO hocalist.paygo_payment_methods(user_id,setup_id,customer_id,payment_method_id,consent_version)
 VALUES(s.user_id,s.id,s.customer_id,p_method,s.consent_version)
 ON CONFLICT(user_id) DO UPDATE SET setup_id=excluded.setup_id,customer_id=excluded.customer_id,payment_method_id=excluded.payment_method_id,consent_version=excluded.consent_version,authorised_at=now(),revoked_at=NULL;
 UPDATE hocalist.paygo_payment_setups SET state='complete' WHERE id=s.id;
END $$;
CREATE FUNCTION hocalist.paygo_payment_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.marketplace_assert_role(auth.uid(),'seller');
 RETURN jsonb_build_object('authorised',EXISTS(SELECT 1 FROM hocalist.paygo_payment_methods WHERE user_id=auth.uid() AND revoked_at IS NULL),'consent_version','paygo-v1');
END $$;
CREATE FUNCTION hocalist.paygo_payment_revoke()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 -- Revoking one's own permission must remain possible after restriction.
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM hocalist.profiles WHERE id=auth.uid() FOR UPDATE;
 UPDATE hocalist.paygo_payment_methods SET revoked_at=coalesce(revoked_at,now()) WHERE user_id=auth.uid();
 UPDATE hocalist.paygo_payment_setups SET state='expired' WHERE user_id=auth.uid() AND state IN ('creating','open');
END $$;
REVOKE ALL ON FUNCTION hocalist.paygo_setup_begin(uuid,uuid,text),hocalist.paygo_setup_bind(uuid,text,text,text),hocalist.paygo_setup_context(uuid,uuid),hocalist.paygo_setup_finish(uuid,text,text,text,boolean),hocalist.paygo_payment_status(),hocalist.paygo_payment_revoke() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.paygo_setup_begin(uuid,uuid,text),hocalist.paygo_setup_bind(uuid,text,text,text),hocalist.paygo_setup_context(uuid,uuid),hocalist.paygo_setup_finish(uuid,text,text,text,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.paygo_payment_status(),hocalist.paygo_payment_revoke() TO authenticated;
REVOKE ALL ON FUNCTION hocalist.paygo_customer(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.paygo_customer(uuid,text) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

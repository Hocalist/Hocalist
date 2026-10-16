-- Provider-neutral buyer withdrawal workflow over the reviewed reward ledger.
--
-- September 26 approved terms: $20 earned-balance minimum, $2.50 deduction,
-- explicit net amount, verified email and phone, reserve while processing and
-- restore only after a confirmed failure with reconciliation that prevents a
-- double payout or refund. No provider call, credential or simulated success
-- is performed here; provider execution stays coordinator-owned.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.buyer_rewards') IS NULL THEN
    RAISE EXCEPTION 'buyer rewards 091 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.withdrawal_requests') IS NOT NULL THEN
    RAISE EXCEPTION 'withdrawals already installed';
  END IF;
END; $guard$;

-- Settled withdrawal terms are admin-managed so a later approved change does
-- not need a new migration, but the defaults are the agreed values.
CREATE TABLE hocalist.withdrawal_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  minimum_minor bigint NOT NULL CHECK (minimum_minor > 0),
  fee_minor bigint NOT NULL CHECK (fee_minor >= 0),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.withdrawal_policy(singleton,minimum_minor,fee_minor)
  VALUES (true,2000,250);

CREATE TABLE hocalist.withdrawal_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  client_key text NOT NULL CHECK (length(btrim(client_key)) BETWEEN 1 AND 128),
  amount_minor bigint NOT NULL,
  fee_minor bigint NOT NULL,
  net_minor bigint NOT NULL,
  status text NOT NULL DEFAULT 'processing'
    CHECK (status IN ('processing','failed','paid')),
  provider text CHECK (provider IS NULL OR length(btrim(provider)) BETWEEN 1 AND 60),
  provider_reference text CHECK (provider_reference IS NULL OR length(btrim(provider_reference)) BETWEEN 1 AND 200),
  failure_reason text CHECK (failure_reason IS NULL OR length(btrim(failure_reason)) BETWEEN 1 AND 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT withdrawal_net_matches CHECK (net_minor = amount_minor - fee_minor AND net_minor > 0),
  CONSTRAINT withdrawal_paid_reference CHECK (status <> 'paid' OR provider_reference IS NOT NULL),
  UNIQUE (user_id, client_key)
);
CREATE INDEX withdrawal_owner_order ON hocalist.withdrawal_requests(user_id, created_at DESC, id DESC);

-- Append-only state history. A late provider success after a recorded failure
-- stays visible for manual reconciliation instead of being silently applied.
CREATE TABLE hocalist.withdrawal_events (
  withdrawal_id uuid NOT NULL REFERENCES hocalist.withdrawal_requests(id) ON DELETE CASCADE,
  revision bigint NOT NULL CHECK (revision > 0),
  event text NOT NULL CHECK (event IN ('requested','paid','failed','reconciliation')),
  actor text NOT NULL CHECK (length(btrim(actor)) BETWEEN 1 AND 60),
  detail text CHECK (detail IS NULL OR length(detail) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (withdrawal_id, revision)
);

ALTER TABLE hocalist.withdrawal_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.withdrawal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.withdrawal_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.withdrawal_policy, hocalist.withdrawal_requests,
  hocalist.withdrawal_events FROM PUBLIC, anon, authenticated, service_role;

-- Email/phone verification is read from Auth, never from editable profile
-- text. "No Auth column" means not verified in this environment.
CREATE FUNCTION hocalist.contact_verified(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_email boolean := false;
  v_phone boolean := false;
BEGIN
  IF p_user IS NULL THEN RAISE EXCEPTION 'invalid_user' USING ERRCODE='22023'; END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='auth' AND table_name='users' AND column_name='email_confirmed_at') THEN
    EXECUTE 'SELECT email_confirmed_at IS NOT NULL FROM auth.users WHERE id=$1'
      INTO v_email USING p_user;
    v_email := coalesce(v_email,false);
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='auth' AND table_name='users' AND column_name='phone_confirmed_at') THEN
    EXECUTE 'SELECT phone_confirmed_at IS NOT NULL FROM auth.users WHERE id=$1'
      INTO v_phone USING p_user;
    v_phone := coalesce(v_phone,false);
  END IF;
  RETURN jsonb_build_object('email_verified',v_email,'phone_verified',v_phone);
END $$;

CREATE FUNCTION hocalist.withdrawal_available_minor(p_user uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT greatest(0,
    coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r
      JOIN hocalist.credit_targets t ON t.id=r.target_id
      WHERE r.buyer_user_id=p_user AND t.status='won'),0)
    - coalesce((SELECT sum(w.amount_minor) FROM hocalist.withdrawal_requests w
      WHERE w.user_id=p_user AND w.status='processing'),0));
$$;

-- Provider-neutral settlement, callable only by the reviewed service path.
-- Idempotent per outcome; a failure can never later become paid through this
-- function, and a replayed success never applies twice.
CREATE FUNCTION hocalist.withdrawal_settle_internal(
  p_withdrawal uuid, p_result text, p_provider text DEFAULT NULL,
  p_reference text DEFAULT NULL, p_reason text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE w hocalist.withdrawal_requests%ROWTYPE; n bigint;
BEGIN
  IF p_result IS NULL OR p_result NOT IN ('paid','failed') THEN
    RAISE EXCEPTION 'invalid_result' USING ERRCODE='22023';
  END IF;
  SELECT * INTO STRICT w FROM hocalist.withdrawal_requests WHERE id=p_withdrawal FOR UPDATE;
  SELECT coalesce(max(revision),0)+1 INTO n
    FROM hocalist.withdrawal_events WHERE withdrawal_id=p_withdrawal;
  IF w.status='paid' THEN
    IF p_result='paid' THEN
      RETURN jsonb_build_object('status','paid','withdrawal_id',w.id);
    END IF;
    RAISE EXCEPTION 'late_failure_after_payout' USING ERRCODE='P0001';
  END IF;
  IF w.status='failed' THEN
    IF p_result='failed' THEN
      RETURN jsonb_build_object('status','failed','withdrawal_id',w.id);
    END IF;
    -- The provider reported success after a recorded failure. Never apply a
    -- second payout silently; record it for manual reconciliation.
    INSERT INTO hocalist.withdrawal_events(withdrawal_id,revision,event,actor,detail)
    VALUES(w.id,n,'reconciliation','provider',
      left(coalesce(p_reason,'late success after failure'),500));
    UPDATE hocalist.withdrawal_requests
      SET provider=coalesce(p_provider,provider),provider_reference=coalesce(p_reference,provider_reference),
          updated_at=now()
      WHERE id=w.id;
    RETURN jsonb_build_object('status','reconciliation_required','withdrawal_id',w.id);
  END IF;
  IF p_result='failed' THEN
    UPDATE hocalist.withdrawal_requests
      SET status='failed',failure_reason=left(coalesce(p_reason,'provider failure'),500),
          provider=coalesce(p_provider,provider),updated_at=now()
      WHERE id=w.id;
    INSERT INTO hocalist.withdrawal_events(withdrawal_id,revision,event,actor,detail)
    VALUES(w.id,n,'failed','provider',left(coalesce(p_reason,'provider failure'),500));
  ELSE
    IF p_provider IS NULL OR length(btrim(p_provider)) NOT BETWEEN 1 AND 60
       OR p_reference IS NULL OR length(btrim(p_reference)) NOT BETWEEN 1 AND 200 THEN
      RAISE EXCEPTION 'invalid_provider_reference' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.withdrawal_requests
      SET status='paid',provider=p_provider,provider_reference=p_reference,failure_reason=NULL,updated_at=now()
      WHERE id=w.id;
    INSERT INTO hocalist.withdrawal_events(withdrawal_id,revision,event,actor,detail)
    VALUES(w.id,n,'paid','provider',left(p_reference,500));
  END IF;
  RETURN jsonb_build_object('status',p_result,'withdrawal_id',w.id);
END $$;

CREATE FUNCTION hocalist.withdrawal_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); p hocalist.withdrawal_policy%ROWTYPE; c jsonb;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='buyer' AND status='active')
   OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'withdrawal_access_denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO p FROM hocalist.withdrawal_policy WHERE singleton;
  c := hocalist.contact_verified(u);
  RETURN jsonb_build_object(
    'currency','USD',
    'minimum_minor',p.minimum_minor,'fee_minor',p.fee_minor,
    'earned_minor',coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r
      JOIN hocalist.credit_targets t ON t.id=r.target_id
      WHERE r.buyer_user_id=u AND t.status='won'),0),
    'processing_minor',coalesce((SELECT sum(w.amount_minor) FROM hocalist.withdrawal_requests w
      WHERE w.user_id=u AND w.status='processing'),0),
    'available_minor',hocalist.withdrawal_available_minor(u),
    'email_verified',(c->>'email_verified')::boolean,
    'phone_verified',(c->>'phone_verified')::boolean,
    'provider_neutral',true,
    'requests',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',w.id,'amount_minor',w.amount_minor,'fee_minor',w.fee_minor,'net_minor',w.net_minor,
      'status',w.status,'failure_reason',w.failure_reason,'created_at',w.created_at,'updated_at',w.updated_at)
      ORDER BY w.created_at DESC,w.id DESC) FROM hocalist.withdrawal_requests w WHERE w.user_id=u),'[]'::jsonb));
END $$;

CREATE FUNCTION hocalist.withdrawal_request(p_key text, p_amount_minor bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid:=auth.uid(); p hocalist.withdrawal_policy%ROWTYPE; c jsonb;
  h text; w hocalist.withdrawal_requests%ROWTYPE;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='buyer' AND status='active')
   OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'withdrawal_access_denied' USING ERRCODE='42501'; END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_amount_minor IS NULL OR p_amount_minor <= 0 THEN
    RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':withdrawal:'||p_key,0));
  SELECT * INTO w FROM hocalist.withdrawal_requests WHERE user_id=u AND client_key=p_key;
  IF FOUND THEN
    RETURN jsonb_build_object('status','processing','withdrawal_id',w.id,
      'amount_minor',w.amount_minor,'fee_minor',w.fee_minor,'net_minor',w.net_minor);
  END IF;
  SELECT * INTO p FROM hocalist.withdrawal_policy WHERE singleton;
  c := hocalist.contact_verified(u);
  IF NOT (c->>'email_verified')::boolean OR NOT (c->>'phone_verified')::boolean THEN
    RAISE EXCEPTION 'contact_verification_required' USING ERRCODE='P0001'; END IF;
  IF p_amount_minor < p.minimum_minor THEN
    RAISE EXCEPTION 'below_minimum' USING ERRCODE='P0001'; END IF;
  IF p_amount_minor > hocalist.withdrawal_available_minor(u) THEN
    RAISE EXCEPTION 'insufficient_earned_balance' USING ERRCODE='P0001'; END IF;
  INSERT INTO hocalist.withdrawal_requests(user_id,client_key,amount_minor,fee_minor,net_minor)
  VALUES(u,btrim(p_key),p_amount_minor,p.fee_minor,p_amount_minor-p.fee_minor)
  RETURNING * INTO w;
  INSERT INTO hocalist.withdrawal_events(withdrawal_id,revision,event,actor,detail)
  VALUES(w.id,1,'requested','user','net '||w.net_minor::text);
  RETURN jsonb_build_object('status','processing','withdrawal_id',w.id,
    'amount_minor',w.amount_minor,'fee_minor',w.fee_minor,'net_minor',w.net_minor);
END $$;

-- Admin read-only queue; settlement stays with the provider-owned service path.
CREATE FUNCTION hocalist.admin_withdrawal_queue(p_limit integer DEFAULT 50, p_cursor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); rows jsonb; next_id uuid;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023'; END IF;
  WITH found AS (
    SELECT w.*,coalesce(rp.display_name,'Hocalist member') AS display_name
    FROM hocalist.withdrawal_requests w
    LEFT JOIN hocalist.memberships m ON m.user_id=w.user_id AND m.role='buyer'
    LEFT JOIN hocalist.role_profiles rp ON rp.membership_id=m.id
    WHERE p_cursor IS NULL OR w.id>p_cursor ORDER BY w.id LIMIT p_limit+1),
  page AS(SELECT * FROM found ORDER BY id LIMIT p_limit)
  SELECT coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'user_id',user_id,'display_name',display_name,
    'amount_minor',amount_minor,'fee_minor',fee_minor,'net_minor',net_minor,'status',status,
    'provider',provider,'provider_reference',provider_reference,'failure_reason',failure_reason,
    'created_at',created_at,'updated_at',updated_at) ORDER BY id) FROM page),'[]'::jsonb),
   CASE WHEN (SELECT count(*) FROM found)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
   INTO rows,next_id;
  RETURN jsonb_build_object('items',rows,'next_cursor',next_id,
    'processing_minor',coalesce((SELECT sum(amount_minor) FROM hocalist.withdrawal_requests WHERE status='processing'),0));
END $$;

REVOKE ALL ON FUNCTION hocalist.contact_verified(uuid),hocalist.withdrawal_available_minor(uuid),
  hocalist.withdrawal_settle_internal(uuid,text,text,text,text),
  hocalist.withdrawal_status(),hocalist.withdrawal_request(text,bigint),
  hocalist.admin_withdrawal_queue(integer,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.withdrawal_status(),hocalist.withdrawal_request(text,bigint),
  hocalist.admin_withdrawal_queue(integer,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.withdrawal_settle_internal(uuid,text,text,text,text) TO service_role;
COMMIT;

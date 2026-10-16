-- Provider-neutral payout execution bridge over the reviewed 093 withdrawal
-- state machine. No provider is called and no provider is named as available:
-- the executor is injected by the coordinator after account/country/recipient
-- eligibility is verified.
--
-- Invariants held here:
--   * the immutable provider/payment intent is persisted BEFORE dispatch and
--     its idempotency identity never changes across transport retries, lease
--     expiry or worker restarts (`request_key = withdrawal_id`);
--   * lease expiry is not payment finality: an expired reservation becomes
--     `outcome_unknown`, which the worker must reconcile through the same
--     request key before any replacement submission; there is no age-based
--     "never sent" claim;
--   * exactly one live intent per withdrawal (reserved/submitted/outcome_unknown);
--   * one provider transfer reference can settle at most one attempt, and a
--     submitted or final reference is immutable;
--   * success after a recorded failure becomes durable `late_success_review`
--     evidence through this entry point and never pays a second time;
--   * polling and reconciliation always carry each attempt's provider binding,
--     so a policy change cannot make one provider poll another's attempt;
--   * provider changes are fenced while unresolved intents exist.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regprocedure('hocalist.withdrawal_settle_internal(uuid,text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'withdrawals 093 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.payout_attempts') IS NOT NULL THEN
    RAISE EXCEPTION 'payout execution bridge already installed';
  END IF;
END $guard$;

-- ---------------------------------------------------------------------------
-- Provider configuration
-- ---------------------------------------------------------------------------

-- Unconfigured by default: no provider key and execution disabled. Naming a
-- provider is a coordinator decision after eligibility verification.
CREATE TABLE hocalist.payout_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  provider_key text CHECK (provider_key IS NULL OR length(btrim(provider_key)) BETWEEN 1 AND 60),
  execution_enabled boolean NOT NULL DEFAULT false,
  -- Lease for an unresolved reservation. Expiry moves the attempt to
  -- `outcome_unknown`; it never authorizes a new payment intent.
  claim_lease_minutes integer NOT NULL DEFAULT 30
    CHECK (claim_lease_minutes BETWEEN 5 AND 1440),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.payout_policy(singleton) VALUES (true);

CREATE TABLE hocalist.payout_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  withdrawal_id uuid NOT NULL REFERENCES hocalist.withdrawal_requests(id),
  attempt integer NOT NULL CHECK (attempt > 0),
  provider_key text NOT NULL CHECK (length(btrim(provider_key)) BETWEEN 1 AND 60),
  -- Immutable intent identity: the same key for every attempt of a withdrawal.
  request_key text NOT NULL CHECK (request_key = withdrawal_id::text),
  provider_reference text CHECK (provider_reference IS NULL
    OR length(btrim(provider_reference)) BETWEEN 1 AND 200),
  state text NOT NULL DEFAULT 'reserved' CHECK (state IN
    ('reserved','submitted','outcome_unknown','succeeded','failed','late_success_review')),
  detail text CHECK (detail IS NULL OR length(detail) <= 500),
  submitted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (withdrawal_id, attempt)
);
-- At most one unresolved intent per withdrawal.
CREATE UNIQUE INDEX payout_attempts_live
  ON hocalist.payout_attempts(withdrawal_id)
  WHERE state IN ('reserved','submitted','outcome_unknown');
-- One provider transfer reference settles at most one attempt.
CREATE UNIQUE INDEX payout_attempts_reference
  ON hocalist.payout_attempts(provider_key, provider_reference)
  WHERE provider_reference IS NOT NULL;

ALTER TABLE hocalist.payout_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.payout_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.payout_policy, hocalist.payout_attempts
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Claim / lease expiry / reconcile / poll (service path only)
-- ---------------------------------------------------------------------------

-- Claims processing withdrawals that have never had an intent, persisting the
-- immutable intent before the executor can dispatch it. Requires an enabled
-- provider; returns per-item `attempt_id` and the stable `request_key`.
CREATE FUNCTION hocalist.payout_claim_internal(p_limit integer DEFAULT 20, p_runner text DEFAULT 'worker')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  pol hocalist.payout_policy%ROWTYPE;
  v_w hocalist.withdrawal_requests%ROWTYPE;
  v_attempt uuid;
  v_items jsonb := '[]'::jsonb;
  v_n integer := 0;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_limit' USING ERRCODE='22023';
  END IF;
  SELECT * INTO pol FROM hocalist.payout_policy WHERE singleton;
  IF pol.provider_key IS NULL OR NOT pol.execution_enabled THEN
    RETURN jsonb_build_object('status','disabled',
      'provider_configured', pol.provider_key IS NOT NULL,
      'execution_enabled', pol.execution_enabled,
      'items','[]'::jsonb);
  END IF;
  IF NOT pg_try_advisory_xact_lock(hashtextextended('hocalist:payout_claim',0)) THEN
    RETURN jsonb_build_object('status','skipped','reason','already_running','items','[]'::jsonb);
  END IF;
  FOR v_w IN
    SELECT w.* FROM hocalist.withdrawal_requests w
    WHERE w.status='processing'
      AND NOT EXISTS (SELECT 1 FROM hocalist.payout_attempts a WHERE a.withdrawal_id=w.id)
    ORDER BY w.created_at, w.id
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO hocalist.payout_attempts(
      withdrawal_id,attempt,provider_key,request_key,state,detail)
    VALUES(v_w.id,1,btrim(pol.provider_key),v_w.id::text,'reserved',
      left(coalesce(p_runner,'worker'),500))
    ON CONFLICT (withdrawal_id) WHERE state IN ('reserved','submitted','outcome_unknown')
      DO NOTHING
    RETURNING id INTO v_attempt;
    IF FOUND THEN
      v_n := v_n + 1;
      v_items := v_items || jsonb_build_object(
        'attempt_id',v_attempt,
        'withdrawal_id',v_w.id,
        'attempt',1,
        'request_key',v_w.id::text,
        'provider_key',btrim(pol.provider_key),
        'currency','USD',
        'amount_minor',v_w.amount_minor,
        'fee_minor',v_w.fee_minor,
        'net_minor',v_w.net_minor);
    END IF;
  END LOOP;
  RETURN jsonb_build_object('status','claimed','claimed',v_n,
    'provider_key',btrim(pol.provider_key),'items',v_items);
END $$;

-- Turns a stale unresolved lease into `outcome_unknown`. This is deliberately
-- not an abandonment: the persisted intent may already exist at the provider,
-- so the only permitted continuation is reconciliation through the same key.
CREATE FUNCTION hocalist.payout_lease_expire_internal(p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  pol hocalist.payout_policy%ROWTYPE;
  a hocalist.payout_attempts%ROWTYPE;
  v_n integer := 0;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_limit' USING ERRCODE='22023';
  END IF;
  SELECT * INTO pol FROM hocalist.payout_policy WHERE singleton;
  FOR a IN
    SELECT * FROM hocalist.payout_attempts
    WHERE state='reserved'
      AND created_at < now() - make_interval(mins => pol.claim_lease_minutes)
    ORDER BY created_at, id LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE hocalist.payout_attempts SET state='outcome_unknown',
      detail='lease expired before dispatch confirmation', updated_at=now()
      WHERE id=a.id;
    v_n := v_n + 1;
  END LOOP;
  RETURN jsonb_build_object('status','expired','expired',v_n);
END $$;

-- Unresolved intents the executor must reconcile before any replacement:
-- resubmit with the SAME request_key when no reference exists, or poll the
-- recorded reference. Never creates a new intent.
CREATE FUNCTION hocalist.payout_reconcile_batch_internal(p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE pol hocalist.payout_policy%ROWTYPE;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_limit' USING ERRCODE='22023';
  END IF;
  SELECT * INTO pol FROM hocalist.payout_policy WHERE singleton;
  RETURN jsonb_build_object(
    'status','ok',
    'provider_key',pol.provider_key,
    'items',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'attempt_id',a.id,'withdrawal_id',a.withdrawal_id,'attempt',a.attempt,
        'request_key',a.request_key,'provider_key',a.provider_key,
        'provider_reference',a.provider_reference,'currency','USD',
        'amount_minor',w.amount_minor,'fee_minor',w.fee_minor,'net_minor',w.net_minor)
        ORDER BY a.updated_at,a.id)
      FROM (SELECT * FROM hocalist.payout_attempts WHERE state='outcome_unknown'
        ORDER BY updated_at,id LIMIT p_limit) a
      JOIN hocalist.withdrawal_requests w ON w.id=a.withdrawal_id),'[]'::jsonb));
END $$;

-- Submitted attempts for provider polling. Available even when new claims are
-- disabled, because an already-dispatched intent must still be settled.
CREATE FUNCTION hocalist.payout_poll_batch_internal(p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE pol hocalist.payout_policy%ROWTYPE;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_limit' USING ERRCODE='22023';
  END IF;
  SELECT * INTO pol FROM hocalist.payout_policy WHERE singleton;
  RETURN jsonb_build_object(
    'status','ok',
    'provider_key',pol.provider_key,
    'items',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'attempt_id',a.id,'withdrawal_id',a.withdrawal_id,'attempt',a.attempt,
        'request_key',a.request_key,'provider_key',a.provider_key,
        'provider_reference',a.provider_reference)
        ORDER BY a.updated_at,a.id)
      FROM (SELECT * FROM hocalist.payout_attempts WHERE state='submitted'
        ORDER BY updated_at,id LIMIT p_limit) a),'[]'::jsonb));
END $$;

-- Records a provider outcome. Exact replays are answers; a conflicting
-- reference or a reference already used by another attempt fails. A success
-- after a recorded failure becomes durable review evidence and never pays.
CREATE FUNCTION hocalist.payout_settle_internal(
  p_attempt uuid, p_result text, p_reference text DEFAULT NULL, p_reason text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  a hocalist.payout_attempts%ROWTYPE;
  r jsonb;
  v_reference text;
  v_n bigint;
BEGIN
  IF p_result IS NULL OR p_result NOT IN ('submitted','succeeded','failed') THEN
    RAISE EXCEPTION 'invalid_result' USING ERRCODE='22023';
  END IF;
  IF p_reason IS NOT NULL AND length(p_reason) > 500 THEN
    RAISE EXCEPTION 'invalid_reason' USING ERRCODE='22023';
  END IF;
  v_reference := nullif(btrim(coalesce(p_reference,'')),'');
  IF p_result IN ('submitted','succeeded')
     AND (v_reference IS NULL OR length(v_reference) NOT BETWEEN 1 AND 200) THEN
    RAISE EXCEPTION 'invalid_provider_reference' USING ERRCODE='22023';
  END IF;
  SELECT * INTO STRICT a FROM hocalist.payout_attempts WHERE id=p_attempt FOR UPDATE;

  -- Final/known states: exact replay answers, everything else is refused.
  IF a.state='succeeded' THEN
    IF p_result='succeeded' AND a.provider_reference IS NOT DISTINCT FROM v_reference THEN
      RETURN jsonb_build_object('status','succeeded','attempt_id',a.id,'replayed',true);
    END IF;
    IF p_result='failed' THEN
      RAISE EXCEPTION 'late_failure_after_payout' USING ERRCODE='P0001';
    END IF;
    RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
  END IF;
  IF a.state='late_success_review' THEN
    IF p_result='succeeded' AND a.provider_reference IS NOT DISTINCT FROM v_reference THEN
      RETURN jsonb_build_object('status','late_success_review','attempt_id',a.id,'replayed',true);
    END IF;
    RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
  END IF;
  -- Immutable transfer binding: a known reference can never be replaced, in
  -- any state. An unexpected different reference is recorded as an anomaly and
  -- leaves both the attempt and the withdrawal untouched.
  IF p_result IN ('submitted','succeeded')
     AND a.provider_reference IS NOT NULL
     AND a.provider_reference IS DISTINCT FROM v_reference THEN
    SELECT coalesce(max(revision),0)+1 INTO v_n
      FROM hocalist.withdrawal_events WHERE withdrawal_id=a.withdrawal_id;
    INSERT INTO hocalist.withdrawal_events(withdrawal_id,revision,event,actor,detail)
    VALUES(a.withdrawal_id,v_n,'reconciliation','provider',
      left('reference mismatch for attempt '||a.id::text,500));
    RETURN jsonb_build_object('status','reference_mismatch','attempt_id',a.id,
      'expected_reference',a.provider_reference,'received_reference',v_reference);
  END IF;

  IF a.state='failed' THEN
    IF p_result='failed' THEN
      RETURN jsonb_build_object('status','failed','attempt_id',a.id,'replayed',true);
    END IF;
    IF p_result='submitted' THEN
      RAISE EXCEPTION 'attempt_final' USING ERRCODE='P0001';
    END IF;
    -- A late success is durable review evidence, never a second payout. 093
    -- records the reconciliation event and refuses to pay again.
    r := hocalist.withdrawal_settle_internal(a.withdrawal_id,'paid',a.provider_key,
      v_reference,left(coalesce(p_reason,'late success after failure'),500));
    IF (r->>'status') <> 'reconciliation_required' THEN
      RAISE EXCEPTION 'unexpected_late_payout_state' USING ERRCODE='P0001';
    END IF;
    UPDATE hocalist.payout_attempts SET state='late_success_review',
      provider_reference=v_reference, detail='late success after recorded failure',
      updated_at=now() WHERE id=a.id;
    RETURN jsonb_build_object('status','late_success_review','attempt_id',a.id,'withdrawal',r);
  END IF;

  -- Active states: reserved, submitted, outcome_unknown. A confirmed failure
  -- carries no reference and keeps the submitted reference for audit.
  IF v_reference IS NOT NULL AND EXISTS (
      SELECT 1 FROM hocalist.payout_attempts x
      WHERE x.id<>a.id AND x.provider_key=a.provider_key
        AND x.provider_reference=v_reference) THEN
    RAISE EXCEPTION 'reference_already_used' USING ERRCODE='P0001';
  END IF;

  IF p_result='submitted' THEN
    UPDATE hocalist.payout_attempts SET state='submitted',
      provider_reference=v_reference, submitted_at=coalesce(submitted_at,now()),
      detail=left(coalesce(p_reason,detail),500), updated_at=now()
      WHERE id=a.id RETURNING * INTO a;
    RETURN jsonb_build_object('status','submitted','attempt_id',a.id);
  ELSIF p_result='succeeded' THEN
    r := hocalist.withdrawal_settle_internal(a.withdrawal_id,'paid',a.provider_key,
      v_reference,left(coalesce(p_reason,'provider success'),500));
    IF (r->>'status')='reconciliation_required' THEN
      -- The withdrawal was already failed; keep review evidence, never pay.
      UPDATE hocalist.payout_attempts SET state='late_success_review',
        provider_reference=v_reference, detail='late success after recorded failure',
        updated_at=now() WHERE id=a.id;
      RETURN jsonb_build_object('status','late_success_review','attempt_id',a.id,'withdrawal',r);
    END IF;
    UPDATE hocalist.payout_attempts SET state='succeeded',
      provider_reference=v_reference, submitted_at=coalesce(submitted_at,now()),
      detail=left(coalesce(p_reason,'provider success'),500), updated_at=now()
      WHERE id=a.id;
    RETURN jsonb_build_object('status','succeeded','attempt_id',a.id,'withdrawal',r);
  END IF;
  -- Confirmed failure: 093 restores the reserved balance exactly once.
  r := hocalist.withdrawal_settle_internal(a.withdrawal_id,'failed',a.provider_key,NULL,
    left(coalesce(p_reason,'provider failure'),500));
  UPDATE hocalist.payout_attempts SET state='failed',
    detail=left(coalesce(p_reason,'provider failure'),500), updated_at=now()
    WHERE id=a.id;
  RETURN jsonb_build_object('status','failed','attempt_id',a.id,'withdrawal',r);
END $$;

-- ---------------------------------------------------------------------------
-- Admin configuration and read
-- ---------------------------------------------------------------------------

-- Records provider configuration as an explicit admin decision. The provider
-- key cannot change while unresolved intents exist, so an in-flight payment
-- can never be handed to a different provider.
CREATE FUNCTION hocalist.payout_admin_command(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  v_provider text;
  pol hocalist.payout_policy%ROWTYPE;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
     OR p_input - ARRAY['provider_key','execution_enabled','claim_lease_minutes',
        'expected_revision'] <> '{}'::jsonb THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  v_provider := nullif(btrim(coalesce(p_input->>'provider_key','')),'');
  IF v_provider IS NOT NULL AND v_provider !~ '^[a-z0-9][a-z0-9_-]{0,59}$' THEN
    RAISE EXCEPTION 'invalid_provider_key' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':payout_admin:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id=u AND operation='payout_admin.policy' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT * INTO pol FROM hocalist.payout_policy WHERE singleton FOR UPDATE;
  IF p_input ? 'provider_key' AND v_provider IS DISTINCT FROM pol.provider_key
     AND EXISTS (SELECT 1 FROM hocalist.payout_attempts
       WHERE state IN ('reserved','submitted','outcome_unknown')) THEN
    RAISE EXCEPTION 'unresolved_intents_present' USING ERRCODE='P0001';
  END IF;
  IF p_input ? 'execution_enabled' AND (p_input->>'execution_enabled')::boolean
     AND coalesce(v_provider, pol.provider_key) IS NULL THEN
    RAISE EXCEPTION 'provider_required_before_enable' USING ERRCODE='P0001';
  END IF;
  UPDATE hocalist.payout_policy SET
    provider_key=CASE WHEN p_input ? 'provider_key' THEN v_provider ELSE provider_key END,
    execution_enabled=CASE WHEN p_input ? 'execution_enabled'
      THEN (p_input->>'execution_enabled')::boolean
      ELSE (execution_enabled AND (v_provider IS NOT NULL OR provider_key IS NOT NULL)) END,
    claim_lease_minutes=CASE WHEN p_input ? 'claim_lease_minutes'
      THEN (p_input->>'claim_lease_minutes')::integer ELSE claim_lease_minutes END,
    revision=revision+1,
    updated_at=now()
  WHERE singleton
    AND (p_input->'expected_revision' IS NULL
      OR revision=(p_input->>'expected_revision')::bigint);
  IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'payout_admin.policy',p_key,h,jsonb_build_object('singleton',true));
  RETURN jsonb_build_object('singleton',true);
END $$;

CREATE FUNCTION hocalist.admin_payout_reconciliation_queue(p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  pol hocalist.payout_policy%ROWTYPE;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  SELECT * INTO pol FROM hocalist.payout_policy WHERE singleton;
  RETURN jsonb_build_object(
    'policy', jsonb_build_object(
      'provider_configured', pol.provider_key IS NOT NULL,
      'provider_key', pol.provider_key,
      'execution_enabled', pol.execution_enabled,
      'claim_lease_minutes', pol.claim_lease_minutes,
      'revision', pol.revision),
    'processing_withdrawals', coalesce((SELECT count(*)
      FROM hocalist.withdrawal_requests WHERE status='processing'),0),
    'late_success_review', coalesce((SELECT count(*) FROM hocalist.payout_attempts
      WHERE state='late_success_review'),0),
    'outcome_unknown', coalesce((SELECT count(*) FROM hocalist.payout_attempts
      WHERE state='outcome_unknown'),0),
    'attempts', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',a.id,'withdrawal_id',a.withdrawal_id,'attempt',a.attempt,
        'provider_key',a.provider_key,'request_key',a.request_key,
        'provider_reference',a.provider_reference,'state',a.state,'detail',a.detail,
        'created_at',a.created_at,'updated_at',a.updated_at) ORDER BY a.created_at DESC,a.id DESC)
      FROM (SELECT * FROM hocalist.payout_attempts
        WHERE state IN ('reserved','submitted','outcome_unknown','late_success_review')
        ORDER BY created_at DESC,id DESC LIMIT p_limit) a),'[]'::jsonb));
END $$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION
  hocalist.payout_claim_internal(integer,text),
  hocalist.payout_lease_expire_internal(integer),
  hocalist.payout_reconcile_batch_internal(integer),
  hocalist.payout_settle_internal(uuid,text,text,text),
  hocalist.payout_poll_batch_internal(integer),
  hocalist.payout_admin_command(text,jsonb),
  hocalist.admin_payout_reconciliation_queue(integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  hocalist.payout_claim_internal(integer,text),
  hocalist.payout_lease_expire_internal(integer),
  hocalist.payout_reconcile_batch_internal(integer),
  hocalist.payout_settle_internal(uuid,text,text,text),
  hocalist.payout_poll_batch_internal(integer) TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.payout_admin_command(text,jsonb),
  hocalist.admin_payout_reconciliation_queue(integer) TO authenticated;
COMMIT;

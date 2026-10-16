-- Reservation-expiry and reconciliation orchestration over the reviewed 092
-- settlement engine. This migration does not modify 092; it adds a
-- single-flight worker sweep and closes the reschedule race by locking the
-- meeting rows before any release decision.
--
-- Preserved authority:
--   * request discovery expiry closes discovery only; an accepted meeting
--     keeps its reservation until the meeting's own exclusive local-day
--     cutoff (plus the configured no-show grace, default 0);
--   * a confirmed purchase always settles the winning difference through
--     `credit_settle_purchase`, even when an earlier attempt was interrupted;
--   * releases never consume or restore a weekly target slot, and never touch
--     another seller's batch;
--   * the unapproved late-window fee override stays gated: policy can record
--     that it must remain off, and the sweep refuses to run while it is on.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.credit_targets') IS NULL
     OR to_regprocedure('hocalist.credit_settle_internal(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'credit settlement 090 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.credit_settle_purchase(uuid)') IS NULL THEN
    RAISE EXCEPTION 'credit settlement 092 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.sale_confirmations') IS NULL THEN
    RAISE EXCEPTION 'outcomes 080 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.reconciliation_policy') IS NOT NULL THEN
    RAISE EXCEPTION 'reconciliation orchestration already installed';
  END IF;
END $guard$;

-- ---------------------------------------------------------------------------
-- Policy and run audit
-- ---------------------------------------------------------------------------

-- `no_show_grace_hours` is an operational delay only: 0 means release at the
-- meeting's exclusive local-day cutoff, which is the reviewed behavior.
-- `late_window_fee_override` is the unapproved late-window fee rule; it is
-- explicitly false and the sweep refuses while it is true.
CREATE TABLE hocalist.reconciliation_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  no_show_grace_hours integer NOT NULL DEFAULT 0
    CHECK (no_show_grace_hours BETWEEN 0 AND 168),
  late_window_fee_override boolean NOT NULL DEFAULT false,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.reconciliation_policy(singleton) VALUES (true);

CREATE TABLE hocalist.reconciliation_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  runner text NOT NULL CHECK (length(btrim(runner)) BETWEEN 1 AND 60),
  status text NOT NULL DEFAULT 'running'
    CHECK (status IN ('running','completed','skipped','failed')),
  examined integer NOT NULL DEFAULT 0 CHECK (examined >= 0),
  released integer NOT NULL DEFAULT 0 CHECK (released >= 0),
  settled integer NOT NULL DEFAULT 0 CHECK (settled >= 0),
  kept integer NOT NULL DEFAULT 0 CHECK (kept >= 0),
  detail text CHECK (detail IS NULL OR length(detail) <= 500),
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz
);

ALTER TABLE hocalist.reconciliation_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.reconciliation_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.reconciliation_policy, hocalist.reconciliation_runs
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Per-target decision
-- ---------------------------------------------------------------------------

-- Re-checks one target under meeting row locks. The lock closes the race where
-- a sweep reads an expired meeting while an accepted reschedule is being
-- written: whichever transaction commits second sees the other's committed
-- state, and a still-valid accepted meeting is never released.
CREATE FUNCTION hocalist.credit_reconcile_target_internal(p_target uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  t hocalist.credit_targets%ROWTYPE;
  o hocalist.offers%ROWTYPE;
  r hocalist.requests%ROWTYPE;
  pol hocalist.reconciliation_policy%ROWTYPE;
  v_closed boolean;
  v_expired boolean;
  v_grace interval;
BEGIN
  IF p_target IS NULL THEN RAISE EXCEPTION 'invalid_target' USING ERRCODE='22023'; END IF;
  SELECT * INTO t FROM hocalist.credit_targets WHERE id=p_target;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','not_found'); END IF;
  IF t.status NOT IN ('reserved','initial_charged') THEN
    RETURN jsonb_build_object('status',t.status,'skipped',true);
  END IF;
  PERFORM 1 FROM hocalist.credit_targets WHERE id=p_target FOR UPDATE;
  SELECT * INTO t FROM hocalist.credit_targets WHERE id=p_target;
  IF t.status NOT IN ('reserved','initial_charged') THEN
    RETURN jsonb_build_object('status',t.status,'skipped',true);
  END IF;
  IF t.offer_id IS NULL THEN
    RETURN jsonb_build_object('status','kept','reason','no_offer');
  END IF;
  SELECT * INTO pol FROM hocalist.reconciliation_policy WHERE singleton;
  v_grace := make_interval(hours => coalesce(pol.no_show_grace_hours,0));

  -- Match the reviewed PIN lock order (request, then meetings) so parallel
  -- sale confirmations cannot deadlock with reconciliation. Meeting mutation
  -- paths lock only the meeting row, which this order also covers.
  PERFORM 1 FROM hocalist.requests WHERE id=t.request_id FOR UPDATE;
  PERFORM 1 FROM hocalist.meetings WHERE offer_id=t.offer_id ORDER BY id FOR UPDATE;

  -- A confirmed purchase is settled, never released. Re-running this repairs
  -- an interrupted PIN settlement and is idempotent.
  IF EXISTS (SELECT 1 FROM hocalist.sale_confirmations s WHERE s.request_id=t.request_id) THEN
    PERFORM hocalist.credit_settle_purchase(t.request_id);
    RETURN jsonb_build_object('status','settled_purchase');
  END IF;

  SELECT * INTO o FROM hocalist.offers WHERE id=t.offer_id;
  SELECT * INTO r FROM hocalist.requests WHERE id=t.request_id;
  IF o.id IS NULL OR r.id IS NULL THEN
    RETURN jsonb_build_object('status','kept','reason','missing_reference');
  END IF;
  v_closed := o.status IN ('withdrawn','declined','cancelled','expired','completed')
    OR r.status IN ('closed','cancelled');
  v_expired := r.acceptance_expires_at IS NOT NULL AND now() >= r.acceptance_expires_at;
  IF NOT (v_closed OR v_expired) THEN
    RETURN jsonb_build_object('status','kept','reason','live_discovery');
  END IF;
  IF EXISTS (
      SELECT 1 FROM hocalist.meetings m
      WHERE m.offer_id=t.offer_id
        AND m.status IN ('accepted','reschedule_proposed')
        AND m.meeting_expires_at IS NOT NULL
        AND now() < m.meeting_expires_at + v_grace) THEN
    -- Discovery may be over, but an accepted meeting can still complete.
    RETURN jsonb_build_object('status','kept','reason','accepted_meeting');
  END IF;
  IF NOT v_closed AND EXISTS (
      SELECT 1 FROM hocalist.meetings m
      WHERE m.offer_id=t.offer_id AND m.status='proposed') THEN
    -- Discovery closed but the accepted negotiation may still confirm a
    -- meeting; keep the reservation until that proposal resolves.
    RETURN jsonb_build_object('status','kept','reason','pending_proposal');
  END IF;
  PERFORM 1 FROM hocalist.profiles WHERE id=t.user_id FOR UPDATE;
  PERFORM hocalist.credit_settle_internal(t.id,'release');
  RETURN jsonb_build_object('status','released');
END $$;

-- ---------------------------------------------------------------------------
-- Worker sweep
-- ---------------------------------------------------------------------------

-- Single-flight, repeatable, service-role-only reconciliation. Repeated calls
-- are safe: every settlement transition is idempotent, and concurrent sweeps
-- skip instead of racing. It never creates a target, so weekly quota is
-- untouched. It returns counts rather than money amounts.
CREATE FUNCTION hocalist.commercial_reconcile_sweep(
  p_limit integer DEFAULT 200, p_runner text DEFAULT 'worker'
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  pol hocalist.reconciliation_policy%ROWTYPE;
  v_run uuid;
  v_request uuid;
  v_target uuid;
  v_result jsonb;
  v_status text;
  v_examined integer := 0;
  v_released integer := 0;
  v_settled integer := 0;
  v_kept integer := 0;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'invalid_limit' USING ERRCODE='22023';
  END IF;
  IF p_runner IS NULL OR length(btrim(p_runner)) NOT BETWEEN 1 AND 60 THEN
    RAISE EXCEPTION 'invalid_runner' USING ERRCODE='22023';
  END IF;
  SELECT * INTO pol FROM hocalist.reconciliation_policy WHERE singleton;
  IF pol.late_window_fee_override THEN
    -- Unapproved policy: refuse to run rather than settle with it.
    RAISE EXCEPTION 'late_window_override_unapproved' USING ERRCODE='P0001';
  END IF;
  IF NOT pg_try_advisory_xact_lock(hashtextextended('hocalist:commercial_reconcile_sweep',0)) THEN
    RETURN jsonb_build_object('status','skipped','reason','already_running');
  END IF;
  INSERT INTO hocalist.reconciliation_runs(runner) VALUES (btrim(p_runner))
    RETURNING id INTO v_run;
  BEGIN
    -- 1. Repair any confirmed purchase whose winning difference is unsettled.
    FOR v_request IN
      SELECT DISTINCT t.request_id
      FROM hocalist.credit_targets t
      JOIN hocalist.sale_confirmations s ON s.request_id=t.request_id
      WHERE t.status IN ('reserved','initial_charged')
      ORDER BY t.request_id
      LIMIT p_limit
    LOOP
      PERFORM hocalist.credit_settle_purchase(v_request);
      v_settled := v_settled + 1;
    END LOOP;

    -- 2. Release targets whose negotiation ended without a purchase.
    FOR v_target IN
      SELECT t.id FROM hocalist.credit_targets t
      WHERE t.status IN ('reserved','initial_charged')
        AND NOT EXISTS (
          SELECT 1 FROM hocalist.sale_confirmations s WHERE s.request_id=t.request_id)
      ORDER BY t.created_at, t.id
      LIMIT p_limit
      FOR UPDATE SKIP LOCKED
    LOOP
      v_examined := v_examined + 1;
      v_result := hocalist.credit_reconcile_target_internal(v_target);
      v_status := v_result->>'status';
      IF v_status = 'released' THEN
        v_released := v_released + 1;
      ELSIF v_status = 'settled_purchase' THEN
        v_settled := v_settled + 1;
      ELSE
        v_kept := v_kept + 1;
      END IF;
    END LOOP;

    UPDATE hocalist.reconciliation_runs
      SET status='completed', examined=v_examined, released=v_released,
          settled=v_settled, kept=v_kept, finished_at=now()
      WHERE id=v_run;
  EXCEPTION WHEN OTHERS THEN
    UPDATE hocalist.reconciliation_runs
      SET status='failed', detail=left(SQLERRM,500), finished_at=now()
      WHERE id=v_run;
    RAISE;
  END;
  RETURN jsonb_build_object(
    'status','completed','run_id',v_run,
    'examined',v_examined,'released',v_released,'settled',v_settled,'kept',v_kept);
END $$;

-- ---------------------------------------------------------------------------
-- Admin policy command and read
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.reconciliation_admin_command(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
     OR p_input - ARRAY['no_show_grace_hours','late_window_fee_override','expected_revision'] <> '{}'::jsonb THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  IF p_input ? 'late_window_fee_override'
     AND (p_input->>'late_window_fee_override')::boolean THEN
    -- The late-window fee override is not approved; it can be recorded as off
    -- but never switched on through this command.
    RAISE EXCEPTION 'late_window_override_unapproved' USING ERRCODE='P0001';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':reconciliation_admin:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id=u AND operation='reconciliation_admin.policy' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  UPDATE hocalist.reconciliation_policy SET
    no_show_grace_hours=CASE WHEN p_input ? 'no_show_grace_hours'
      THEN (p_input->>'no_show_grace_hours')::integer ELSE no_show_grace_hours END,
    late_window_fee_override=false,
    revision=revision+1,
    updated_at=now()
  WHERE singleton
    AND (p_input->'expected_revision' IS NULL
      OR revision=(p_input->>'expected_revision')::bigint);
  IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'reconciliation_admin.policy',p_key,h,jsonb_build_object('singleton',true));
  RETURN jsonb_build_object('singleton',true);
END $$;

CREATE FUNCTION hocalist.admin_reconciliation_overview(p_runs integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_runs IS NULL OR p_runs NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  RETURN jsonb_build_object(
    'live_targets', coalesce((SELECT count(*) FROM hocalist.credit_targets
      WHERE status IN ('reserved','initial_charged')),0),
    'held_by_accepted_meeting', coalesce((SELECT count(*) FROM hocalist.credit_targets t
      WHERE t.status IN ('reserved','initial_charged') AND EXISTS (
        SELECT 1 FROM hocalist.meetings m WHERE m.offer_id=t.offer_id
          AND m.status IN ('accepted','reschedule_proposed')
          AND m.meeting_expires_at IS NOT NULL AND now() < m.meeting_expires_at)),0),
    'unsettled_confirmed_sales', coalesce((SELECT count(*) FROM hocalist.credit_targets t
      JOIN hocalist.sale_confirmations s ON s.request_id=t.request_id
      WHERE t.status IN ('reserved','initial_charged')),0),
    'policy', (SELECT jsonb_build_object(
      'no_show_grace_hours', no_show_grace_hours,
      'late_window_fee_override', late_window_fee_override,
      'revision', revision) FROM hocalist.reconciliation_policy WHERE singleton),
    'runs', coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',id,'runner',runner,'status',status,'examined',examined,'released',released,
      'settled',settled,'kept',kept,'detail',detail,
      'started_at',started_at,'finished_at',finished_at) ORDER BY started_at DESC,id DESC)
      FROM (SELECT * FROM hocalist.reconciliation_runs
        ORDER BY started_at DESC,id DESC LIMIT p_runs) x),'[]'::jsonb));
END $$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION
  hocalist.credit_reconcile_target_internal(uuid),
  hocalist.commercial_reconcile_sweep(integer,text),
  hocalist.reconciliation_admin_command(text,jsonb),
  hocalist.admin_reconciliation_overview(integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.commercial_reconcile_sweep(integer,text) TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.reconciliation_admin_command(text,jsonb),
  hocalist.admin_reconciliation_overview(integer) TO authenticated;
COMMIT;

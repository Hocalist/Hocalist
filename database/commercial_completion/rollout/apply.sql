BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
DO $guard$ BEGIN
IF to_regprocedure('hocalist.withdrawal_available_minor(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.withdrawal_available_minor(uuid)')),chr(13),''))<>'4123a66f1e85a86f2db301cc99c064a1' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.withdrawal_available_minor(uuid)'; END IF;
IF to_regprocedure('hocalist.withdrawal_request(text,bigint)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.withdrawal_request(text,bigint)')),chr(13),''))<>'56d70610f58760eda3c7ca76f15706fe' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.withdrawal_request(text,bigint)'; END IF;
IF to_regprocedure('hocalist.marketplace_seller_plan(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_seller_plan(uuid)')),chr(13),''))<>'4f5e6dec55d2e5f5a4ac560ce26a78bd' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_seller_plan(uuid)'; END IF;
IF to_regprocedure('hocalist.marketplace_store_limit(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_store_limit(uuid)')),chr(13),''))<>'566cd5ebb44a0b335f267f79e2a43754' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_store_limit(uuid)'; END IF;
IF to_regprocedure('hocalist.marketplace_weekly_target_limit(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_weekly_target_limit(uuid)')),chr(13),''))<>'c0f81ba7d560df4b3148897bfb9ac760' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_weekly_target_limit(uuid)'; END IF;
IF to_regclass('hocalist.entitlement_policy') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: entitlement_policy'; END IF;
IF to_regclass('hocalist.reconciliation_policy') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: reconciliation_policy'; END IF;
IF to_regclass('hocalist.reconciliation_runs') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: reconciliation_runs'; END IF;
IF to_regclass('hocalist.reversal_policy') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: reversal_policy'; END IF;
IF to_regclass('hocalist.payment_reversals') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: payment_reversals'; END IF;
IF to_regclass('hocalist.ledger_corrections') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: ledger_corrections'; END IF;
IF to_regclass('hocalist.reversal_events') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: reversal_events'; END IF;
IF to_regclass('hocalist.payout_policy') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: payout_policy'; END IF;
IF to_regclass('hocalist.payout_attempts') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: payout_attempts'; END IF;
END $guard$;

-- Authoritative seller entitlement lifecycle over verified account records.
--
-- September 26 authority: seven PIN-confirmed sales in one calendar month
-- grant following-month Pro benefits. The threshold is settled; the calendar
-- zone and the earned/paid overlap rule are NOT approved, and neither is
-- annual/trial eligibility or downgrade counting. This migration therefore:
--   * resolves every plan from server records only -- a client never selects
--     its own plan;
--   * seeds only the settled threshold and leaves the calendar, overlap,
--     downgrade and annual/trial settings explicitly unconfigured;
--   * reports an unavailable transition (with a reason) instead of guessing
--     when a required policy is missing;
--   * applies earned Pro only when its own counting is configured and, when a
--     paid/admin plan also exists, only when the overlap rule is configured;
--   * exposes a read-only downgrade/annual/trial preview that never mutates
--     listings or entitlements.
--
-- Provider subscription state is read through the existing verified
-- `stripe_test_subscriptions` record; this file writes no billing state.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.seller_entitlements') IS NULL THEN
    RAISE EXCEPTION 'marketplace entitlement 020 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.sale_confirmations') IS NULL THEN
    RAISE EXCEPTION 'outcomes 080 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.marketplace_weekly_target_limit(uuid)') IS NULL THEN
    RAISE EXCEPTION 'marketplace weekly capacity 023 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL THEN
    RAISE EXCEPTION 'marketplace admin guard prerequisite missing';
  END IF;
  IF to_regclass('hocalist.entitlement_policy') IS NOT NULL THEN
    RAISE EXCEPTION 'entitlement lifecycle already installed';
  END IF;
END $guard$;

-- ---------------------------------------------------------------------------
-- Versioned policy: settled values seeded, unapproved rules explicitly absent
-- ---------------------------------------------------------------------------

CREATE TABLE hocalist.entitlement_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  -- Settled by the September 26 authority and safe to seed.
  earned_pro_threshold integer NOT NULL DEFAULT 7 CHECK (earned_pro_threshold BETWEEN 1 AND 100),
  -- NOT approved: the calendar zone used to count a monthly window.
  calendar_timezone text CHECK (calendar_timezone IS NULL OR length(btrim(calendar_timezone)) BETWEEN 1 AND 100),
  -- NOT approved: how an earned Pro benefit coexists with an active paid plan.
  paid_overlap text CHECK (
    paid_overlap IS NULL OR paid_overlap IN ('paid_priority','earned_priority','highest_priority')
  ),
  -- NOT approved: what a plan downgrade does to existing over-limit listings.
  downgrade_visibility text CHECK (
    downgrade_visibility IS NULL OR downgrade_visibility IN ('keep_existing_block_new','hide_over_limit')
  ),
  -- NOT approved: annual/trial eligibility. No amounts are stored here; the
  -- checkout catalogue is website-owned.
  annual_enabled boolean NOT NULL DEFAULT false,
  trial_days integer CHECK (trial_days IS NULL OR trial_days BETWEEN 1 AND 365),
  policy_version text NOT NULL DEFAULT 'threshold-only-v1'
    CHECK (length(btrim(policy_version)) BETWEEN 1 AND 100),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.entitlement_policy(singleton, earned_pro_threshold)
  VALUES (true, 7);

ALTER TABLE hocalist.entitlement_policy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.entitlement_policy FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Resolution from verified records
-- ---------------------------------------------------------------------------

-- Returns the verified component readings for one user. A restricted or
-- disabled membership contributes no paid/admin/earned benefit.
CREATE FUNCTION hocalist.entitlement_readings_internal(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  p hocalist.entitlement_policy%ROWTYPE;
  v_paid text;
  v_paid_status text;
  v_paid_until timestamptz;
  v_paid_review boolean := false;
  v_admin text;
  v_tz text;
  v_now timestamp;
  v_cur_start timestamp;
  v_prev_start timestamp;
  v_progress integer;
  v_qualifying integer;
  v_blocked boolean := false;
BEGIN
  IF p_user IS NULL THEN RAISE EXCEPTION 'invalid_user' USING ERRCODE='22023'; END IF;
  SELECT * INTO p FROM hocalist.entitlement_policy WHERE singleton;
  v_blocked := EXISTS (
    SELECT 1 FROM hocalist.memberships m
    WHERE m.user_id=p_user AND m.status IN ('restricted','disabled'));

  IF NOT v_blocked AND to_regclass('hocalist.stripe_test_subscriptions') IS NOT NULL THEN
    SELECT s.plan_code, s.provider_status, s.paid_until, coalesce(s.requires_review,false)
      INTO v_paid, v_paid_status, v_paid_until, v_paid_review
    FROM hocalist.memberships m
    JOIN hocalist.stripe_test_subscriptions s ON s.membership_id=m.id
    WHERE m.user_id=p_user AND m.role='seller' AND m.status='active'
      AND s.provider_status='active' AND s.plan_code IS NOT NULL
      AND s.paid_until>now() AND NOT s.requires_review
      AND NOT EXISTS (SELECT 1 FROM hocalist.stripe_test_customers c
        WHERE c.membership_id=m.id AND c.requires_review);
    IF NOT FOUND THEN
      v_paid := NULL; v_paid_until := NULL;
      SELECT s.provider_status, coalesce(s.requires_review,false)
        INTO v_paid_status, v_paid_review
      FROM hocalist.memberships m
      JOIN hocalist.stripe_test_subscriptions s ON s.membership_id=m.id
      WHERE m.user_id=p_user AND m.role='seller';
      IF NOT FOUND THEN v_paid_status := NULL; v_paid_review := false; END IF;
    END IF;
  END IF;

  IF NOT v_blocked THEN
    SELECT e.plan_code INTO v_admin FROM hocalist.seller_entitlements e
      WHERE e.user_id=p_user AND e.active AND e.source='admin';
    IF NOT FOUND THEN v_admin := NULL; END IF;
  END IF;

  v_tz := p.calendar_timezone;
  IF v_tz IS NOT NULL THEN
    v_now := now() AT TIME ZONE v_tz;
    v_cur_start := date_trunc('month', v_now);
    v_prev_start := v_cur_start - interval '1 month';
    SELECT count(*) INTO v_qualifying FROM hocalist.sale_confirmations s
      WHERE s.seller_user_id=p_user
        AND (s.confirmed_at AT TIME ZONE v_tz) >= v_prev_start
        AND (s.confirmed_at AT TIME ZONE v_tz) < v_cur_start;
    SELECT count(*) INTO v_progress FROM hocalist.sale_confirmations s
      WHERE s.seller_user_id=p_user
        AND (s.confirmed_at AT TIME ZONE v_tz) >= v_cur_start
        AND (s.confirmed_at AT TIME ZONE v_tz) < v_cur_start + interval '1 month';
  END IF;

  RETURN jsonb_build_object(
    'policy_revision', p.revision,
    'threshold', p.earned_pro_threshold,
    'restricted', v_blocked,
    'billing_plan', v_paid,
    'billing_status', v_paid_status,
    'billing_paid_until', v_paid_until,
    'billing_review_required', v_paid_review,
    'admin_plan', v_admin,
    'calendar_timezone', v_tz,
    'current_month_start', CASE WHEN v_tz IS NULL THEN NULL ELSE v_cur_start::date END,
    'qualifying_month_start', CASE WHEN v_tz IS NULL THEN NULL ELSE v_prev_start::date END,
    'current_month_sales', CASE WHEN v_tz IS NULL THEN NULL ELSE v_progress END,
    'qualifying_month_sales', CASE WHEN v_tz IS NULL THEN NULL ELSE v_qualifying END,
    'earned_available', (v_tz IS NOT NULL AND NOT v_blocked
      AND coalesce(v_qualifying,0) >= p.earned_pro_threshold),
    'overlap', p.paid_overlap);
END $$;

-- Effective plan for one user from verified records. When an earned benefit
-- and a paid/admin plan both apply and the overlap rule is unconfigured, the
-- paid/admin plan stays effective and the earned component is reported as
-- `applied: false` with `overlap_unconfigured: true`; nothing is guessed.
CREATE FUNCTION hocalist.entitlement_resolve_internal(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  r jsonb;
  v_paid text;
  v_admin text;
  v_earned boolean;
  v_overlap text;
  v_base text;
  v_base_source text;
  v_effective text;
  v_source text;
  v_earned_applied boolean := false;
  v_overlap_unconfigured boolean := false;
  v_rank integer;
BEGIN
  r := hocalist.entitlement_readings_internal(p_user);
  v_paid := r->>'billing_plan';
  v_admin := r->>'admin_plan';
  v_earned := (r->>'earned_available')::boolean;
  v_overlap := r->>'overlap';

  IF v_paid IS NOT NULL AND (v_admin IS NULL
      OR CASE v_paid WHEN 'elite' THEN 3 WHEN 'pro' THEN 2 ELSE 1 END
       >= CASE v_admin WHEN 'elite' THEN 3 WHEN 'pro' THEN 2 ELSE 1 END) THEN
    v_base := v_paid; v_base_source := 'billing';
  ELSIF v_admin IS NOT NULL THEN
    v_base := v_admin; v_base_source := 'admin';
  ELSE
    v_base := NULL; v_base_source := NULL;
  END IF;

  IF v_earned AND v_base IS NULL THEN
    v_effective := 'pro'; v_source := 'earned'; v_earned_applied := true;
  ELSIF v_earned AND v_base IS NOT NULL AND v_overlap IS NULL THEN
    v_effective := v_base; v_source := v_base_source;
    v_overlap_unconfigured := true;
  ELSIF v_earned AND v_base IS NOT NULL THEN
    -- Rank: free 1, pro 2, elite 3. The configured overlap rule decides.
    v_rank := CASE v_base WHEN 'elite' THEN 3 WHEN 'pro' THEN 2 ELSE 1 END;
    IF v_overlap = 'earned_priority' THEN
      v_effective := 'pro'; v_source := 'earned'; v_earned_applied := true;
      IF v_rank > 2 THEN
        v_effective := v_base; v_source := v_base_source;
      END IF;
    ELSIF v_overlap = 'paid_priority' THEN
      v_effective := v_base; v_source := v_base_source;
    ELSE -- highest_priority
      IF v_rank >= 2 THEN
        v_effective := v_base; v_source := v_base_source;
      ELSE
        v_effective := 'pro'; v_source := 'earned'; v_earned_applied := true;
      END IF;
    END IF;
  ELSIF v_base IS NOT NULL THEN
    v_effective := v_base; v_source := v_base_source;
  ELSE
    v_effective := 'free'; v_source := 'free';
  END IF;

  RETURN jsonb_build_object(
    'readings', r,
    'effective_plan', v_effective,
    'effective_source', v_source,
    'earned_applied', v_earned_applied,
    'overlap_unconfigured', v_overlap_unconfigured);
END $$;

-- ---------------------------------------------------------------------------
-- Client reads
-- ---------------------------------------------------------------------------

-- The signed-in seller's own entitlement, from verified records only.
CREATE FUNCTION hocalist.account_entitlement()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  v jsonb;
  r jsonb;
  v_limit integer;
  v_used integer;
  p hocalist.entitlement_policy%ROWTYPE;
BEGIN
  IF u IS NULL OR NOT EXISTS (
      SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id=u AND m.role='seller' AND m.status='active')
     OR EXISTS (SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id=u AND m.status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'entitlement_access_denied' USING ERRCODE='42501';
  END IF;
  v := hocalist.entitlement_resolve_internal(u);
  r := v->'readings';
  SELECT * INTO p FROM hocalist.entitlement_policy WHERE singleton;
  v_limit := hocalist.marketplace_store_limit(u);
  SELECT count(*) INTO v_used FROM hocalist.store_listings l
    WHERE l.seller_user_id=u AND l.status='active';
  RETURN jsonb_build_object(
    'role','seller',
    'effective_plan', v->>'effective_plan',
    'effective_source', v->>'effective_source',
    'policy', jsonb_build_object(
      'revision', p.revision,
      'version', p.policy_version,
      'earned_pro_threshold', p.earned_pro_threshold,
      'calendar_configured', p.calendar_timezone IS NOT NULL,
      'calendar_timezone', p.calendar_timezone,
      'paid_overlap_configured', p.paid_overlap IS NOT NULL,
      'paid_overlap', p.paid_overlap,
      'downgrade_visibility_configured', p.downgrade_visibility IS NOT NULL,
      'downgrade_visibility', p.downgrade_visibility,
      'annual_enabled', p.annual_enabled,
      'trial_days', p.trial_days),
    'verified', jsonb_build_object(
      'billing', jsonb_build_object(
        'available', r->>'billing_plan' IS NOT NULL,
        'plan', r->>'billing_plan',
        'provider_status', r->>'billing_status',
        'paid_until', r->>'billing_paid_until',
        'review_required', coalesce((r->>'billing_review_required')::boolean,false)),
      'admin', jsonb_build_object(
        'available', r->>'admin_plan' IS NOT NULL,
        'plan', r->>'admin_plan'),
      'earned', jsonb_build_object(
        'configured', r->>'calendar_timezone' IS NOT NULL,
        'unavailable_reason', CASE WHEN r->>'calendar_timezone' IS NULL
          THEN 'calendar_unconfigured' END,
        'threshold', (r->>'threshold')::integer,
        'timezone', r->>'calendar_timezone',
        'current_window', CASE WHEN r->>'calendar_timezone' IS NULL THEN NULL
          ELSE jsonb_build_object(
            'start', r->>'current_month_start',
            'sales', (r->>'current_month_sales')::integer) END,
        'qualifying_window', CASE WHEN r->>'calendar_timezone' IS NULL THEN NULL
          ELSE jsonb_build_object(
            'start', r->>'qualifying_month_start',
            'sales', (r->>'qualifying_month_sales')::integer) END,
        'plan', CASE WHEN coalesce((r->>'earned_available')::boolean,false) THEN 'pro' END,
        'applied', coalesce((v->>'earned_applied')::boolean,false),
        'overlap_unconfigured', coalesce((v->>'overlap_unconfigured')::boolean,false))),
    'annual', jsonb_build_object('available', p.annual_enabled),
    'trial', jsonb_build_object('available', p.trial_days IS NOT NULL, 'days', p.trial_days),
    'store_listing', jsonb_build_object('limit', v_limit, 'active', v_used),
    'plans', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'plan_code', l.plan_code,
        'store_listing_limit', l.store_listing_limit,
        'weekly_target_limit', l.weekly_target_limit)
        ORDER BY CASE l.plan_code WHEN 'free' THEN 1 WHEN 'pro' THEN 2 ELSE 3 END)
      FROM hocalist.marketplace_plan_limits l), '[]'::jsonb));
END $$;

-- Read-only preview of what switching plan would mean. It never mutates a
-- listing or an entitlement. A missing downgrade policy reports an explicit
-- unconfigured state instead of a guessed hide/block effect.
CREATE FUNCTION hocalist.entitlement_plan_preview(p_plan text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  l hocalist.marketplace_plan_limits%ROWTYPE;
  p hocalist.entitlement_policy%ROWTYPE;
  v_used integer;
BEGIN
  IF u IS NULL OR NOT EXISTS (
      SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id=u AND m.role='seller' AND m.status='active') THEN
    RAISE EXCEPTION 'entitlement_access_denied' USING ERRCODE='42501';
  END IF;
  IF p_plan IS NULL OR p_plan NOT IN ('free','pro','elite') THEN
    RAISE EXCEPTION 'invalid_plan' USING ERRCODE='22023';
  END IF;
  SELECT * INTO STRICT l FROM hocalist.marketplace_plan_limits WHERE plan_code=p_plan;
  SELECT * INTO p FROM hocalist.entitlement_policy WHERE singleton;
  SELECT count(*) INTO v_used FROM hocalist.store_listings x
    WHERE x.seller_user_id=u AND x.status='active';
  RETURN jsonb_build_object(
    'plan_code', p_plan,
    'store_listing_limit', l.store_listing_limit,
    'weekly_target_limit', l.weekly_target_limit,
    'active_listings', v_used,
    'over_limit', v_used > l.store_listing_limit,
    'downgrade', jsonb_build_object(
      'policy_configured', p.downgrade_visibility IS NOT NULL,
      'policy', p.downgrade_visibility,
      'unavailable_reason', CASE WHEN p.downgrade_visibility IS NULL
        THEN 'downgrade_policy_unconfigured' END,
      'would_hide_existing', CASE WHEN p.downgrade_visibility='hide_over_limit'
        THEN v_used > l.store_listing_limit END,
      'would_block_new_publishes', CASE WHEN p.downgrade_visibility='keep_existing_block_new'
        THEN v_used > l.store_listing_limit END),
    'annual', jsonb_build_object(
      'available', p.annual_enabled,
      'amount_minor', NULL),
    'trial', jsonb_build_object(
      'available', p.trial_days IS NOT NULL,
      'days', p.trial_days));
END $$;

-- ---------------------------------------------------------------------------
-- Admin configuration command (idempotent, revision-checked, patch semantics)
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.entitlement_admin_command(p_operation text, p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  result jsonb;
  v_tz text;
  existing hocalist.seller_entitlements%ROWTYPE;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_operation IS NULL
     OR p_operation NOT IN ('policy.set','grant.set','grant.clear')
     OR p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':entitlement_admin:'||p_operation||':'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id=u AND operation='entitlement_admin.'||p_operation AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;

  IF p_operation='policy.set' THEN
    IF p_input - ARRAY['earned_pro_threshold','calendar_timezone','paid_overlap','downgrade_visibility',
        'annual_enabled','trial_days','policy_version','expected_revision'] <> '{}'::jsonb THEN
      RAISE EXCEPTION 'invalid_policy' USING ERRCODE='22023';
    END IF;
    v_tz := nullif(btrim(coalesce(p_input->>'calendar_timezone','')),'');
    IF v_tz IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM pg_timezone_names t WHERE t.name=v_tz) THEN
      RAISE EXCEPTION 'invalid_timezone' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.entitlement_policy SET
      earned_pro_threshold=CASE WHEN p_input ? 'earned_pro_threshold'
        THEN (p_input->>'earned_pro_threshold')::integer ELSE earned_pro_threshold END,
      calendar_timezone=CASE WHEN p_input ? 'calendar_timezone' THEN v_tz ELSE calendar_timezone END,
      paid_overlap=CASE WHEN p_input ? 'paid_overlap'
        THEN nullif(p_input->>'paid_overlap','') ELSE paid_overlap END,
      downgrade_visibility=CASE WHEN p_input ? 'downgrade_visibility'
        THEN nullif(p_input->>'downgrade_visibility','') ELSE downgrade_visibility END,
      annual_enabled=CASE WHEN p_input ? 'annual_enabled'
        THEN (p_input->>'annual_enabled')::boolean ELSE annual_enabled END,
      trial_days=CASE WHEN p_input ? 'trial_days'
        THEN nullif(p_input->>'trial_days','')::integer ELSE trial_days END,
      policy_version=CASE WHEN p_input ? 'policy_version'
        THEN coalesce(nullif(btrim(p_input->>'policy_version'),''), policy_version)
        ELSE policy_version END,
      revision=revision+1,
      updated_at=now()
    WHERE singleton
      AND (p_input->'expected_revision' IS NULL
        OR revision=(p_input->>'expected_revision')::bigint);
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    result := jsonb_build_object('singleton',true);
  ELSIF p_operation='grant.set' THEN
    IF p_input - ARRAY['user_id','plan_code','active','expected_revision'] <> '{}'::jsonb
       OR (p_input->>'user_id') IS NULL
       OR (p_input->>'plan_code') IS NULL
       OR (p_input->>'plan_code') NOT IN ('free','pro','elite')
       OR jsonb_typeof(p_input->'active') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION 'invalid_grant' USING ERRCODE='22023';
    END IF;
    SELECT * INTO existing FROM hocalist.seller_entitlements
      WHERE user_id=(p_input->>'user_id')::uuid FOR UPDATE;
    IF FOUND THEN
      IF existing.source<>'admin' THEN
        -- Provider/earned-owned entitlements are never overwritten here.
        RAISE EXCEPTION 'grant_not_admin_owned' USING ERRCODE='P0001';
      END IF;
      IF p_input->'expected_revision' IS NOT NULL
         AND existing.revision<>(p_input->>'expected_revision')::bigint THEN
        RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
      END IF;
      UPDATE hocalist.seller_entitlements SET
        plan_code=p_input->>'plan_code',
        active=(p_input->>'active')::boolean,
        revision=revision+1,
        updated_at=now()
      WHERE user_id=existing.user_id;
    ELSE
      INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source,active)
      VALUES((p_input->>'user_id')::uuid, p_input->>'plan_code','admin',(p_input->>'active')::boolean);
    END IF;
    result := jsonb_build_object('user_id', p_input->>'user_id','plan_code',p_input->>'plan_code');
  ELSE
    IF p_input - ARRAY['user_id','expected_revision'] <> '{}'::jsonb
       OR (p_input->>'user_id') IS NULL THEN
      RAISE EXCEPTION 'invalid_grant' USING ERRCODE='22023';
    END IF;
    SELECT * INTO existing FROM hocalist.seller_entitlements
      WHERE user_id=(p_input->>'user_id')::uuid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'grant_not_found' USING ERRCODE='P0002'; END IF;
    IF existing.source<>'admin' THEN
      RAISE EXCEPTION 'grant_not_admin_owned' USING ERRCODE='P0001';
    END IF;
    IF p_input->'expected_revision' IS NOT NULL
       AND existing.revision<>(p_input->>'expected_revision')::bigint THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    DELETE FROM hocalist.seller_entitlements WHERE user_id=existing.user_id;
    result := jsonb_build_object('user_id', p_input->>'user_id','cleared',true);
  END IF;

  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'entitlement_admin.'||p_operation,p_key,h,result);
  RETURN result;
END $$;

-- ---------------------------------------------------------------------------
-- Capacity enforcement uses the same authoritative resolver
-- ---------------------------------------------------------------------------

-- The reviewed 020/023 helpers read `seller_entitlements` directly, so a
-- verified paid plan, an earned-Pro month, an expiry or a review flag had no
-- effect on the actual Store/targeting admission. These replacements keep the
-- same signatures and call the single authoritative resolver instead. Plan
-- changes never touch immutable deposit-batch pricing.
DO $patch$ BEGIN
  IF to_regprocedure('hocalist.marketplace_seller_plan(uuid)') IS NOT NULL THEN
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION hocalist.marketplace_seller_plan(p_user uuid)
      RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
        SELECT hocalist.entitlement_resolve_internal(p_user)->>'effective_plan';
      $$;
    $sql$;
  END IF;
  IF to_regprocedure('hocalist.marketplace_store_limit(uuid)') IS NOT NULL THEN
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION hocalist.marketplace_store_limit(p_user uuid)
      RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
        SELECT l.store_listing_limit
        FROM hocalist.marketplace_plan_limits l
        WHERE l.plan_code = hocalist.marketplace_seller_plan(p_user);
      $$;
    $sql$;
  END IF;
  IF to_regprocedure('hocalist.marketplace_weekly_target_limit(uuid)') IS NOT NULL THEN
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION hocalist.marketplace_weekly_target_limit(p_user uuid)
      RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
        SELECT l.weekly_target_limit
        FROM hocalist.marketplace_plan_limits l
        WHERE l.plan_code = hocalist.marketplace_seller_plan(p_user);
      $$;
    $sql$;
  END IF;
END $patch$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION
  hocalist.entitlement_readings_internal(uuid),
  hocalist.entitlement_resolve_internal(uuid),
  hocalist.account_entitlement(),
  hocalist.entitlement_plan_preview(text),
  hocalist.entitlement_admin_command(text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.account_entitlement(),
  hocalist.entitlement_plan_preview(text),
  hocalist.entitlement_admin_command(text,text,jsonb) TO authenticated;

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

-- Append-only reversal and dispute correction contracts over the reviewed
-- credit/reward/withdrawal ledgers.
--
-- Boundary held by this migration:
--   * no provider call, no automatic clawback, no physical item refund;
--   * a reversal is opened only by a verified service record, then every
--     fund-moving step is an explicit admin-reviewed decision with an
--     audit event and an idempotency key;
--   * compensation can only debit the causally-linked seller ledger row, never
--     another batch, another seller, or the buyer's unrelated balance;
--   * buyer rewards tied to a reversed sale become held (not withdrawable)
--     only when the reward-hold policy is explicitly configured;
--   * holds and releases are append-only compensating entries; ledger history
--     is never rewritten;
--   * the buyer reward, seller credit and withdrawal ledgers stay separate.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.credit_batches') IS NULL
     OR to_regclass('hocalist.buyer_rewards') IS NULL THEN
    RAISE EXCEPTION 'commercial 090/091 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.withdrawal_requests') IS NULL THEN
    RAISE EXCEPTION 'withdrawals 093 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.payment_reversals') IS NOT NULL THEN
    RAISE EXCEPTION 'reversal contracts already installed';
  END IF;
END $guard$;

-- ---------------------------------------------------------------------------
-- Policy and append-only records
-- ---------------------------------------------------------------------------

-- Both policy settings stay unconfigured/false: the owner has not approved a
-- chargeback clawback rule or a reward-hold effect, so nothing activates until
-- an admin explicitly configures it.
CREATE TABLE hocalist.reversal_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  clawback_mode text CHECK (clawback_mode IS NULL OR clawback_mode IN ('same_batch_only')),
  reward_hold_enabled boolean NOT NULL DEFAULT false,
  reward_hold_days integer CHECK (reward_hold_days IS NULL OR reward_hold_days BETWEEN 1 AND 365),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.reversal_policy(singleton) VALUES (true);

CREATE TABLE hocalist.payment_reversals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_key text NOT NULL CHECK (length(btrim(provider_key)) BETWEEN 1 AND 60),
  provider_reference text NOT NULL CHECK (length(btrim(provider_reference)) BETWEEN 1 AND 200),
  kind text NOT NULL CHECK (kind IN ('chargeback','refund','dispute','correction')),
  scope text NOT NULL CHECK (scope IN ('credit_batch','buyer_reward','withdrawal','subscription')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  currency text NOT NULL DEFAULT 'USD' CHECK (currency ~ '^[A-Z]{3}$'),
  causal_outcome_id uuid REFERENCES hocalist.sale_confirmations(id),
  causal_withdrawal_id uuid REFERENCES hocalist.withdrawal_requests(id),
  causal_user_id uuid REFERENCES hocalist.profiles(id),
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open','held','dismissed','resolved')),
  hold_minor bigint NOT NULL DEFAULT 0 CHECK (hold_minor >= 0),
  -- Face value of the causal reward covered by this decision. It is recorded
  -- for audit even when nothing was recoverable, so an unrecovered shortfall
  -- is never mistaken for an active hold or an implicit debt.
  reversed_face_minor bigint NOT NULL DEFAULT 0 CHECK (reversed_face_minor >= 0),
  shortfall_minor bigint NOT NULL DEFAULT 0 CHECK (shortfall_minor >= 0),
  note text CHECK (note IS NULL OR length(note) <= 500),
  created_by uuid REFERENCES hocalist.profiles(id),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider_key, provider_reference)
);
CREATE INDEX payment_reversals_open
  ON hocalist.payment_reversals(id) WHERE state IN ('open','held');

CREATE TABLE hocalist.ledger_corrections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reversal_id uuid NOT NULL REFERENCES hocalist.payment_reversals(id),
  target_kind text NOT NULL CHECK (target_kind IN ('credit_batch','buyer_reward','withdrawal')),
  target_id uuid NOT NULL,
  entry_kind text NOT NULL CHECK (entry_kind IN
    ('hold','release_hold','compensate','reward_hold','reward_release','reward_reversed')),
  amount_minor bigint NOT NULL CHECK (amount_minor <> 0),
  reserve_delta_minor bigint NOT NULL DEFAULT 0,
  note text CHECK (note IS NULL OR length(note) <= 500),
  actor text NOT NULL CHECK (length(btrim(actor)) BETWEEN 1 AND 60),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (reversal_id, entry_kind, target_id)
);

CREATE TABLE hocalist.reversal_events (
  reversal_id uuid NOT NULL REFERENCES hocalist.payment_reversals(id),
  revision bigint NOT NULL CHECK (revision > 0),
  event text NOT NULL CHECK (length(btrim(event)) BETWEEN 1 AND 60),
  actor text NOT NULL CHECK (length(btrim(actor)) BETWEEN 1 AND 60),
  detail text CHECK (detail IS NULL OR length(detail) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (reversal_id, revision)
);

ALTER TABLE hocalist.reversal_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.payment_reversals ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.ledger_corrections ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.reversal_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.reversal_policy, hocalist.payment_reversals,
  hocalist.ledger_corrections, hocalist.reversal_events
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Verified-source intake (service path only; moves no funds)
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.reversal_open_internal(
  p_provider text, p_reference text, p_kind text, p_scope text, p_amount bigint,
  p_user uuid DEFAULT NULL, p_outcome uuid DEFAULT NULL,
  p_withdrawal uuid DEFAULT NULL, p_note text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r hocalist.payment_reversals%ROWTYPE; n bigint;
BEGIN
  IF p_provider IS NULL OR length(btrim(p_provider)) NOT BETWEEN 1 AND 60
     OR p_reference IS NULL OR length(btrim(p_reference)) NOT BETWEEN 1 AND 200
     OR p_kind IS NULL OR p_kind NOT IN ('chargeback','refund','dispute','correction')
     OR p_scope IS NULL OR p_scope NOT IN ('credit_batch','buyer_reward','withdrawal','subscription')
     OR p_amount IS NULL OR p_amount <= 0
     OR (p_note IS NOT NULL AND length(p_note) > 500) THEN
    RAISE EXCEPTION 'invalid_reversal' USING ERRCODE='22023';
  END IF;
  -- Causal linkage is required: a reversal must name the affected sale,
  -- withdrawal or account, and the withdrawal scope requires its own row.
  IF p_scope='withdrawal' AND p_withdrawal IS NULL THEN
    RAISE EXCEPTION 'causal_withdrawal_required' USING ERRCODE='22023';
  END IF;
  IF p_scope IN ('credit_batch','buyer_reward') AND p_outcome IS NULL THEN
    RAISE EXCEPTION 'causal_outcome_required' USING ERRCODE='22023';
  END IF;
  IF p_scope='subscription' AND p_user IS NULL THEN
    RAISE EXCEPTION 'causal_user_required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_provider||':'||p_reference,901));
  SELECT * INTO r FROM hocalist.payment_reversals
    WHERE provider_key=p_provider AND provider_reference=p_reference;
  IF FOUND THEN
    IF r.kind<>p_kind OR r.scope<>p_scope OR r.amount_minor<>p_amount
       OR r.causal_outcome_id IS DISTINCT FROM p_outcome
       OR r.causal_withdrawal_id IS DISTINCT FROM p_withdrawal THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
    END IF;
    RETURN jsonb_build_object('status',r.state,'reversal_id',r.id,'replayed',true);
  END IF;
  INSERT INTO hocalist.payment_reversals(
    provider_key,provider_reference,kind,scope,amount_minor,causal_outcome_id,
    causal_withdrawal_id,causal_user_id,note)
  VALUES(btrim(p_provider),btrim(p_reference),p_kind,p_scope,p_amount,p_outcome,
    p_withdrawal,p_user,left(p_note,500))
  RETURNING * INTO r;
  INSERT INTO hocalist.reversal_events(reversal_id,revision,event,actor,detail)
    VALUES(r.id,1,'opened','provider',left(coalesce(p_note,'verified provider reversal'),500));
  RETURN jsonb_build_object('status',r.state,'reversal_id',r.id,'replayed',false);
END $$;

-- ---------------------------------------------------------------------------
-- Causal recoverability of one reward
-- ---------------------------------------------------------------------------

-- Conservative, history-based proof of how much of ONE causal reward has not
-- been spent. Account-wide availability is not evidence that this reward is
-- unspent, and a later unrelated reward must never make an older loss
-- recoverable. Withdrawals are assumed to consume every non-causal reward that
-- already existed at the withdrawal's time before they can charge the causal
-- reward; the largest cumulative deficit at any withdrawal is therefore the
-- part of this reward that must have been spent. This is a provability rule
-- for one reward, not a cross-reward allocation or clawback policy: it never
-- charges another reward. It is always combined with the identity-wide
-- conservation ceiling below.
CREATE FUNCTION hocalist.reward_causal_unspent_internal(p_reward uuid)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  w hocalist.buyer_rewards%ROWTYPE;
  v_consumed bigint;
  v_corrections bigint;
BEGIN
  SELECT * INTO STRICT w FROM hocalist.buyer_rewards WHERE id=p_reward;
  SELECT least(w.amount_minor, coalesce(max(d.gap),0)) INTO v_consumed
  FROM (
    SELECT
      (sum(wo.amount_minor) OVER (ORDER BY wo.created_at, wo.id)) -
      (SELECT coalesce(sum(o.amount_minor),0)
         FROM hocalist.buyer_rewards o
         JOIN hocalist.credit_targets tg ON tg.id=o.target_id
        WHERE o.buyer_user_id=w.buyer_user_id AND o.id<>w.id AND tg.status='won'
          AND o.created_at <= wo.created_at) AS gap
    FROM hocalist.withdrawal_requests wo
    WHERE wo.user_id=w.buyer_user_id AND wo.status IN ('processing','paid')
  ) d;
  -- Any prior hold or permanent reversal of this reward already covers part
  -- of the face value.
  SELECT coalesce(sum(c.amount_minor),0) INTO v_corrections
    FROM hocalist.ledger_corrections c
   WHERE c.target_kind='buyer_reward' AND c.target_id=w.id
     AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed');
  RETURN greatest(0, w.amount_minor - coalesce(v_consumed,0) - v_corrections);
END $$;

-- Identity-wide conservation ceiling: every debit of the reward ledger
-- (processing/paid withdrawals plus every reward hold/reversal and withdrawal
-- hold) can never exceed the funds actually earned. A per-reward estimate is
-- only an upper bound on that reward's remainder; the same unspent minor unit
-- must not be recoverable twice through separate causal records, so a hold is
-- additionally capped by this pool.
CREATE FUNCTION hocalist.reward_identity_free_internal(p_user uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT greatest(0,
    coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r
      JOIN hocalist.credit_targets t ON t.id=r.target_id
      WHERE r.buyer_user_id=p_user AND t.status='won'),0)
    - coalesce((SELECT sum(w.amount_minor) FROM hocalist.withdrawal_requests w
      WHERE w.user_id=p_user AND w.status IN ('processing','paid')),0)
    - coalesce((SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
      JOIN hocalist.buyer_rewards w ON w.id=c.target_id
      WHERE c.target_kind='buyer_reward' AND w.buyer_user_id=p_user
        AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed')),0)
    - coalesce((SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
      JOIN hocalist.withdrawal_requests wd ON wd.id=c.target_id
      WHERE c.target_kind='withdrawal' AND wd.user_id=p_user
        AND c.entry_kind IN ('hold','release_hold')),0));
$$;

-- Stable disputed-pool guard. A reward can only ever have been consumed by a
-- withdrawal created at or after that reward, so the pool's membership boundary
-- is the EARLIEST such withdrawal. That boundary is derived from immutable
-- timestamps, so later clean rewards are never pulled into an old pool. Every
-- withdrawal the identity has ever had (processing or paid) is charged against
-- the pool: records cannot prove which reward funded a withdrawal, so a split
-- withdrawal sequence must reduce the pool exactly as one combined withdrawal
-- would. The remaining pool is its rewards minus all withdrawals and the
-- corrections already taken from those rewards. When no withdrawal has touched
-- the reward's era, nothing has consumed it and only its own corrections apply.
-- This remains a conservative provability bound, not a FIFO/allocation policy:
-- when the pool is exhausted (including when records cannot attribute a
-- withdrawal to another reward) the remainder is left as shortfall/manual
-- review rather than inferred.
CREATE FUNCTION hocalist.reward_disputed_pool_free_internal(p_reward uuid)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  w hocalist.buyer_rewards%ROWTYPE;
  v_boundary timestamptz;
  v_pool bigint;
  v_outflow bigint;
  v_corrections bigint;
BEGIN
  SELECT * INTO STRICT w FROM hocalist.buyer_rewards WHERE id=p_reward;
  SELECT min(wo.created_at) INTO v_boundary
    FROM hocalist.withdrawal_requests wo
   WHERE wo.user_id=w.buyer_user_id AND wo.status IN ('processing','paid')
     AND wo.created_at >= w.created_at;
  IF v_boundary IS NULL THEN
    -- No withdrawal since this reward was created: it is clean.
    SELECT coalesce(sum(c.amount_minor),0) INTO v_corrections
      FROM hocalist.ledger_corrections c
     WHERE c.target_kind='buyer_reward' AND c.target_id=w.id
       AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed');
    RETURN greatest(0, w.amount_minor - v_corrections);
  END IF;
  SELECT coalesce(sum(r.amount_minor),0) INTO v_pool
    FROM hocalist.buyer_rewards r
    JOIN hocalist.credit_targets t ON t.id=r.target_id
   WHERE r.buyer_user_id=w.buyer_user_id AND t.status='won'
     AND r.created_at <= v_boundary;
  -- Every withdrawal is charged, split or combined.
  SELECT coalesce(sum(wo.amount_minor),0) INTO v_outflow
    FROM hocalist.withdrawal_requests wo
   WHERE wo.user_id=w.buyer_user_id AND wo.status IN ('processing','paid');
  SELECT coalesce(sum(c.amount_minor),0) INTO v_corrections
    FROM hocalist.ledger_corrections c
    JOIN hocalist.buyer_rewards r ON r.id=c.target_id
   WHERE c.target_kind='buyer_reward' AND r.buyer_user_id=w.buyer_user_id
     AND r.created_at <= v_boundary
     AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed');
  RETURN greatest(0, v_pool - v_outflow - v_corrections);
END $$;

-- ---------------------------------------------------------------------------
-- Admin-reviewed decisions
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.reversal_admin_command(p_operation text, p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  result jsonb;
  r hocalist.payment_reversals%ROWTYPE;
  pol hocalist.reversal_policy%ROWTYPE;
  t hocalist.credit_targets%ROWTYPE;
  w hocalist.buyer_rewards%ROWTYPE;
  wd hocalist.withdrawal_requests%ROWTYPE;
  v_available bigint;
  v_hold bigint;
  v_release bigint;
  v_prior bigint;
  v_recoverable bigint;
  v_shortfall bigint;
  v_face bigint;
  v_face_used bigint;
  v_reversed_amount bigint;
  v_row hocalist.ledger_corrections%ROWTYPE;
  v_event text;
  v_n bigint;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_operation IS NULL OR p_operation NOT IN ('policy.set','reversal.hold','reversal.dismiss','reversal.compensate')
     OR p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':reversal_admin:'||p_operation||':'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id=u AND operation='reversal_admin.'||p_operation AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT * INTO pol FROM hocalist.reversal_policy WHERE singleton;

  IF p_operation='policy.set' THEN
    IF p_input - ARRAY['clawback_mode','reward_hold_enabled','reward_hold_days','expected_revision'] <> '{}'::jsonb THEN
      RAISE EXCEPTION 'invalid_policy' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.reversal_policy SET
      clawback_mode=CASE WHEN p_input ? 'clawback_mode'
        THEN nullif(p_input->>'clawback_mode','') ELSE clawback_mode END,
      reward_hold_enabled=CASE WHEN p_input ? 'reward_hold_enabled'
        THEN (p_input->>'reward_hold_enabled')::boolean ELSE reward_hold_enabled END,
      reward_hold_days=CASE WHEN p_input ? 'reward_hold_days'
        THEN nullif(p_input->>'reward_hold_days','')::integer ELSE reward_hold_days END,
      revision=revision+1, updated_at=now()
    WHERE singleton
      AND (p_input->'expected_revision' IS NULL
        OR revision=(p_input->>'expected_revision')::bigint);
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    result := jsonb_build_object('singleton',true);
  ELSE
    IF (p_input->>'reversal_id') IS NULL THEN
      RAISE EXCEPTION 'invalid_target' USING ERRCODE='22023';
    END IF;
    SELECT * INTO r FROM hocalist.payment_reversals
      WHERE id=(p_input->>'reversal_id')::uuid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'reversal_not_found' USING ERRCODE='P0002'; END IF;
    IF p_input ? 'expected_revision'
       AND r.revision<>(p_input->>'expected_revision')::bigint THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;

    IF p_operation='reversal.hold' THEN
      IF p_input - ARRAY['reversal_id','expected_revision','note'] <> '{}'::jsonb THEN
        RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
      END IF;
      IF r.state<>'open' THEN RAISE EXCEPTION 'reversal_final' USING ERRCODE='P0001'; END IF;
      v_hold := 0;
      IF r.scope='credit_batch' THEN
        IF pol.clawback_mode IS NULL THEN
          RAISE EXCEPTION 'reversal_policy_unconfigured' USING ERRCODE='P0001';
        END IF;
        SELECT ct.* INTO t FROM hocalist.credit_targets ct
          WHERE ct.request_id=(SELECT s.request_id FROM hocalist.sale_confirmations s WHERE s.id=r.causal_outcome_id)
            AND ct.offer_id=(SELECT s.offer_id FROM hocalist.sale_confirmations s WHERE s.id=r.causal_outcome_id)
            AND ct.status='won'
          ORDER BY ct.created_at DESC, ct.id DESC LIMIT 1;
        IF NOT FOUND THEN RAISE EXCEPTION 'causal_batch_not_found' USING ERRCODE='P0001'; END IF;
        PERFORM 1 FROM hocalist.credit_batches WHERE id=t.batch_id FOR UPDATE;
        SELECT greatest(0, balance_minor-reserved_minor) INTO v_available
          FROM hocalist.credit_batches WHERE id=t.batch_id;
        v_hold := least(r.amount_minor, v_available);
        IF v_hold > 0 THEN
          UPDATE hocalist.credit_batches SET reserved_minor=reserved_minor+v_hold WHERE id=t.batch_id;
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'credit_batch',t.batch_id,'hold',v_hold,v_hold,
            left(p_input->>'note',500),'admin');
        END IF;
      ELSIF r.scope='buyer_reward' THEN
        IF NOT pol.reward_hold_enabled THEN
          RAISE EXCEPTION 'reward_hold_policy_unconfigured' USING ERRCODE='P0001';
        END IF;
        SELECT * INTO w FROM hocalist.buyer_rewards WHERE outcome_id=r.causal_outcome_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'causal_reward_not_found' USING ERRCODE='P0001'; END IF;
        -- Serialize every reward-ledger transition for this buyer with the
        -- withdrawal admission path so a hold and a withdrawal cannot spend
        -- the same funds.
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||w.buyer_user_id::text,902));
        -- Bound the hold by the face value not already covered by other
        -- reversal decisions for this reward. Unrecovered shortfalls count
        -- toward the face bound but are never deducted from spendable funds.
        SELECT coalesce(sum(rv2.reversed_face_minor + rv2.hold_minor),0) INTO v_face_used
          FROM hocalist.payment_reversals rv2
          WHERE rv2.scope='buyer_reward' AND rv2.causal_outcome_id=r.causal_outcome_id
            AND rv2.id<>r.id AND rv2.state IN ('held','resolved');
        -- Recoverability is causal: only funds this reward provably still
        -- holds may be reserved. An unrelated reward arriving before, between
        -- or after the decisions can never make an old loss recoverable.
        v_recoverable := hocalist.reward_causal_unspent_internal(w.id);
        -- Conservation: the identity's whole unspent pool and the time-aware
        -- disputed pool also cap the hold, so two causal records can never
        -- recover the same minor unit twice and a post-withdrawal reward is
        -- never consumed by an older loss.
        v_hold := least(
          r.amount_minor,
          greatest(0, w.amount_minor - v_face_used),
          v_recoverable,
          hocalist.reward_identity_free_internal(w.buyer_user_id),
          hocalist.reward_disputed_pool_free_internal(w.id));
        IF v_hold > 0 THEN
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'buyer_reward',w.id,'reward_hold',v_hold,0,
            left(p_input->>'note',500),'admin');
        END IF;
      ELSIF r.scope='withdrawal' THEN
        IF pol.clawback_mode IS NULL THEN
          RAISE EXCEPTION 'reversal_policy_unconfigured' USING ERRCODE='P0001';
        END IF;
        SELECT * INTO wd FROM hocalist.withdrawal_requests WHERE id=r.causal_withdrawal_id;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'causal_withdrawal_not_found' USING ERRCODE='P0001'; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||wd.user_id::text,902));
        v_hold := r.amount_minor;
        INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
          amount_minor,reserve_delta_minor,note,actor)
        VALUES(r.id,'withdrawal',r.causal_withdrawal_id,'hold',v_hold,0,
          left(p_input->>'note',500),'admin');
      ELSE
        v_hold := 0;
      END IF;
      UPDATE hocalist.payment_reversals SET state='held', hold_minor=v_hold,
        shortfall_minor=greatest(0,r.amount_minor-v_hold), note=coalesce(left(p_input->>'note',500),note),
        revision=revision+1, updated_at=now() WHERE id=r.id RETURNING * INTO r;
      SELECT coalesce(max(revision),0)+1 INTO v_n FROM hocalist.reversal_events WHERE reversal_id=r.id;
      INSERT INTO hocalist.reversal_events(reversal_id,revision,event,actor,detail)
        VALUES(r.id,v_n,'held','admin',left(coalesce(p_input->>'note',format('hold %s',v_hold)),500));
      result := jsonb_build_object('reversal_id',r.id,'state',r.state,
        'hold_minor',r.hold_minor,'shortfall_minor',r.shortfall_minor);
    ELSIF p_operation='reversal.dismiss' THEN
      IF p_input - ARRAY['reversal_id','expected_revision','note'] <> '{}'::jsonb THEN
        RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
      END IF;
      IF r.state NOT IN ('open','held') THEN RAISE EXCEPTION 'reversal_final' USING ERRCODE='P0001'; END IF;
      -- Serialize with the buyer's reward-ledger admission path before any
      -- reservation is released.
      PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||x.user_id::text,902))
        FROM (
          SELECT rw.buyer_user_id AS user_id FROM hocalist.ledger_corrections c
            JOIN hocalist.buyer_rewards rw ON rw.id=c.target_id
            WHERE c.reversal_id=r.id AND c.target_kind='buyer_reward'
          UNION
          SELECT wx.user_id FROM hocalist.ledger_corrections c
            JOIN hocalist.withdrawal_requests wx ON wx.id=c.target_id
            WHERE c.reversal_id=r.id AND c.target_kind='withdrawal'
        ) x ORDER BY x.user_id;
      v_release := 0;
      FOR v_row IN SELECT * FROM hocalist.ledger_corrections
          WHERE reversal_id=r.id AND entry_kind='hold' LOOP
        UPDATE hocalist.credit_batches SET reserved_minor=greatest(0,reserved_minor-v_row.reserve_delta_minor)
          WHERE id=v_row.target_id;
        v_release := v_release + v_row.amount_minor;
      END LOOP;
      INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
        amount_minor,reserve_delta_minor,note,actor)
      SELECT r.id, c.target_kind, c.target_id,
        CASE WHEN c.target_kind='buyer_reward' THEN 'reward_release' ELSE 'release_hold' END,
        -c.amount_minor, -c.reserve_delta_minor, 'dismissed', 'admin'
      FROM hocalist.ledger_corrections c
      WHERE c.reversal_id=r.id AND c.entry_kind IN ('hold','reward_hold');
      UPDATE hocalist.payment_reversals SET state='dismissed', hold_minor=0,
        revision=revision+1, updated_at=now()
        WHERE id=r.id RETURNING * INTO r;
      SELECT coalesce(max(revision),0)+1 INTO v_n FROM hocalist.reversal_events WHERE reversal_id=r.id;
      INSERT INTO hocalist.reversal_events(reversal_id,revision,event,actor,detail)
        VALUES(r.id,v_n,'dismissed','admin',left(p_input->>'note',500));
      result := jsonb_build_object('reversal_id',r.id,'state',r.state,'released_minor',v_release);
    ELSE
      -- Compensation is only allowed after an explicit hold decision and only
      -- against the causally-linked ledger row.
      IF p_input - ARRAY['reversal_id','expected_revision','note'] <> '{}'::jsonb THEN
        RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
      END IF;
      IF r.state<>'held' THEN RAISE EXCEPTION 'hold_required_before_compensation' USING ERRCODE='P0001'; END IF;
      IF pol.clawback_mode IS NULL OR pol.clawback_mode<>'same_batch_only' THEN
        RAISE EXCEPTION 'reversal_policy_unconfigured' USING ERRCODE='P0001';
      END IF;
      v_recoverable := 0;
      IF r.scope='credit_batch' THEN
        SELECT ct.* INTO t FROM hocalist.credit_targets ct
          WHERE ct.request_id=(SELECT s.request_id FROM hocalist.sale_confirmations s WHERE s.id=r.causal_outcome_id)
            AND ct.offer_id=(SELECT s.offer_id FROM hocalist.sale_confirmations s WHERE s.id=r.causal_outcome_id)
            AND ct.status='won'
          ORDER BY ct.created_at DESC, ct.id DESC LIMIT 1;
        IF NOT FOUND THEN RAISE EXCEPTION 'causal_batch_not_found' USING ERRCODE='P0001'; END IF;
        PERFORM 1 FROM hocalist.credit_batches WHERE id=t.batch_id FOR UPDATE;
        -- Release this review's hold first so the batch invariant
        -- (balance >= reserved) holds through the compensating debit.
        SELECT coalesce(sum(reserve_delta_minor),0) INTO v_release
          FROM hocalist.ledger_corrections
          WHERE reversal_id=r.id AND entry_kind='hold';
        FOR v_row IN SELECT * FROM hocalist.ledger_corrections
            WHERE reversal_id=r.id AND entry_kind='hold' LOOP
          UPDATE hocalist.credit_batches SET reserved_minor=greatest(0,reserved_minor-v_row.reserve_delta_minor)
            WHERE id=v_row.target_id;
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'credit_batch',v_row.target_id,'release_hold',-v_row.amount_minor,
            -v_row.reserve_delta_minor,'compensation settled','admin')
          ON CONFLICT (reversal_id,entry_kind,target_id) DO NOTHING;
        END LOOP;
        SELECT greatest(0, balance_minor-reserved_minor) INTO v_available
          FROM hocalist.credit_batches WHERE id=t.batch_id;
        v_hold := least(r.amount_minor, v_available);
        IF v_hold > 0 THEN
          UPDATE hocalist.credit_batches SET balance_minor=balance_minor-v_hold WHERE id=t.batch_id;
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'credit_batch',t.batch_id,'compensate',-v_hold,0,
            left(p_input->>'note',500),'admin');
        END IF;
      ELSIF r.scope='buyer_reward' THEN
        SELECT * INTO w FROM hocalist.buyer_rewards WHERE outcome_id=r.causal_outcome_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'causal_reward_not_found' USING ERRCODE='P0001'; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||w.buyer_user_id::text,902));
        -- Face value already applied or reserved by other reversals of this
        -- reward. An unrecovered shortfall counts toward the face bound but is
        -- never deducted from spendable funds.
        SELECT coalesce(sum(rv2.reversed_face_minor + rv2.hold_minor),0) INTO v_face_used
          FROM hocalist.payment_reversals rv2
          WHERE rv2.scope='buyer_reward' AND rv2.causal_outcome_id=r.causal_outcome_id
            AND rv2.id<>r.id AND rv2.state IN ('held','resolved');
        v_face := least(r.amount_minor, greatest(0, w.amount_minor - v_face_used));
        -- The temporary hold is the causal, conservatively proved recoverable
        -- amount. Compensation settles exactly that reservation and never
        -- recomputes an account-wide balance, so an unrelated reward arriving
        -- after the hold cannot be debited. Anything above it stays an
        -- explicit unrecovered shortfall for manual policy.
        SELECT coalesce(sum(cor.amount_minor),0) INTO v_reversed_amount
          FROM hocalist.ledger_corrections cor
         WHERE cor.reversal_id=r.id AND cor.entry_kind='reward_hold';
        v_reversed_amount := least(v_face, v_reversed_amount);
        -- Convert the temporary reservation into a permanent debit: release
        -- the hold, then append the final reversal (append-only, no rewrite).
        FOR v_row IN SELECT * FROM hocalist.ledger_corrections
            WHERE reversal_id=r.id AND entry_kind='reward_hold' LOOP
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'buyer_reward',v_row.target_id,'reward_release',
            -v_row.amount_minor,0,'compensation settled','admin')
          ON CONFLICT (reversal_id,entry_kind,target_id) DO NOTHING;
        END LOOP;
        IF v_reversed_amount > 0 THEN
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'buyer_reward',w.id,'reward_reversed',v_reversed_amount,0,
            left(p_input->>'note',500),'admin')
          ON CONFLICT (reversal_id,entry_kind,target_id) DO NOTHING;
        END IF;
        v_hold := v_reversed_amount;
      ELSE
        -- Withdrawal/subscription corrections stay review records; no reward
        -- or credit balance is silently debited from them. Any logical hold is
        -- released because the review closed.
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||x.user_id::text,902))
          FROM (
            SELECT wx.user_id FROM hocalist.ledger_corrections c
              JOIN hocalist.withdrawal_requests wx ON wx.id=c.target_id
              WHERE c.reversal_id=r.id AND c.target_kind='withdrawal'
          ) x ORDER BY x.user_id;
        v_hold := 0;
        FOR v_row IN SELECT * FROM hocalist.ledger_corrections
            WHERE reversal_id=r.id AND entry_kind='hold' LOOP
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,v_row.target_kind,v_row.target_id,'release_hold',
            -v_row.amount_minor,-v_row.reserve_delta_minor,'review closed','admin')
          ON CONFLICT (reversal_id,entry_kind,target_id) DO NOTHING;
        END LOOP;
      END IF;
      UPDATE hocalist.payment_reversals SET state='resolved', hold_minor=0,
        reversed_face_minor=CASE WHEN r.scope='buyer_reward'
          THEN greatest(0, coalesce(v_face,0)) ELSE 0 END,
        shortfall_minor=CASE WHEN r.scope='buyer_reward'
          THEN greatest(0, coalesce(v_face,0) - coalesce(v_reversed_amount,0))
          ELSE greatest(0, r.amount_minor - coalesce(v_hold,0)) END,
        revision=revision+1, updated_at=now() WHERE id=r.id RETURNING * INTO r;
      SELECT coalesce(max(revision),0)+1 INTO v_n FROM hocalist.reversal_events WHERE reversal_id=r.id;
      INSERT INTO hocalist.reversal_events(reversal_id,revision,event,actor,detail)
        VALUES(r.id,v_n,'resolved','admin',left(coalesce(p_input->>'note',format('compensated %s',v_hold)),500));
      result := jsonb_build_object('reversal_id',r.id,'state',r.state,
        'compensated_minor',greatest(0,coalesce(v_hold,0)),
        'reversed_face_minor',coalesce(r.reversed_face_minor,0),
        'shortfall_minor',r.shortfall_minor);
    END IF;
  END IF;

  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'reversal_admin.'||p_operation,p_key,h,result);
  RETURN result;
END $$;

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------

-- The caller's own holds only. Provider references and admin notes for other
-- accounts are never exposed.
CREATE FUNCTION hocalist.commercial_reversal_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  pol hocalist.reversal_policy%ROWTYPE;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'reversal_access_denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO pol FROM hocalist.reversal_policy WHERE singleton;
  RETURN jsonb_build_object(
    'policy', jsonb_build_object(
      'clawback_mode_configured', pol.clawback_mode IS NOT NULL,
      'clawback_mode', pol.clawback_mode,
      'reward_hold_configured', pol.reward_hold_enabled,
      'reward_hold_days', pol.reward_hold_days,
      'revision', pol.revision),
    'reward_holds', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'reversal_id',rv.id,'kind',rv.kind,'state',rv.state,
        'amount_minor',c.amount_minor,'created_at',c.created_at) ORDER BY c.created_at DESC)
      FROM hocalist.ledger_corrections c
      JOIN hocalist.payment_reversals rv ON rv.id=c.reversal_id
      JOIN hocalist.buyer_rewards w ON w.id=c.target_id
      WHERE c.target_kind='buyer_reward' AND rv.state='held'
        AND c.entry_kind IN ('reward_hold','reward_reversed')
        AND w.buyer_user_id=u),'[]'::jsonb),
    'credit_holds', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'reversal_id',rv.id,'kind',rv.kind,'state',rv.state,
        'amount_minor',c.amount_minor,'reserved_minor',c.reserve_delta_minor,
        'created_at',c.created_at) ORDER BY c.created_at DESC)
      FROM hocalist.ledger_corrections c
      JOIN hocalist.payment_reversals rv ON rv.id=c.reversal_id
      JOIN hocalist.credit_batches b ON b.id=c.target_id
      WHERE c.target_kind='credit_batch' AND rv.state='held'
        AND c.entry_kind='hold' AND b.user_id=u),'[]'::jsonb),
    'withdrawal_holds', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'reversal_id',rv.id,'kind',rv.kind,'state',rv.state,
        'amount_minor',c.amount_minor,'created_at',c.created_at) ORDER BY c.created_at DESC)
      FROM hocalist.ledger_corrections c
      JOIN hocalist.payment_reversals rv ON rv.id=c.reversal_id
      JOIN hocalist.withdrawal_requests wd ON wd.id=c.target_id
      WHERE c.target_kind='withdrawal' AND rv.state='held'
        AND c.entry_kind='hold' AND wd.user_id=u),'[]'::jsonb));
END $$;

CREATE FUNCTION hocalist.admin_reversal_queue(p_limit integer DEFAULT 50, p_cursor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); rows jsonb; next_id uuid;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  WITH found AS (
    SELECT r.id,r.kind,r.scope,r.amount_minor,r.currency,r.state,r.hold_minor,
      r.shortfall_minor,r.causal_outcome_id,r.causal_withdrawal_id,r.causal_user_id,
      r.note,r.created_at,r.updated_at
    FROM hocalist.payment_reversals r
    WHERE r.state IN ('open','held') AND (p_cursor IS NULL OR r.id>p_cursor)
    ORDER BY r.id LIMIT p_limit+1),
  page AS (SELECT * FROM found ORDER BY id LIMIT p_limit)
  SELECT coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',id,'kind',kind,'scope',scope,'amount_minor',amount_minor,'currency',currency,
      'state',state,'hold_minor',hold_minor,'shortfall_minor',shortfall_minor,
      'causal_outcome_id',causal_outcome_id,'causal_withdrawal_id',causal_withdrawal_id,
      'causal_user_id',causal_user_id,'note',note,'created_at',created_at,'updated_at',updated_at)
      ORDER BY id) FROM page),'[]'::jsonb),
    CASE WHEN (SELECT count(*) FROM found)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
    INTO rows,next_id;
  RETURN jsonb_build_object('items',rows,'next_cursor',next_id,
    'open_count',(SELECT count(*) FROM hocalist.payment_reversals WHERE state='open'),
    'held_count',(SELECT count(*) FROM hocalist.payment_reversals WHERE state='held'));
END $$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION
  hocalist.reward_causal_unspent_internal(uuid),
  hocalist.reward_identity_free_internal(uuid),
  hocalist.reward_disputed_pool_free_internal(uuid),
  hocalist.reversal_open_internal(text,text,text,text,bigint,uuid,uuid,uuid,text),
  hocalist.reversal_admin_command(text,text,jsonb),
  hocalist.commercial_reversal_status(),
  hocalist.admin_reversal_queue(integer,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  hocalist.reversal_open_internal(text,text,text,text,bigint,uuid,uuid,uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.commercial_reversal_status(),
  hocalist.reversal_admin_command(text,text,jsonb),
  hocalist.admin_reversal_queue(integer,uuid) TO authenticated;

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

-- Additive commercial reads for the app wallet surfaces.
--
-- These functions expose only server-computed values from the reviewed
-- ledgers (090/091/092/093 and, when present, 180-183). Nothing here is
-- fabricated client-side: availability, weekly quota, holds and reward
-- eligibility are derived from committed rows, and every read is owner-scoped.
--
-- Dependencies are optional on purpose so this file can apply on the reviewed
-- checkpoint without the sibling commercial_completion migrations. When an
-- optional module is absent the corresponding field reports that it is not
-- configured instead of inventing a value.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regprocedure('hocalist.credit_wallet()') IS NULL THEN
    RAISE EXCEPTION 'credit wallet 092 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.reward_wallet()') IS NULL THEN
    RAISE EXCEPTION 'reward wallet 091 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.sale_confirmations') IS NULL THEN
    RAISE EXCEPTION 'outcomes 080 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.commercial_credit_wallet') IS NOT NULL THEN
    RAISE EXCEPTION 'commercial reads already installed';
  END IF;
END $guard$;

-- ---------------------------------------------------------------------------
-- Authoritative reward availability (one rule for wallet, withdrawal, payout)
-- ---------------------------------------------------------------------------

-- Signed ledger corrections that reduce the withdrawable balance for one
-- buyer: temporary reward holds/releases, permanent reward reversals, and
-- withdrawal-scope logical holds/releases. Positive = reserved, negative =
-- released. Policy keeps the corrections inert: nothing is deducted until an
-- admin has configured and applied a reversal.
CREATE FUNCTION hocalist.commercial_reward_hold_minor(p_user uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT coalesce((
    SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
    JOIN hocalist.buyer_rewards w ON w.id=c.target_id
    WHERE c.target_kind='buyer_reward' AND w.buyer_user_id=p_user
      AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed')),0)
    + coalesce((
    SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
    JOIN hocalist.withdrawal_requests wd ON wd.id=c.target_id
    WHERE c.target_kind='withdrawal' AND wd.user_id=p_user
      AND c.entry_kind IN ('hold','release_hold')),0);
$$;

-- Safety correction to the reviewed 093 helper: the original body subtracted
-- only `processing` requests, so a paid withdrawal became withdrawable again.
-- The corrected body keeps the same signature and subtracts processing, paid
-- amounts AND every active/permanent correction, so the wallet projection, the
-- authenticated withdrawal command and payout admission share one rule.
-- Applied only when 093 exists.
DO $patch$ BEGIN
  IF to_regprocedure('hocalist.withdrawal_available_minor(uuid)') IS NOT NULL THEN
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION hocalist.withdrawal_available_minor(p_user uuid)
      RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
        SELECT greatest(0,
          coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r
            JOIN hocalist.credit_targets t ON t.id=r.target_id
            WHERE r.buyer_user_id=p_user AND t.status='won'),0)
          - coalesce((SELECT sum(w.amount_minor) FROM hocalist.withdrawal_requests w
            WHERE w.user_id=p_user AND w.status IN ('processing','paid')),0)
          - hocalist.commercial_reward_hold_minor(p_user));
      $$;
    $sql$;
    REVOKE ALL ON FUNCTION hocalist.withdrawal_available_minor(uuid)
      FROM PUBLIC, anon, authenticated, service_role;
  END IF;
END $patch$;

-- Serialize withdrawal admission with reversal holds for the same buyer, so a
-- hold and a withdrawal cannot both reserve the same funds. Same signature and
-- behavior as the reviewed 093 command; only the ledger lock is added before
-- the existing per-key idempotency lock.
DO $patch$ BEGIN
  IF to_regprocedure('hocalist.withdrawal_request(text,bigint)') IS NOT NULL THEN
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION hocalist.withdrawal_request(p_key text, p_amount_minor bigint)
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
        -- Ledger lock first, then the per-key lock: the hold path takes only
        -- the ledger lock, so this order cannot deadlock.
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||u::text,902));
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
    $sql$;
    REVOKE ALL ON FUNCTION hocalist.withdrawal_request(text,bigint)
      FROM PUBLIC, anon, authenticated, service_role;
    GRANT EXECUTE ON FUNCTION hocalist.withdrawal_request(text,bigint) TO authenticated;
  END IF;
END $patch$;

-- ---------------------------------------------------------------------------
-- Seller credit wallet
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.commercial_credit_wallet()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  v_week date := date_trunc('week', now() AT TIME ZONE 'UTC')::date;
  v_balance bigint;
  v_reserved bigint;
  v_limit integer;
  v_has_reversals boolean := to_regclass('hocalist.ledger_corrections') IS NOT NULL;
BEGIN
  IF u IS NULL OR NOT EXISTS (
      SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id=u AND m.role='seller' AND m.status='active')
     OR EXISTS (SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id=u AND m.status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE='42501';
  END IF;
  -- Same caller-scoped reconciliation as the reviewed wallet: idempotent and
  -- never settles a live accepted meeting.
  PERFORM hocalist.credit_reconcile_internal(u);
  SELECT coalesce(sum(balance_minor),0), coalesce(sum(reserved_minor),0)
    INTO v_balance, v_reserved
  FROM hocalist.credit_batches WHERE user_id=u;
  v_limit := hocalist.marketplace_weekly_target_limit(u);
  RETURN jsonb_build_object(
    'currency','HC',
    'balance_minor',v_balance,
    'reserved_minor',v_reserved,
    'available_minor',greatest(0,v_balance-v_reserved),
    'charged_minor',coalesce((SELECT sum(charged_minor) FROM hocalist.credit_targets
      WHERE user_id=u),0),
    'deposited_minor',coalesce((SELECT sum(original_minor) FROM hocalist.credit_batches
      WHERE user_id=u),0),
    'reversal_hold_minor',CASE WHEN v_has_reversals THEN coalesce((
      SELECT sum(c.reserve_delta_minor) FROM hocalist.ledger_corrections c
      JOIN hocalist.payment_reversals rv ON rv.id=c.reversal_id
      JOIN hocalist.credit_batches b ON b.id=c.target_id
      WHERE c.target_kind='credit_batch' AND b.user_id=u
        AND rv.state='held' AND c.entry_kind='hold'),0) ELSE 0 END,
    'weekly',jsonb_build_object(
      'week_start',v_week,
      'used',(SELECT count(*) FROM hocalist.credit_targets WHERE user_id=u AND week_start=v_week),
      'limit',v_limit),
    'deposit_options',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',id,'amount_minor',amount_minor,'initial_fee_minor',initial_fee_minor,
        'winning_total_minor',winning_total_minor,'rate_version',rate_version,
        'active',active,'revision',revision,'sort_order',sort_order)
        ORDER BY sort_order,amount_minor)
      FROM hocalist.credit_deposit_options WHERE active),'[]'::jsonb),
    'batches',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',b.id,'original_minor',b.original_minor,'balance_minor',b.balance_minor,
        'reserved_minor',b.reserved_minor,
        'available_minor',greatest(0,b.balance_minor-b.reserved_minor),
        'charged_minor',coalesce((SELECT sum(t.charged_minor) FROM hocalist.credit_targets t
          WHERE t.batch_id=b.id),0),
        'initial_fee_minor',b.initial_fee_minor,'winning_total_minor',b.winning_total_minor,
        'rate_version',b.rate_version,'created_at',b.created_at)
        ORDER BY b.created_at,b.id)
      FROM hocalist.credit_batches b WHERE b.user_id=u),'[]'::jsonb),
    'targets',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',t.id,'request_id',t.request_id,'request_title',q.title,'offer_id',t.offer_id,
        'status',t.status,'initial_minor',t.initial_minor,'winning_minor',t.winning_minor,
        'charged_minor',t.charged_minor,'reserved_minor',t.reserved_minor,
        'week_start',t.week_start,'rate_version',t.rate_version,
        'qualified_at',t.qualified_at,'created_at',t.created_at)
        ORDER BY t.created_at DESC,t.id DESC)
      FROM (SELECT * FROM hocalist.credit_targets
        WHERE user_id=u ORDER BY created_at DESC,id DESC LIMIT 50) t
      LEFT JOIN hocalist.requests q ON q.id=t.request_id),'[]'::jsonb),
    'policy',jsonb_build_object(
      'deposit_options_configured',EXISTS(
        SELECT 1 FROM hocalist.credit_deposit_options WHERE active),
      'weekly_limit_resolved',v_limit));
END $$;

-- ---------------------------------------------------------------------------
-- Buyer reward wallet (separate ledger, explicit held/available split)
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.commercial_reward_wallet()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  v_earned bigint;
  v_pending bigint;
  v_holds bigint := 0;
  v_reward_hold bigint := 0;
  v_withdrawal_hold bigint := 0;
  v_reversed bigint := 0;
  v_shortfall bigint := 0;
  v_processing bigint := 0;
  v_paid bigint := 0;
  v_minimum bigint;
  v_fee bigint;
  v_email boolean := false;
  v_phone boolean := false;
  v_has_reversals boolean := to_regclass('hocalist.ledger_corrections') IS NOT NULL;
  v_has_withdrawals boolean := to_regprocedure('hocalist.withdrawal_available_minor(uuid)') IS NOT NULL;
  v_has_payout boolean := to_regclass('hocalist.payout_policy') IS NOT NULL;
  pol hocalist.reward_policy%ROWTYPE;
BEGIN
  IF u IS NULL OR NOT EXISTS (
      SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id=u AND m.role='buyer' AND m.status='active')
     OR EXISTS (SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id=u AND m.status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT coalesce(sum(r.amount_minor),0) INTO v_earned
  FROM hocalist.buyer_rewards r JOIN hocalist.credit_targets t ON t.id=r.target_id
  WHERE r.buyer_user_id=u AND t.status='won';
  SELECT coalesce(sum(r.amount_minor),0) INTO v_pending
  FROM hocalist.buyer_rewards r JOIN hocalist.credit_targets t ON t.id=r.target_id
  WHERE r.buyer_user_id=u AND t.status<>'won';
  IF v_has_reversals THEN
    -- One authoritative deduction rule, shared with withdrawal admission.
    -- Temporary holds and permanent reversals are reported separately so the
    -- per-item rows can be reconciled with the totals.
    v_holds := hocalist.commercial_reward_hold_minor(u);
    SELECT coalesce(sum(c.amount_minor),0) INTO v_reward_hold
    FROM hocalist.ledger_corrections c
    JOIN hocalist.buyer_rewards w ON w.id=c.target_id
    WHERE c.target_kind='buyer_reward' AND w.buyer_user_id=u
      AND c.entry_kind IN ('reward_hold','reward_release');
    SELECT coalesce(sum(c.amount_minor),0) INTO v_withdrawal_hold
    FROM hocalist.ledger_corrections c
    JOIN hocalist.withdrawal_requests wd ON wd.id=c.target_id
    WHERE c.target_kind='withdrawal' AND wd.user_id=u
      AND c.entry_kind IN ('hold','release_hold');
    SELECT coalesce(sum(c.amount_minor),0) INTO v_reversed
    FROM hocalist.ledger_corrections c
    JOIN hocalist.buyer_rewards w ON w.id=c.target_id
    WHERE c.target_kind='buyer_reward' AND w.buyer_user_id=u
      AND c.entry_kind='reward_reversed';
    -- Unrecovered reversal losses are audit history only: they are never an
    -- implicit debt against future or unrelated rewards.
    SELECT coalesce(sum(rv.shortfall_minor),0) INTO v_shortfall
    FROM hocalist.payment_reversals rv
    JOIN hocalist.buyer_rewards w ON w.outcome_id=rv.causal_outcome_id
    WHERE rv.scope='buyer_reward' AND rv.state='resolved' AND w.buyer_user_id=u;
  END IF;
  IF v_has_withdrawals THEN
    SELECT coalesce(sum(w.amount_minor),0) INTO v_processing
    FROM hocalist.withdrawal_requests w WHERE w.user_id=u AND w.status='processing';
    SELECT coalesce(sum(w.amount_minor),0) INTO v_paid
    FROM hocalist.withdrawal_requests w WHERE w.user_id=u AND w.status='paid';
    SELECT minimum_minor, fee_minor INTO v_minimum, v_fee
    FROM hocalist.withdrawal_policy WHERE singleton;
    v_email := (hocalist.contact_verified(u)->>'email_verified')::boolean;
    v_phone := (hocalist.contact_verified(u)->>'phone_verified')::boolean;
  END IF;
  SELECT * INTO pol FROM hocalist.reward_policy WHERE singleton;
  RETURN jsonb_build_object(
    'currency','USD',
    'earned_minor',v_earned,
    'held_minor',greatest(0,v_pending+v_reward_hold+v_withdrawal_hold),
    'pending_minor',v_pending,
    'hold_minor',greatest(0,v_reward_hold),
    'withdrawal_hold_minor',greatest(0,v_withdrawal_hold),
    'reversed_minor',greatest(0,v_reversed),
    'shortfall_minor',greatest(0,v_shortfall),
    'processing_minor',v_processing,
    'paid_minor',v_paid,
    'available_minor',greatest(0,v_earned-v_processing-v_paid-v_holds),
    'reward_policy_configured',FOUND,
    'normal_minor',CASE WHEN FOUND THEN pol.normal_minor END,
    'late_minor',CASE WHEN FOUND THEN pol.late_minor END,
    'late_window_hours',CASE WHEN FOUND THEN pol.late_window_hours END,
    'withdrawal',jsonb_build_object(
      'configured',v_has_withdrawals,
      'minimum_minor',v_minimum,'fee_minor',v_fee,
      'email_verified',v_email,'phone_verified',v_phone),
    'payout',jsonb_build_object(
      'provider_configured',CASE WHEN v_has_payout THEN EXISTS(
        SELECT 1 FROM hocalist.payout_policy WHERE singleton AND provider_key IS NOT NULL) ELSE false END,
      'execution_enabled',CASE WHEN v_has_payout THEN EXISTS(
        SELECT 1 FROM hocalist.payout_policy WHERE singleton AND execution_enabled) ELSE false END,
      'provider_neutral',true),
    'reversal_policy',jsonb_build_object(
      'clawback_mode_configured',CASE WHEN v_has_reversals THEN EXISTS(
        SELECT 1 FROM hocalist.reversal_policy WHERE singleton AND clawback_mode IS NOT NULL) ELSE false END,
      'reward_hold_configured',CASE WHEN v_has_reversals THEN EXISTS(
        SELECT 1 FROM hocalist.reversal_policy WHERE singleton AND reward_hold_enabled) ELSE false END),
    'items',coalesce((SELECT jsonb_agg(x.data ORDER BY x.created_at DESC,x.id DESC) FROM (
      SELECT r.id,r.created_at,jsonb_build_object(
        'id',r.id,'amount_minor',r.amount_minor,'created_at',r.created_at,
        'status',CASE WHEN t.status='won'
          AND coalesce((SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
            WHERE c.target_kind='buyer_reward' AND c.target_id=r.id
              AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed')),0)=0
          THEN 'earned' ELSE 'held' END,
        'hold_minor',CASE WHEN v_has_reversals THEN greatest(0,coalesce((
          SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
          WHERE c.target_kind='buyer_reward' AND c.target_id=r.id
            AND c.entry_kind IN ('reward_hold','reward_release')),0)) ELSE 0 END,
        'reversed_minor',CASE WHEN v_has_reversals THEN greatest(0,coalesce((
          SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
          WHERE c.target_kind='buyer_reward' AND c.target_id=r.id
            AND c.entry_kind='reward_reversed'),0)) ELSE 0 END,
        'shortfall_minor',CASE WHEN v_has_reversals THEN greatest(0,coalesce((
          SELECT sum(rv.shortfall_minor) FROM hocalist.payment_reversals rv
          WHERE rv.scope='buyer_reward' AND rv.state='resolved'
            AND rv.causal_outcome_id=r.outcome_id),0)) ELSE 0 END,
        'item_title',q.title) AS data
      FROM hocalist.buyer_rewards r
      JOIN hocalist.credit_targets t ON t.id=r.target_id
      LEFT JOIN hocalist.sale_confirmations s ON s.id=r.outcome_id
      LEFT JOIN hocalist.requests q ON q.id=s.request_id
      WHERE r.buyer_user_id=u ORDER BY r.created_at DESC,r.id DESC LIMIT 50) x),'[]'::jsonb));
END $$;

-- ---------------------------------------------------------------------------
-- Role-aware sale history and drill-down
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.commercial_sale_history(
  p_before_time timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid := auth.uid(); items jsonb;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501'; END IF;
  IF (p_before_time IS NULL)<>(p_before_id IS NULL) THEN
    RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023';
  END IF;
  SELECT coalesce(jsonb_agg(x.data ORDER BY x.confirmed_at DESC,x.id DESC),'[]'::jsonb)
    INTO items FROM (
    SELECT s.id,s.confirmed_at,jsonb_build_object(
      'id',s.id,'side',CASE WHEN s.buyer_user_id=u THEN 'purchase' ELSE 'sale' END,
      'confirmed_at',s.confirmed_at,'title',q.title,
      'price_minor',r.price_minor,'currency',r.currency_code,
      'reward',CASE WHEN s.buyer_user_id=u THEN jsonb_build_object(
        'amount_minor',rw.amount_minor,
        'status',CASE WHEN rw.id IS NULL THEN 'none'
          WHEN t.status='won' THEN 'earned' ELSE 'held' END,
        'rule_version',rw.rule_version) END,
      'fee',CASE WHEN s.seller_user_id=u THEN jsonb_build_object(
        'status',coalesce(t.status,'none'),
        'charged_minor',coalesce(t.charged_minor,0),
        'winning_minor',coalesce(t.winning_minor,0),
        'rate_version',t.rate_version) END) AS data
    FROM hocalist.sale_confirmations s
    JOIN hocalist.requests q ON q.id=s.request_id
    JOIN hocalist.offers o ON o.id=s.offer_id
    JOIN hocalist.offer_revisions r ON r.id=o.accepted_revision_id
    LEFT JOIN hocalist.buyer_rewards rw ON rw.outcome_id=s.id
    LEFT JOIN hocalist.credit_targets t ON t.id=rw.target_id
    WHERE (s.buyer_user_id=u OR s.seller_user_id=u)
      AND (p_before_time IS NULL OR (s.confirmed_at,s.id)<(p_before_time,p_before_id))
    ORDER BY s.confirmed_at DESC,s.id DESC LIMIT 25) x;
  RETURN jsonb_build_object('items',items);
END $$;

CREATE FUNCTION hocalist.commercial_sale_detail(p_outcome uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  s hocalist.sale_confirmations%ROWTYPE;
  q hocalist.requests%ROWTYPE;
  r hocalist.offer_revisions%ROWTYPE;
  m hocalist.meetings%ROWTYPE;
  ms hocalist.meeting_schedule_revisions%ROWTYPE;
  rw hocalist.buyer_rewards%ROWTYPE;
  t hocalist.credit_targets%ROWTYPE;
  v_reward jsonb;
  v_fee jsonb;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501'; END IF;
  IF p_outcome IS NULL THEN RAISE EXCEPTION 'invalid_outcome' USING ERRCODE='22023'; END IF;
  SELECT * INTO s FROM hocalist.sale_confirmations WHERE id=p_outcome;
  IF NOT FOUND OR (s.buyer_user_id<>u AND s.seller_user_id<>u) THEN
    RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO q FROM hocalist.requests WHERE id=s.request_id;
  SELECT * INTO m FROM hocalist.meetings WHERE id=s.meeting_id;
  SELECT * INTO ms FROM hocalist.meeting_schedule_revisions WHERE id=s.schedule_revision_id;
  SELECT x.* INTO r FROM hocalist.offer_revisions x
    JOIN hocalist.offers o ON o.id=x.offer_id
    WHERE o.id=s.offer_id AND o.accepted_revision_id=x.id;
  SELECT * INTO rw FROM hocalist.buyer_rewards WHERE outcome_id=s.id;
  IF FOUND THEN
    SELECT * INTO t FROM hocalist.credit_targets WHERE id=rw.target_id;
    v_reward := jsonb_build_object(
      'amount_minor',rw.amount_minor,'rule_version',rw.rule_version,
      'status',CASE WHEN t.status='won' THEN 'earned' ELSE 'held' END);
    v_fee := jsonb_build_object(
      'status',coalesce(t.status,'none'),
      'charged_minor',coalesce(t.charged_minor,0),
      'winning_minor',coalesce(t.winning_minor,0),
      'initial_minor',coalesce(t.initial_minor,0),
      'rate_version',t.rate_version);
  END IF;
  RETURN jsonb_build_object(
    'id',s.id,
    'side',CASE WHEN s.buyer_user_id=u THEN 'purchase' ELSE 'sale' END,
    'confirmed_at',s.confirmed_at,
    'request_id',s.request_id,'offer_id',s.offer_id,'meeting_id',s.meeting_id,
    'title',q.title,'description',q.description,
    'price_minor',r.price_minor,'currency',r.currency_code,
    'schedule',jsonb_build_object(
      'date',ms.schedule_date,'time',ms.schedule_time,'timezone',ms.schedule_timezone,
      'place_choice',ms.place_choice,'place_label',ms.place_label,
      'meeting_expires_at',m.meeting_expires_at),
    'reward',v_reward,
    'fee',v_fee,
    'item_payment','offline');
END $$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION
  hocalist.commercial_reward_hold_minor(uuid),
  hocalist.commercial_credit_wallet(),
  hocalist.commercial_reward_wallet(),
  hocalist.commercial_sale_history(timestamptz,uuid),
  hocalist.commercial_sale_detail(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  hocalist.commercial_credit_wallet(),
  hocalist.commercial_reward_wallet(),
  hocalist.commercial_sale_history(timestamptz,uuid),
  hocalist.commercial_sale_detail(uuid) TO authenticated;
DO $verify$ DECLARE f oid; r text; priv text; BEGIN
f:=to_regprocedure('hocalist.account_entitlement()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'d450c9edba2157fd2ddd4c6384073911' THEN RAISE EXCEPTION 'Function drift: hocalist.account_entitlement()'; END IF;
f:=to_regprocedure('hocalist.entitlement_plan_preview(text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'407096aaae03273706eb5ec5b5e4d5e6' THEN RAISE EXCEPTION 'Function drift: hocalist.entitlement_plan_preview(text)'; END IF;
f:=to_regprocedure('hocalist.entitlement_admin_command(text,text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'087a5fe51cf6f5196405dfff871872ae' THEN RAISE EXCEPTION 'Function drift: hocalist.entitlement_admin_command(text,text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.reconciliation_admin_command(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'bc0267d3180894673297ed4444cd3bdd' THEN RAISE EXCEPTION 'Function drift: hocalist.reconciliation_admin_command(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.admin_reconciliation_overview(integer)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'e2bda02bd8af9dfd6dd649ddef188082' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_reconciliation_overview(integer)'; END IF;
f:=to_regprocedure('hocalist.reversal_admin_command(text,text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'51f17edd3e667eedc6bb0b0143d1d13b' THEN RAISE EXCEPTION 'Function drift: hocalist.reversal_admin_command(text,text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.commercial_reversal_status()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'5f6257f419f9ad9076717a52531f9ae0' THEN RAISE EXCEPTION 'Function drift: hocalist.commercial_reversal_status()'; END IF;
f:=to_regprocedure('hocalist.admin_reversal_queue(integer,uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'f52c48105d3dfbc809a5ba9eaf3fa712' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_reversal_queue(integer,uuid)'; END IF;
f:=to_regprocedure('hocalist.payout_admin_command(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'527e2bd679863e0e172f78a80fdc3ce2' THEN RAISE EXCEPTION 'Function drift: hocalist.payout_admin_command(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.admin_payout_reconciliation_queue(integer)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'52f36b6c1d1a95dfacf18f0a4ad2aca0' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_payout_reconciliation_queue(integer)'; END IF;
f:=to_regprocedure('hocalist.commercial_credit_wallet()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'12c2ea1d41670ef89445acaac6f37813' THEN RAISE EXCEPTION 'Function drift: hocalist.commercial_credit_wallet()'; END IF;
f:=to_regprocedure('hocalist.commercial_reward_wallet()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'542748f5266ebda37c3c7a845782cc3f' THEN RAISE EXCEPTION 'Function drift: hocalist.commercial_reward_wallet()'; END IF;
f:=to_regprocedure('hocalist.commercial_sale_history(timestamptz,uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'18cf345be2ca3b942fe1958153a021c2' THEN RAISE EXCEPTION 'Function drift: hocalist.commercial_sale_history(timestamptz,uuid)'; END IF;
f:=to_regprocedure('hocalist.commercial_sale_detail(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'aa5ac9478d4bfdae5803781e6e54d28f' THEN RAISE EXCEPTION 'Function drift: hocalist.commercial_sale_detail(uuid)'; END IF;
f:=to_regprocedure('hocalist.commercial_reconcile_sweep(integer,text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'50c1634201d09ef1c9db2a6b6f789cfa' THEN RAISE EXCEPTION 'Function drift: hocalist.commercial_reconcile_sweep(integer,text)'; END IF;
f:=to_regprocedure('hocalist.reversal_open_internal(text,text,text,text,bigint,uuid,uuid,uuid,text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'b4206f02e311e75cbf1bd1e5d379e682' THEN RAISE EXCEPTION 'Function drift: hocalist.reversal_open_internal(text,text,text,text,bigint,uuid,uuid,uuid,text)'; END IF;
f:=to_regprocedure('hocalist.payout_claim_internal(integer,text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'568078d6d661ec42ba0e6ac522f8d1ae' THEN RAISE EXCEPTION 'Function drift: hocalist.payout_claim_internal(integer,text)'; END IF;
f:=to_regprocedure('hocalist.payout_lease_expire_internal(integer)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c0ff76a842e3fca86a8de52d80845b11' THEN RAISE EXCEPTION 'Function drift: hocalist.payout_lease_expire_internal(integer)'; END IF;
f:=to_regprocedure('hocalist.payout_reconcile_batch_internal(integer)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'2191ab2731b500d072a06192e4550a69' THEN RAISE EXCEPTION 'Function drift: hocalist.payout_reconcile_batch_internal(integer)'; END IF;
f:=to_regprocedure('hocalist.payout_settle_internal(uuid,text,text,text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'cd84d7526efebb5f0dc0fb821e286c49' THEN RAISE EXCEPTION 'Function drift: hocalist.payout_settle_internal(uuid,text,text,text)'; END IF;
f:=to_regprocedure('hocalist.payout_poll_batch_internal(integer)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'a0bc9258fb22d17036dd27082dfb8fdd' THEN RAISE EXCEPTION 'Function drift: hocalist.payout_poll_batch_internal(integer)'; END IF;
f:=to_regprocedure('hocalist.entitlement_readings_internal(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c896e9ddafc32452ec0785933f0f4549' THEN RAISE EXCEPTION 'Function drift: hocalist.entitlement_readings_internal(uuid)'; END IF;
f:=to_regprocedure('hocalist.entitlement_resolve_internal(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'ee68dc39b4738e2114af75b53823db78' THEN RAISE EXCEPTION 'Function drift: hocalist.entitlement_resolve_internal(uuid)'; END IF;
f:=to_regprocedure('hocalist.credit_reconcile_target_internal(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'9237c1b055eabdec4735430d07f3e99f' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_reconcile_target_internal(uuid)'; END IF;
f:=to_regprocedure('hocalist.withdrawal_available_minor(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'b2256f979f94bc7a55347ee9777cb725' THEN RAISE EXCEPTION 'Function drift: hocalist.withdrawal_available_minor(uuid)'; END IF;
f:=to_regprocedure('hocalist.commercial_reward_hold_minor(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'709399b963fee7b45077d7fd636f0996' THEN RAISE EXCEPTION 'Function drift: hocalist.commercial_reward_hold_minor(uuid)'; END IF;
f:=to_regprocedure('hocalist.reward_causal_unspent_internal(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'a839fa2373b394f3ef7d90ff728af487' THEN RAISE EXCEPTION 'Function drift: hocalist.reward_causal_unspent_internal(uuid)'; END IF;
f:=to_regprocedure('hocalist.reward_identity_free_internal(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'9ba80b02aa1c8411ed2e23220d5a1cc8' THEN RAISE EXCEPTION 'Function drift: hocalist.reward_identity_free_internal(uuid)'; END IF;
f:=to_regprocedure('hocalist.reward_disputed_pool_free_internal(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'8c3efe6ac214bac90fe3137b082aeb70' THEN RAISE EXCEPTION 'Function drift: hocalist.reward_disputed_pool_free_internal(uuid)'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.entitlement_policy')),false) THEN RAISE EXCEPTION 'Missing RLS: entitlement_policy'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.entitlement_policy',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: entitlement_policy % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.reconciliation_policy')),false) THEN RAISE EXCEPTION 'Missing RLS: reconciliation_policy'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.reconciliation_policy',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: reconciliation_policy % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.reconciliation_runs')),false) THEN RAISE EXCEPTION 'Missing RLS: reconciliation_runs'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.reconciliation_runs',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: reconciliation_runs % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.reversal_policy')),false) THEN RAISE EXCEPTION 'Missing RLS: reversal_policy'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.reversal_policy',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: reversal_policy % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.payment_reversals')),false) THEN RAISE EXCEPTION 'Missing RLS: payment_reversals'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.payment_reversals',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: payment_reversals % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.ledger_corrections')),false) THEN RAISE EXCEPTION 'Missing RLS: ledger_corrections'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.ledger_corrections',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: ledger_corrections % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.reversal_events')),false) THEN RAISE EXCEPTION 'Missing RLS: reversal_events'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.reversal_events',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: reversal_events % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.payout_policy')),false) THEN RAISE EXCEPTION 'Missing RLS: payout_policy'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.payout_policy',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: payout_policy % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.payout_attempts')),false) THEN RAISE EXCEPTION 'Missing RLS: payout_attempts'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.payout_attempts',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: payout_attempts % %',r,priv; END IF; END LOOP; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.account_entitlement()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.account_entitlement() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.entitlement_plan_preview(text)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.entitlement_plan_preview(text) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.entitlement_admin_command(text,text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.entitlement_admin_command(text,text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.reconciliation_admin_command(text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.reconciliation_admin_command(text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_reconciliation_overview(integer)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_reconciliation_overview(integer) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.reversal_admin_command(text,text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.reversal_admin_command(text,text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.commercial_reversal_status()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.commercial_reversal_status() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_reversal_queue(integer,uuid)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_reversal_queue(integer,uuid) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.payout_admin_command(text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.payout_admin_command(text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_payout_reconciliation_queue(integer)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_payout_reconciliation_queue(integer) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.commercial_credit_wallet()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.commercial_credit_wallet() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.commercial_reward_wallet()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.commercial_reward_wallet() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.commercial_sale_history(timestamptz,uuid)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.commercial_sale_history(timestamptz,uuid) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.commercial_sale_detail(uuid)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.commercial_sale_detail(uuid) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.commercial_reconcile_sweep(integer,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: hocalist.commercial_reconcile_sweep(integer,text)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.commercial_reconcile_sweep(integer,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.commercial_reconcile_sweep(integer,text)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.reversal_open_internal(text,text,text,text,bigint,uuid,uuid,uuid,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: hocalist.reversal_open_internal(text,text,text,text,bigint,uuid,uuid,uuid,text)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.reversal_open_internal(text,text,text,text,bigint,uuid,uuid,uuid,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.reversal_open_internal(text,text,text,text,bigint,uuid,uuid,uuid,text)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.payout_claim_internal(integer,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: hocalist.payout_claim_internal(integer,text)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.payout_claim_internal(integer,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.payout_claim_internal(integer,text)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.payout_lease_expire_internal(integer)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: hocalist.payout_lease_expire_internal(integer)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.payout_lease_expire_internal(integer)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.payout_lease_expire_internal(integer)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.payout_reconcile_batch_internal(integer)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: hocalist.payout_reconcile_batch_internal(integer)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.payout_reconcile_batch_internal(integer)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.payout_reconcile_batch_internal(integer)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.payout_settle_internal(uuid,text,text,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: hocalist.payout_settle_internal(uuid,text,text,text)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.payout_settle_internal(uuid,text,text,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.payout_settle_internal(uuid,text,text,text)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.payout_poll_batch_internal(integer)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: hocalist.payout_poll_batch_internal(integer)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.payout_poll_batch_internal(integer)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.payout_poll_batch_internal(integer)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.entitlement_readings_internal(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Internal helper exposed: hocalist.entitlement_readings_internal(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.entitlement_resolve_internal(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Internal helper exposed: hocalist.entitlement_resolve_internal(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.credit_reconcile_target_internal(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Internal helper exposed: hocalist.credit_reconcile_target_internal(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.withdrawal_available_minor(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Internal helper exposed: hocalist.withdrawal_available_minor(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.commercial_reward_hold_minor(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Internal helper exposed: hocalist.commercial_reward_hold_minor(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.reward_causal_unspent_internal(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Internal helper exposed: hocalist.reward_causal_unspent_internal(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.reward_identity_free_internal(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Internal helper exposed: hocalist.reward_identity_free_internal(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.reward_disputed_pool_free_internal(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Internal helper exposed: hocalist.reward_disputed_pool_free_internal(uuid)'; END IF; END LOOP;
END $verify$;
COMMIT;

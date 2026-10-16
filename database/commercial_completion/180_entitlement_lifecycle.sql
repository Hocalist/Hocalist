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
BEGIN;
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
COMMIT;

BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
DO $guard$ BEGIN
IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_assert_admin(uuid)')),chr(13),''))<>'21180e7020200a2d299930b9f72e519f' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_assert_admin(uuid)'; END IF;
IF to_regprocedure('hocalist.credit_admin_command(text,text,jsonb)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.credit_admin_command(text,text,jsonb)')),chr(13),''))<>'0a33275e2a20239aad8e3d4f3fbcc07c' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.credit_admin_command(text,text,jsonb)'; END IF;
IF to_regprocedure('hocalist.admin_trust_command(text,text,jsonb)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.admin_trust_command(text,text,jsonb)')),chr(13),''))<>'7ff01a309889845ad833d753d2609241' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.admin_trust_command(text,text,jsonb)'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='credit_deposit_options' AND column_name='revision') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.credit_deposit_options.revision'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='credit_deposit_options' AND column_name='sort_order') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.credit_deposit_options.sort_order'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='credit_deposit_options' AND column_name='rate_version') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.credit_deposit_options.rate_version'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='reward_policy' AND column_name='late_window_hours') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.reward_policy.late_window_hours'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='reward_policy' AND column_name='rule_version') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.reward_policy.rule_version'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='stripe_test_inbox' AND column_name='attempts') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.stripe_test_inbox.attempts'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='stripe_test_inbox' AND column_name='available_at') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.stripe_test_inbox.available_at'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='stripe_test_inbox' AND column_name='last_error') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.stripe_test_inbox.last_error'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='verification_submissions' AND column_name='evidence_media_ids') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.verification_submissions.evidence_media_ids'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='verification_submissions' AND column_name='revision') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.verification_submissions.revision'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='account_restrictions' AND column_name='revision') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.account_restrictions.revision'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='account_restrictions' AND column_name='revoked_by') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.account_restrictions.revoked_by'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='restriction_appeals' AND column_name='revision') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.restriction_appeals.revision'; END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='withdrawal_events' AND column_name='actor') THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.withdrawal_events.actor'; END IF;
IF to_regprocedure('hocalist.admin_commercial_config()') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.admin_commercial_config()'; END IF;
IF to_regprocedure('hocalist.admin_review_queue(integer,text,text,text,text,text,text)') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.admin_review_queue(integer,text,text,text,text,text,text)'; END IF;
IF to_regprocedure('hocalist.admin_evidence_reference(uuid,uuid)') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.admin_evidence_reference(uuid,uuid)'; END IF;
IF to_regprocedure('hocalist.admin_failed_events(integer,text,text,text)') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.admin_failed_events(integer,text,text,text)'; END IF;
IF to_regprocedure('hocalist.admin_failed_event_detail(text)') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.admin_failed_event_detail(text)'; END IF;
IF to_regprocedure('hocalist.admin_audit_feed(integer,text,text,uuid,text)') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.admin_audit_feed(integer,text,text,uuid,text)'; END IF;
END $guard$;
-- Additive administrator-only read of the admin-managed commercial
-- configuration (160, draft).
--
-- Exposes exactly the two reviewed configuration sources an authorized admin
-- edits through the existing `credit_admin_command`:
--   * `credit_deposit_options` including retired rows and revisions, so an
--     editor can carry the current revision and show an honest empty state;
--   * the singleton `reward_policy`, or JSON null when it has never been
--     configured (never an invented default).
--
-- Read-only: this file seeds nothing, activates nothing and reprices no batch.
-- Historical batches keep their immutable rate snapshot regardless of edits.
--
-- Not an instruction to apply to a live project. Generate a guarded rollout
-- bundle and obtain coordinating review before applying.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $admin_commercial_config_guard$
BEGIN
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL
     OR to_regprocedure('hocalist.credit_admin_command(text,text,jsonb)') IS NULL
     OR to_regclass('hocalist.credit_deposit_options') IS NULL
     OR to_regclass('hocalist.reward_policy') IS NULL THEN
    RAISE EXCEPTION 'Admin commercial configuration requires the credit settlement contract';
  END IF;
  IF to_regprocedure('hocalist.admin_commercial_config()') IS NOT NULL THEN
    RAISE EXCEPTION 'Admin commercial configuration read already exists; review before replacement';
  END IF;
END
$admin_commercial_config_guard$;

CREATE FUNCTION hocalist.admin_commercial_config()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_options jsonb;
  v_policy jsonb;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  -- Every option, active or retired, with its revision. No fee rate is
  -- inferred or defaulted anywhere in this projection.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id,
      'amount_minor', o.amount_minor,
      'initial_fee_minor', o.initial_fee_minor,
      'winning_total_minor', o.winning_total_minor,
      'rate_version', o.rate_version,
      'active', o.active,
      'sort_order', o.sort_order,
      'revision', o.revision,
      'updated_at', o.updated_at
    ) ORDER BY o.sort_order, o.amount_minor, o.id), '[]'::jsonb)
    INTO v_options
    FROM hocalist.credit_deposit_options o;

  SELECT jsonb_build_object(
      'normal_minor', p.normal_minor,
      'late_minor', p.late_minor,
      'late_window_hours', p.late_window_hours,
      'rule_version', p.rule_version,
      'revision', p.revision,
      'updated_at', p.updated_at)
    INTO v_policy
    FROM hocalist.reward_policy p WHERE p.singleton;

  RETURN jsonb_build_object(
    'deposit_options', v_options,
    'reward_policy', coalesce(v_policy, 'null'::jsonb));
END; $$;

REVOKE ALL ON FUNCTION hocalist.admin_commercial_config()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_commercial_config() TO authenticated;

DO $hocalist_admin_commercial_config_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT has_function_privilege('authenticated','hocalist.admin_commercial_config()','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_commercial_config()','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_commercial_config()','EXECUTE') THEN
    v_issues := array_append(v_issues, 'admin commercial configuration grants are wrong');
  END IF;
  IF has_table_privilege('authenticated','hocalist.credit_deposit_options','SELECT')
     OR has_table_privilege('authenticated','hocalist.reward_policy','SELECT')
     OR has_table_privilege('anon','hocalist.credit_deposit_options','SELECT')
     OR has_table_privilege('service_role','hocalist.credit_deposit_options','SELECT') THEN
    v_issues := array_append(v_issues, 'private commercial configuration became client-readable');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist admin commercial configuration post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_admin_commercial_config_postapply$;

-- Additive administrator-only review queue with carried revisions, filters and
-- keyset pagination (161, draft).
--
-- The deployed 120 `admin_trust_queue` exposes restrictions and appeals
-- without their current `revision`, so a decision form cannot safely carry the
-- optimistic-concurrency value the reviewed `admin_trust_command` requires.
-- This read adds the missing revisions plus the bounded evidence media
-- references the admin evidence gateway needs, and it makes each queue
-- reachable: newest-first keyset pagination, an actionable-state filter per
-- section and a deterministic tie-break, so completed records can never hide
-- pending work behind a fixed limit.
--
-- Read-only: every decision still goes through `admin_trust_command`.
--
-- Not an instruction to apply to a live project. Generate a guarded rollout
-- bundle and obtain coordinating review before applying.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $admin_review_queue_guard$
BEGIN
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL
     OR to_regprocedure('hocalist.admin_trust_command(text,text,jsonb)') IS NULL
     OR to_regclass('hocalist.verification_submissions') IS NULL
     OR to_regclass('hocalist.account_restrictions') IS NULL
     OR to_regclass('hocalist.restriction_appeals') IS NULL
     OR to_regclass('hocalist.health_review_notes') IS NULL
     OR to_regclass('hocalist.support_cases') IS NULL THEN
    RAISE EXCEPTION 'Admin review queue requires the deployed trust review contract';
  END IF;
  IF to_regprocedure('hocalist.admin_review_queue(integer,text,text,text,text,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Admin review queue read already exists; review before replacement';
  END IF;
END
$admin_review_queue_guard$;

CREATE FUNCTION hocalist.admin_review_queue(
  p_limit integer DEFAULT 50,
  p_verifications_cursor text DEFAULT NULL,
  p_health_cursor text DEFAULT NULL,
  p_restrictions_cursor text DEFAULT NULL,
  p_verification_status text DEFAULT NULL,
  p_health_state text DEFAULT NULL,
  p_restriction_status text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  n integer;
  vc_micros bigint;
  vc_id uuid;
  hc_micros bigint;
  hc_id uuid;
  rc_micros bigint;
  rc_id uuid;
  v_items jsonb;
  v_more boolean;
  v_next text;
  h_items jsonb;
  h_more boolean;
  h_next text;
  r_items jsonb;
  r_more boolean;
  r_next text;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
     OR (p_verification_status IS NOT NULL AND p_verification_status NOT IN ('pending','approved','rejected'))
     OR (p_health_state IS NOT NULL AND p_health_state NOT IN ('needs_review','reviewed'))
     OR (p_restriction_status IS NOT NULL AND p_restriction_status NOT IN ('active','revoked'))
     OR (p_verifications_cursor IS NOT NULL AND p_verifications_cursor !~ '^[0-9]{1,20}\|[0-9a-f-]{36}$')
     OR (p_health_cursor IS NOT NULL AND p_health_cursor !~ '^[0-9]{1,20}\|[0-9a-f-]{36}$')
     OR (p_restrictions_cursor IS NOT NULL AND p_restrictions_cursor !~ '^[0-9]{1,20}\|[0-9a-f-]{36}$') THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  n := p_limit;
  IF p_verifications_cursor IS NOT NULL THEN
    vc_micros := (split_part(p_verifications_cursor, '|', 1))::bigint;
    vc_id := split_part(p_verifications_cursor, '|', 2)::uuid;
  END IF;
  IF p_health_cursor IS NOT NULL THEN
    hc_micros := (split_part(p_health_cursor, '|', 1))::bigint;
    hc_id := split_part(p_health_cursor, '|', 2)::uuid;
  END IF;
  IF p_restrictions_cursor IS NOT NULL THEN
    rc_micros := (split_part(p_restrictions_cursor, '|', 1))::bigint;
    rc_id := split_part(p_restrictions_cursor, '|', 2)::uuid;
  END IF;

  -- Verification submissions: newest first, filtered by decision state.
  -- Evidence references are the reviewer gateway's input only and stay
  -- bounded; no URL, storage path or credential is exposed.
  WITH source AS (
    SELECT v.*, (extract(epoch FROM v.created_at) * 1000000)::bigint AS micros
    FROM hocalist.verification_submissions v
    WHERE p_verification_status IS NULL OR v.status = p_verification_status
  ), windowed AS (
    SELECT * FROM source
    WHERE p_verifications_cursor IS NULL OR (micros, id) < (vc_micros, vc_id)
    ORDER BY micros DESC, id DESC
    LIMIT n + 1
  ), visible AS (
    SELECT * FROM windowed ORDER BY micros DESC, id DESC LIMIT n
  )
  SELECT
    coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id', v.id,
      'user_id', v.user_id,
      'kind', v.kind,
      'note', v.note,
      'evidence_media_ids', coalesce((
        SELECT jsonb_agg(media_id ORDER BY ordinality)
        FROM jsonb_array_elements_text(v.evidence_media_ids) WITH ORDINALITY AS e(media_id, ordinality)
        WHERE ordinality <= 8), '[]'::jsonb),
      'evidence_count', jsonb_array_length(v.evidence_media_ids),
      'status', v.status,
      'revision', v.revision,
      'created_at', v.created_at,
      'decision_reason', v.decision_reason
    ) ORDER BY v.micros DESC, v.id DESC) FROM visible v), '[]'::jsonb),
    (SELECT count(*) > n FROM windowed),
    (SELECT v.micros::text || '|' || v.id FROM visible v
      ORDER BY v.micros ASC, v.id ASC LIMIT 1)
    INTO v_items, v_more, v_next;

  -- Health cases (safety/deal reports): newest first, optionally only cases
  -- without a recorded review or only reviewed cases.
  WITH source AS (
    SELECT q.id, q.reason_code, q.status, q.body, q.created_at,
      (extract(epoch FROM q.created_at) * 1000000)::bigint AS micros,
      h.decision, h.reason
    FROM hocalist.support_cases q
    LEFT JOIN hocalist.health_review_notes h ON h.case_id = q.id
    WHERE q.reason_code IN ('safety','deal')
      AND (p_health_state IS NULL
        OR (p_health_state = 'needs_review' AND h.case_id IS NULL)
        OR (p_health_state = 'reviewed' AND h.case_id IS NOT NULL))
  ), windowed AS (
    SELECT * FROM source
    WHERE p_health_cursor IS NULL OR (micros, id) < (hc_micros, hc_id)
    ORDER BY micros DESC, id DESC
    LIMIT n + 1
  ), visible AS (
    SELECT * FROM windowed ORDER BY micros DESC, id DESC LIMIT n
  )
  SELECT
    coalesce((SELECT jsonb_agg(jsonb_build_object(
      'case_id', q.id,
      'reason_code', q.reason_code,
      'status', q.status,
      'body', q.body,
      'created_at', q.created_at,
      'decision', q.decision,
      'decision_reason', q.reason
    ) ORDER BY q.micros DESC, q.id DESC) FROM visible q), '[]'::jsonb),
    (SELECT count(*) > n FROM windowed),
    (SELECT q.micros::text || '|' || q.id FROM visible q
      ORDER BY q.micros ASC, q.id ASC LIMIT 1)
    INTO h_items, h_more, h_next;

  -- Current restriction revision and, when an appeal exists, its own
  -- revision, so revoke and appeal decisions carry the committed value.
  WITH source AS (
    SELECT r.*, a.id AS appeal_id, a.status AS appeal_status, a.revision AS appeal_revision,
      (extract(epoch FROM r.created_at) * 1000000)::bigint AS micros
    FROM hocalist.account_restrictions r
    LEFT JOIN LATERAL (
      SELECT id, status, revision FROM hocalist.restriction_appeals x
      WHERE x.restriction_id = r.id
    ) a ON true
    WHERE p_restriction_status IS NULL OR r.status = p_restriction_status
  ), windowed AS (
    SELECT * FROM source
    WHERE p_restrictions_cursor IS NULL OR (micros, id) < (rc_micros, rc_id)
    ORDER BY micros DESC, id DESC
    LIMIT n + 1
  ), visible AS (
    SELECT * FROM windowed ORDER BY micros DESC, id DESC LIMIT n
  )
  SELECT
    coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id', r.id,
      'user_id', r.user_id,
      'scope', r.scope,
      'reason', r.reason,
      'source', r.source,
      'status', r.status,
      'revision', r.revision,
      'created_at', r.created_at,
      'appeal_id', r.appeal_id,
      'appeal_status', r.appeal_status,
      'appeal_revision', r.appeal_revision
    ) ORDER BY r.micros DESC, r.id DESC) FROM visible r), '[]'::jsonb),
    (SELECT count(*) > n FROM windowed),
    (SELECT r.micros::text || '|' || r.id FROM visible r
      ORDER BY r.micros ASC, r.id ASC LIMIT 1)
    INTO r_items, r_more, r_next;

  RETURN jsonb_build_object(
    'verifications', jsonb_build_object(
      'items', v_items,
      'next_cursor', CASE WHEN v_more THEN v_next ELSE NULL END),
    'health_reviews', jsonb_build_object(
      'items', h_items,
      'next_cursor', CASE WHEN h_more THEN h_next ELSE NULL END),
    'restrictions', jsonb_build_object(
      'items', r_items,
      'next_cursor', CASE WHEN r_more THEN r_next ELSE NULL END),
    'single_report_penalty', false);
END; $$;

-- Narrow reference check for the admin evidence gateway. Confirms that the
-- requested media reference belongs to one reviewable submission before any
-- accounts/media gateway is asked for a URL. Returns the reference match only:
-- no URL, no storage path and no media metadata.
CREATE FUNCTION hocalist.admin_evidence_reference(p_submission uuid, p_media uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v hocalist.verification_submissions%ROWTYPE;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF p_submission IS NULL OR p_media IS NULL THEN
    RAISE EXCEPTION 'invalid_admin_query' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v FROM hocalist.verification_submissions WHERE id = p_submission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission_not_found' USING ERRCODE='P0002';
  END IF;
  RETURN jsonb_build_object(
    'submission_id', v.id,
    'status', v.status,
    'reference_ok', coalesce(
      (SELECT EXISTS(
        SELECT 1 FROM jsonb_array_elements_text(v.evidence_media_ids) AS e(media_id)
        WHERE e.media_id = p_media::text)), false));
END; $$;

REVOKE ALL ON FUNCTION hocalist.admin_review_queue(integer,text,text,text,text,text,text),
  hocalist.admin_evidence_reference(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_review_queue(integer,text,text,text,text,text,text),
  hocalist.admin_evidence_reference(uuid,uuid) TO authenticated;

DO $hocalist_admin_review_queue_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT has_function_privilege('authenticated','hocalist.admin_review_queue(integer,text,text,text,text,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.admin_evidence_reference(uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_review_queue(integer,text,text,text,text,text,text)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_review_queue(integer,text,text,text,text,text,text)','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_evidence_reference(uuid,uuid)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_evidence_reference(uuid,uuid)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'admin review queue grants are wrong');
  END IF;
  IF has_table_privilege('authenticated','hocalist.verification_submissions','SELECT')
     OR has_table_privilege('authenticated','hocalist.account_restrictions','SELECT')
     OR has_table_privilege('authenticated','hocalist.restriction_appeals','SELECT')
     OR has_table_privilege('authenticated','hocalist.health_review_notes','SELECT') THEN
    v_issues := array_append(v_issues, 'private review tables became client-readable');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist admin review queue post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_admin_review_queue_postapply$;

-- Additive administrator-only failed-event operations read (162, draft).
--
-- Bounded, read-only view of the deployed Stripe TEST receipt inbox
-- (`stripe_test_inbox`): events the reconciliation worker has not finished,
-- their attempt count, next attempt time and the sanitized error class written
-- by the review worker. No provider object id, customer id, checkout session,
-- payload, payment amount, credential or token is projected.
--
-- Email bounce/suppression status is deliberately absent: no ingestion exists,
-- so `email_events_available` is always false. Provider event ingestion is
-- coordinator work; this file does not invent a status to fill the gap.
--
-- There is no retry, replay, delete or quarantine command here. A broad retry
-- action would require a separately reviewed idempotent worker command.
--
-- Not an instruction to apply to a live project. Generate a guarded rollout
-- bundle and obtain coordinating review before applying.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $admin_event_operations_guard$
BEGIN
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL
     OR to_regclass('hocalist.stripe_test_inbox') IS NULL THEN
    RAISE EXCEPTION 'Admin failed-event operations require the deployed Stripe TEST receipt inbox';
  END IF;
  IF to_regprocedure('hocalist.admin_failed_events(integer,text,text,text)') IS NOT NULL
     OR to_regprocedure('hocalist.admin_failed_event_detail(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Admin failed-event read objects already exist; review before replacement';
  END IF;
END
$admin_event_operations_guard$;

CREATE FUNCTION hocalist.admin_failed_events(
  p_limit integer DEFAULT 50,
  p_cursor text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_type text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rows jsonb;
  v_more boolean;
  v_cursor text;
  v_cursor_micros bigint;
  v_cursor_event text;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
     OR (p_status IS NOT NULL AND p_status NOT IN ('pending','processed','quarantined'))
     OR (p_type IS NOT NULL AND p_type NOT IN (
       'checkout.session.completed','checkout.session.async_payment_succeeded',
       'checkout.session.async_payment_failed','customer.subscription.created',
       'customer.subscription.updated','customer.subscription.deleted',
       'invoice.paid','invoice.payment_failed','charge.refunded',
       'charge.dispute.created','charge.dispute.closed'))
     OR (p_cursor IS NOT NULL AND p_cursor !~ '^[0-9]{1,20}\|[A-Za-z0-9_]{5,255}$') THEN
    RAISE EXCEPTION 'invalid_admin_query' USING ERRCODE='22023';
  END IF;
  IF p_cursor IS NOT NULL THEN
    v_cursor_micros := (split_part(p_cursor, '|', 1))::bigint;
    v_cursor_event := split_part(p_cursor, '|', 2);
  END IF;

  WITH rows AS (
    SELECT i.event_id,
      i.event_type,
      i.status,
      i.attempts,
      i.available_at,
      i.received_at,
      left(coalesce(i.last_error, ''), 80) AS error_class,
      (extract(epoch FROM i.received_at) * 1000000)::bigint AS micros
    FROM hocalist.stripe_test_inbox i
    WHERE (p_status IS NULL OR i.status = p_status)
      AND (p_type IS NULL OR i.event_type = p_type)
  ), windowed AS (
    SELECT * FROM rows
    WHERE p_cursor IS NULL OR (micros, event_id) < (v_cursor_micros, v_cursor_event)
    ORDER BY micros DESC, event_id DESC
    LIMIT p_limit + 1
  ), visible AS (
    SELECT * FROM windowed ORDER BY micros DESC, event_id DESC LIMIT p_limit
  )
  SELECT
    coalesce((SELECT jsonb_agg(jsonb_build_object(
      'event_id', event_id,
      'event_type', event_type,
      'status', status,
      'attempts', attempts,
      'available_at', available_at,
      'received_at', received_at,
      'error_class', error_class
    ) ORDER BY micros DESC, event_id DESC) FROM visible), '[]'::jsonb),
    (SELECT count(*) > p_limit FROM windowed),
    (SELECT micros::text || '|' || event_id FROM visible
      ORDER BY micros ASC, event_id ASC LIMIT 1)
    INTO v_rows, v_more, v_cursor;

  RETURN jsonb_build_object(
    'items', v_rows,
    'next_cursor', CASE WHEN v_more THEN v_cursor ELSE NULL END,
    'email_events_available', false,
    'retry_available', false);
END; $$;

-- One event's sanitized operational metadata. The provider object id is
-- reduced to its class; the raw id, payload and any provider secret stay out.
CREATE FUNCTION hocalist.admin_failed_event_detail(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  e hocalist.stripe_test_inbox%ROWTYPE;
  v_kind text;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF p_event_id IS NULL OR p_event_id !~ '^evt_[A-Za-z0-9]{1,251}$'
     OR length(p_event_id) > 255 THEN
    RAISE EXCEPTION 'invalid_admin_query' USING ERRCODE='22023';
  END IF;
  SELECT * INTO e FROM hocalist.stripe_test_inbox WHERE event_id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event_not_found' USING ERRCODE='P0002';
  END IF;
  v_kind := CASE split_part(e.object_id, '_', 1)
    WHEN 'cus' THEN 'customer'
    WHEN 'sub' THEN 'subscription'
    WHEN 'cs' THEN 'checkout_session'
    WHEN 'in' THEN 'invoice'
    WHEN 'ch' THEN 'charge'
    WHEN 'dp' THEN 'dispute'
    WHEN 'pi' THEN 'payment_intent'
    WHEN 'evt' THEN 'event'
    ELSE 'other'
  END;
  RETURN jsonb_build_object(
    'event_id', e.event_id,
    'event_type', e.event_type,
    'status', e.status,
    'attempts', e.attempts,
    'available_at', e.available_at,
    'received_at', e.received_at,
    'event_created', e.event_created,
    'object_kind', v_kind,
    'error_class', left(coalesce(e.last_error, ''), 80),
    'livemode', e.livemode);
END; $$;

REVOKE ALL ON FUNCTION hocalist.admin_failed_events(integer,text,text,text),
  hocalist.admin_failed_event_detail(text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_failed_events(integer,text,text,text),
  hocalist.admin_failed_event_detail(text) TO authenticated;

DO $hocalist_admin_event_operations_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT has_function_privilege('authenticated','hocalist.admin_failed_events(integer,text,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.admin_failed_event_detail(text)','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_failed_events(integer,text,text,text)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_failed_events(integer,text,text,text)','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_failed_event_detail(text)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_failed_event_detail(text)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'admin failed-event grants are wrong');
  END IF;
  IF has_table_privilege('authenticated','hocalist.stripe_test_inbox','SELECT')
     OR has_table_privilege('anon','hocalist.stripe_test_inbox','SELECT')
     OR has_table_privilege('service_role','hocalist.stripe_test_inbox','SELECT') THEN
    v_issues := array_append(v_issues, 'Stripe receipt inbox became directly readable');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist admin failed-event post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_admin_event_operations_postapply$;

-- Additive administrator-only cross-feature audit feed (163, draft).
--
-- One bounded, filtered, keyset-paged view over auditable records that already
-- exist in their owning modules. Every row keeps its source, actor, action,
-- target and time; free-text detail is included only for reviewer decisions
-- (bounded to 500 characters). It never projects a support response body, a
-- message body, a provider payload, a credential or a private contact field,
-- and it never selects from an arbitrary client-named table or function.
--
-- Read-only. There is no delete, no rewrite and no client-controlled source.
--
-- Dependencies (must already be deployed): marketplace 020 receipts, support
-- 070 case events, trust 120 review records, calls 110 setting audit and
-- commercial 093 withdrawal events.
--
-- Not an instruction to apply to a live project. Generate a guarded rollout
-- bundle and obtain coordinating review before applying.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $admin_audit_feed_guard$
BEGIN
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL
     OR to_regclass('hocalist.marketplace_receipts') IS NULL
     OR to_regclass('hocalist.support_case_events') IS NULL
     OR to_regclass('hocalist.support_cases') IS NULL
     OR to_regclass('hocalist.verification_submissions') IS NULL
     OR to_regclass('hocalist.account_restrictions') IS NULL
     OR to_regclass('hocalist.restriction_appeals') IS NULL
     OR to_regclass('hocalist.health_review_notes') IS NULL
     OR to_regclass('hocalist.call_settings_audit') IS NULL
     OR to_regclass('hocalist.withdrawal_events') IS NULL THEN
    RAISE EXCEPTION 'Admin audit feed requires the deployed audit sources';
  END IF;
  IF to_regprocedure('hocalist.admin_audit_feed(integer,text,text,uuid,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Admin audit feed read already exists; review before replacement';
  END IF;
END
$admin_audit_feed_guard$;

CREATE FUNCTION hocalist.admin_audit_feed(
  p_limit integer DEFAULT 50,
  p_cursor text DEFAULT NULL,
  p_source text DEFAULT NULL,
  p_actor uuid DEFAULT NULL,
  p_query text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rows jsonb;
  v_more boolean;
  v_cursor text;
  v_cursor_micros bigint;
  v_cursor_id text;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
     OR (p_source IS NOT NULL AND p_source NOT IN (
       'moderation','configuration','commercial','support','trust','calls','withdrawals'))
     OR length(coalesce(p_query, '')) > 100
     OR (p_cursor IS NOT NULL AND p_cursor !~ '^[0-9]{1,20}\|[0-9a-f]{32}$') THEN
    RAISE EXCEPTION 'invalid_admin_query' USING ERRCODE='22023';
  END IF;
  IF p_cursor IS NOT NULL THEN
    v_cursor_micros := (split_part(p_cursor, '|', 1))::bigint;
    v_cursor_id := split_part(p_cursor, '|', 2);
  END IF;

  WITH entries AS (
    SELECT md5('moderation:' || r.user_id::text || ':' || r.operation || ':' || r.idempotency_key) AS id,
      r.created_at AS occurred_at,
      'moderation'::text AS source,
      r.operation AS action,
      r.user_id::text AS actor,
      coalesce(r.result->>'id', '') AS target,
      coalesce(r.result->>'moderation_status', '') AS summary,
      null::text AS detail
    FROM hocalist.marketplace_receipts r
    WHERE r.operation = 'store.set_moderation'
    UNION ALL
    SELECT md5('configuration:' || r.user_id::text || ':' || r.operation || ':' || r.idempotency_key),
      r.created_at, 'configuration', r.operation, r.user_id::text,
      coalesce(r.result->>'id', r.result->>'plan_code', ''),
      coalesce(r.result->>'status', ''), null
    FROM hocalist.marketplace_receipts r
    WHERE r.operation IN (
      'category.create','category.update','group.create','group.update',
      'option.create','option.update','entry.set_status',
      'location.create','location.update','location.set_status','plan_limit.update')
    UNION ALL
    SELECT md5('commercial:' || r.user_id::text || ':' || r.operation || ':' || r.idempotency_key),
      r.created_at, 'commercial', r.operation, r.user_id::text,
      coalesce(r.result->>'id', ''), coalesce(r.result->>'active', ''), null
    FROM hocalist.marketplace_receipts r
    WHERE r.operation LIKE 'credit_admin.%'
    UNION ALL
    SELECT md5('support:' || e.case_id::text || ':' || e.revision::text),
      e.created_at, 'support',
      CASE WHEN e.actor_id = c.reporter_id THEN 'support.create' ELSE 'support.review' END,
      e.actor_id::text, e.case_id::text, e.status, null
    FROM hocalist.support_case_events e
    JOIN hocalist.support_cases c ON c.id = e.case_id
    UNION ALL
    SELECT md5('trust-verification:' || v.id::text || ':' || v.revision::text),
      coalesce(v.decided_at, v.updated_at), 'trust', 'verification.decide',
      v.reviewer_id::text, v.id::text, v.status, left(v.decision_reason, 500)
    FROM hocalist.verification_submissions v
    WHERE v.reviewer_id IS NOT NULL
    UNION ALL
    SELECT md5('trust-restriction:' || r.id::text),
      r.created_at, 'trust', 'restriction.apply', r.created_by::text, r.id::text,
      r.scope || ' ' || r.status, left(r.reason, 500)
    FROM hocalist.account_restrictions r
    UNION ALL
    SELECT md5('trust-restriction-revoke:' || r.id::text),
      r.revoked_at, 'trust', 'restriction.revoke', r.revoked_by::text, r.id::text,
      'revoked', left(r.revoke_reason, 500)
    FROM hocalist.account_restrictions r
    WHERE r.revoked_by IS NOT NULL AND r.revoked_at IS NOT NULL
    UNION ALL
    SELECT md5('trust-appeal:' || a.id::text || ':' || a.revision::text),
      coalesce(a.decided_at, a.created_at), 'trust', 'appeal.decide',
      a.reviewer_id::text, a.id::text, a.status, left(a.decision_reason, 500)
    FROM hocalist.restriction_appeals a
    WHERE a.reviewer_id IS NOT NULL
    UNION ALL
    SELECT md5('trust-health:' || h.case_id::text),
      h.created_at, 'trust', 'health.review', h.reviewer_id::text, h.case_id::text,
      h.decision, left(h.reason, 500)
    FROM hocalist.health_review_notes h
    UNION ALL
    SELECT md5('calls:' || a.revision::text),
      a.changed_at, 'calls', 'call_setting.change', a.changed_by::text, 'call_settings',
      CASE WHEN a.enabled THEN 'enabled' ELSE 'disabled' END, null
    FROM hocalist.call_settings_audit a
    UNION ALL
    SELECT md5('withdrawal:' || e.withdrawal_id::text || ':' || e.revision::text),
      e.created_at, 'withdrawals', 'withdrawal.' || e.event, e.actor::text,
      e.withdrawal_id::text, e.event, null
    FROM hocalist.withdrawal_events e
  ), prepared AS (
    SELECT id, occurred_at, source, action, actor, target, summary, detail,
      (extract(epoch FROM occurred_at) * 1000000)::bigint AS micros
    FROM entries
  ), filtered AS (
    SELECT * FROM prepared
    WHERE (p_source IS NULL OR source = p_source)
      AND (p_actor IS NULL OR actor = p_actor::text)
      AND (nullif(btrim(coalesce(p_query, '')), '') IS NULL
        OR strpos(lower(action || ' ' || coalesce(target, '') || ' ' ||
           coalesce(summary, '') || ' ' || coalesce(detail, '')),
           lower(btrim(p_query))) > 0)
  ), windowed AS (
    SELECT * FROM filtered
    WHERE p_cursor IS NULL OR (micros, id) < (v_cursor_micros, v_cursor_id)
    ORDER BY micros DESC, id DESC
    LIMIT p_limit + 1
  ), visible AS (
    SELECT * FROM windowed ORDER BY micros DESC, id DESC LIMIT p_limit
  )
  SELECT
    coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id', id,
      'occurred_at', occurred_at,
      'source', source,
      'action', action,
      'actor', actor,
      'target', target,
      'summary', summary,
      'detail', detail
    ) ORDER BY micros DESC, id DESC) FROM visible), '[]'::jsonb),
    (SELECT count(*) > p_limit FROM windowed),
    (SELECT micros::text || '|' || id FROM visible
      ORDER BY micros ASC, id ASC LIMIT 1)
    INTO v_rows, v_more, v_cursor;

  RETURN jsonb_build_object(
    'items', v_rows,
    'next_cursor', CASE WHEN v_more THEN v_cursor ELSE NULL END,
    'sources', jsonb_build_array('moderation','configuration','commercial',
      'support','trust','calls','withdrawals'));
END; $$;

REVOKE ALL ON FUNCTION hocalist.admin_audit_feed(integer,text,text,uuid,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_audit_feed(integer,text,text,uuid,text)
  TO authenticated;

DO $hocalist_admin_audit_feed_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT has_function_privilege('authenticated','hocalist.admin_audit_feed(integer,text,text,uuid,text)','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_audit_feed(integer,text,text,uuid,text)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_audit_feed(integer,text,text,uuid,text)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'admin audit feed grants are wrong');
  END IF;
  IF has_table_privilege('authenticated','hocalist.marketplace_receipts','SELECT')
     OR has_table_privilege('authenticated','hocalist.support_case_events','SELECT')
     OR has_table_privilege('authenticated','hocalist.call_settings_audit','SELECT')
     OR has_table_privilege('authenticated','hocalist.withdrawal_events','SELECT') THEN
    v_issues := array_append(v_issues, 'audit source tables became client-readable');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist admin audit feed post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_admin_audit_feed_postapply$;

DO $verify$ DECLARE f oid; r text; BEGIN
f:=to_regprocedure('hocalist.admin_commercial_config()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'0d0ca58a72deec5baca2735cbd220dc3' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_commercial_config()'; END IF;
f:=to_regprocedure('hocalist.admin_review_queue(integer,text,text,text,text,text,text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'5190491e44e74c3edb048d6ee7f7a169' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_review_queue(integer,text,text,text,text,text,text)'; END IF;
f:=to_regprocedure('hocalist.admin_evidence_reference(uuid,uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'54b17dea98f5180547aef90239619ca9' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_evidence_reference(uuid,uuid)'; END IF;
f:=to_regprocedure('hocalist.admin_failed_events(integer,text,text,text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'35091e6156cbbb92e8eff89b957b9176' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_failed_events(integer,text,text,text)'; END IF;
f:=to_regprocedure('hocalist.admin_failed_event_detail(text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'267b6bc7cde256a1a7ec1345ad3a31ee' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_failed_event_detail(text)'; END IF;
f:=to_regprocedure('hocalist.admin_audit_feed(integer,text,text,uuid,text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'b147e5d1a1b9b507a2acd9f43da6df41' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_audit_feed(integer,text,text,uuid,text)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_commercial_config()'),'EXECUTE') IS DISTINCT FROM (r='authenticated') THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_commercial_config() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_review_queue(integer,text,text,text,text,text,text)'),'EXECUTE') IS DISTINCT FROM (r='authenticated') THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_review_queue(integer,text,text,text,text,text,text) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_evidence_reference(uuid,uuid)'),'EXECUTE') IS DISTINCT FROM (r='authenticated') THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_evidence_reference(uuid,uuid) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_failed_events(integer,text,text,text)'),'EXECUTE') IS DISTINCT FROM (r='authenticated') THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_failed_events(integer,text,text,text) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_failed_event_detail(text)'),'EXECUTE') IS DISTINCT FROM (r='authenticated') THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_failed_event_detail(text) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_audit_feed(integer,text,text,uuid,text)'),'EXECUTE') IS DISTINCT FROM (r='authenticated') THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_audit_feed(integer,text,text,uuid,text) %',r; END IF; END LOOP;
END $verify$;
COMMIT;

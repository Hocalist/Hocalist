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
BEGIN;
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
COMMIT;

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
BEGIN;
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
COMMIT;

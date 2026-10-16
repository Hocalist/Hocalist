-- Additive administrator-only read of the optional-calling setting history
-- (063, draft).
--
-- Projects the append-only `call_settings_audit` rows: revision, enabled state,
-- the acting administrator id and the change time. No credential, TURN server
-- or media detail exists here, and the read never changes the setting.
--
-- Not an instruction to apply to a live project. Generate a guarded rollout
-- bundle and obtain coordinating review before applying.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $admin_call_audit_guard$
BEGIN
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL
     OR to_regclass('hocalist.call_settings') IS NULL
     OR to_regclass('hocalist.call_settings_audit') IS NULL THEN
    RAISE EXCEPTION 'Admin call audit requires admin and call foundations';
  END IF;
  IF to_regprocedure('hocalist.admin_call_settings_history()') IS NOT NULL THEN
    RAISE EXCEPTION 'Admin call audit read already exists; review before replacement';
  END IF;
END
$admin_call_audit_guard$;

CREATE FUNCTION hocalist.admin_call_settings_history()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_items jsonb;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'revision', a.revision,
      'enabled', a.enabled,
      'changed_by', a.changed_by,
      'changed_at', a.changed_at
    ) ORDER BY a.revision DESC), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT * FROM hocalist.call_settings_audit
      ORDER BY revision DESC
      LIMIT 20
    ) a;
  RETURN jsonb_build_object(
    'current_enabled',
      (SELECT enabled FROM hocalist.call_settings WHERE singleton),
    'items', v_items);
END; $$;

REVOKE ALL ON FUNCTION hocalist.admin_call_settings_history()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_call_settings_history() TO authenticated;

DO $hocalist_admin_call_audit_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT has_function_privilege('authenticated','hocalist.admin_call_settings_history()','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_call_settings_history()','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_call_settings_history()','EXECUTE') THEN
    v_issues := array_append(v_issues, 'admin call audit grants are wrong');
  END IF;
  IF has_table_privilege('authenticated','hocalist.call_settings_audit','SELECT') THEN
    v_issues := array_append(v_issues, 'call audit table became client-readable');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist admin call audit post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_admin_call_audit_postapply$;
COMMIT;

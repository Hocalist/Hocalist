BEGIN READ ONLY;
DO $verify$
DECLARE v_fn text; v_acl record;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['hocalist.admin_records(text,integer,uuid,text,text)','hocalist.admin_overview()'] LOOP
    IF to_regprocedure(v_fn) IS NULL THEN RAISE EXCEPTION 'Missing admin function: %',v_fn; END IF;
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=v_fn::regprocedure AND prosecdef
      AND provolatile='s' AND proconfig=ARRAY['search_path=""']::text[]) THEN
      RAISE EXCEPTION 'Admin function security changed: %',v_fn;
    END IF;
    IF NOT has_function_privilege('authenticated',v_fn,'EXECUTE')
      OR has_function_privilege('anon',v_fn,'EXECUTE')
      OR has_function_privilege('service_role',v_fn,'EXECUTE') THEN
      RAISE EXCEPTION 'Admin function privileges changed: %',v_fn;
    END IF;
    FOR v_acl IN SELECT a.* FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=v_fn::regprocedure AND a.grantee<>p.proowner LOOP
      IF v_acl.grantee<>('authenticated'::regrole)::oid OR v_acl.is_grantable THEN
        RAISE EXCEPTION 'Unexpected admin function grant: %',v_fn;
      END IF;
    END LOOP;
  END LOOP;
END $verify$;
SELECT 'admin read verification passed' AS status;
COMMIT;

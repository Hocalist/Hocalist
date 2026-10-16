DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='hocalist' AND p.proname='verification_status'
      AND p.pronargs=0 AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']
      AND md5(replace(p.prosrc,chr(13),''))='cbf9f714f4e30511688c936b91f0886e') THEN
    RAISE EXCEPTION 'Verify: verification_status definition drift';
  END IF;
  IF has_function_privilege('anon','hocalist.verification_status()','EXECUTE')
     OR has_function_privilege('service_role','hocalist.verification_status()','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.verification_status()','EXECUTE') THEN
    RAISE EXCEPTION 'Verify: verification_status privilege drift';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p, LATERAL aclexplode(p.proacl) a
    WHERE p.oid='hocalist.verification_status()'::regprocedure
      AND a.grantee <> p.proowner
      AND (a.grantee <> (SELECT oid FROM pg_roles WHERE rolname='authenticated')
        OR a.privilege_type <> 'EXECUTE' OR a.is_grantable))
    OR (SELECT proacl IS NULL FROM pg_proc WHERE oid='hocalist.verification_status()'::regprocedure) THEN
    RAISE EXCEPTION 'Verify: verification_status ACL drift';
  END IF;
END $guard$;

BEGIN READ ONLY;
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid = to_regprocedure('hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)')
    AND md5(replace(p.prosrc, E'\r\n', E'\n')) = 'be33038e027379ba9ba64686b0f995ef'
    AND p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'Service-area function definition drift: marketplace_discovery_leads';
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)','EXECUTE')
    OR has_function_privilege('anon','hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)','EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)')
      AND (a.grantee = 0 OR a.is_grantable AND a.grantee <> p.proowner)) THEN
    RAISE EXCEPTION 'Service-area function privilege drift: marketplace_discovery_leads';
  END IF;
END;
$guard$;
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid = to_regprocedure('hocalist.marketplace_recommended_leads(integer)')
    AND md5(replace(p.prosrc, E'\r\n', E'\n')) = 'aa00ae988071499a8d5b6b716f0633d4'
    AND p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'Service-area function definition drift: marketplace_recommended_leads';
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.marketplace_recommended_leads(integer)','EXECUTE')
    OR has_function_privilege('anon','hocalist.marketplace_recommended_leads(integer)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_recommended_leads(integer)','EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.marketplace_recommended_leads(integer)')
      AND (a.grantee = 0 OR a.is_grantable AND a.grantee <> p.proowner)) THEN
    RAISE EXCEPTION 'Service-area function privilege drift: marketplace_recommended_leads';
  END IF;
END;
$guard$;
ROLLBACK;

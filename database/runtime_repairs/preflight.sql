BEGIN READ ONLY;
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid = to_regprocedure('hocalist.marketplace_timezones()')
    AND md5(replace(p.prosrc, E'\r\n', E'\n')) = 'ff1cde18f96d91e11c1df0195a539062'
    AND p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'Timezone function definition drift';
  END IF;
  IF NOT has_function_privilege('authenticated', 'hocalist.marketplace_timezones()', 'EXECUTE')
    OR has_function_privilege('anon', 'hocalist.marketplace_timezones()', 'EXECUTE')
    OR has_function_privilege('service_role', 'hocalist.marketplace_timezones()', 'EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.marketplace_timezones()') AND (a.grantee = 0 OR a.is_grantable AND a.grantee <> p.proowner)) THEN
    RAISE EXCEPTION 'Timezone function privilege drift';
  END IF;
END;
$guard$;
ROLLBACK;

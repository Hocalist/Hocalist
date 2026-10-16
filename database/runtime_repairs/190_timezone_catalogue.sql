-- One catalogue scan; authentication, result shape, accepted zones and ACLs unchanged.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
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
CREATE OR REPLACE FUNCTION hocalist.marketplace_timezones() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('items', coalesce((
    SELECT jsonb_agg(n.name ORDER BY n.name)
    FROM pg_catalog.pg_timezone_names n
    WHERE n.name ~ '^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)+$'
      AND n.name NOT LIKE 'Etc/%'
      AND n.name NOT LIKE 'posix/%'
      AND n.name NOT LIKE 'SystemV/%'
  ), '[]'::jsonb));
END; $$;
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid = to_regprocedure('hocalist.marketplace_timezones()')
    AND md5(replace(p.prosrc, E'\r\n', E'\n')) = '9e74c71e9d9a9cfa6681fd08153b7b84'
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
COMMIT;

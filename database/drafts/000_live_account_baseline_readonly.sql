-- Read-only preflight. Run only in the approved shared Supabase project.
-- No user records, Auth metadata or credentials are selected.
BEGIN READ ONLY;
SELECT n.nspname AS schema_name, pg_get_userbyid(n.nspowner) AS owner,
       n.nspacl::text AS schema_acl
FROM pg_namespace n WHERE n.nspname='hocalist';

SELECT c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity,
       pg_get_userbyid(c.relowner) AS owner, c.relacl::text AS grants
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='hocalist' AND c.relkind IN ('r','p','v','m','S')
ORDER BY c.relname;

SELECT table_name,column_name,data_type,is_nullable,column_default
FROM information_schema.columns WHERE table_schema='hocalist'
ORDER BY table_name,ordinal_position;

SELECT tablename,policyname,roles,cmd,qual,with_check
FROM pg_policies WHERE schemaname='hocalist' ORDER BY tablename,policyname;

SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_get_userbyid(p.proowner) AS owner,p.prosecdef,p.proconfig,
       p.proacl::text AS grants,md5(pg_get_functiondef(p.oid)) AS definition_hash
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='hocalist' ORDER BY p.proname;

SELECT t.tgname,t.tgenabled,pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
WHERE t.tgrelid='auth.users'::regclass AND NOT t.tgisinternal;

SELECT pg_get_userbyid(d.defaclrole) AS grant_owner,
       coalesce(n.nspname,'ALL SCHEMAS') AS schema_name,
       d.defaclobjtype,d.defaclacl::text AS default_grants
FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
WHERE d.defaclnamespace=0 OR n.nspname='hocalist';

SELECT r.rolname AS role_name,
       has_schema_privilege(r.oid,'hocalist','USAGE') AS schema_usage,
       has_schema_privilege(r.oid,'hocalist','CREATE') AS schema_create
FROM pg_roles r WHERE r.rolname IN ('anon','authenticated','service_role');
ROLLBACK;
-- Dashboard API schema exposure must also be inspected separately.
-- Stop rollout on unexpected grants, policies, owners, trigger or schema drift.

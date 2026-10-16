-- Isolated namespace bootstrap only; no application tables or auth changes.
-- Apply only after confirming the target project and schema absence.
BEGIN;
CREATE SCHEMA hocalist AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA hocalist FROM PUBLIC, anon, authenticated;
COMMENT ON SCHEMA hocalist IS
  'Hocalist business namespace. Client access remains disabled pending reviewed grants and RLS.';
COMMIT;

-- Verification (read-only):
SELECT nspname, pg_get_userbyid(nspowner) AS owner,
       has_schema_privilege('anon', oid, 'USAGE') AS anon_usage,
       has_schema_privilege('authenticated', oid, 'USAGE') AS authenticated_usage,
       has_schema_privilege('anon', oid, 'CREATE') AS anon_create,
       has_schema_privilege('authenticated', oid, 'CREATE') AS authenticated_create
FROM pg_namespace WHERE nspname = 'hocalist';

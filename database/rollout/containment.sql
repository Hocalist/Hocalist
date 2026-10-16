-- Hocalist account rollout containment. NON-DESTRUCTIVE.
--
-- Use after account_apply.sql to withdraw client access without deleting any
-- user data: revokes the client schema, table, column and command grants
-- added by (or drifted onto) the account bundle. Tables, rows, RLS policies,
-- the signup seed/trigger and the deployed 005 receipt objects are preserved;
-- shared Postaneur objects are never touched. Safe to run repeatedly.
--
-- Limits: containment withdraws client access only. It does not repair or
-- validate unrelated privilege or policy drift on preserved baseline objects;
-- use preflight.sql/verify.sql for those. The three-account-policy count is a
-- current-bundle gate that must be re-reviewed before later drafts add
-- policies. A destructive table rollback is not supplied or authorized.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '15s';
REVOKE ALL PRIVILEGES ON SCHEMA hocalist FROM anon, authenticated;
REVOKE ALL PRIVILEGES ON hocalist.memberships, hocalist.role_profiles,
  hocalist.profile_contacts, hocalist.command_receipts FROM anon, authenticated;
REVOKE ALL PRIVILEGES (id, user_id, role, status, revision, created_at, updated_at)
  ON hocalist.memberships FROM anon, authenticated;
REVOKE ALL PRIVILEGES (membership_id, display_name, area_label, profile_note,
  preferred_meetup_type, service_radius_miles, pickup_availability, revision,
  created_at, updated_at) ON hocalist.role_profiles FROM anon, authenticated;
REVOKE ALL PRIVILEGES (user_id, phone, address_line1, address_line2, city, region,
  postal_code, country_code, revision, created_at, updated_at)
  ON hocalist.profile_contacts FROM anon, authenticated;
REVOKE ALL PRIVILEGES (user_id, operation, idempotency_key, request_hash, result,
  created_at) ON hocalist.command_receipts FROM anon, authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION hocalist.account_command(text,text,jsonb)
  FROM anon, authenticated;
DO $hocalist_containment$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_tables constant text[] := ARRAY[
    'memberships', 'role_profiles', 'profile_contacts', 'command_receipts'];
  v_client_roles constant text[] := ARRAY['anon', 'authenticated'];
  v_privileges constant text[] := ARRAY[
    'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'];
  v_table text;
  v_role text;
  v_priv text;
  v_function constant text := 'hocalist.account_command(text,text,jsonb)';
  v_receipt_function constant text := 'hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)';
BEGIN
  IF has_schema_privilege('authenticated', 'hocalist', 'USAGE')
     OR has_schema_privilege('authenticated', 'hocalist', 'CREATE')
     OR has_schema_privilege('anon', 'hocalist', 'USAGE')
     OR has_schema_privilege('anon', 'hocalist', 'CREATE') THEN
    v_issues := array_append(v_issues, 'client schema access is still granted');
  END IF;
  IF has_function_privilege('authenticated', v_function, 'EXECUTE')
     OR has_function_privilege('anon', v_function, 'EXECUTE') THEN
    v_issues := array_append(v_issues, 'client can still execute account_command');
  END IF;
  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues,
        'account table missing (containment must not drop data): ' || v_table);
    ELSE
      IF EXISTS (
        SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
        WHERE c.oid = ('hocalist.' || v_table)::regclass
          AND pg_get_userbyid(a.grantee) IN ('anon', 'authenticated')
      ) THEN
        v_issues := array_append(v_issues, 'client table ACL remains on ' || v_table);
      END IF;
      IF EXISTS (
        SELECT 1 FROM pg_attribute att, aclexplode(att.attacl) a
        WHERE att.attrelid = ('hocalist.' || v_table)::regclass
          AND att.attnum > 0 AND NOT att.attisdropped
          AND pg_get_userbyid(a.grantee) IN ('anon', 'authenticated')
      ) THEN
        v_issues := array_append(v_issues, 'client column ACL remains on ' || v_table);
      END IF;
      FOREACH v_role IN ARRAY v_client_roles LOOP
        FOREACH v_priv IN ARRAY v_privileges LOOP
          IF has_table_privilege(v_role, 'hocalist.' || v_table, v_priv) THEN
            v_issues := array_append(v_issues,
              'client ' || v_priv || ' remains for ' || v_role || ' on ' || v_table);
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END LOOP;

  -- 001/002/005 must survive containment unchanged.
  IF NOT has_schema_privilege('service_role', 'hocalist', 'USAGE')
     OR NOT has_function_privilege('service_role', v_receipt_function, 'EXECUTE')
     OR to_regclass('hocalist.stripe_test_inbox') IS NULL
     OR to_regclass('hocalist.profiles') IS NULL THEN
    v_issues := array_append(v_issues, 'deployed 001/002/005 objects or grants were disturbed');
  END IF;
  IF has_table_privilege('authenticated', 'hocalist.stripe_test_inbox', 'SELECT')
     OR has_table_privilege('authenticated', 'hocalist.profiles', 'SELECT') THEN
    v_issues := array_append(v_issues, 'unrelated deployed grants changed');
  END IF;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname = 'hocalist') <> 3 THEN
    v_issues := array_append(v_issues,
      'account policies were altered (containment revokes grants only)');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'auth.users'::regclass
      AND t.tgname = 'on_auth_user_created'
      AND t.tgfoid = to_regprocedure('hocalist.handle_new_user()')
      AND t.tgenabled = 'O'
  ) THEN
    v_issues := array_append(v_issues, 'signup routing trigger changed');
  END IF;

  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist containment verification failed: %', array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_containment$;
COMMIT;
SELECT 'PASS: client account access contained; rows and deployed objects preserved' AS account_containment;

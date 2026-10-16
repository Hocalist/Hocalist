-- Hocalist account rollout preflight. READ-ONLY: safe to run repeatedly.
--
-- Aborts on any baseline drift, unexpected existing target object, unexpected
-- grant (table, column, schema or function, including PUBLIC, TRUNCATE and
-- effective inherited access) or unexpected policy instead of mutating. The
-- DO $hocalist_guard$ block below is textually identical to the guard inside
-- account_apply.sql; database/tests/rollout.test.mjs asserts it.
--
-- Expected reviewed baseline: bootstrap 001/002 applied (private hocalist
-- schema, hocalist.profiles signup seed, on_auth_user_created routing trigger)
-- and draft 005 applied (private stripe_test_inbox and service-only
-- receive_stripe_test_event). API schema exposure is a dashboard setting and
-- is not mutated by this bundle.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $hocalist_guard$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_seed_columns constant text[] := ARRAY[
    'id', 'full_name', 'avatar_url', 'onboarding_status', 'created_at', 'updated_at'];
  v_allowed_relations constant text[] := ARRAY['profiles', 'stripe_test_inbox'];
  v_target_relations constant text[] := ARRAY[
    'memberships', 'role_profiles', 'profile_contacts', 'command_receipts'];
  v_allowed_functions constant text[] := ARRAY[
    'handle_new_user()',
    'receive_stripe_test_event(text,text,text,text,bigint,boolean)'];
  v_target_functions constant text[] := ARRAY['account_command(text,text,jsonb)'];
  v_roles constant text[] := ARRAY['anon', 'authenticated', 'service_role'];
  v_privileges constant text[] := ARRAY[
    'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'];
  v_rel text;
  v_fn text;
  v_role text;
  v_priv text;
  v_missing text;
BEGIN
  IF to_regnamespace('hocalist') IS NULL THEN
    v_issues := array_append(v_issues, 'hocalist schema is missing (bootstrap 001 not applied)');
  ELSE
    IF (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'hocalist')
       IS DISTINCT FROM 'postgres' THEN
      v_issues := array_append(v_issues, 'hocalist schema owner is not postgres');
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_namespace n, aclexplode(n.nspacl) a
      WHERE n.nspname = 'hocalist'
        AND NOT (
          pg_get_userbyid(a.grantee) = 'postgres'
          OR (pg_get_userbyid(a.grantee) = 'service_role'
              AND a.privilege_type = 'USAGE' AND NOT a.is_grantable)
        )
    ) THEN
      v_issues := array_append(v_issues,
        'hocalist schema ACL differs from the reviewed 001/005 baseline');
    END IF;
    IF has_schema_privilege('anon', 'hocalist', 'USAGE')
       OR has_schema_privilege('anon', 'hocalist', 'CREATE')
       OR has_schema_privilege('authenticated', 'hocalist', 'USAGE')
       OR has_schema_privilege('authenticated', 'hocalist', 'CREATE')
       OR has_schema_privilege('service_role', 'hocalist', 'CREATE') THEN
      v_issues := array_append(v_issues,
        'unexpected client/service schema access; review before rollout');
    END IF;
    IF NOT has_schema_privilege('service_role', 'hocalist', 'USAGE') THEN
      v_issues := array_append(v_issues, 'service_role is missing its reviewed 005 schema USAGE');
    END IF;
  END IF;

  IF to_regclass('hocalist.profiles') IS NULL THEN
    v_issues := array_append(v_issues,
      'hocalist.profiles signup seed is missing (bootstrap 002 not applied)');
  ELSE
    SELECT string_agg(c, ', ') INTO v_missing
    FROM unnest(v_seed_columns) c
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_attribute a
      WHERE a.attrelid = 'hocalist.profiles'::regclass
        AND a.attname = c AND NOT a.attisdropped
    );
    IF v_missing IS NOT NULL THEN
      v_issues := array_append(v_issues, 'signup seed is missing columns: ' || v_missing);
    END IF;
    IF (SELECT count(*) FROM pg_attribute a
        WHERE a.attrelid = 'hocalist.profiles'::regclass
          AND a.attnum > 0 AND NOT a.attisdropped) <> array_length(v_seed_columns, 1) THEN
      v_issues := array_append(v_issues, 'signup seed has unexpected extra columns');
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'hocalist.profiles'::regclass) THEN
      v_issues := array_append(v_issues, 'signup seed row level security is not enabled');
    END IF;
  END IF;

  IF to_regclass('hocalist.stripe_test_inbox') IS NULL THEN
    v_issues := array_append(v_issues, 'deployed 005 stripe_test_inbox is missing');
  ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'hocalist.stripe_test_inbox'::regclass) THEN
    v_issues := array_append(v_issues, 'stripe_test_inbox row level security is not enabled');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'auth.users'::regclass
      AND t.tgname = 'on_auth_user_created'
      AND t.tgfoid = to_regprocedure('hocalist.handle_new_user()')
      AND t.tgtype = 5 AND t.tgenabled = 'O'
  ) THEN
    v_issues := array_append(v_issues,
      'signup routing trigger is missing, disabled or differs from baseline');
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'auth.users'::regclass
      AND NOT t.tgisinternal AND t.tgname <> 'on_auth_user_created'
  ) THEN
    v_issues := array_append(v_issues, 'unexpected non-internal trigger on auth.users');
  END IF;

  -- Preserved baseline privilege matrix. RLS does not cover TRUNCATE, so the
  -- seed and inbox ACLs must stay owner-only with no column grants, no
  -- policies and no effective access, including access inherited from another
  -- role.
  FOREACH v_rel IN ARRAY v_allowed_relations LOOP
    IF to_regclass('hocalist.' || v_rel) IS NOT NULL THEN
      IF EXISTS (
        SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
        WHERE c.oid = ('hocalist.' || v_rel)::regclass
          AND pg_get_userbyid(a.grantee) <> 'postgres'
      ) THEN
        v_issues := array_append(v_issues,
          'hocalist.' || v_rel || ' has unexpected non-owner grants');
      END IF;
      IF EXISTS (
        SELECT 1 FROM pg_attribute att, aclexplode(att.attacl) a
        WHERE att.attrelid = ('hocalist.' || v_rel)::regclass
          AND att.attnum > 0 AND NOT att.attisdropped
      ) THEN
        v_issues := array_append(v_issues,
          'hocalist.' || v_rel || ' has unexpected column grants');
      END IF;
      IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'hocalist' AND tablename = v_rel
      ) THEN
        v_issues := array_append(v_issues,
          'hocalist.' || v_rel || ' has an unexpected policy');
      END IF;
      FOREACH v_role IN ARRAY v_roles LOOP
        FOREACH v_priv IN ARRAY v_privileges LOOP
          IF has_table_privilege(v_role, 'hocalist.' || v_rel, v_priv) THEN
            v_issues := array_append(v_issues,
              'unexpected ' || v_priv || ' for ' || v_role || ' on hocalist.' || v_rel);
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END LOOP;

  IF to_regprocedure('hocalist.handle_new_user()') IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.handle_new_user()')
        AND pg_get_userbyid(a.grantee) <> 'postgres'
    ) OR EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid = to_regprocedure('hocalist.handle_new_user()') AND p.proacl IS NULL
    ) THEN
      v_issues := array_append(v_issues, 'handle_new_user has unexpected execution grants');
    END IF;
    FOREACH v_role IN ARRAY v_roles LOOP
      IF has_function_privilege(v_role, 'hocalist.handle_new_user()', 'EXECUTE') THEN
        v_issues := array_append(v_issues,
          'unexpected EXECUTE for ' || v_role || ' on handle_new_user');
      END IF;
    END LOOP;
    IF EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid = to_regprocedure('hocalist.handle_new_user()')
        AND (NOT p.prosecdef
          OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']
          OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres')
    ) THEN
      v_issues := array_append(v_issues, 'handle_new_user security properties changed');
    END IF;
  END IF;

  IF to_regprocedure('hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)') IS NULL THEN
    v_issues := array_append(v_issues, 'deployed 005 receive_stripe_test_event is missing');
  ELSE
    IF EXISTS (
      SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)')
        AND NOT (
          pg_get_userbyid(a.grantee) = 'postgres'
          OR (pg_get_userbyid(a.grantee) = 'service_role'
              AND a.privilege_type = 'EXECUTE' AND NOT a.is_grantable)
        )
    ) OR EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid = to_regprocedure('hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)')
        AND p.proacl IS NULL
    ) THEN
      v_issues := array_append(v_issues,
        'receive_stripe_test_event ACL differs from the reviewed 005 state');
    END IF;
    FOREACH v_role IN ARRAY v_roles LOOP
      IF (v_role = 'service_role'
          AND NOT has_function_privilege(
            v_role,
            'hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)',
            'EXECUTE'))
         OR (v_role <> 'service_role'
          AND has_function_privilege(
            v_role,
            'hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)',
            'EXECUTE')) THEN
        v_issues := array_append(v_issues,
          'receive_stripe_test_event execution differs for ' || v_role);
      END IF;
    END LOOP;
    IF EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid = to_regprocedure('hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)')
        AND (NOT p.prosecdef
          OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']
          OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres')
    ) THEN
      v_issues := array_append(v_issues, 'receive_stripe_test_event security properties changed');
    END IF;
  END IF;

  FOR v_rel IN
    SELECT c.relname FROM pg_class c
    WHERE c.relnamespace = to_regnamespace('hocalist')
      AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
  LOOP
    IF v_rel = ANY(v_target_relations) THEN
      v_issues := array_append(v_issues, 'target relation already exists: ' || v_rel);
    ELSIF NOT (v_rel = ANY(v_allowed_relations)) THEN
      v_issues := array_append(v_issues, 'unexpected relation in hocalist: ' || v_rel);
    END IF;
  END LOOP;
  FOR v_fn IN
    SELECT p.proname || '(' || replace(oidvectortypes(p.proargtypes), ', ', ',') || ')'
    FROM pg_proc p
    WHERE p.pronamespace = to_regnamespace('hocalist')
  LOOP
    IF v_fn = ANY(v_target_functions) THEN
      v_issues := array_append(v_issues, 'target function already exists: ' || v_fn);
    ELSIF NOT (v_fn = ANY(v_allowed_functions)) THEN
      v_issues := array_append(v_issues, 'unexpected function in hocalist: ' || v_fn);
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_default_acl d
    WHERE pg_get_userbyid(d.defaclrole) = 'postgres'
      AND (d.defaclnamespace = 0 OR d.defaclnamespace = to_regnamespace('hocalist'))
      AND EXISTS (
        SELECT 1 FROM aclexplode(d.defaclacl) a
        WHERE a.grantee = 0
          OR a.grantee IN (
            SELECT oid FROM pg_roles
            WHERE rolname IN ('anon', 'authenticated', 'service_role'))
      )
  ) THEN
    v_issues := array_append(v_issues,
      'postgres default privileges would grant client/service access to new hocalist objects');
  END IF;

  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist preflight failed: %', array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_guard$;
SELECT 'PASS: reviewed baseline intact; 003/004 targets absent' AS preflight;
ROLLBACK;

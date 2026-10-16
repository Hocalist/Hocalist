-- Hocalist account rollout: guarded single-transaction apply of drafts
-- 003 (memberships/private profiles) and 004 (account commands).
--
-- Prerequisites (already applied and preserved, never re-run blindly):
--   * bootstrap 001 (hocalist namespace) and 002 (signup seed + trigger)
--   * draft 005 (private stripe_test_inbox + service-only receipt function)
-- API schema exposure is a dashboard setting and is NOT mutated here.
--
-- On any drift, unexpected grant or unexpected existing target object the
-- guard aborts the whole transaction; nothing is dropped, cascaded or
-- overwritten. The DO blocks are textually identical to preflight.sql
-- ($hocalist_guard$) and verify.sql ($hocalist_postapply$);
-- database/tests/rollout.test.mjs asserts this.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
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


-- ==== draft 003 DDL (hardened; keep in sync with database/drafts/003) ====
CREATE TABLE hocalist.memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('buyer', 'seller')),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'active', 'restricted', 'disabled')),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);

-- Domain profile id = membership id; Auth identity remains a separate id.
CREATE TABLE hocalist.role_profiles (
  membership_id uuid PRIMARY KEY REFERENCES hocalist.memberships(id) ON DELETE CASCADE,
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 200),
  area_label text CHECK (length(area_label) <= 200),
  profile_note text CHECK (length(profile_note) <= 2000),
  preferred_meetup_type text CHECK (length(preferred_meetup_type) <= 100),
  service_radius_miles integer CHECK (service_radius_miles >= 0),
  pickup_availability text CHECK (length(pickup_availability) <= 500),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Never join these columns into public profile/search/realtime responses.
-- Email stays in Auth; phone here is unverified user input, not a trust signal.
CREATE TABLE hocalist.profile_contacts (
  user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  phone text CHECK (length(phone) <= 40),
  address_line1 text CHECK (length(address_line1) <= 300),
  address_line2 text CHECK (length(address_line2) <= 300),
  city text CHECK (length(city) <= 150),
  region text CHECK (length(region) <= 150),
  postal_code text CHECK (length(postal_code) <= 40),
  country_code text CHECK (country_code ~ '^[A-Z]{2}$'),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE hocalist.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.role_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.profile_contacts ENABLE ROW LEVEL SECURITY;
-- No client or service-role direct writes. The commands are the only writers.
REVOKE ALL ON hocalist.memberships, hocalist.role_profiles, hocalist.profile_contacts
  FROM PUBLIC, anon, authenticated, service_role;

-- Re-assert the bootstrap intent: clients never create objects in this schema.
REVOKE ALL ON SCHEMA hocalist FROM PUBLIC, anon, authenticated;

-- The owner can read membership status to render restriction/onboarding UI.
CREATE POLICY membership_owner_read ON hocalist.memberships
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY active_owner_profile_read ON hocalist.role_profiles
  FOR SELECT TO authenticated USING (EXISTS (
    SELECT 1 FROM hocalist.memberships m
    WHERE m.id = membership_id AND m.user_id = (SELECT auth.uid()) AND m.status = 'active'
  ));
CREATE POLICY active_owner_contact_read ON hocalist.profile_contacts
  FOR SELECT TO authenticated USING (
    user_id = (SELECT auth.uid()) AND EXISTS (
      SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id = (SELECT auth.uid()) AND m.status = 'active'
    )
  );

GRANT USAGE ON SCHEMA hocalist TO authenticated;
GRANT SELECT ON hocalist.memberships, hocalist.role_profiles, hocalist.profile_contacts
  TO authenticated;
COMMENT ON TABLE hocalist.memberships IS
  'Server-provisioned Hocalist membership. No client writes or automatic activation.';
COMMENT ON TABLE hocalist.role_profiles IS
  'Private owner read model. Not a public profile projection. Writes require future reviewed commands.';
COMMENT ON TABLE hocalist.profile_contacts IS
  'Owner-only contacts. No email copy, verification evidence or public projection.';

-- ==== draft 004 DDL (hardened; keep in sync with database/drafts/004) ====
CREATE TABLE hocalist.command_receipts (
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  operation text NOT NULL,
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 128),
  request_hash text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation, idempotency_key)
);
ALTER TABLE hocalist.command_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.command_receipts FROM PUBLIC, anon, authenticated, service_role;

-- Every command locks the caller's seed first. This serializes retries and
-- conflicting changes for that identity, including its shared contacts.
CREATE FUNCTION hocalist.account_command(p_operation text, p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_hash text;
  v_receipt hocalist.command_receipts%ROWTYPE;
  v_member hocalist.memberships%ROWTYPE;
  v_profile hocalist.role_profiles%ROWTYPE;
  v_contact hocalist.profile_contacts%ROWTYPE;
  v_result jsonb;
  v_id uuid;
  v_expected bigint;
  v_allowed text[];
  v_field text;
  v_max integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_operation IS NULL OR p_operation NOT IN ('onboard','profile.update','contact.update') THEN
    RAISE EXCEPTION 'invalid_operation' USING ERRCODE='22023';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
    OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object' OR octet_length(p_input::text) > 16384 THEN
    RAISE EXCEPTION 'invalid_command' USING ERRCODE='22023';
  END IF;
  PERFORM 1 FROM hocalist.profiles WHERE id=v_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'onboarding_seed_required' USING ERRCODE='42501'; END IF;
  -- A restriction cannot be bypassed by enrolling in another role or replaying.
  IF EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id=v_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;

  IF p_operation='onboard' THEN
    v_allowed := ARRAY['role','display_name'];
    IF coalesce(p_input->>'role','') NOT IN ('buyer','seller') THEN
      RAISE EXCEPTION 'invalid_role' USING ERRCODE='22023';
    END IF;
  ELSIF p_operation='profile.update' THEN
    v_allowed := ARRAY['profile_id','expected_revision','display_name','area_label','profile_note',
      'preferred_meetup_type','service_radius_miles','pickup_availability'];
  ELSE
    v_allowed := ARRAY['expected_revision','phone','address_line1','address_line2','city','region','postal_code','country_code'];
  END IF;
  FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
    RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
  END LOOP;
  FOR v_field IN SELECT jsonb_object_keys(p_input) LOOP
    IF v_field NOT IN ('expected_revision','service_radius_miles') AND
       jsonb_typeof(p_input->v_field) NOT IN ('string','null') THEN
      RAISE EXCEPTION 'invalid_field_type: %', v_field USING ERRCODE='22023';
    END IF;
  END LOOP;
  -- Explicit bounds keep a stable 22023 field error instead of a nameless 23514.
  FOR v_field, v_max IN
    SELECT t.f, t.n FROM (VALUES
      ('area_label', 200), ('profile_note', 2000), ('preferred_meetup_type', 100),
      ('pickup_availability', 500), ('phone', 40), ('address_line1', 300),
      ('address_line2', 300), ('city', 150), ('region', 150), ('postal_code', 40)
    ) AS t(f, n)
  LOOP
    IF p_input ? v_field AND jsonb_typeof(p_input->v_field) = 'string'
       AND length(p_input->>v_field) > v_max THEN
      RAISE EXCEPTION 'invalid_field_value: %', v_field USING ERRCODE='22023';
    END IF;
  END LOOP;
  IF p_operation IN ('onboard','profile.update') AND
     (NOT (p_input ? 'display_name') OR p_input->>'display_name' IS NULL
      OR length(btrim(p_input->>'display_name')) NOT BETWEEN 1 AND 200) THEN
    RAISE EXCEPTION 'invalid_display_name' USING ERRCODE='22023';
  END IF;
  IF p_operation <> 'onboard' THEN
    IF jsonb_typeof(p_input->'expected_revision') <> 'number'
      OR coalesce(p_input->>'expected_revision','') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_revision')::bigint;
    IF p_operation='profile.update' THEN
      IF NOT (p_input ? 'profile_id') OR jsonb_typeof(p_input->'profile_id') <> 'string' THEN
        RAISE EXCEPTION 'invalid_profile_id' USING ERRCODE='22023';
      END IF;
      BEGIN v_id := (p_input->>'profile_id')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_profile_id' USING ERRCODE='22023'; END;
      SELECT * INTO v_member FROM hocalist.memberships WHERE id=v_id AND user_id=v_user AND status='active';
      IF NOT FOUND THEN RAISE EXCEPTION 'profile_access_denied' USING ERRCODE='42501'; END IF;
      IF v_member.role='buyer' AND (p_input ? 'service_radius_miles' OR p_input ? 'pickup_availability') THEN
        RAISE EXCEPTION 'seller_fields_on_buyer' USING ERRCODE='22023';
      END IF;
      IF p_input ? 'service_radius_miles' AND jsonb_typeof(p_input->'service_radius_miles') <> 'null' AND
        (jsonb_typeof(p_input->'service_radius_miles') <> 'number' OR (p_input->>'service_radius_miles') !~ '^[0-9]{1,8}$') THEN
        RAISE EXCEPTION 'invalid_radius' USING ERRCODE='22023';
      END IF;
    ELSE
      IF NOT EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id=v_user AND status='active') THEN
        RAISE EXCEPTION 'contact_access_denied' USING ERRCODE='42501';
      END IF;
      IF p_input ? 'country_code' AND jsonb_typeof(p_input->'country_code') = 'string'
         AND p_input->>'country_code' !~ '^[A-Z]{2}$' THEN
        RAISE EXCEPTION 'invalid_country_code' USING ERRCODE='22023';
      END IF;
    END IF;
  END IF;
  v_hash := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  SELECT * INTO v_receipt FROM hocalist.command_receipts
    WHERE user_id=v_user AND operation=p_operation AND idempotency_key=p_key;
  IF FOUND THEN
    IF v_receipt.request_hash <> v_hash THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN v_receipt.result;
  END IF;

  IF p_operation='onboard' THEN
    SELECT * INTO v_member FROM hocalist.memberships WHERE user_id=v_user AND role=p_input->>'role';
    IF FOUND THEN RAISE EXCEPTION 'membership_exists' USING ERRCODE='P0001'; END IF;
    INSERT INTO hocalist.memberships(user_id,role,status) VALUES(v_user,p_input->>'role','active') RETURNING * INTO v_member;
    INSERT INTO hocalist.role_profiles(membership_id,display_name)
      VALUES(v_member.id,btrim(p_input->>'display_name')) RETURNING * INTO v_profile;
    INSERT INTO hocalist.profile_contacts(user_id) VALUES(v_user) ON CONFLICT(user_id) DO NOTHING;
    UPDATE hocalist.profiles SET onboarding_status='complete', updated_at=now() WHERE id=v_user;
    v_result := jsonb_build_object('profile_id',v_member.id,'role',v_member.role,'revision',v_profile.revision);
  ELSIF p_operation='profile.update' THEN
    UPDATE hocalist.role_profiles SET
      display_name=btrim(p_input->>'display_name'),
      area_label=CASE WHEN p_input ? 'area_label' THEN p_input->>'area_label' ELSE area_label END,
      profile_note=CASE WHEN p_input ? 'profile_note' THEN p_input->>'profile_note' ELSE profile_note END,
      preferred_meetup_type=CASE WHEN p_input ? 'preferred_meetup_type' THEN p_input->>'preferred_meetup_type' ELSE preferred_meetup_type END,
      service_radius_miles=CASE WHEN p_input ? 'service_radius_miles' THEN (p_input->>'service_radius_miles')::integer ELSE service_radius_miles END,
      pickup_availability=CASE WHEN p_input ? 'pickup_availability' THEN p_input->>'pickup_availability' ELSE pickup_availability END,
      revision=revision+1,updated_at=now()
    WHERE membership_id=v_id AND revision=v_expected RETURNING * INTO v_profile;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    v_result := jsonb_build_object('profile_id',v_id,'revision',v_profile.revision);
  ELSE
    -- Missing-contact behaviour stays explicit: no upsert and no legacy
    -- identity migration. A missing row (onboard always creates one) is
    -- reported like a stale revision so the adapter keeps its ConflictError.
    IF NOT EXISTS (SELECT 1 FROM hocalist.profile_contacts WHERE user_id=v_user) THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    UPDATE hocalist.profile_contacts SET
      phone=CASE WHEN p_input ? 'phone' THEN p_input->>'phone' ELSE phone END,
      address_line1=CASE WHEN p_input ? 'address_line1' THEN p_input->>'address_line1' ELSE address_line1 END,
      address_line2=CASE WHEN p_input ? 'address_line2' THEN p_input->>'address_line2' ELSE address_line2 END,
      city=CASE WHEN p_input ? 'city' THEN p_input->>'city' ELSE city END,
      region=CASE WHEN p_input ? 'region' THEN p_input->>'region' ELSE region END,
      postal_code=CASE WHEN p_input ? 'postal_code' THEN p_input->>'postal_code' ELSE postal_code END,
      country_code=CASE WHEN p_input ? 'country_code' THEN p_input->>'country_code' ELSE country_code END,
      revision=revision+1,updated_at=now()
    WHERE user_id=v_user AND revision=v_expected RETURNING * INTO v_contact;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    v_result := jsonb_build_object('revision',v_contact.revision);
  END IF;
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(v_user,p_operation,p_key,v_hash,v_result);
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION hocalist.account_command(text,text,jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.account_command(text,text,jsonb) TO authenticated;

-- Post-apply assertions inside the same transaction: any mismatch rolls the
-- whole bundle back.

DO $hocalist_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_function constant text := 'hocalist.account_command(text,text,jsonb)';
  v_receipt_function constant text := 'hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)';
  v_roles constant text[] := ARRAY['anon', 'authenticated', 'service_role'];
  v_privileges constant text[] := ARRAY[
    'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'];
  -- Predicates are sourced from drafts 003 and compared after lowercasing,
  -- removing whitespace, the pg_get_expr "AS uid" alias and ::text casts.
  v_expected_membership_qual constant text :=
    '(user_id=(selectauth.uid()))';
  v_expected_profile_qual constant text :=
    '(exists(select1fromhocalist.membershipsmwhere((m.id=role_profiles.membership_id)and(m.user_id=(selectauth.uid()))and(m.status=''active''))))';
  v_expected_contact_qual constant text :=
    '((user_id=(selectauth.uid()))and(exists(select1fromhocalist.membershipsmwhere((m.user_id=(selectauth.uid()))and(m.status=''active'')))))';
  v_expected_memberships constant text[] := ARRAY[
    'id:uuid', 'user_id:uuid', 'role:text', 'status:text', 'revision:bigint',
    'created_at:timestamp with time zone', 'updated_at:timestamp with time zone'];
  v_expected_role_profiles constant text[] := ARRAY[
    'membership_id:uuid', 'display_name:text', 'area_label:text', 'profile_note:text',
    'preferred_meetup_type:text', 'service_radius_miles:integer', 'pickup_availability:text',
    'revision:bigint', 'created_at:timestamp with time zone', 'updated_at:timestamp with time zone'];
  v_expected_profile_contacts constant text[] := ARRAY[
    'user_id:uuid', 'phone:text', 'address_line1:text', 'address_line2:text', 'city:text',
    'region:text', 'postal_code:text', 'country_code:text', 'revision:bigint',
    'created_at:timestamp with time zone', 'updated_at:timestamp with time zone'];
  v_expected_receipts constant text[] := ARRAY[
    'user_id:uuid', 'operation:text', 'idempotency_key:text', 'request_hash:text',
    'result:jsonb', 'created_at:timestamp with time zone'];
  v_account_tables constant text[] := ARRAY[
    'memberships', 'role_profiles', 'profile_contacts'];
  v_preserved_relations constant text[] := ARRAY['profiles', 'stripe_test_inbox'];
  v_table text;
  v_role text;
  v_priv text;
  v_columns text[];
  v_policy record;
  v_norm text;
BEGIN
  FOREACH v_table IN ARRAY v_account_tables || ARRAY['command_receipts'] LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing table: ' || v_table);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = ('hocalist.' || v_table)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: ' || v_table);
    END IF;
  END LOOP;

  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum) INTO v_columns
  FROM pg_attribute
  WHERE attrelid = 'hocalist.memberships'::regclass AND attnum > 0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_memberships THEN
    v_issues := array_append(v_issues, 'memberships columns differ from the adapter allowlist');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum) INTO v_columns
  FROM pg_attribute
  WHERE attrelid = 'hocalist.role_profiles'::regclass AND attnum > 0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_role_profiles THEN
    v_issues := array_append(v_issues, 'role_profiles columns differ from the adapter allowlist');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum) INTO v_columns
  FROM pg_attribute
  WHERE attrelid = 'hocalist.profile_contacts'::regclass AND attnum > 0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_profile_contacts THEN
    v_issues := array_append(v_issues, 'profile_contacts columns differ from the adapter allowlist');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum) INTO v_columns
  FROM pg_attribute
  WHERE attrelid = 'hocalist.command_receipts'::regclass AND attnum > 0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_receipts THEN
    v_issues := array_append(v_issues, 'command_receipts columns differ from the reviewed shape');
  END IF;

  -- Policy set, attributes and full predicates. Name/role/command checks alone
  -- do not prove row isolation, so the normalized predicate is compared too.
  IF (SELECT count(*) FROM pg_policies
      WHERE schemaname = 'hocalist' AND tablename = ANY(v_account_tables)) <> 3 THEN
    v_issues := array_append(v_issues, 'unexpected account policy set');
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies
             WHERE schemaname = 'hocalist' AND tablename = ANY(v_preserved_relations)) THEN
    v_issues := array_append(v_issues, 'preserved baseline object gained a policy');
  END IF;
  FOR v_policy IN
    SELECT tablename, policyname, permissive, roles::text[] AS roles, cmd, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'hocalist' AND tablename = ANY(v_account_tables)
  LOOP
    IF v_policy.policyname NOT IN (
      'membership_owner_read', 'active_owner_profile_read', 'active_owner_contact_read') THEN
      v_issues := array_append(v_issues, 'unexpected account policy: ' || v_policy.policyname);
      CONTINUE;
    END IF;
    IF v_policy.permissive <> 'PERMISSIVE'
       OR v_policy.cmd <> 'SELECT'
       OR v_policy.roles <> ARRAY['authenticated']
       OR v_policy.with_check IS NOT NULL THEN
      v_issues := array_append(v_issues, 'policy attributes changed: ' || v_policy.policyname);
    END IF;
    v_norm := regexp_replace(
      regexp_replace(
        regexp_replace(lower(coalesce(v_policy.qual, '')), '\s+', '', 'g'),
        'asuid', '', 'g'),
      '::text', '', 'g');
    IF v_policy.policyname = 'membership_owner_read'
       AND v_norm IS DISTINCT FROM v_expected_membership_qual THEN
      v_issues := array_append(v_issues, 'policy predicate changed: ' || v_policy.policyname);
    ELSIF v_policy.policyname = 'active_owner_profile_read'
       AND v_norm IS DISTINCT FROM v_expected_profile_qual THEN
      v_issues := array_append(v_issues, 'policy predicate changed: ' || v_policy.policyname);
    ELSIF v_policy.policyname = 'active_owner_contact_read'
       AND v_norm IS DISTINCT FROM v_expected_contact_qual THEN
      v_issues := array_append(v_issues, 'policy predicate changed: ' || v_policy.policyname);
    END IF;
  END LOOP;

  -- Account table ACLs: exactly authenticated SELECT without grant option,
  -- no column grants, and no effective privilege beyond that.
  FOREACH v_table IN ARRAY v_account_tables LOOP
    IF EXISTS (
      SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
      WHERE c.oid = ('hocalist.' || v_table)::regclass
        AND pg_get_userbyid(a.grantee) <> 'postgres'
        AND NOT (pg_get_userbyid(a.grantee) = 'authenticated'
                 AND a.privilege_type = 'SELECT' AND NOT a.is_grantable)
    ) THEN
      v_issues := array_append(v_issues,
        'hocalist.' || v_table || ' ACL differs from the reviewed authenticated SELECT grant');
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
      WHERE c.oid = ('hocalist.' || v_table)::regclass
        AND pg_get_userbyid(a.grantee) = 'authenticated'
        AND a.privilege_type = 'SELECT' AND NOT a.is_grantable
    ) THEN
      v_issues := array_append(v_issues,
        'authenticated is missing SELECT on hocalist.' || v_table);
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_attribute att, aclexplode(att.attacl) a
      WHERE att.attrelid = ('hocalist.' || v_table)::regclass
        AND att.attnum > 0 AND NOT att.attisdropped
    ) THEN
      v_issues := array_append(v_issues,
        'hocalist.' || v_table || ' has unexpected column grants');
    END IF;
    FOREACH v_role IN ARRAY v_roles LOOP
      FOREACH v_priv IN ARRAY v_privileges LOOP
        IF has_table_privilege(v_role, 'hocalist.' || v_table, v_priv)
           IS DISTINCT FROM (v_role = 'authenticated' AND v_priv = 'SELECT') THEN
          v_issues := array_append(v_issues,
            'unexpected ' || v_priv || ' for ' || v_role || ' on hocalist.' || v_table);
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  -- Receipts: owner-only ACL, no column grants, no effective client access.
  IF EXISTS (
    SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
    WHERE c.oid = 'hocalist.command_receipts'::regclass
      AND pg_get_userbyid(a.grantee) <> 'postgres'
  ) THEN
    v_issues := array_append(v_issues, 'command_receipts has unexpected non-owner grants');
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_attribute att, aclexplode(att.attacl) a
    WHERE att.attrelid = 'hocalist.command_receipts'::regclass
      AND att.attnum > 0 AND NOT att.attisdropped
  ) THEN
    v_issues := array_append(v_issues, 'command_receipts has unexpected column grants');
  END IF;
  FOREACH v_role IN ARRAY v_roles LOOP
    FOREACH v_priv IN ARRAY v_privileges LOOP
      IF has_table_privilege(v_role, 'hocalist.command_receipts', v_priv) THEN
        v_issues := array_append(v_issues,
          'unexpected ' || v_priv || ' for ' || v_role || ' on hocalist.command_receipts');
      END IF;
    END LOOP;
  END LOOP;

  -- account_command: exactly authenticated EXECUTE without grant option.
  IF EXISTS (
    SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
    WHERE p.oid = to_regprocedure(v_function)
      AND pg_get_userbyid(a.grantee) <> 'postgres'
      AND NOT (pg_get_userbyid(a.grantee) = 'authenticated'
               AND a.privilege_type = 'EXECUTE' AND NOT a.is_grantable)
  ) OR EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(v_function) AND p.proacl IS NULL
  ) THEN
    v_issues := array_append(v_issues,
      'account_command ACL differs from the reviewed authenticated EXECUTE grant');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
    WHERE p.oid = to_regprocedure(v_function)
      AND pg_get_userbyid(a.grantee) = 'authenticated'
      AND a.privilege_type = 'EXECUTE' AND NOT a.is_grantable
  ) THEN
    v_issues := array_append(v_issues, 'authenticated is missing EXECUTE on account_command');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = to_regprocedure(v_function)
      AND p.prosecdef
      AND p.proconfig = ARRAY['search_path=""']
      AND pg_get_userbyid(p.proowner) = 'postgres'
  ) THEN
    v_issues := array_append(v_issues, 'account_command security properties changed');
  END IF;
  FOREACH v_role IN ARRAY v_roles LOOP
    IF has_function_privilege(v_role, v_function, 'EXECUTE')
       IS DISTINCT FROM (v_role = 'authenticated') THEN
      v_issues := array_append(v_issues,
        'unexpected EXECUTE for ' || v_role || ' on account_command');
    END IF;
  END LOOP;

  -- Schema: owner plus authenticated and service_role USAGE only.
  IF EXISTS (
    SELECT 1 FROM pg_namespace n, aclexplode(n.nspacl) a
    WHERE n.nspname = 'hocalist'
      AND NOT (
        pg_get_userbyid(a.grantee) = 'postgres'
        OR (pg_get_userbyid(a.grantee) IN ('authenticated', 'service_role')
            AND a.privilege_type = 'USAGE' AND NOT a.is_grantable)
      )
  ) THEN
    v_issues := array_append(v_issues,
      'hocalist schema ACL differs from the reviewed account grant set');
  END IF;
  IF NOT has_schema_privilege('authenticated', 'hocalist', 'USAGE')
     OR has_schema_privilege('authenticated', 'hocalist', 'CREATE')
     OR has_schema_privilege('anon', 'hocalist', 'USAGE')
     OR has_schema_privilege('anon', 'hocalist', 'CREATE')
     OR NOT has_schema_privilege('service_role', 'hocalist', 'USAGE')
     OR has_schema_privilege('service_role', 'hocalist', 'CREATE') THEN
    v_issues := array_append(v_issues, 'schema privileges are wrong after apply');
  END IF;

  -- Preserved baseline privilege matrix (same rules as the guard).
  FOREACH v_table IN ARRAY v_preserved_relations LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'preserved object missing: hocalist.' || v_table);
    ELSE
      IF EXISTS (
        SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
        WHERE c.oid = ('hocalist.' || v_table)::regclass
          AND pg_get_userbyid(a.grantee) <> 'postgres'
      ) THEN
        v_issues := array_append(v_issues,
          'hocalist.' || v_table || ' has unexpected non-owner grants');
      END IF;
      IF EXISTS (
        SELECT 1 FROM pg_attribute att, aclexplode(att.attacl) a
        WHERE att.attrelid = ('hocalist.' || v_table)::regclass
          AND att.attnum > 0 AND NOT att.attisdropped
      ) THEN
        v_issues := array_append(v_issues,
          'hocalist.' || v_table || ' has unexpected column grants');
      END IF;
      IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'hocalist' AND tablename = v_table
      ) THEN
        v_issues := array_append(v_issues,
          'hocalist.' || v_table || ' has an unexpected policy');
      END IF;
      FOREACH v_role IN ARRAY v_roles LOOP
        FOREACH v_priv IN ARRAY v_privileges LOOP
          IF has_table_privilege(v_role, 'hocalist.' || v_table, v_priv) THEN
            v_issues := array_append(v_issues,
              'unexpected ' || v_priv || ' for ' || v_role || ' on hocalist.' || v_table);
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END LOOP;

  IF to_regprocedure(v_receipt_function) IS NULL THEN
    v_issues := array_append(v_issues, 'deployed 005 receive_stripe_test_event is missing');
  ELSE
    IF EXISTS (
      SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure(v_receipt_function)
        AND NOT (
          pg_get_userbyid(a.grantee) = 'postgres'
          OR (pg_get_userbyid(a.grantee) = 'service_role'
              AND a.privilege_type = 'EXECUTE' AND NOT a.is_grantable)
        )
    ) THEN
      v_issues := array_append(v_issues,
        'receive_stripe_test_event ACL differs from the reviewed 005 state');
    END IF;
    FOREACH v_role IN ARRAY v_roles LOOP
      IF (v_role = 'service_role'
          AND NOT has_function_privilege(v_role, v_receipt_function, 'EXECUTE'))
         OR (v_role <> 'service_role'
          AND has_function_privilege(v_role, v_receipt_function, 'EXECUTE')) THEN
        v_issues := array_append(v_issues,
          'receive_stripe_test_event execution differs for ' || v_role);
      END IF;
    END LOOP;
  END IF;
  IF to_regprocedure('hocalist.handle_new_user()') IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.handle_new_user()')
        AND pg_get_userbyid(a.grantee) <> 'postgres'
    ) THEN
      v_issues := array_append(v_issues, 'handle_new_user has unexpected execution grants');
    END IF;
    FOREACH v_role IN ARRAY v_roles LOOP
      IF has_function_privilege(v_role, 'hocalist.handle_new_user()', 'EXECUTE') THEN
        v_issues := array_append(v_issues,
          'unexpected EXECUTE for ' || v_role || ' on handle_new_user');
      END IF;
    END LOOP;
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
    RAISE EXCEPTION 'hocalist post-apply verification failed: %', array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_postapply$;
COMMIT;
SELECT 'PASS: account bundle applied and verified' AS account_rollout;

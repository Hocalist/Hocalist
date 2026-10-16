-- Read-only foundation verification, before plan activation.
BEGIN READ ONLY;
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
DO $provider_verify$
DECLARE t text; r text; p text; f record; allowed_role text;
BEGIN
 FOREACH t IN ARRAY ARRAY['stripe_test_plans','stripe_test_customers','stripe_test_checkouts','stripe_test_subscriptions','stripe_test_worker_lock','push_devices','notifications','push_deliveries'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('hocalist.'||t) AND relrowsecurity AND relowner='postgres'::regrole) THEN
   RAISE EXCEPTION 'Provider table owner/RLS mismatch: %',t; END IF;
  IF EXISTS(SELECT 1 FROM pg_class c,aclexplode(c.relacl) a WHERE c.oid=to_regclass('hocalist.'||t)
   AND NOT(a.grantee='postgres'::regrole OR(t='notifications' AND a.grantee='authenticated'::regrole AND a.privilege_type='SELECT' AND NOT a.is_grantable))) THEN
   RAISE EXCEPTION 'Provider table ACL mismatch: %',t; END IF;
  IF EXISTS(SELECT 1 FROM pg_attribute a,aclexplode(a.attacl) x WHERE a.attrelid=to_regclass('hocalist.'||t) AND x.grantee<>'postgres'::regrole) THEN
   RAISE EXCEPTION 'Unexpected provider column grant: %',t; END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   FOREACH p IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
    IF has_table_privilege(r,'hocalist.'||t,p) IS DISTINCT FROM (t='notifications' AND r='authenticated' AND p='SELECT') THEN
     RAISE EXCEPTION 'Unexpected provider permission: % % %',t,r,p; END IF;
   END LOOP;
  END LOOP;
 END LOOP;
 IF (SELECT count(*) FROM pg_policy WHERE polrelid='hocalist.notifications'::regclass)<>1
 OR NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.notifications'::regclass AND polname='own_notification_read'
  AND polcmd='r' AND polpermissive AND polroles=ARRAY['authenticated'::regrole::oid] AND polwithcheck IS NULL
  AND md5(pg_get_expr(polqual,polrelid))='b29f9d33454f4464ad0d1df1486aaf69') THEN RAISE EXCEPTION 'Notification policy mismatch'; END IF;
 FOR f IN SELECT * FROM (VALUES
 ('hocalist.notification_enqueue(uuid,uuid,text,uuid)','ce9fe8b53787f218be794206deb9b4ee','service_role'),
 ('hocalist.push_claim()','b03572856ee85a8b44cf25c974447769','service_role'),
 ('hocalist.push_delivery_target(uuid,uuid)','4cb8c3d0df011f98c730a7d491a694a9','service_role'),
 ('hocalist.push_device_disable(uuid,text)','b83ac1d7f4d40e36337a6ba2439dde3e','authenticated'),
 ('hocalist.push_device_register(uuid,text,text,boolean)','3f16426321e84d08eb8016c0f04d1d28','authenticated'),
 ('hocalist.push_finish(uuid,uuid,text,integer)','11c1a677253561b798f889301e240b6a','service_role'),
 ('hocalist.stripe_test_billing_status()','9f187a6c93e9eaa8f4c843548f3987ff','authenticated'),
 ('hocalist.stripe_test_checkout_begin(uuid,text,uuid)','8b31107c499f9cb50fb0ab5996b2fa3a','service_role'),
 ('hocalist.stripe_test_checkout_bind(uuid,text,text,text)','408b9084dd5c322af60691177bbe9ebe','service_role'),
 ('hocalist.stripe_test_checkout_expire(uuid,text,text)','259ef6a9a81c2643cd92eda43cc350c9','service_role'),
 ('hocalist.stripe_test_claim()','14d7aa63e072dc8e2c9c935fc6793393','service_role'),
 ('hocalist.stripe_test_customer_context(text)','f652b2bbb9f8256512a14a4cb439ffc7','service_role'),
 ('hocalist.stripe_test_finish(uuid,text,text,jsonb,text)','492c607acaceaf0e47ee3026cd55f957','service_role')
 ) AS expected(signature,digest,grantee) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(f.signature) AND prosecdef AND proowner='postgres'::regrole
   AND md5(replace(pg_get_functiondef(oid),chr(13),''))=f.digest AND proacl IS NOT NULL) THEN RAISE EXCEPTION 'Provider function mismatch: %',f.signature; END IF;
  IF EXISTS(SELECT 1 FROM pg_proc q,aclexplode(q.proacl) a WHERE q.oid=to_regprocedure(f.signature)
   AND NOT(a.grantee='postgres'::regrole OR(a.grantee=f.grantee::regrole AND a.privilege_type='EXECUTE' AND NOT a.is_grantable))) THEN
   RAISE EXCEPTION 'Provider function ACL mismatch: %',f.signature; END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_function_privilege(r,f.signature,'EXECUTE') IS DISTINCT FROM (r=f.grantee) THEN
    RAISE EXCEPTION 'Unexpected provider execution permission: % %',f.signature,r; END IF;
  END LOOP;
 END LOOP;
 IF EXISTS(SELECT 1 FROM hocalist.stripe_test_plans WHERE enabled) THEN RAISE EXCEPTION 'Plans must stay disabled at foundation rollout'; END IF;
END;
$provider_verify$;
SELECT 'PASS: provider foundation permissions and disabled plans verified' AS provider_verify;
ROLLBACK;

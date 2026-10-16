-- Hocalist chat rollout preflight. READ-ONLY: safe to run repeatedly.
--
-- Validates the deployed account 003/004, Stripe receipt 005, billing 006 and
-- push 007 inventory, and aborts on any baseline drift or pre-existing chat
-- object. The DO block is textually identical to the guard in apply.sql;
-- database/chat/tests/chat_rollout.test.mjs asserts it.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $hocalist_chat_guard$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_required_relations constant text[] := ARRAY[
    'profiles','memberships','role_profiles','profile_contacts','command_receipts',
    'stripe_test_inbox','stripe_test_plans','stripe_test_customers','stripe_test_checkouts',
    'stripe_test_subscriptions','stripe_test_worker_lock',
    'push_devices','notifications','push_deliveries'];
  v_chat_relations constant text[] := ARRAY[
    'conversations','conversation_members','conversation_messages'];
  v_required_functions constant text[] := ARRAY[
    'handle_new_user()',
    'receive_stripe_test_event(text,text,text,text,bigint,boolean)',
    'account_command(text,text,jsonb)',
    'stripe_test_checkout_begin(uuid,text,uuid)',
    'stripe_test_checkout_bind(uuid,text,text,text)',
    'stripe_test_checkout_expire(uuid,text,text)',
    'stripe_test_claim()','stripe_test_customer_context(text)',
    'stripe_test_finish(uuid,text,text,jsonb,text)','stripe_test_billing_status()',
    'push_device_register(uuid,text,text,boolean)','push_device_disable(uuid,text)',
    'notification_enqueue(uuid,uuid,text,uuid)','push_claim()',
    'push_delivery_target(uuid,uuid)','push_finish(uuid,uuid,text,integer)'];
  v_chat_functions constant text[] := ARRAY[
    'chat_inbox(integer,text)','chat_conversation(uuid)','chat_messages(uuid,integer,uuid)',
    'chat_send(uuid,text,text)','chat_mark_read(uuid,uuid)','chat_set_muted(uuid,boolean)',
    'chat_assert_participant(uuid,uuid)','chat_conversation_json(uuid)','chat_is_member(uuid,uuid)',
    'chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)'];
  -- Optional independently deployed Places module: exact names, verified below.
  v_places_relations constant text[] := ARRAY[
    'places_search_sessions','places_search_suggestions','places_rate_counters'];
  v_places_functions constant text[] := ARRAY[
    'places_gate(uuid,text,uuid,text,text)',
    'places_record_suggestions(uuid,uuid,text[])',
    'places_resolve_session(uuid,uuid)','places_release_session(uuid,uuid)',
    'places_rate_bump(text,text,text,timestamp with time zone)'];
  v_rel text;
  v_fn text;
BEGIN
  IF to_regnamespace('hocalist') IS NULL THEN
    v_issues := array_append(v_issues, 'hocalist schema is missing');
  ELSE
    IF (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname='hocalist')
       IS DISTINCT FROM 'postgres' THEN
      v_issues := array_append(v_issues, 'hocalist schema owner is not postgres');
    END IF;
    IF NOT has_schema_privilege('authenticated','hocalist','USAGE')
       OR NOT has_schema_privilege('service_role','hocalist','USAGE')
       OR has_schema_privilege('anon','hocalist','USAGE')
       OR has_schema_privilege('anon','hocalist','CREATE')
       OR has_schema_privilege('authenticated','hocalist','CREATE')
       OR has_schema_privilege('service_role','hocalist','CREATE') THEN
      v_issues := array_append(v_issues, 'hocalist schema access differs from the reviewed baseline');
    END IF;
  END IF;

  -- Relations: required present, chat absent, nothing else unexpected.
  FOREACH v_rel IN ARRAY v_required_relations LOOP
    IF to_regclass('hocalist.' || v_rel) IS NULL THEN
      v_issues := array_append(v_issues, 'missing baseline relation: hocalist.' || v_rel);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.' || v_rel)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: hocalist.' || v_rel);
    END IF;
  END LOOP;
  FOR v_rel IN
    SELECT c.relname FROM pg_class c
    WHERE c.relnamespace = to_regnamespace('hocalist')
      AND c.relkind IN ('r','p','v','m','S','f')
  LOOP
    IF v_rel = ANY(v_chat_relations) THEN
      v_issues := array_append(v_issues, 'chat relation already exists: ' || v_rel);
    ELSIF NOT (v_rel = ANY(v_required_relations) OR v_rel = ANY(v_places_relations)) THEN
      v_issues := array_append(v_issues, 'unexpected relation in hocalist: ' || v_rel);
    END IF;
  END LOOP;

  -- Functions: required present, chat absent, nothing else unexpected.
  FOREACH v_fn IN ARRAY v_required_functions LOOP
    IF to_regprocedure('hocalist.' || v_fn) IS NULL THEN
      v_issues := array_append(v_issues, 'missing baseline function: ' || v_fn);
    END IF;
  END LOOP;
  FOR v_fn IN
    SELECT p.proname || '(' || replace(oidvectortypes(p.proargtypes), ', ', ',') || ')'
    FROM pg_proc p WHERE p.pronamespace = to_regnamespace('hocalist')
  LOOP
    IF v_fn = ANY(v_chat_functions) THEN
      v_issues := array_append(v_issues, 'chat function already exists: ' || v_fn);
    ELSIF NOT (v_fn = ANY(v_required_functions) OR v_fn = ANY(v_places_functions)) THEN
      v_issues := array_append(v_issues, 'unexpected function in hocalist: ' || v_fn);
    END IF;
  END LOOP;

  -- Focused ACL invariants for the deployed account, billing and push state.
  IF to_regclass('hocalist.memberships') IS NOT NULL
     AND to_regclass('hocalist.role_profiles') IS NOT NULL
     AND to_regclass('hocalist.profile_contacts') IS NOT NULL
     AND to_regclass('hocalist.command_receipts') IS NOT NULL
     AND to_regprocedure('hocalist.account_command(text,text,jsonb)') IS NOT NULL THEN
    IF NOT has_table_privilege('authenticated','hocalist.memberships','SELECT')
       OR NOT has_table_privilege('authenticated','hocalist.role_profiles','SELECT')
       OR NOT has_table_privilege('authenticated','hocalist.profile_contacts','SELECT')
       OR has_table_privilege('authenticated','hocalist.memberships','INSERT')
       OR has_table_privilege('authenticated','hocalist.command_receipts','SELECT')
       OR has_table_privilege('anon','hocalist.memberships','SELECT')
       OR has_table_privilege('service_role','hocalist.memberships','SELECT') THEN
      v_issues := array_append(v_issues, 'account table grants differ from the reviewed rollout');
    END IF;
    IF NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE')
       OR has_function_privilege('anon','hocalist.account_command(text,text,jsonb)','EXECUTE')
       OR has_function_privilege('service_role','hocalist.account_command(text,text,jsonb)','EXECUTE') THEN
      v_issues := array_append(v_issues, 'account_command grants differ from the reviewed rollout');
    END IF;
  END IF;
  IF to_regclass('hocalist.stripe_test_inbox') IS NOT NULL
     AND to_regprocedure('hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)') IS NOT NULL THEN
    IF NOT has_function_privilege('service_role','hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)','EXECUTE')
       OR has_function_privilege('authenticated','hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)','EXECUTE')
       OR has_table_privilege('service_role','hocalist.stripe_test_inbox','SELECT') THEN
      v_issues := array_append(v_issues, 'stripe receipt grants differ from the reviewed rollout');
    END IF;
  END IF;
  IF to_regprocedure('hocalist.stripe_test_billing_status()') IS NOT NULL
     AND to_regprocedure('hocalist.stripe_test_checkout_begin(uuid,text,uuid)') IS NOT NULL
     AND to_regprocedure('hocalist.stripe_test_claim()') IS NOT NULL
     AND to_regclass('hocalist.stripe_test_checkouts') IS NOT NULL THEN
    IF NOT has_function_privilege('authenticated','hocalist.stripe_test_billing_status()','EXECUTE')
       OR has_function_privilege('authenticated','hocalist.stripe_test_checkout_begin(uuid,text,uuid)','EXECUTE')
       OR NOT has_function_privilege('service_role','hocalist.stripe_test_claim()','EXECUTE')
       OR has_table_privilege('authenticated','hocalist.stripe_test_checkouts','SELECT') THEN
      v_issues := array_append(v_issues, 'billing grants differ from the reviewed rollout');
    END IF;
  END IF;
  IF to_regclass('hocalist.notifications') IS NOT NULL
     AND to_regclass('hocalist.push_devices') IS NOT NULL
     AND to_regprocedure('hocalist.push_device_register(uuid,text,text,boolean)') IS NOT NULL
     AND to_regprocedure('hocalist.push_claim()') IS NOT NULL THEN
    IF NOT has_table_privilege('authenticated','hocalist.notifications','SELECT')
       OR has_table_privilege('authenticated','hocalist.push_devices','SELECT')
       OR NOT has_function_privilege('authenticated','hocalist.push_device_register(uuid,text,text,boolean)','EXECUTE')
       OR NOT has_function_privilege('service_role','hocalist.push_claim()','EXECUTE')
       OR has_function_privilege('authenticated','hocalist.push_claim()','EXECUTE') THEN
      v_issues := array_append(v_issues, 'push grants differ from the reviewed rollout');
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='auth.users'::regclass AND t.tgname='on_auth_user_created'
      AND t.tgfoid=to_regprocedure('hocalist.handle_new_user()')
      AND t.tgtype=5 AND t.tgenabled='O'
  ) THEN
    v_issues := array_append(v_issues, 'signup routing trigger changed');
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_default_acl d
    WHERE pg_get_userbyid(d.defaclrole)='postgres'
      AND (d.defaclnamespace=0 OR d.defaclnamespace=to_regnamespace('hocalist'))
      AND EXISTS (
        SELECT 1 FROM aclexplode(d.defaclacl) a
        WHERE a.grantee=0 OR a.grantee IN (
          SELECT oid FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role'))
      )
  ) THEN
    v_issues := array_append(v_issues,
      'postgres default privileges would grant client/service access to new hocalist objects');
  END IF;


  -- If any Places object exists, require the complete reviewed module.
  IF EXISTS (SELECT 1 FROM pg_class WHERE relnamespace=to_regnamespace('hocalist')
      AND relname=ANY(v_places_relations))
     OR EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace=to_regnamespace('hocalist')
      AND proname LIKE 'places_%') THEN
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_service_functions constant text[] := ARRAY[
    'places_gate(uuid,text,uuid,text,text)',
    'places_record_suggestions(uuid,uuid,text[])',
    'places_resolve_session(uuid,uuid)',
    'places_release_session(uuid,uuid)'];
  v_tables constant text[] := ARRAY[
    'places_search_sessions','places_search_suggestions','places_rate_counters'];
  v_fn text;
  v_table text;
  v_columns text[];
  v_expected_sessions constant text[] := ARRAY[
    'token:uuid','user_id:uuid','operation_count:integer',
    'created_at:timestamp with time zone','expires_at:timestamp with time zone',
    'resolved_at:timestamp with time zone','resolving_at:timestamp with time zone'];
  v_expected_suggestions constant text[] := ARRAY[
    'session_token:uuid','place_id:text','created_at:timestamp with time zone'];
  v_expected_counters constant text[] := ARRAY[
    'scope:text','operation:text','window_kind:text',
    'bucket:timestamp with time zone','count:integer'];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing places table: ' || v_table);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.' || v_table)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: ' || v_table);
    ELSIF has_table_privilege('authenticated', 'hocalist.' || v_table, 'SELECT')
       OR has_table_privilege('anon', 'hocalist.' || v_table, 'SELECT') THEN
      v_issues := array_append(v_issues, 'places table is client-readable: ' || v_table);
    END IF;
  END LOOP;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_search_sessions'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_sessions THEN
    v_issues := array_append(v_issues, 'places_search_sessions columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_search_suggestions'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_suggestions THEN
    v_issues := array_append(v_issues, 'places_search_suggestions columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_rate_counters'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_counters THEN
    v_issues := array_append(v_issues, 'places_rate_counters columns differ from the reviewed shape');
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist'
      AND table_name IN ('places_search_sessions','places_search_suggestions','places_rate_counters')
      AND column_name ~* '(query|label|address|input|display|formatted|latitude|longitude)'
  ) THEN
    v_issues := array_append(v_issues, 'places gateway must not store queries, labels or addresses');
  END IF;
  FOREACH v_fn IN ARRAY v_service_functions LOOP
    IF NOT has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'places function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  IF has_function_privilege(
       'authenticated','hocalist.places_rate_bump(text,text,text,timestamptz)','EXECUTE')
     OR has_function_privilege(
       'service_role','hocalist.places_rate_bump(text,text,text,timestamptz)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'internal places helper is executable');
  END IF;
  IF NOT has_function_privilege(
       'authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed account grants changed');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist places post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
;
    IF to_regprocedure('hocalist.places_rate_bump(text,text,text,timestamptz)') IS NULL THEN
      RAISE EXCEPTION 'Places internal helper missing';
    END IF;
  END IF;

  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist chat preflight failed: %', array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_chat_guard$;
SELECT 'PASS: reviewed baseline intact; chat objects absent' AS chat_preflight;
ROLLBACK;

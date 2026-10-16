-- Hocalist chat rollout verification. READ-ONLY: safe any time after
-- apply.sql. The DO block is textually identical to the post-apply block in
-- apply.sql; database/chat/tests/chat_rollout.test.mjs asserts that equality.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $hocalist_chat_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_table text;
  v_role text;
  v_priv text;
  v_columns text[];
  v_roles constant text[] := ARRAY['anon','authenticated','service_role'];
  v_privileges constant text[] := ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'];
  v_chat_tables constant text[] := ARRAY['conversations','conversation_members','conversation_messages'];
  v_client_functions constant text[] := ARRAY[
    'chat_inbox(integer,text)','chat_conversation(uuid)','chat_messages(uuid,integer,uuid)',
    'chat_send(uuid,text,text)','chat_mark_read(uuid,uuid)','chat_set_muted(uuid,boolean)'];
  v_internal_functions constant text[] := ARRAY[
    'chat_assert_participant(uuid,uuid)','chat_conversation_json(uuid)',
    'chat_is_member(uuid,uuid)','chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)'];
  v_expected_conversations constant text[] := ARRAY[
    'id:uuid','origin:text','status:text','request_id:uuid','offer_id:uuid','listing_id:uuid',
    'discovery_topic_id:uuid','revision:bigint','created_at:timestamp with time zone',
    'updated_at:timestamp with time zone'];
  v_expected_messages constant text[] := ARRAY[
    'id:uuid','conversation_id:uuid','sender_user_id:uuid','sender_profile_id:uuid','kind:text',
    'text:text','client_message_id:text','request_hash:text','seq:bigint',
    'sent_at:timestamp with time zone'];
  v_expected_members constant text[] := ARRAY[
    'conversation_id:uuid','user_id:uuid','profile_id:uuid','role:text','joined_at:timestamp with time zone',
    'revoked_at:timestamp with time zone','is_muted:boolean','last_read_seq:bigint',
    'last_read_message_id:uuid','last_read_at:timestamp with time zone'];
  v_fn text;
BEGIN
  FOREACH v_table IN ARRAY v_chat_tables LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing chat table: ' || v_table);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.' || v_table)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: ' || v_table);
    END IF;
  END LOOP;

  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum) INTO v_columns
  FROM pg_attribute WHERE attrelid='hocalist.conversations'::regclass AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_conversations THEN
    v_issues := array_append(v_issues, 'conversations columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum) INTO v_columns
  FROM pg_attribute WHERE attrelid='hocalist.conversation_messages'::regclass AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_messages THEN
    v_issues := array_append(v_issues, 'conversation_messages columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum) INTO v_columns
  FROM pg_attribute WHERE attrelid='hocalist.conversation_members'::regclass AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_members THEN
    v_issues := array_append(v_issues, 'conversation_members columns differ from the reviewed shape');
  END IF;

  IF (SELECT count(*) FROM pg_policies WHERE schemaname='hocalist' AND tablename LIKE 'conversation%') <> 3 THEN
    v_issues := array_append(v_issues, 'unexpected chat policy set');
  END IF;

  FOREACH v_table IN ARRAY v_chat_tables LOOP
    IF EXISTS (
      SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
      WHERE c.oid=('hocalist.' || v_table)::regclass
        AND pg_get_userbyid(a.grantee) <> 'postgres'
    ) THEN
      v_issues := array_append(v_issues, 'unexpected non-owner grants on ' || v_table);
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_attribute att, aclexplode(att.attacl) a
      WHERE att.attrelid=('hocalist.' || v_table)::regclass
        AND att.attnum>0 AND NOT att.attisdropped
    ) THEN
      v_issues := array_append(v_issues, 'unexpected column grants on ' || v_table);
    END IF;
    FOREACH v_role IN ARRAY v_roles LOOP
      FOREACH v_priv IN ARRAY v_privileges LOOP
        IF has_table_privilege(v_role, 'hocalist.' || v_table, v_priv) THEN
          v_issues := array_append(v_issues,
            'unexpected ' || v_priv || ' for ' || v_role || ' on ' || v_table);
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  FOREACH v_fn IN ARRAY v_client_functions LOOP
    IF NOT has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'chat function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY v_internal_functions LOOP
    IF has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'internal chat function is executable: ' || v_fn);
    END IF;
  END LOOP;

  -- Deployed account, billing and push state must be untouched.
  IF NOT has_table_privilege('authenticated','hocalist.memberships','SELECT')
     OR has_table_privilege('authenticated','hocalist.memberships','INSERT')
     OR NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.stripe_test_billing_status()','EXECUTE')
     OR NOT has_table_privilege('authenticated','hocalist.notifications','SELECT')
     OR NOT has_function_privilege('service_role','hocalist.push_claim()','EXECUTE')
     OR has_table_privilege('service_role','hocalist.stripe_test_inbox','SELECT') THEN
    v_issues := array_append(v_issues, 'deployed account/billing/push grants changed');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='auth.users'::regclass AND t.tgname='on_auth_user_created'
      AND t.tgfoid=to_regprocedure('hocalist.handle_new_user()') AND t.tgenabled='O'
  ) THEN
    v_issues := array_append(v_issues, 'signup routing trigger changed');
  END IF;

  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist chat post-apply verification failed: %', array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_chat_postapply$;
SELECT 'PASS: chat objects, grants and preserved deployed state verified' AS chat_verify;
ROLLBACK;

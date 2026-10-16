-- Hocalist chat containment. NON-DESTRUCTIVE.
--
-- Withdraws client execution of the chat RPCs without deleting any rows:
-- conversations, members and messages stay intact, as do the deployed
-- account/billing/push objects and grants. Safe to run repeatedly.
--
-- Limits: this is grants-only containment, not a rollback. It does not repair
-- baseline drift and does not touch other schemas.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '15s';
REVOKE EXECUTE ON FUNCTION hocalist.chat_inbox(integer,text),
  hocalist.chat_conversation(uuid), hocalist.chat_messages(uuid,integer,uuid),
  hocalist.chat_send(uuid,text,text), hocalist.chat_mark_read(uuid,uuid),
  hocalist.chat_set_muted(uuid,boolean)
  FROM PUBLIC, anon, authenticated, service_role;
DO $hocalist_chat_containment$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_fn text;
  v_functions constant text[] := ARRAY[
    'chat_inbox(integer,text)','chat_conversation(uuid)','chat_messages(uuid,integer,uuid)',
    'chat_send(uuid,text,text)','chat_mark_read(uuid,uuid)','chat_set_muted(uuid,boolean)'];
  v_table text;
BEGIN
  FOREACH v_fn IN ARRAY v_functions LOOP
    IF has_function_privilege('authenticated','hocalist.' || v_fn,'EXECUTE')
       OR has_function_privilege('anon','hocalist.' || v_fn,'EXECUTE')
       OR has_function_privilege('service_role','hocalist.' || v_fn,'EXECUTE') THEN
      v_issues := array_append(v_issues, 'client can still execute ' || v_fn);
    END IF;
  END LOOP;
  FOREACH v_table IN ARRAY ARRAY['conversations','conversation_members','conversation_messages'] LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'chat table missing (containment must not drop data): ' || v_table);
    END IF;
  END LOOP;
  IF NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE')
     OR NOT has_table_privilege('authenticated','hocalist.notifications','SELECT')
     OR NOT has_function_privilege('service_role','hocalist.push_claim()','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed account/push grants were disturbed');
  END IF;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname='hocalist' AND tablename LIKE 'conversation%') <> 3 THEN
    v_issues := array_append(v_issues, 'chat policies were altered');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist chat containment verification failed: %', array_to_string(v_issues,' | ');
  END IF;
END
$hocalist_chat_containment$;
COMMIT;
SELECT 'PASS: client chat access contained; rows and deployed objects preserved' AS chat_containment;

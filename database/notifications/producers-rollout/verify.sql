-- Hocalist notification producer rollout verification. READ-ONLY: safe any
-- time after apply.sql. The DO block is textually identical to the post-apply
-- block in apply.sql; database/notifications/tests/producers_rollout.test.mjs
-- asserts that equality.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $hocalist_notification_producer_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_producer_functions constant text[] := ARRAY[
    'notification_recipient_allowed(uuid)',
    'notification_on_offer_insert()','notification_on_message_insert()',
    'notification_on_meeting_proposal()','notification_on_meeting_status()'];
  v_triggers constant text[] := ARRAY[
    'offers:notification_offer_insert',
    'conversation_messages:notification_message_insert',
    'meeting_schedule_revisions:notification_meeting_proposal',
    'meetings:notification_meeting_status'];
  v_fn text;
  v_entry text;
  v_table text;
  v_trigger text;
BEGIN
  FOREACH v_fn IN ARRAY v_producer_functions LOOP
    IF to_regprocedure('hocalist.' || v_fn) IS NULL THEN
      v_issues := array_append(v_issues, 'missing producer function: ' || v_fn);
    ELSIF has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'producer function is executable: ' || v_fn);
    END IF;
  END LOOP;
  FOREACH v_entry IN ARRAY v_triggers LOOP
    v_table := split_part(v_entry, ':', 1);
    v_trigger := split_part(v_entry, ':', 2);
    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgrelid = ('hocalist.' || v_table)::regclass
        AND tgname = v_trigger AND NOT tgisinternal
    ) THEN
      v_issues := array_append(v_issues, 'missing producer trigger: ' || v_entry);
    END IF;
  END LOOP;
  IF NOT has_function_privilege(
       'authenticated','hocalist.notification_inbox(integer,text)','EXECUTE')
     OR has_function_privilege(
       'authenticated','hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed notification/account grants changed');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist notification producer post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_notification_producer_postapply$;
SELECT 'notification producer verification passed' AS status;
COMMIT;

-- Hocalist notification inbox rollout verification. READ-ONLY: safe any time
-- after apply.sql. The DO block is textually identical to the post-apply block
-- in apply.sql; database/notifications/tests/notifications_rollout.test.mjs
-- asserts that equality.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $hocalist_notification_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_client_functions constant text[] := ARRAY[
    'notification_inbox(integer,text)','notification_mark_read(uuid)',
    'notification_mark_all_read()','notification_preferences()',
    'notification_preferences_update(jsonb)'];
  v_internal_functions constant text[] := ARRAY[
    'notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)',
    'notification_enqueue(uuid,uuid,text,uuid)'];
  v_fn text;
  v_columns text[];
  v_expected text[] := ARRAY[
    'id:uuid','user_id:uuid','event_key:uuid','kind:text','source_id:uuid',
    'created_at:timestamp with time zone','read_at:timestamp with time zone',
    'title:text','body:text','deep_link:text','payload:jsonb'];
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'hocalist.notification_preferences'::regclass
      AND conname = 'notification_preferences_safety_mandatory'
  ) THEN
    v_issues := array_append(v_issues, 'safety preference is not mandatory');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid = 'hocalist.notifications'::regclass AND attnum > 0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected THEN
    v_issues := array_append(v_issues, 'notifications columns differ from the reviewed shape');
  END IF;
  FOREACH v_fn IN ARRAY v_client_functions LOOP
    IF NOT has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'notification function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY v_internal_functions LOOP
    IF has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'internal notification function is executable: ' || v_fn);
    END IF;
  END LOOP;
  -- The deployed push queue and account state must be untouched.
  IF NOT has_function_privilege('authenticated','hocalist.push_device_register(uuid,text,text,boolean)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE')
     OR NOT has_table_privilege('authenticated','hocalist.memberships','SELECT') THEN
    v_issues := array_append(v_issues, 'deployed account/push grants changed');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist notification post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_notification_postapply$;
SELECT 'notification inbox verification passed' AS status;
COMMIT;

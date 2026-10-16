BEGIN READ ONLY;
DO $hocalist_request_update_producer_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF to_regprocedure('hocalist.notification_on_request_update()') IS NULL THEN
    v_issues := array_append(v_issues, 'missing request-update producer function');
  ELSIF has_function_privilege(
          'authenticated','hocalist.notification_on_request_update()','EXECUTE')
     OR has_function_privilege('anon','hocalist.notification_on_request_update()','EXECUTE')
     OR has_function_privilege('service_role','hocalist.notification_on_request_update()','EXECUTE') THEN
    v_issues := array_append(v_issues, 'request-update producer function is executable');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'hocalist.requests'::regclass
      AND tgname = 'notification_request_update' AND NOT tgisinternal
  ) THEN
    v_issues := array_append(v_issues, 'missing request-update producer trigger');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'hocalist.notification_preferences'::regclass
      AND attname = 'leads' AND attnotnull AND NOT attisdropped
  ) THEN
    v_issues := array_append(v_issues, 'missing mandatory leads preference column');
  END IF;
  IF NOT has_function_privilege(
       'authenticated','hocalist.notification_preferences()','EXECUTE')
     OR NOT has_function_privilege(
       'authenticated','hocalist.notification_preferences_update(jsonb)','EXECUTE')
     OR has_function_privilege(
       'authenticated','hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'notification preference grants changed');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist request-update producer post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_request_update_producer_postapply$;
DO $request_update_state_verify$
BEGIN
IF to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL
     OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)')), chr(13), '')) <> 'c71fd4f4e7a92718967e8d7b705f8e15' THEN
  RAISE EXCEPTION 'Function drift: notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)';
END IF;
IF has_function_privilege('anon', 'hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)', 'EXECUTE') IS DISTINCT FROM false
   OR has_function_privilege('authenticated', 'hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)', 'EXECUTE') IS DISTINCT FROM false
   OR has_function_privilege('service_role', 'hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)', 'EXECUTE') IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Function privilege drift: notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)';
END IF;
IF to_regprocedure('hocalist.notification_preferences()') IS NULL
     OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.notification_preferences()')), chr(13), '')) <> 'fa85ac29dc234fa491d78b3781536ed6' THEN
  RAISE EXCEPTION 'Function drift: notification_preferences()';
END IF;
IF has_function_privilege('anon', 'hocalist.notification_preferences()', 'EXECUTE') IS DISTINCT FROM false
   OR has_function_privilege('authenticated', 'hocalist.notification_preferences()', 'EXECUTE') IS DISTINCT FROM true
   OR has_function_privilege('service_role', 'hocalist.notification_preferences()', 'EXECUTE') IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Function privilege drift: notification_preferences()';
END IF;
IF to_regprocedure('hocalist.notification_preferences_update(jsonb)') IS NULL
     OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.notification_preferences_update(jsonb)')), chr(13), '')) <> '26f24990369f0a91603054ec42af7c69' THEN
  RAISE EXCEPTION 'Function drift: notification_preferences_update(jsonb)';
END IF;
IF has_function_privilege('anon', 'hocalist.notification_preferences_update(jsonb)', 'EXECUTE') IS DISTINCT FROM false
   OR has_function_privilege('authenticated', 'hocalist.notification_preferences_update(jsonb)', 'EXECUTE') IS DISTINCT FROM true
   OR has_function_privilege('service_role', 'hocalist.notification_preferences_update(jsonb)', 'EXECUTE') IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Function privilege drift: notification_preferences_update(jsonb)';
END IF;
IF to_regprocedure('hocalist.notification_on_request_update()') IS NULL
     OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.notification_on_request_update()')), chr(13), '')) <> '6d795ac88dce5b89c15d9c1c3b16a353' THEN
  RAISE EXCEPTION 'Function drift: notification_on_request_update()';
END IF;
IF has_function_privilege('anon', 'hocalist.notification_on_request_update()', 'EXECUTE') IS DISTINCT FROM false
   OR has_function_privilege('authenticated', 'hocalist.notification_on_request_update()', 'EXECUTE') IS DISTINCT FROM false
   OR has_function_privilege('service_role', 'hocalist.notification_on_request_update()', 'EXECUTE') IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Function privilege drift: notification_on_request_update()';
END IF;
IF NOT EXISTS (
  SELECT 1 FROM pg_constraint
  WHERE conrelid = 'hocalist.notifications'::regclass
    AND conname = 'notifications_kind_check'
    AND pg_get_constraintdef(oid) = 'CHECK ((kind = ANY (ARRAY[''new_offer''::text, ''new_message''::text, ''meeting_update''::text, ''request_update''::text, ''billing_update''::text, ''account_update''::text])))') THEN
  RAISE EXCEPTION 'Notification kind constraint drift';
END IF;
IF NOT EXISTS (
  SELECT 1 FROM pg_trigger
  WHERE tgrelid = 'hocalist.requests'::regclass
    AND tgname = 'notification_request_update' AND tgenabled = 'O'
    AND md5(pg_get_triggerdef(oid)) = 'f521b51df6e87a4a3196a0ffd6ff0644') THEN
  RAISE EXCEPTION 'Trigger drift: notification_request_update';
END IF;
IF NOT EXISTS (
  SELECT 1 FROM pg_attribute a
  JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE a.attrelid = 'hocalist.notification_preferences'::regclass
    AND a.attname = 'leads' AND a.attnotnull AND NOT a.attisdropped
    AND pg_get_expr(d.adbin, d.adrelid) = 'true') THEN
  RAISE EXCEPTION 'leads preference column drift';
END IF;
END
$request_update_state_verify$;
ROLLBACK;

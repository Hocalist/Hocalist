BEGIN READ ONLY;
DO $request_update_producer_guard$
BEGIN
  IF to_regclass('hocalist.notifications') IS NULL
     OR to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('hocalist.notification_recipient_allowed(uuid)') IS NULL
     OR to_regclass('hocalist.notification_preferences') IS NULL
     OR to_regclass('hocalist.requests') IS NULL
     OR to_regclass('hocalist.offers') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL THEN
    RAISE EXCEPTION 'Notification/producer/request foundation is missing';
  END IF;
  IF to_regprocedure('hocalist.notification_on_request_update()') IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM pg_attribute
       WHERE attrelid = 'hocalist.notification_preferences'::regclass
         AND attname = 'leads' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'Request-update producer already exists; review before applying';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM pg_constraint
       WHERE conrelid = 'hocalist.notifications'::regclass
         AND conname = 'notifications_kind_check'
         AND pg_get_constraintdef(oid) NOT LIKE '%request_update%')
     OR to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Notification kind constraint is missing or already extended';
  END IF;
END
$request_update_producer_guard$;
DO $request_update_drift_guard$
BEGIN
IF to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL
     OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)')), chr(13), '')) <> 'e8ebd8e28f1c5ddc30e54eea1adb1669' THEN
  RAISE EXCEPTION 'Prerequisite function drift: notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)';
END IF;
IF to_regprocedure('hocalist.notification_preferences()') IS NULL
     OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.notification_preferences()')), chr(13), '')) <> '754694afdc5e85958343210cc909890c' THEN
  RAISE EXCEPTION 'Prerequisite function drift: notification_preferences()';
END IF;
IF to_regprocedure('hocalist.notification_preferences_update(jsonb)') IS NULL
     OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.notification_preferences_update(jsonb)')), chr(13), '')) <> '8e62dfccd96585c2487f45f6ba0c48ff' THEN
  RAISE EXCEPTION 'Prerequisite function drift: notification_preferences_update(jsonb)';
END IF;
IF to_regprocedure('hocalist.notification_recipient_allowed(uuid)') IS NULL
     OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.notification_recipient_allowed(uuid)')), chr(13), '')) <> '033b349858256fd16474d66e454f2a86' THEN
  RAISE EXCEPTION 'Prerequisite function drift: notification_recipient_allowed(uuid)';
END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'hocalist.notifications'::regclass
      AND conname = 'notifications_kind_check'
      AND pg_get_constraintdef(oid) = 'CHECK ((kind = ANY (ARRAY[''new_offer''::text, ''new_message''::text, ''meeting_update''::text, ''billing_update''::text, ''account_update''::text])))') THEN
    RAISE EXCEPTION 'Notification kind constraint drift';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'hocalist.notification_preferences'::regclass
      AND attname = 'leads' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'leads preference column already exists';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'hocalist.requests'::regclass
      AND tgname = 'notification_request_update' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'request-update producer trigger already exists';
  END IF;
END
$request_update_drift_guard$;
ROLLBACK;

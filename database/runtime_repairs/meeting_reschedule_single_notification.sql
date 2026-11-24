-- A schedule revision already notifies the counterpart. Do not emit a second
-- status notification for that same proposal. Preserve confirmation, decline,
-- cancellation, recipient checks and all existing function privileges.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $$
DECLARE
  definition text;
  original_guard constant text := 'IF NEW.status = OLD.status THEN';
  replacement_guard constant text := 'IF NEW.status = OLD.status OR NEW.status = ''reschedule_proposed'' THEN';
BEGIN
  IF to_regprocedure('hocalist.notification_on_meeting_proposal()') IS NULL THEN
    RAISE EXCEPTION 'meeting proposal notification producer is required';
  END IF;
  SELECT pg_get_functiondef('hocalist.notification_on_meeting_status()'::regprocedure)
    INTO definition;
  IF position(replacement_guard in definition) > 0 THEN RETURN; END IF;
  IF position(original_guard in definition) = 0 THEN
    RAISE EXCEPTION 'notification status guard differs; review before applying';
  END IF;
  EXECUTE replace(definition, original_guard, replacement_guard);
END $$;
COMMIT;

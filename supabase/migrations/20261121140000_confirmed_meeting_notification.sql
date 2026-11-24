-- Direct acceptance inserts an already accepted schedule. Only unresolved
-- proposals should ask the counterpart to respond; the existing status
-- producer emits the confirmation for both participants.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $$
DECLARE
  definition text;
  marker constant text := 'IF NEW.status <> ''proposed'' THEN RETURN NEW; END IF;';
BEGIN
  SELECT pg_get_functiondef('hocalist.notification_on_meeting_proposal()'::regprocedure)
    INTO definition;
  IF position(marker in definition) > 0 THEN RETURN; END IF;
  IF position('SELECT * INTO v_meeting FROM hocalist.meetings WHERE id = NEW.meeting_id;' in definition) = 0 THEN
    RAISE EXCEPTION 'Meeting notification producer changed; review before applying';
  END IF;
  EXECUTE replace(definition,
    'SELECT * INTO v_meeting FROM hocalist.meetings WHERE id = NEW.meeting_id;',
    marker || E'\n  SELECT * INTO v_meeting FROM hocalist.meetings WHERE id = NEW.meeting_id;');
END $$;
COMMIT;

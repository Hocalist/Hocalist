-- Missed-call, incoming-call and meeting-reminder notification producers
-- (allocation 153). Additive to the notification inbox 030 and producers 031.
--
-- Recipients are derived from the committed rows only: the callee of the call
-- or the two meeting participants. Every event carries a deterministic key so a
-- retried transition or a repeated scheduler run cannot duplicate a row.
-- Reminder dedupe uses the accepted schedule revision plus the absolute UTC
-- instant, so a reschedule produces a new reminder and a timezone or clock
-- change cannot duplicate or suppress one. Content stays generic: no address,
-- contact, PIN, amount or signal payload is copied into a notification.
--
-- No scheduler is created or activated and no historical row is backfilled.
-- `notification_enqueue_meeting_reminders` is service-role only and runs only
-- when a coordinator-owned schedule invokes it.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $communication_producer_guard$
BEGIN
  IF to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('hocalist.notification_recipient_allowed(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Notification inbox/producer foundation 030/031 is missing';
  END IF;
  IF to_regclass('hocalist.calls') IS NULL
     OR to_regclass('hocalist.meetings') IS NULL
     OR to_regclass('hocalist.meeting_schedule_revisions') IS NULL THEN
    RAISE EXCEPTION 'Call 110 / meeting 040 foundation is missing';
  END IF;
  IF to_regprocedure('hocalist.notification_on_call_ringing()') IS NOT NULL
     OR to_regprocedure('hocalist.notification_on_call_status()') IS NOT NULL
     OR to_regprocedure('hocalist.notification_enqueue_meeting_reminders(integer,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'Communication producers already exist; review before applying';
  END IF;
END
$communication_producer_guard$;

-- ---------------------------------------------------------------------------
-- Calls
-- ---------------------------------------------------------------------------

-- One ringing invitation notification for the callee. Deduplicated per call;
-- a retried invite returns the same call and therefore the same notification.
CREATE FUNCTION hocalist.notification_on_call_ringing() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF hocalist.notification_recipient_allowed(NEW.callee_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.callee_id,
      md5('call:ringing:' || NEW.id::text)::uuid,
      'meeting_update',
      NEW.id,
      'Incoming Hocalist call',
      'You have a call invitation. Open Hocalist to answer or decline.',
      'hocalist://chat/' || NEW.conversation_id::text,
      jsonb_build_object('call_id', NEW.id, 'conversation_id', NEW.conversation_id, 'state', 'ringing'));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_call_ringing
  AFTER INSERT ON hocalist.calls
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_call_ringing();

-- Ringing that never connected notifies the callee as missed when the caller
-- cancels or the invitation times out. A callee decline notifies the caller.
-- Connected calls that end do not notify either participant.
CREATE FUNCTION hocalist.notification_on_call_status() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF OLD.state = NEW.state THEN
    RETURN NEW;
  END IF;
  IF OLD.state = 'ringing' AND NEW.state IN ('missed','cancelled') THEN
    IF hocalist.notification_recipient_allowed(NEW.callee_id) THEN
      PERFORM hocalist.notification_emit(
        NEW.callee_id,
        md5('call:missed:' || NEW.id::text)::uuid,
        'meeting_update',
        NEW.id,
        'Missed call',
        'You missed a Hocalist call. Open the chat to call back.',
        'hocalist://chat/' || NEW.conversation_id::text,
        jsonb_build_object('call_id', NEW.id, 'conversation_id', NEW.conversation_id, 'state', NEW.state));
    END IF;
  ELSIF OLD.state = 'ringing' AND NEW.state = 'declined' THEN
    IF hocalist.notification_recipient_allowed(NEW.caller_id) THEN
      PERFORM hocalist.notification_emit(
        NEW.caller_id,
        md5('call:declined:' || NEW.id::text)::uuid,
        'meeting_update',
        NEW.id,
        'Call declined',
        'The call was declined. Open the chat to send a message instead.',
        'hocalist://chat/' || NEW.conversation_id::text,
        jsonb_build_object('call_id', NEW.id, 'conversation_id', NEW.conversation_id, 'state', NEW.state));
    END IF;
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_call_status
  AFTER UPDATE OF state ON hocalist.calls
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_call_status();

-- ---------------------------------------------------------------------------
-- Accepted-meeting reminders (scheduler entry point, not scheduled here)
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.notification_enqueue_meeting_reminders(
  p_window_minutes integer DEFAULT 60,
  p_limit integer DEFAULT 200
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_count integer := 0;
  v_recipient uuid;
  v_key uuid;
  r record;
BEGIN
  IF p_window_minutes IS NULL OR p_window_minutes NOT BETWEEN 5 AND 1440 THEN
    RAISE EXCEPTION 'invalid_field: p_window_minutes' USING ERRCODE='22023';
  END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'invalid_field: p_limit' USING ERRCODE='22023';
  END IF;
  FOR r IN
    SELECT m.id AS meeting_id,
           m.revision AS meeting_revision,
           m.buyer_user_id,
           m.seller_user_id,
           rev.schedule_instant
    FROM hocalist.meetings m
    JOIN hocalist.meeting_schedule_revisions rev ON rev.id = m.accepted_revision_id
    WHERE m.status = 'accepted'
      AND rev.status = 'accepted'
      AND rev.schedule_instant > now()
      AND rev.schedule_instant <= now() + make_interval(mins => p_window_minutes)
    ORDER BY rev.schedule_instant
    LIMIT p_limit
  LOOP
    FOREACH v_recipient IN ARRAY ARRAY[r.buyer_user_id, r.seller_user_id] LOOP
      IF hocalist.notification_recipient_allowed(v_recipient) THEN
        v_key := md5(
          'meeting:reminder:' || r.meeting_id::text || ':' ||
          r.meeting_revision::text || ':' ||
          extract(epoch from r.schedule_instant)::bigint::text
        )::uuid;
        -- Count only a genuinely new row; `notification_emit` returns the
        -- existing id for a replay so it cannot report a duplicate as queued.
        IF NOT EXISTS (
             SELECT 1 FROM hocalist.notifications n
             WHERE n.user_id = v_recipient AND n.event_key = v_key
           )
           AND hocalist.notification_emit(
             v_recipient,
             v_key,
             'meeting_update',
             r.meeting_id,
             'Meeting reminder',
             'Your accepted meeting is coming up. Open Hocalist for the details.',
             'hocalist://meetings/' || r.meeting_id::text,
             jsonb_build_object(
               'meeting_id', r.meeting_id,
               'window_minutes', p_window_minutes
             )
           ) IS NOT NULL THEN
          v_count := v_count + 1;
        END IF;
      END IF;
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object('queued', v_count);
END; $$;

-- ---------------------------------------------------------------------------
-- Grants and post-apply verification
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION hocalist.notification_on_call_ringing(),
  hocalist.notification_on_call_status(),
  hocalist.notification_enqueue_meeting_reminders(integer,integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.notification_enqueue_meeting_reminders(integer,integer)
  TO service_role;

DO $hocalist_communication_producer_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_entry text;
  v_table text;
  v_trigger text;
BEGIN
  FOREACH v_entry IN ARRAY ARRAY[
    'calls:notification_call_ringing','calls:notification_call_status'] LOOP
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
  IF has_function_privilege('authenticated','hocalist.notification_on_call_ringing()','EXECUTE')
     OR has_function_privilege('authenticated','hocalist.notification_on_call_status()','EXECUTE')
     OR has_function_privilege('authenticated','hocalist.notification_enqueue_meeting_reminders(integer,integer)','EXECUTE')
     OR has_function_privilege('anon','hocalist.notification_enqueue_meeting_reminders(integer,integer)','EXECUTE')
     OR NOT has_function_privilege('service_role','hocalist.notification_enqueue_meeting_reminders(integer,integer)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'producer grants are wrong');
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.notification_inbox(integer,text)','EXECUTE')
     OR has_function_privilege('authenticated','hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.call_command(text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed notification/call grants changed');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist communication producer post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_communication_producer_postapply$;
COMMIT;

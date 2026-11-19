-- Notify declined revision proposers without falsely announcing confirmation.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $$ BEGIN
  IF to_regprocedure('hocalist.notification_on_meeting_status()') IS NULL THEN
    RAISE EXCEPTION 'notification producers must be installed first';
  END IF;
END $$;
CREATE OR REPLACE FUNCTION hocalist.notification_on_meeting_status() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_title text;
  v_body text;
  v_recipient uuid;
  v_declined hocalist.meeting_schedule_revisions%ROWTYPE;
BEGIN
  IF OLD.status IN ('proposed', 'reschedule_proposed')
     AND NEW.status IN ('proposed', 'accepted') AND NEW.revision > OLD.revision THEN
    SELECT * INTO v_declined FROM hocalist.meeting_schedule_revisions
      WHERE meeting_id = NEW.id ORDER BY sequence DESC LIMIT 1;
    IF v_declined.status = 'rejected' THEN
      IF hocalist.notification_recipient_allowed(v_declined.proposed_by_user_id) THEN
        PERFORM hocalist.notification_emit(
          v_declined.proposed_by_user_id,
          md5('meeting:declined:' || v_declined.id::text)::uuid,
          'meeting_update', NEW.id,
          CASE WHEN NEW.accepted_revision_id IS NULL THEN 'Meeting proposal declined'
               ELSE 'Proposed meeting change declined' END,
          CASE WHEN NEW.accepted_revision_id IS NULL
               THEN 'Your meeting proposal was declined. Open Hocalist to propose new details.'
               ELSE 'Your proposed change was declined. Your original meeting is still confirmed.' END,
          'hocalist://meetings/' || NEW.id::text,
          jsonb_build_object('meeting_id', NEW.id, 'revision_id', v_declined.id,
            'event', 'meeting_proposal_declined', 'status', NEW.status));
      END IF;
      RETURN NEW;
    END IF;
  END IF;
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;
  v_title := CASE NEW.status
    WHEN 'accepted' THEN 'Meeting confirmed'
    WHEN 'cancelled' THEN 'Meeting cancelled'
    WHEN 'reschedule_proposed' THEN 'Reschedule requested'
    ELSE 'Meeting updated'
  END;
  v_body := CASE NEW.status
    WHEN 'accepted' THEN 'The meeting was confirmed. Open Hocalist to view the details.'
    WHEN 'cancelled' THEN 'The meeting was cancelled. Open Hocalist to view the details.'
    WHEN 'reschedule_proposed' THEN 'A new meeting time was proposed. Open Hocalist to respond.'
    ELSE 'The meeting schedule changed. Open Hocalist to review it.'
  END;
  FOREACH v_recipient IN ARRAY ARRAY[NEW.buyer_user_id, NEW.seller_user_id] LOOP
    IF hocalist.notification_recipient_allowed(v_recipient) THEN
      PERFORM hocalist.notification_emit(
        v_recipient,
        md5('meeting:status:' || NEW.id::text || ':' || NEW.revision::text)::uuid,
        'meeting_update',
        NEW.id,
        v_title,
        v_body,
        'hocalist://meetings/' || NEW.id::text,
        jsonb_build_object('meeting_id', NEW.id, 'status', NEW.status));
    END IF;
  END LOOP;
  RETURN NEW;
END; $$;


REVOKE ALL ON FUNCTION hocalist.notification_on_meeting_status()
  FROM PUBLIC, anon, authenticated, service_role;
COMMIT;

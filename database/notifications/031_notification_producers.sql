-- DRAFT: notification event producers (additive to inbox 030).
--
-- Domain triggers translate committed marketplace, chat and meeting events
-- into participant notifications through the internal `notification_emit`
-- producer. Recipients are always derived from the committed domain rows
-- (request buyer, conversation members, meeting participants) — never from
-- client input — and every event carries a deterministic key so a retried or
-- replayed transition cannot emit a duplicate row. Disabled optional topics
-- are skipped inside `notification_emit`; safety content is never suppressed.
--
-- Titles, bodies, deep links and payloads stay generic: no exact address,
-- phone, PIN or payment detail is copied into a notification.
--
-- Not an instruction to apply to a live project. Apply only through the
-- guarded bundle in database/notifications/producers-rollout after
-- coordinating review.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $notification_producer_guard$
BEGIN
  IF to_regclass('hocalist.notifications') IS NULL
     OR to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regclass('hocalist.offers') IS NULL
     OR to_regclass('hocalist.conversation_messages') IS NULL
     OR to_regclass('hocalist.conversation_members') IS NULL
     OR to_regclass('hocalist.meetings') IS NULL
     OR to_regclass('hocalist.meeting_schedule_revisions') IS NULL THEN
    RAISE EXCEPTION 'Notification/chat/marketplace/meeting foundation is missing';
  END IF;
  IF to_regprocedure('hocalist.notification_on_offer_insert()') IS NOT NULL
     OR to_regprocedure('hocalist.notification_on_message_insert()') IS NOT NULL
     OR to_regprocedure('hocalist.notification_on_meeting_proposal()') IS NOT NULL
     OR to_regprocedure('hocalist.notification_on_meeting_status()') IS NOT NULL THEN
    RAISE EXCEPTION 'Notification producers already exist; review before applying';
  END IF;
END
$notification_producer_guard$;

-- ---------------------------------------------------------------------------
-- Producer triggers
-- ---------------------------------------------------------------------------

-- Established restriction policy for producer recipients: an active membership
-- is required and restricted/disabled accounts are never notified. Optional
-- topic preferences and mute state are applied downstream.
CREATE FUNCTION hocalist.notification_recipient_allowed(p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM hocalist.memberships m
    WHERE m.user_id = p_user AND m.status = 'active')
  AND NOT EXISTS (
    SELECT 1 FROM hocalist.memberships m
    WHERE m.user_id = p_user AND m.status IN ('restricted','disabled'));
$$;

-- A submitted offer notifies the buyer who owns the request. The seller never
-- receives their own submission.
CREATE FUNCTION hocalist.notification_on_offer_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF hocalist.notification_recipient_allowed(NEW.buyer_user_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.buyer_user_id,
      md5('offer:new:' || NEW.id::text)::uuid,
      'new_offer',
      NEW.id,
      'New offer received',
      'A seller sent an offer on your request. Open Hocalist to review it.',
      'hocalist://offers/' || NEW.id::text,
      jsonb_build_object('offer_id', NEW.id, 'request_id', NEW.request_id));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_offer_insert
  AFTER INSERT ON hocalist.offers
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_offer_insert();

-- A text message notifies the other non-revoked, unmuted conversation members.
CREATE FUNCTION hocalist.notification_on_message_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_member record;
BEGIN
  IF NEW.kind <> 'text' THEN
    RETURN NEW;
  END IF;
  FOR v_member IN
    SELECT cm.user_id
    FROM hocalist.conversation_members cm
    WHERE cm.conversation_id = NEW.conversation_id
      AND cm.revoked_at IS NULL
      AND cm.is_muted = false
      AND cm.user_id <> NEW.sender_user_id
  LOOP
    IF hocalist.notification_recipient_allowed(v_member.user_id) THEN
      PERFORM hocalist.notification_emit(
        v_member.user_id,
        md5('message:new:' || NEW.id::text || ':' || v_member.user_id::text)::uuid,
        'new_message',
        NEW.id,
        'New message',
        'You have a new message. Open Hocalist to read it.',
        'hocalist://chat/' || NEW.conversation_id::text,
        jsonb_build_object(
          'conversation_id', NEW.conversation_id, 'message_id', NEW.id));
    END IF;
  END LOOP;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_message_insert
  AFTER INSERT ON hocalist.conversation_messages
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_message_insert();

-- A schedule proposal notifies the other meeting participant.
CREATE FUNCTION hocalist.notification_on_meeting_proposal() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_meeting hocalist.meetings%ROWTYPE;
  v_recipient uuid;
BEGIN
  SELECT * INTO v_meeting FROM hocalist.meetings WHERE id = NEW.meeting_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;
  v_recipient := CASE
    WHEN NEW.proposed_by_user_id = v_meeting.buyer_user_id
      THEN v_meeting.seller_user_id
    ELSE v_meeting.buyer_user_id
  END;
  IF hocalist.notification_recipient_allowed(v_recipient) THEN
    PERFORM hocalist.notification_emit(
      v_recipient,
      md5('meeting:proposal:' || NEW.id::text)::uuid,
      'meeting_update',
      v_meeting.id,
      'New meeting time proposed',
      'A new meeting time was proposed. Open Hocalist to respond.',
      'hocalist://meetings/' || v_meeting.id::text,
      jsonb_build_object('meeting_id', v_meeting.id, 'revision_id', NEW.id));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_meeting_proposal
  AFTER INSERT ON hocalist.meeting_schedule_revisions
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_meeting_proposal();

-- Every accepted, rejected, rescheduled or cancelled status change notifies
-- both participants with the revision-scoped key, so replaying the same
-- transition cannot duplicate the row.
CREATE FUNCTION hocalist.notification_on_meeting_status() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_title text;
  v_body text;
  v_recipient uuid;
BEGIN
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

CREATE TRIGGER notification_meeting_status
  AFTER UPDATE OF status ON hocalist.meetings
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_meeting_status();

-- ---------------------------------------------------------------------------
-- Grants and post-apply verification
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION hocalist.notification_recipient_allowed(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.notification_on_offer_insert()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.notification_on_message_insert()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.notification_on_meeting_proposal()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.notification_on_meeting_status()
  FROM PUBLIC, anon, authenticated, service_role;

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
COMMIT;

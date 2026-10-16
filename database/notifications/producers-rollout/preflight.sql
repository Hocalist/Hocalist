-- Hocalist notification producer rollout preflight. READ-ONLY: safe to run
-- repeatedly.
--
-- Validates the deployed notification inbox 030 plus the chat/marketplace/
-- meeting baseline and aborts on any pre-existing producer object. The DO block
-- is textually identical to the guard in apply.sql;
-- database/notifications/tests/producers_rollout.test.mjs asserts it.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
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
SELECT 'notification producer preflight passed' AS status;
COMMIT;

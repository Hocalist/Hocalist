-- Hocalist notification producer containment: trigger withdrawal.
--
-- Drops the four producer triggers so committed domain events stop creating
-- inbox rows. Functions, receipts and existing notification rows are kept, so
-- the state is inspectable and re-applying the bundle restores the producers.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DROP TRIGGER IF EXISTS notification_offer_insert ON hocalist.offers;
DROP TRIGGER IF EXISTS notification_message_insert
  ON hocalist.conversation_messages;
DROP TRIGGER IF EXISTS notification_meeting_proposal
  ON hocalist.meeting_schedule_revisions;
DROP TRIGGER IF EXISTS notification_meeting_status ON hocalist.meetings;
COMMIT;

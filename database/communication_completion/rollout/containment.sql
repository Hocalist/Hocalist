-- Containment for a suspicious communications-completion apply. Revokes every
-- client and scheduler capability this bundle added and stops new producer
-- writes, while preserving message history, block records, signal rows and the
-- replaced function bodies. It is not a destructive rollback.
BEGIN;
REVOKE ALL ON FUNCTION hocalist.chat_block(uuid,text), hocalist.chat_unblock(uuid),
  hocalist.chat_block_state(uuid),
  hocalist.chat_search(text,integer,text,uuid),
  hocalist.chat_search_inbox(text,integer,text),
  hocalist.call_status(uuid,bigint)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.chat_signal_member(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.notification_enqueue_meeting_reminders(integer,integer)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE hocalist.chat_change_signals FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS chat_signal_message ON hocalist.conversation_messages;
DROP TRIGGER IF EXISTS notification_call_ringing ON hocalist.calls;
DROP TRIGGER IF EXISTS notification_call_status ON hocalist.calls;
DO $containment_publication$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'hocalist'
        AND tablename = 'chat_change_signals'
    ) THEN
      ALTER PUBLICATION supabase_realtime DROP TABLE hocalist.chat_change_signals;
    END IF;
  END IF;
END
$containment_publication$;
COMMIT;

-- Chat live-update signaling: least-exposure Realtime preparation
-- (allocation 154).
--
-- Purpose: give subscribed clients a content-free "this conversation may have
-- changed" signal so they can perform an authoritative, participant-authorized
-- refetch. The published table carries only an opaque signal id, the
-- conversation id and a timestamp. Message text, senders, read markers and
-- preference rows are never published, and no other `hocalist` table is added
-- to any publication.
--
-- Exposure model:
-- * `chat_change_signals` is RLS-protected; the `authenticated` role receives
--   SELECT only (required for Realtime postgres_changes authorization) and the
--   member policy limits each subscriber to their own conversations.
-- * Anonymous and service roles receive no grant.
-- * The `supabase_realtime` publication is extended only when it exists. If the
--   project has not provisioned Realtime, the table and trigger still work and
--   the publication is untouched.
--
-- Applying this migration is the reviewed signaling change; live activation
-- (Realtime enablement, client capability flag) remains coordinator-owned.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $chat_signal_guard$
BEGIN
  IF to_regclass('hocalist.conversations') IS NULL
     OR to_regclass('hocalist.conversation_messages') IS NULL
     OR to_regprocedure('hocalist.chat_is_member(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Chat foundation 010 is missing';
  END IF;
  IF to_regclass('hocalist.chat_change_signals') IS NOT NULL THEN
    RAISE EXCEPTION 'Chat change signals already exist; review before applying';
  END IF;
END
$chat_signal_guard$;

CREATE TABLE hocalist.chat_change_signals (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX chat_change_signals_conversation_idx
  ON hocalist.chat_change_signals(conversation_id, id DESC);
ALTER TABLE hocalist.chat_change_signals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.chat_change_signals FROM PUBLIC, anon, authenticated, service_role;
-- Realtime checks the subscriber's SELECT privilege and this policy with the
-- subscriber's JWT; rows contain no message content. The policy helper takes
-- only the conversation id and derives the caller from auth.uid(), so a client
-- cannot use it to probe another identity's membership.
--
-- The policy mirrors the reviewed conversation-read fence: an unrevoked member
-- with a matching active role membership, no restricted/disabled membership in
-- any role, and not the blocked party of an active block. The blocker keeps
-- signal access to their own conversations. Content-free metadata still reveals
-- conversation activity, so it honors the same read boundary as messages.
GRANT SELECT ON hocalist.chat_change_signals TO authenticated;
CREATE FUNCTION hocalist.chat_signal_member(p_conversation uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1
    FROM hocalist.conversation_members m
    WHERE m.conversation_id = p_conversation
      AND m.user_id = auth.uid()
      AND m.revoked_at IS NULL
      AND EXISTS (
        SELECT 1 FROM hocalist.memberships ms
        WHERE ms.id = m.profile_id AND ms.user_id = m.user_id
          AND ms.role = m.role AND ms.status = 'active')
      AND NOT EXISTS (
        SELECT 1 FROM hocalist.memberships r
        WHERE r.user_id = auth.uid() AND r.status IN ('restricted','disabled'))
      AND NOT EXISTS (
        SELECT 1 FROM hocalist.conversation_blocks b
        WHERE b.conversation_id = m.conversation_id
          AND b.revoked_at IS NULL
          AND b.blocked_user_id = m.user_id)
  );
$$;
REVOKE ALL ON FUNCTION hocalist.chat_signal_member(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_signal_member(uuid) TO authenticated;
CREATE POLICY chat_member_signal_read ON hocalist.chat_change_signals
  FOR SELECT TO authenticated
  USING (hocalist.chat_signal_member(conversation_id));

CREATE FUNCTION hocalist.chat_signal_on_message()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO hocalist.chat_change_signals(conversation_id) VALUES (NEW.conversation_id);
  DELETE FROM hocalist.chat_change_signals
    WHERE conversation_id = NEW.conversation_id
      AND created_at < now() - interval '15 minutes';
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION hocalist.chat_signal_on_message()
  FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER chat_signal_message
  AFTER INSERT ON hocalist.conversation_messages
  FOR EACH ROW EXECUTE FUNCTION hocalist.chat_signal_on_message();

DO $chat_signal_publication$
DECLARE
  v_added boolean := false;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'hocalist'
        AND tablename = 'chat_change_signals'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE hocalist.chat_change_signals;
      v_added := true;
    END IF;
  END IF;
  RAISE NOTICE 'hocalist chat_change_signals publication added: %', v_added;
END
$chat_signal_publication$;

DO $hocalist_chat_signal_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_public_tables text[];
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'hocalist.conversation_messages'::regclass
      AND tgname = 'chat_signal_message' AND NOT tgisinternal
  ) THEN
    v_issues := array_append(v_issues, 'missing chat signal trigger');
  END IF;
  IF NOT has_table_privilege('authenticated','hocalist.chat_change_signals','SELECT')
     OR has_table_privilege('anon','hocalist.chat_change_signals','SELECT')
     OR has_table_privilege('service_role','hocalist.chat_change_signals','SELECT') THEN
    v_issues := array_append(v_issues, 'signal table grants differ from the reviewed shape');
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.chat_signal_member(uuid)','EXECUTE')
     OR has_function_privilege('anon','hocalist.chat_signal_member(uuid)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.chat_signal_member(uuid)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'signal policy helper grants differ from the reviewed shape');
  END IF;
  IF position('conversation_blocks' in pg_get_functiondef(
       to_regprocedure('hocalist.chat_signal_member(uuid)'))) = 0
     OR position('memberships' in pg_get_functiondef(
       to_regprocedure('hocalist.chat_signal_member(uuid)'))) = 0 THEN
    v_issues := array_append(v_issues, 'signal policy does not mirror the conversation read fence');
  END IF;
  IF has_function_privilege('authenticated','hocalist.chat_is_member(uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','hocalist.chat_signal_on_message()','EXECUTE') THEN
    v_issues := array_append(v_issues, 'internal signal helper is executable by a client role');
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='hocalist.chat_change_signals'::regclass) THEN
    v_issues := array_append(v_issues, 'signal table RLS is disabled');
  END IF;
  -- Never allow a broad publication of private tables: only the single signal
  -- table may appear for the hocalist schema.
  SELECT array_agg(tablename ORDER BY tablename) INTO v_public_tables
  FROM pg_publication_tables
  WHERE pubname = 'supabase_realtime' AND schemaname = 'hocalist';
  IF v_public_tables IS NOT NULL
     AND v_public_tables <> ARRAY['chat_change_signals']::text[] THEN
    v_issues := array_append(v_issues, 'hocalist publication exposes more than chat_change_signals');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist chat signal post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_chat_signal_postapply$;
COMMIT;

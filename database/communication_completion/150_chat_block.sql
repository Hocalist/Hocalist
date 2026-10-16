-- Chat block/unblock contract (communications package, allocation 150).
--
-- Additive against the deployed chat 010 foundation. A block is a durable,
-- per-conversation directional record owned by the blocker. It never cancels a
-- deal, releases money, deletes messages or changes account status: it only
-- stops new messages in both directions and denies the blocked member's later
-- reads/search of that conversation. The blocker keeps their history so the
-- block remains reviewable and reversible.
--
-- Replaced function bodies are hash-guarded against the reviewed chat 010
-- definitions; any other source aborts the apply.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $chat_block_guard$
BEGIN
  IF to_regclass('hocalist.conversations') IS NULL
     OR to_regclass('hocalist.conversation_members') IS NULL
     OR to_regclass('hocalist.conversation_messages') IS NULL
     OR to_regclass('hocalist.profiles') IS NULL
     OR to_regprocedure('hocalist.chat_assert_participant(uuid,uuid)') IS NULL
     OR to_regprocedure('hocalist.chat_inbox(integer,text)') IS NULL
     OR to_regprocedure('hocalist.chat_is_member(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Chat foundation 010 is missing';
  END IF;
  IF to_regclass('hocalist.conversation_blocks') IS NOT NULL
     OR to_regprocedure('hocalist.chat_block(uuid,text)') IS NOT NULL
     OR to_regprocedure('hocalist.chat_unblock(uuid)') IS NOT NULL
     OR to_regprocedure('hocalist.chat_block_state(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Chat block objects already exist; review before applying';
  END IF;
  IF md5(replace(pg_get_functiondef(to_regprocedure('hocalist.chat_assert_participant(uuid,uuid)')),chr(13),''))
       <> 'ab46a1b7b3c40c9ece49f082b1bbde21' THEN
    RAISE EXCEPTION 'Prerequisite drift: hocalist.chat_assert_participant(uuid,uuid)';
  END IF;
  IF md5(replace(pg_get_functiondef(to_regprocedure('hocalist.chat_inbox(integer,text)')),chr(13),''))
       <> '8dd963b2ceb94e1abb42a96717a16317' THEN
    RAISE EXCEPTION 'Prerequisite drift: hocalist.chat_inbox(integer,text)';
  END IF;
END
$chat_block_guard$;

-- ---------------------------------------------------------------------------
-- Durable block records
-- ---------------------------------------------------------------------------

CREATE TABLE hocalist.conversation_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id) ON DELETE CASCADE,
  blocker_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  blocked_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  -- Optional review context. The reason is never returned to the blocked
  -- member and never becomes an account penalty by itself.
  reason_code text CHECK (
    reason_code IS NULL OR reason_code IN ('safety','harassment','spam','deal_dispute','other')
  ),
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  CONSTRAINT conversation_blocks_distinct CHECK (blocker_user_id <> blocked_user_id),
  CONSTRAINT conversation_blocks_revoked_after_created CHECK (
    revoked_at IS NULL OR revoked_at >= created_at
  )
);
CREATE UNIQUE INDEX conversation_blocks_active_pair
  ON hocalist.conversation_blocks(conversation_id, blocker_user_id, blocked_user_id)
  WHERE revoked_at IS NULL;
CREATE INDEX conversation_blocks_blocked_lookup
  ON hocalist.conversation_blocks(conversation_id, blocked_user_id)
  WHERE revoked_at IS NULL;
CREATE INDEX conversation_blocks_blocker_lookup
  ON hocalist.conversation_blocks(conversation_id, blocker_user_id)
  WHERE revoked_at IS NULL;

ALTER TABLE hocalist.conversation_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.conversation_blocks FROM PUBLIC, anon, authenticated, service_role;

-- Defense in depth: no client table grant exists, so this policy is inert
-- today and exists so a future reviewed grant cannot expose another member's
-- block records. All functional access goes through the RPCs below.
CREATE POLICY chat_member_block_read ON hocalist.conversation_blocks
  FOR SELECT TO authenticated
  USING (hocalist.chat_is_member(conversation_id, (SELECT auth.uid())));

-- New messages are refused in both directions while any active block exists
-- for the sender in that conversation. This is a table trigger so every write
-- path (text send, attachment send, any later internal path) is covered.
CREATE FUNCTION hocalist.chat_block_enforce_insert()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM hocalist.conversation_blocks b
    WHERE b.conversation_id = NEW.conversation_id
      AND b.revoked_at IS NULL
      AND (b.blocker_user_id = NEW.sender_user_id OR b.blocked_user_id = NEW.sender_user_id)
  ) THEN
    RAISE EXCEPTION 'conversation_blocked' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER chat_block_enforce_message
  BEFORE INSERT ON hocalist.conversation_messages
  FOR EACH ROW EXECUTE FUNCTION hocalist.chat_block_enforce_insert();

-- ---------------------------------------------------------------------------
-- Read/participation enforcement (replaces the reviewed 010 definitions)
-- ---------------------------------------------------------------------------

-- Same contract as 010 plus one addition: a member who is the blocked party of
-- an active block is denied every participant operation that routes through
-- this helper (messages, conversation read, send, mark-read, mute and calls).
-- The blocker is not denied by this helper, so they retain their own history
-- and can reverse the block.
CREATE OR REPLACE FUNCTION hocalist.chat_assert_participant(p_conversation uuid, p_user uuid)
RETURNS hocalist.conversation_members
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  m hocalist.conversation_members%ROWTYPE;
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO m FROM hocalist.conversation_members
    WHERE conversation_id = p_conversation AND user_id = p_user;
  IF NOT FOUND OR m.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'conversation_access_denied' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = p_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.memberships
                 WHERE id = m.profile_id AND user_id = p_user
                   AND role = m.role AND status = 'active') THEN
    RAISE EXCEPTION 'role_not_active' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.conversation_blocks b
             WHERE b.conversation_id = p_conversation
               AND b.revoked_at IS NULL
               AND b.blocked_user_id = p_user) THEN
    RAISE EXCEPTION 'conversation_blocked' USING ERRCODE='42501';
  END IF;
  RETURN m;
END; $$;

-- Same contract as 010 plus: a member who is the blocked party of an active
-- block does not see the conversation in their inbox. A blocker keeps the row
-- so the block state (and its reverse action) stays reachable.
CREATE OR REPLACE FUNCTION hocalist.chat_inbox(p_page_size integer DEFAULT 50, p_cursor text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_size integer;
  v_cursor_seq bigint;
  v_cursor_id uuid;
  v_last_seq bigint;
  v_last_id uuid;
  v_items jsonb;
  v_next text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = v_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  v_size := greatest(1, least(coalesce(p_page_size, 50), 100));
  IF p_cursor IS NOT NULL THEN
    BEGIN
      v_cursor_seq := split_part(p_cursor, '.', 1)::bigint;
      v_cursor_id := split_part(p_cursor, '.', 2)::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023';
    END;
  END IF;

  SELECT coalesce(jsonb_agg(row_json ORDER BY row_seq DESC, row_id DESC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT c.id AS row_id,
           coalesce(latest.seq, 0) AS row_seq,
           jsonb_build_object(
             'conversation', hocalist.chat_conversation_json(c.id),
             'counterpart_display_name', coalesce(nullif(btrim(counterpart.display_name), ''), 'Hocalist member'),
             'counterpart_profile_id', counterpart_member.profile_id,
             'latest_message', latest.message,
             'unread_count', (
               SELECT count(*)::integer FROM hocalist.conversation_messages m
               WHERE m.conversation_id = c.id AND m.seq > self.last_read_seq
                 AND m.sender_user_id <> v_user
             )
           ) AS row_json
    FROM hocalist.conversation_members self
    JOIN hocalist.conversations c ON c.id = self.conversation_id
    LEFT JOIN LATERAL (
      SELECT m.seq, to_jsonb(m) AS message FROM hocalist.conversation_messages m
      WHERE m.conversation_id = c.id ORDER BY m.seq DESC LIMIT 1
    ) latest ON true
    LEFT JOIN LATERAL (
      SELECT om.profile_id FROM hocalist.conversation_members om
      WHERE om.conversation_id = c.id AND om.user_id <> v_user
      ORDER BY om.joined_at, om.user_id LIMIT 1
    ) counterpart_member ON true
    LEFT JOIN hocalist.role_profiles counterpart ON counterpart.membership_id = counterpart_member.profile_id
    WHERE self.user_id = v_user AND self.revoked_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM hocalist.conversation_blocks b
        WHERE b.conversation_id = c.id AND b.revoked_at IS NULL
          AND b.blocked_user_id = v_user
      )
      AND EXISTS (
        SELECT 1 FROM hocalist.memberships m
        WHERE m.id = self.profile_id AND m.user_id = v_user
          AND m.role = self.role AND m.status = 'active'
      )
      AND (p_cursor IS NULL OR (coalesce(latest.seq, 0), c.id) < (v_cursor_seq, v_cursor_id))
    ORDER BY coalesce(latest.seq, 0) DESC, c.id DESC
    LIMIT v_size
  ) rows;

  v_next := NULL;
  IF jsonb_array_length(v_items) = v_size THEN
    v_last_seq := coalesce((v_items->-1->'latest_message'->>'seq')::bigint, 0);
    v_last_id := (v_items->-1->'conversation'->>'id')::uuid;
    IF EXISTS (
      SELECT 1 FROM hocalist.conversation_members self
      JOIN hocalist.conversations c ON c.id = self.conversation_id
      LEFT JOIN LATERAL (
        SELECT m.seq FROM hocalist.conversation_messages m
        WHERE m.conversation_id = c.id ORDER BY m.seq DESC LIMIT 1
      ) latest ON true
      WHERE self.user_id = v_user AND self.revoked_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM hocalist.conversation_blocks b
          WHERE b.conversation_id = c.id AND b.revoked_at IS NULL
            AND b.blocked_user_id = v_user
        )
        AND EXISTS (
          SELECT 1 FROM hocalist.memberships m
          WHERE m.id = self.profile_id AND m.user_id = v_user
            AND m.role = self.role AND m.status = 'active'
        )
        AND (coalesce(latest.seq, 0), c.id) < (v_last_seq, v_last_id)
    ) THEN
      v_next := v_last_seq::text || '.' || v_last_id::text;
    END IF;
  END IF;

  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

-- ---------------------------------------------------------------------------
-- Client RPCs
-- ---------------------------------------------------------------------------

-- Creates (or returns) one active block from the caller to every other
-- unrevoked member of the conversation. Idempotent. It deliberately changes
-- nothing else: no offer, meeting, credit, reward, message or membership row
-- is touched.
CREATE FUNCTION hocalist.chat_block(p_conversation uuid, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_member hocalist.conversation_members%ROWTYPE;
  v_peer uuid;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, v_user);
  IF p_reason IS NOT NULL AND p_reason NOT IN ('safety','harassment','spam','deal_dispute','other') THEN
    RAISE EXCEPTION 'invalid_field: p_reason' USING ERRCODE='22023';
  END IF;
  FOR v_peer IN
    SELECT user_id FROM hocalist.conversation_members
    WHERE conversation_id = p_conversation AND revoked_at IS NULL AND user_id <> v_user
  LOOP
    INSERT INTO hocalist.conversation_blocks(
      conversation_id, blocker_user_id, blocked_user_id, reason_code)
    VALUES (p_conversation, v_user, v_peer, p_reason)
    ON CONFLICT (conversation_id, blocker_user_id, blocked_user_id)
      WHERE revoked_at IS NULL DO NOTHING;
  END LOOP;
  -- A live call in this conversation ends deterministically when the block is
  -- recorded. Only the call state changes; the signaling rows are pruned by
  -- the next call command/status sweep. Calls may not be deployed yet.
  IF to_regclass('hocalist.calls') IS NOT NULL THEN
    EXECUTE 'UPDATE hocalist.calls SET state = ''ended''
             WHERE conversation_id = $1 AND state IN (''ringing'',''accepted'')'
      USING p_conversation;
  END IF;
  RETURN hocalist.chat_block_state(p_conversation);
END; $$;

-- Revokes the caller's own active blocks in this conversation. Idempotent.
CREATE FUNCTION hocalist.chat_unblock(p_conversation uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_member hocalist.conversation_members%ROWTYPE;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, v_user);
  UPDATE hocalist.conversation_blocks
    SET revoked_at = now()
    WHERE conversation_id = p_conversation AND blocker_user_id = v_user
      AND revoked_at IS NULL;
  RETURN hocalist.chat_block_state(p_conversation);
END; $$;

-- Block state for the caller only. Deliberately does not use the participant
-- helper so the blocked member can still read their own "messages are not
-- available" state and refresh the UI. `is_blocked_by_me` is only ever true
-- for the blocker; `can_message` is false when any active block involves the
-- caller or the conversation is closed.
CREATE FUNCTION hocalist.chat_block_state(p_conversation uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_member hocalist.conversation_members%ROWTYPE;
  v_status text;
  v_mine boolean;
  v_theirs boolean;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_member FROM hocalist.conversation_members
    WHERE conversation_id = p_conversation AND user_id = v_user;
  IF NOT FOUND OR v_member.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'conversation_access_denied' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = v_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.memberships
                 WHERE id = v_member.profile_id AND user_id = v_user
                   AND role = v_member.role AND status = 'active') THEN
    RAISE EXCEPTION 'role_not_active' USING ERRCODE='42501';
  END IF;
  SELECT status INTO v_status FROM hocalist.conversations WHERE id = p_conversation;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'conversation_access_denied' USING ERRCODE='42501';
  END IF;
  v_mine := EXISTS (
    SELECT 1 FROM hocalist.conversation_blocks b
    WHERE b.conversation_id = p_conversation AND b.revoked_at IS NULL
      AND b.blocker_user_id = v_user
  );
  v_theirs := EXISTS (
    SELECT 1 FROM hocalist.conversation_blocks b
    WHERE b.conversation_id = p_conversation AND b.revoked_at IS NULL
      AND b.blocked_user_id = v_user
  );
  RETURN jsonb_build_object(
    'conversation_id', p_conversation,
    'is_blocked_by_me', v_mine,
    'blocked_by_counterpart', v_theirs,
    'conversation_status', v_status,
    'can_message', v_status = 'open' AND NOT v_mine AND NOT v_theirs
  );
END; $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION hocalist.chat_block_enforce_insert()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.chat_block(uuid,text), hocalist.chat_unblock(uuid),
  hocalist.chat_block_state(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_block(uuid,text), hocalist.chat_unblock(uuid),
  hocalist.chat_block_state(uuid)
  TO authenticated;

DO $hocalist_chat_block_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_fn text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'hocalist.conversation_messages'::regclass
      AND tgname = 'chat_block_enforce_message' AND NOT tgisinternal
  ) THEN
    v_issues := array_append(v_issues, 'missing block enforcement trigger');
  END IF;
  FOREACH v_fn IN ARRAY ARRAY[
    'chat_block(uuid,text)','chat_unblock(uuid)','chat_block_state(uuid)'] LOOP
    IF NOT has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'block function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  IF has_function_privilege('authenticated','hocalist.chat_block_enforce_insert()','EXECUTE')
     OR has_function_privilege('anon','hocalist.chat_block_enforce_insert()','EXECUTE') THEN
    v_issues := array_append(v_issues, 'block trigger function is executable');
  END IF;
  IF has_table_privilege('authenticated','hocalist.conversation_blocks','SELECT')
     OR has_table_privilege('anon','hocalist.conversation_blocks','SELECT')
     OR NOT (SELECT relrowsecurity FROM pg_class
             WHERE oid = 'hocalist.conversation_blocks'::regclass) THEN
    v_issues := array_append(v_issues, 'block table exposure differs from the reviewed shape');
  END IF;
  IF position('conversation_blocked' in pg_get_functiondef(
       to_regprocedure('hocalist.chat_assert_participant(uuid,uuid)'))) = 0
     OR position('conversation_blocks' in pg_get_functiondef(
       to_regprocedure('hocalist.chat_inbox(integer,text)'))) = 0 THEN
    v_issues := array_append(v_issues, 'block enforcement was not applied to the chat reads');
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.chat_send(uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.chat_messages(uuid,integer,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed chat/account grants changed');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist chat block post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_chat_block_postapply$;
COMMIT;

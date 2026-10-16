-- Server-side paged conversation and message search (allocation 151).
--
-- Additive to chat 010 and the block contract 150. Search is participant-only:
-- rows are scoped by unrevoked membership plus an active membership for the
-- member's role, and a member who is the blocked party of an active block gets
-- no search results through the general paths. Query text is matched with
-- `position()` so no caller-supplied LIKE pattern or wildcard is interpreted,
-- and the raw query is never written to a log, error or audit row.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $chat_search_guard$
BEGIN
  IF to_regclass('hocalist.conversations') IS NULL
     OR to_regclass('hocalist.conversation_members') IS NULL
     OR to_regclass('hocalist.conversation_messages') IS NULL
     OR to_regprocedure('hocalist.chat_conversation_json(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Chat foundation 010 is missing';
  END IF;
  IF to_regclass('hocalist.conversation_blocks') IS NULL THEN
    RAISE EXCEPTION 'Chat block contract 150 is missing';
  END IF;
  IF to_regprocedure('hocalist.chat_search(text,integer,text,uuid)') IS NOT NULL
     OR to_regprocedure('hocalist.chat_search_inbox(text,integer,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Chat search objects already exist; review before applying';
  END IF;
END
$chat_search_guard$;

-- One paged message search for the caller. Optional p_conversation narrows the
-- search to a conversation the caller may read; without it, every conversation
-- the caller currently belongs to is searched.
CREATE FUNCTION hocalist.chat_search(
  p_query text,
  p_page_size integer DEFAULT 25,
  p_cursor text DEFAULT NULL,
  p_conversation uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_query text;
  v_size integer;
  v_cursor_seq bigint;
  v_cursor_id uuid;
  v_last_seq bigint;
  v_last_id uuid;
  v_items jsonb;
  v_next text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = v_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  IF p_query IS NULL OR length(btrim(p_query)) NOT BETWEEN 2 AND 64 THEN
    RAISE EXCEPTION 'invalid_field: p_query' USING ERRCODE='22023';
  END IF;
  v_query := lower(btrim(p_query));
  v_size := greatest(1, least(coalesce(p_page_size, 25), 50));
  IF p_cursor IS NOT NULL THEN
    BEGIN
      v_cursor_seq := split_part(p_cursor, '.', 1)::bigint;
      v_cursor_id := split_part(p_cursor, '.', 2)::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023';
    END;
  END IF;
  -- Scoped search reuses the participant fence so a blocked, revoked or
  -- inactive member gets the same typed denial here as on a direct read.
  IF p_conversation IS NOT NULL THEN
    PERFORM hocalist.chat_assert_participant(p_conversation, v_user);
  END IF;

  SELECT coalesce(jsonb_agg(row_json ORDER BY row_seq DESC, row_id DESC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT m.seq AS row_seq,
           m.id AS row_id,
           jsonb_build_object(
             'message', to_jsonb(m),
             'conversation_id', m.conversation_id,
             'conversation_origin', c.origin,
             'conversation_status', c.status,
             'counterpart_display_name', coalesce(nullif(btrim(counterpart.display_name), ''), 'Hocalist member'),
             'counterpart_profile_id', counterpart_member.profile_id
           ) AS row_json
    FROM hocalist.conversation_members self
    JOIN hocalist.conversations c ON c.id = self.conversation_id
    JOIN hocalist.conversation_messages m ON m.conversation_id = c.id
    LEFT JOIN LATERAL (
      SELECT om.profile_id FROM hocalist.conversation_members om
      WHERE om.conversation_id = c.id AND om.user_id <> v_user
      ORDER BY om.joined_at, om.user_id LIMIT 1
    ) counterpart_member ON true
    LEFT JOIN hocalist.role_profiles counterpart
      ON counterpart.membership_id = counterpart_member.profile_id
    WHERE self.user_id = v_user AND self.revoked_at IS NULL
      AND EXISTS (
        SELECT 1 FROM hocalist.memberships ms
        WHERE ms.id = self.profile_id AND ms.user_id = v_user
          AND ms.role = self.role AND ms.status = 'active'
      )
      AND NOT EXISTS (
        SELECT 1 FROM hocalist.conversation_blocks b
        WHERE b.conversation_id = c.id AND b.revoked_at IS NULL
          AND b.blocked_user_id = v_user
      )
      AND (p_conversation IS NULL OR c.id = p_conversation)
      AND position(v_query in lower(m.text)) > 0
      AND (p_cursor IS NULL OR (m.seq, m.id) < (v_cursor_seq, v_cursor_id))
    ORDER BY m.seq DESC, m.id DESC
    LIMIT v_size
  ) rows;

  v_next := NULL;
  IF jsonb_array_length(v_items) = v_size THEN
    v_last_seq := (v_items->-1->'message'->>'seq')::bigint;
    v_last_id := (v_items->-1->'message'->>'id')::uuid;
    IF EXISTS (
      SELECT 1 FROM hocalist.conversation_members self
      JOIN hocalist.conversations c ON c.id = self.conversation_id
      JOIN hocalist.conversation_messages m ON m.conversation_id = c.id
      WHERE self.user_id = v_user AND self.revoked_at IS NULL
        AND EXISTS (
          SELECT 1 FROM hocalist.memberships ms
          WHERE ms.id = self.profile_id AND ms.user_id = v_user
            AND ms.role = self.role AND ms.status = 'active'
        )
        AND NOT EXISTS (
          SELECT 1 FROM hocalist.conversation_blocks b
          WHERE b.conversation_id = c.id AND b.revoked_at IS NULL
            AND b.blocked_user_id = v_user
        )
        AND (p_conversation IS NULL OR c.id = p_conversation)
        AND position(v_query in lower(m.text)) > 0
        AND (m.seq, m.id) < (v_last_seq, v_last_id)
    ) THEN
      v_next := v_last_seq::text || '.' || v_last_id::text;
    END IF;
  END IF;

  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

-- One paged conversation search over the caller's own inbox rows, matched on
-- the counterpart display name. Cursor format matches chat_inbox.
CREATE FUNCTION hocalist.chat_search_inbox(
  p_query text,
  p_page_size integer DEFAULT 25,
  p_cursor text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_query text;
  v_size integer;
  v_cursor_seq bigint;
  v_cursor_id uuid;
  v_last_seq bigint;
  v_last_id uuid;
  v_items jsonb;
  v_next text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = v_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  IF p_query IS NULL OR length(btrim(p_query)) NOT BETWEEN 2 AND 64 THEN
    RAISE EXCEPTION 'invalid_field: p_query' USING ERRCODE='22023';
  END IF;
  v_query := lower(btrim(p_query));
  v_size := greatest(1, least(coalesce(p_page_size, 25), 50));
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
    LEFT JOIN hocalist.role_profiles counterpart
      ON counterpart.membership_id = counterpart_member.profile_id
    WHERE self.user_id = v_user AND self.revoked_at IS NULL
      AND EXISTS (
        SELECT 1 FROM hocalist.memberships ms
        WHERE ms.id = self.profile_id AND ms.user_id = v_user
          AND ms.role = self.role AND ms.status = 'active'
      )
      AND NOT EXISTS (
        SELECT 1 FROM hocalist.conversation_blocks b
        WHERE b.conversation_id = c.id AND b.revoked_at IS NULL
          AND b.blocked_user_id = v_user
      )
      AND position(v_query in lower(coalesce(counterpart.display_name, ''))) > 0
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
      LEFT JOIN LATERAL (
        SELECT om.profile_id FROM hocalist.conversation_members om
        WHERE om.conversation_id = c.id AND om.user_id <> v_user
        ORDER BY om.joined_at, om.user_id LIMIT 1
      ) counterpart_member ON true
      LEFT JOIN hocalist.role_profiles counterpart
        ON counterpart.membership_id = counterpart_member.profile_id
      WHERE self.user_id = v_user AND self.revoked_at IS NULL
        AND EXISTS (
          SELECT 1 FROM hocalist.memberships ms
          WHERE ms.id = self.profile_id AND ms.user_id = v_user
            AND ms.role = self.role AND ms.status = 'active'
        )
        AND NOT EXISTS (
          SELECT 1 FROM hocalist.conversation_blocks b
          WHERE b.conversation_id = c.id AND b.revoked_at IS NULL
            AND b.blocked_user_id = v_user
        )
        AND position(v_query in lower(coalesce(counterpart.display_name, ''))) > 0
        AND (coalesce(latest.seq, 0), c.id) < (v_last_seq, v_last_id)
    ) THEN
      v_next := v_last_seq::text || '.' || v_last_id::text;
    END IF;
  END IF;

  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

-- ---------------------------------------------------------------------------
-- Grants and post-apply verification
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION hocalist.chat_search(text,integer,text,uuid),
  hocalist.chat_search_inbox(text,integer,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_search(text,integer,text,uuid),
  hocalist.chat_search_inbox(text,integer,text)
  TO authenticated;

DO $hocalist_chat_search_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'chat_search(text,integer,text,uuid)','chat_search_inbox(text,integer,text)'] LOOP
    IF NOT has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'search function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  IF NOT has_function_privilege('authenticated','hocalist.chat_messages(uuid,integer,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.chat_inbox(integer,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed chat/account grants changed');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist chat search post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_chat_search_postapply$;
COMMIT;

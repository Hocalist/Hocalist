-- DRAFT: persistent text-chat foundation. Locally tested only.
-- Not an instruction to apply to a live project. Apply only through the
-- guarded bundle in database/chat/rollout after coordinating review.
--
-- Scope: private conversations, participants, text messages, per-member
-- read/mute state. Attachments, search, blocking/reporting, notification
-- dispatch, request/offer opening and calls are NOT implemented here.
--
-- Authorization model: no table is readable or writable by clients. All
-- access goes through SECURITY DEFINER functions that derive the caller from
-- auth.uid(), assert participation and an active membership for the member's
-- role, and never trust a caller-supplied owner, role or participant list.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $chat_guard$
BEGIN
  IF to_regclass('hocalist.profiles') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regprocedure('hocalist.account_command(text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Account foundation 002/003/004 is missing';
  END IF;
  IF to_regclass('hocalist.conversations') IS NOT NULL
     OR to_regclass('hocalist.conversation_members') IS NOT NULL
     OR to_regclass('hocalist.conversation_messages') IS NOT NULL
     OR to_regprocedure('hocalist.chat_inbox(integer,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Chat objects already exist; review before applying';
  END IF;
END
$chat_guard$;

CREATE TABLE hocalist.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  origin text NOT NULL CHECK (origin IN ('targeted_request','store_listing','hocatrends_enquiry')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  -- Subject ids are recorded marketplace ids. The authoritative request,
  -- offer, listing and discovery tables do not exist in hocalist yet, so
  -- these are validated by the internal opening boundary and intentionally
  -- carry no foreign keys.
  request_id uuid,
  offer_id uuid,
  listing_id uuid,
  discovery_topic_id uuid,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chat_origin_subject CHECK (
    (origin = 'targeted_request' AND request_id IS NOT NULL AND listing_id IS NULL AND discovery_topic_id IS NULL)
    OR (origin = 'store_listing' AND listing_id IS NOT NULL AND request_id IS NULL AND offer_id IS NULL AND discovery_topic_id IS NULL)
    OR (origin = 'hocatrends_enquiry' AND discovery_topic_id IS NOT NULL AND request_id IS NULL AND offer_id IS NULL AND listing_id IS NULL)
  )
);

CREATE TABLE hocalist.conversation_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id) ON DELETE CASCADE,
  sender_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  sender_profile_id uuid NOT NULL REFERENCES hocalist.memberships(id),
  kind text NOT NULL DEFAULT 'text' CHECK (kind IN ('text','system_notice')),
  text text NOT NULL,
  client_message_id text CHECK (client_message_id IS NULL OR length(client_message_id) BETWEEN 1 AND 128),
  request_hash text,
  -- Server ordering key. Timestamps can tie; the identity sequence cannot.
  seq bigint GENERATED ALWAYS AS IDENTITY,
  sent_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chat_message_text CHECK (length(btrim(text)) BETWEEN 1 AND 4000),
  CONSTRAINT chat_text_message_identity CHECK (
    kind <> 'text' OR (client_message_id IS NOT NULL AND request_hash IS NOT NULL)
  )
);
CREATE UNIQUE INDEX conversation_messages_client_key
  ON hocalist.conversation_messages(conversation_id, sender_user_id, client_message_id)
  WHERE client_message_id IS NOT NULL;
CREATE INDEX conversation_messages_page ON hocalist.conversation_messages(conversation_id, seq DESC);

CREATE TABLE hocalist.conversation_members (
  conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  -- Domain profile id = membership id (account contract).
  profile_id uuid NOT NULL REFERENCES hocalist.memberships(id),
  role text NOT NULL CHECK (role IN ('buyer','seller')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  is_muted boolean NOT NULL DEFAULT false,
  last_read_seq bigint NOT NULL DEFAULT 0 CHECK (last_read_seq >= 0),
  last_read_message_id uuid REFERENCES hocalist.conversation_messages(id),
  last_read_at timestamptz,
  PRIMARY KEY (conversation_id, user_id),
  UNIQUE (conversation_id, profile_id),
  CONSTRAINT chat_member_revoked_after_join CHECK (revoked_at IS NULL OR revoked_at >= joined_at)
);

ALTER TABLE hocalist.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.conversation_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.conversation_members ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.conversations, hocalist.conversation_messages, hocalist.conversation_members
  FROM PUBLIC, anon, authenticated, service_role;

-- Internal helper used by the defense-in-depth policies below. SECURITY
-- DEFINER avoids RLS self-recursion when a policy checks membership.
CREATE FUNCTION hocalist.chat_is_member(p_conversation uuid, p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM hocalist.conversation_members m
    WHERE m.conversation_id = p_conversation AND m.user_id = p_user
      AND m.revoked_at IS NULL
  );
$$;

-- Defense in depth: clients have no table grants, so these policies are inert
-- today and exist so a future reviewed grant cannot expose another member's
-- rows. All functional access still goes through the RPCs below.
CREATE POLICY chat_member_conversation_read ON hocalist.conversations
  FOR SELECT TO authenticated USING (hocalist.chat_is_member(id, (SELECT auth.uid())));
CREATE POLICY chat_member_message_read ON hocalist.conversation_messages
  FOR SELECT TO authenticated USING (hocalist.chat_is_member(conversation_id, (SELECT auth.uid())));
CREATE POLICY chat_member_member_read ON hocalist.conversation_members
  FOR SELECT TO authenticated USING (hocalist.chat_is_member(conversation_id, (SELECT auth.uid())));

-- Internal helper. Not executable by any client role.
CREATE FUNCTION hocalist.chat_assert_participant(p_conversation uuid, p_user uuid)
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
  RETURN m;
END; $$;

-- Internal conversation JSON builder shared by inbox/conversation reads.
CREATE FUNCTION hocalist.chat_conversation_json(p_conversation uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', c.id,
    'origin', c.origin,
    'status', c.status,
    'request_id', c.request_id,
    'offer_id', c.offer_id,
    'listing_id', c.listing_id,
    'discovery_topic_id', c.discovery_topic_id,
    'revision', c.revision,
    'created_at', c.created_at,
    'updated_at', c.updated_at,
    'members', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', m.user_id,
        'profile_id', m.profile_id,
        'role', m.role,
        'joined_at', m.joined_at,
        'revoked_at', m.revoked_at,
        'is_muted', m.is_muted,
        'last_read_message_id', m.last_read_message_id,
        'last_read_at', m.last_read_at
      ) ORDER BY m.joined_at, m.user_id)
      FROM hocalist.conversation_members m WHERE m.conversation_id = c.id
    ), '[]'::jsonb)
  )
  FROM hocalist.conversations c WHERE c.id = p_conversation;
$$;

-- Inbox: participant rows with counterpart, latest message and unread count.
CREATE FUNCTION hocalist.chat_inbox(p_page_size integer DEFAULT 50, p_cursor text DEFAULT NULL)
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

-- One conversation with its members, for participants only.
CREATE FUNCTION hocalist.chat_conversation(p_conversation uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_member hocalist.conversation_members%ROWTYPE;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, auth.uid());
  RETURN hocalist.chat_conversation_json(p_conversation);
END; $$;

-- Paged history. Newest page first internally, returned oldest-to-newest.
CREATE FUNCTION hocalist.chat_messages(
  p_conversation uuid,
  p_page_size integer DEFAULT 50,
  p_before_message uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_member hocalist.conversation_members%ROWTYPE;
  v_size integer;
  v_before_seq bigint;
  v_items jsonb;
  v_next text;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, auth.uid());
  v_size := greatest(1, least(coalesce(p_page_size, 50), 100));
  IF p_before_message IS NOT NULL THEN
    SELECT seq INTO v_before_seq FROM hocalist.conversation_messages
      WHERE id = p_before_message AND conversation_id = p_conversation;
    IF NOT FOUND THEN RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023'; END IF;
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.seq ASC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT * FROM hocalist.conversation_messages m
    WHERE m.conversation_id = p_conversation
      AND (p_before_message IS NULL OR m.seq < v_before_seq)
    ORDER BY m.seq DESC
    LIMIT v_size
  ) page;

  IF jsonb_array_length(v_items) = v_size AND EXISTS (
    SELECT 1 FROM hocalist.conversation_messages m
    WHERE m.conversation_id = p_conversation
      AND m.seq < (v_items->0->>'seq')::bigint
  ) THEN
    v_next := v_items->0->>'id';
  ELSE
    v_next := NULL;
  END IF;

  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

-- Idempotent text send. Same key and payload returns the stored message;
-- same key with a changed payload conflicts.
CREATE FUNCTION hocalist.chat_send(p_conversation uuid, p_key text, p_text text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_member hocalist.conversation_members%ROWTYPE;
  v_message hocalist.conversation_messages%ROWTYPE;
  v_hash text;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, v_user);
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_text IS NULL OR length(btrim(p_text)) NOT BETWEEN 1 AND 4000 THEN
    RAISE EXCEPTION 'invalid_message' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.conversations WHERE id = p_conversation AND status = 'open') THEN
    RAISE EXCEPTION 'conversation_closed' USING ERRCODE='P0001';
  END IF;
  v_hash := encode(sha256(convert_to(p_text, 'UTF8')), 'hex');
  INSERT INTO hocalist.conversation_messages(
    conversation_id, sender_user_id, sender_profile_id, kind, text, client_message_id, request_hash)
  VALUES (p_conversation, v_user, v_member.profile_id, 'text', p_text, p_key, v_hash)
  ON CONFLICT (conversation_id, sender_user_id, client_message_id)
    WHERE client_message_id IS NOT NULL DO NOTHING
  RETURNING * INTO v_message;
  IF NOT FOUND THEN
    SELECT * INTO v_message FROM hocalist.conversation_messages
      WHERE conversation_id = p_conversation AND sender_user_id = v_user AND client_message_id = p_key;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
    END IF;
    IF v_message.request_hash <> v_hash THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
    END IF;
  END IF;
  RETURN to_jsonb(v_message);
END; $$;

-- Monotonic mark-read: never moves the marker backwards, including when two
-- sessions of the same member race. The guarded UPDATE compares against the
-- current committed row after the row lock is acquired (READ COMMITTED
-- re-evaluates the WHERE on the locked row), so the older session becomes a
-- no-op instead of overwriting the newer committed position. A no-op re-reads
-- and returns the authoritative current marker so message id, sequence and
-- timestamp stay coherent.
CREATE FUNCTION hocalist.chat_mark_read(p_conversation uuid, p_last_read uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_member hocalist.conversation_members%ROWTYPE;
  v_seq bigint;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, v_user);
  IF p_last_read IS NULL THEN RAISE EXCEPTION 'invalid_message' USING ERRCODE='22023'; END IF;
  SELECT seq INTO v_seq FROM hocalist.conversation_messages
    WHERE id = p_last_read AND conversation_id = p_conversation;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023'; END IF;
  UPDATE hocalist.conversation_members
    SET last_read_seq = v_seq, last_read_message_id = p_last_read, last_read_at = now()
    WHERE conversation_id = p_conversation AND user_id = v_user
      AND last_read_seq < v_seq
    RETURNING * INTO v_member;
  IF NOT FOUND THEN
    SELECT * INTO v_member FROM hocalist.conversation_members
      WHERE conversation_id = p_conversation AND user_id = v_user;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'conversation_access_denied' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN to_jsonb(v_member);
END; $$;

-- Per-member mute. Naturally idempotent; only the caller's own row changes.
CREATE FUNCTION hocalist.chat_set_muted(p_conversation uuid, p_muted boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_member hocalist.conversation_members%ROWTYPE;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, v_user);
  IF p_muted IS NULL THEN RAISE EXCEPTION 'invalid_message' USING ERRCODE='22023'; END IF;
  UPDATE hocalist.conversation_members SET is_muted = p_muted
    WHERE conversation_id = p_conversation AND user_id = v_user
    RETURNING * INTO v_member;
  RETURN to_jsonb(v_member);
END; $$;

-- INTERNAL transaction boundary for the later eligibility operation.
-- No client role may execute it. It validates the origin/subject shape and
-- that every participant holds the matching active membership, then creates
-- (or returns) one conversation for that origin + subject + participant set.
-- It deliberately does not charge credits, accept offers, create deals or
-- decide any pending eligibility policy.
CREATE FUNCTION hocalist.chat_open_internal(
  p_origin text,
  p_request uuid,
  p_offer uuid,
  p_listing uuid,
  p_topic uuid,
  p_participants jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_count integer;
  v_id uuid;
BEGIN
  IF p_origin NOT IN ('targeted_request','store_listing','hocatrends_enquiry') THEN
    RAISE EXCEPTION 'invalid_origin' USING ERRCODE='22023';
  END IF;
  IF NOT (
    (p_origin = 'targeted_request' AND p_request IS NOT NULL AND p_listing IS NULL AND p_topic IS NULL)
    OR (p_origin = 'store_listing' AND p_listing IS NOT NULL AND p_request IS NULL AND p_offer IS NULL AND p_topic IS NULL)
    OR (p_origin = 'hocatrends_enquiry' AND p_topic IS NOT NULL AND p_request IS NULL AND p_offer IS NULL AND p_listing IS NULL)
  ) THEN
    RAISE EXCEPTION 'invalid_subject' USING ERRCODE='22023';
  END IF;
  IF p_participants IS NULL OR jsonb_typeof(p_participants) <> 'array' THEN
    RAISE EXCEPTION 'invalid_participants' USING ERRCODE='22023';
  END IF;
  v_count := jsonb_array_length(p_participants);
  IF v_count < 2 OR v_count > 10 THEN
    RAISE EXCEPTION 'invalid_participants' USING ERRCODE='22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM (
      SELECT e->>'user_id' AS user_id FROM jsonb_array_elements(p_participants) e
    ) ids GROUP BY user_id HAVING count(*) > 1 OR user_id IS NULL
  ) THEN
    RAISE EXCEPTION 'invalid_participants' USING ERRCODE='22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_participants) e
    WHERE e->>'profile_id' IS NULL
       OR (e->>'role') IS NULL OR (e->>'role') NOT IN ('buyer','seller')
       OR NOT EXISTS (
         SELECT 1 FROM hocalist.memberships m
         WHERE m.id = (e->>'profile_id')::uuid
           AND m.user_id = (e->>'user_id')::uuid
           AND m.role = e->>'role'
           AND m.status = 'active'
       )
  ) THEN
    RAISE EXCEPTION 'invalid_participants' USING ERRCODE='22023';
  END IF;

  SELECT c.id INTO v_id FROM hocalist.conversations c
  WHERE c.origin = p_origin
    AND c.request_id IS NOT DISTINCT FROM p_request
    AND c.offer_id IS NOT DISTINCT FROM p_offer
    AND c.listing_id IS NOT DISTINCT FROM p_listing
    AND c.discovery_topic_id IS NOT DISTINCT FROM p_topic
    AND (SELECT array_agg(m.user_id ORDER BY m.user_id) FROM hocalist.conversation_members m
         WHERE m.conversation_id = c.id)
      = (SELECT array_agg((e->>'user_id')::uuid ORDER BY (e->>'user_id')::uuid)
         FROM jsonb_array_elements(p_participants) e)
  LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  INSERT INTO hocalist.conversations(origin, request_id, offer_id, listing_id, discovery_topic_id)
  VALUES (p_origin, p_request, p_offer, p_listing, p_topic)
  RETURNING id INTO v_id;
  INSERT INTO hocalist.conversation_members(conversation_id, user_id, profile_id, role)
  SELECT v_id, (e->>'user_id')::uuid, (e->>'profile_id')::uuid, e->>'role'
  FROM jsonb_array_elements(p_participants) e;
  RETURN v_id;
END; $$;

-- Client-executable surface: reads and the three writes. Nothing else.
REVOKE ALL ON FUNCTION hocalist.chat_inbox(integer,text), hocalist.chat_conversation(uuid),
  hocalist.chat_messages(uuid,integer,uuid), hocalist.chat_send(uuid,text,text),
  hocalist.chat_mark_read(uuid,uuid), hocalist.chat_set_muted(uuid,boolean),
  hocalist.chat_assert_participant(uuid,uuid), hocalist.chat_conversation_json(uuid),
  hocalist.chat_is_member(uuid,uuid),
  hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_inbox(integer,text), hocalist.chat_conversation(uuid),
  hocalist.chat_messages(uuid,integer,uuid), hocalist.chat_send(uuid,text,text),
  hocalist.chat_mark_read(uuid,uuid), hocalist.chat_set_muted(uuid,boolean)
  TO authenticated;
COMMIT;

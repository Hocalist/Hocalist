-- DRAFT: authorized chat image attachments (additive to chat 010 + media 100).
--
-- Adds an `attachment` message kind whose media references must be ready,
-- sender-owned `chat`-purpose images, plus the participant-authorized send RPC.
-- It extends the media gateway so a participant of a conversation can read a
-- chat image referenced by a message in that conversation. Text messages stay
-- unchanged, and the existing text send path is not replaced.
--
-- Not an instruction to apply to a live project. Generate a guarded rollout
-- bundle and obtain coordinating review before applying.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $chat_attachment_guard$
BEGIN
  IF to_regclass('hocalist.conversation_messages') IS NULL
     OR to_regclass('hocalist.conversation_members') IS NULL
     OR to_regprocedure('hocalist.chat_send(uuid,text,text)') IS NULL
     OR to_regprocedure('hocalist.chat_assert_participant(uuid,uuid)') IS NULL
     OR to_regclass('hocalist.media_images') IS NULL
     OR to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Chat/media foundation 010/100 is missing';
  END IF;
  IF EXISTS (
       SELECT 1 FROM pg_attribute
       WHERE attrelid = 'hocalist.conversation_messages'::regclass
         AND attname = 'attachment_media_ids' AND NOT attisdropped)
     OR to_regprocedure('hocalist.chat_send_attachment(uuid,text,text,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'Chat attachments already exist; review before applying';
  END IF;
END
$chat_attachment_guard$;

-- ---------------------------------------------------------------------------
-- Attachment column and message shape
-- ---------------------------------------------------------------------------

ALTER TABLE hocalist.conversation_messages
  ADD COLUMN attachment_media_ids jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE hocalist.conversation_messages
  DROP CONSTRAINT conversation_messages_kind_check;
ALTER TABLE hocalist.conversation_messages
  ADD CONSTRAINT conversation_messages_kind_check CHECK (
    kind IN ('text','attachment','system_notice')
  );

ALTER TABLE hocalist.conversation_messages
  DROP CONSTRAINT chat_message_text;
ALTER TABLE hocalist.conversation_messages
  ADD CONSTRAINT chat_message_text CHECK (
    length(btrim(text)) <= 4000
    AND (length(btrim(text)) >= 1 OR kind = 'attachment')
  );

ALTER TABLE hocalist.conversation_messages
  DROP CONSTRAINT chat_text_message_identity;
ALTER TABLE hocalist.conversation_messages
  ADD CONSTRAINT chat_message_identity CHECK (
    kind NOT IN ('text','attachment')
    OR (client_message_id IS NOT NULL AND request_hash IS NOT NULL)
  );

ALTER TABLE hocalist.conversation_messages
  ADD CONSTRAINT chat_attachment_shape CHECK (
    jsonb_typeof(attachment_media_ids) = 'array'
    AND jsonb_array_length(attachment_media_ids) BETWEEN 0 AND 4
    AND (kind = 'attachment') = (jsonb_array_length(attachment_media_ids) BETWEEN 1 AND 4)
  );

-- Every referenced id must be a ready, sender-owned, chat-purpose image.
CREATE FUNCTION hocalist.chat_validate_attachments() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_item text;
BEGIN
  IF jsonb_array_length(NEW.attachment_media_ids) = 0 THEN
    RETURN NEW;
  END IF;
  FOR v_item IN SELECT jsonb_array_elements_text(NEW.attachment_media_ids) LOOP
    IF v_item !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
       OR NOT EXISTS (
         SELECT 1 FROM hocalist.media_images m
         WHERE m.id = v_item::uuid
           AND m.owner_user_id = NEW.sender_user_id
           AND m.state = 'ready'
           AND m.purpose = 'chat') THEN
      RAISE EXCEPTION 'invalid_media_reference' USING ERRCODE='22023';
    END IF;
  END LOOP;
  RETURN NEW;
END; $$;

CREATE TRIGGER chat_message_validate_attachments
  BEFORE INSERT ON hocalist.conversation_messages
  FOR EACH ROW EXECUTE FUNCTION hocalist.chat_validate_attachments();

-- ---------------------------------------------------------------------------
-- Idempotent attachment send
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.chat_send_attachment(
  p_conversation uuid,
  p_key text,
  p_text text,
  p_media_ids jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_member hocalist.conversation_members%ROWTYPE;
  v_message hocalist.conversation_messages%ROWTYPE;
  v_text text := coalesce(p_text, '');
  v_ids text[];
  v_hash text;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, v_user);
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR length(btrim(v_text)) > 4000
     OR p_media_ids IS NULL
     OR jsonb_typeof(p_media_ids) <> 'array'
     OR jsonb_array_length(p_media_ids) NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'invalid_message' USING ERRCODE='22023';
  END IF;
  SELECT array_agg(value ORDER BY value) INTO v_ids
  FROM jsonb_array_elements_text(p_media_ids) AS value;
  IF EXISTS (
       SELECT 1 FROM unnest(v_ids) AS item
       WHERE item !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') THEN
    RAISE EXCEPTION 'invalid_message' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.conversations WHERE id = p_conversation AND status = 'open') THEN
    RAISE EXCEPTION 'conversation_closed' USING ERRCODE='P0001';
  END IF;
  v_hash := encode(
    sha256(convert_to(v_text || '|' || array_to_string(v_ids, ','), 'UTF8')), 'hex');
  INSERT INTO hocalist.conversation_messages(
    conversation_id, sender_user_id, sender_profile_id, kind, text,
    attachment_media_ids, client_message_id, request_hash)
  VALUES (p_conversation, v_user, v_member.profile_id, 'attachment', v_text,
          to_jsonb(v_ids), p_key, v_hash)
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

-- ---------------------------------------------------------------------------
-- Media read authorization for chat participants
-- ---------------------------------------------------------------------------

-- Referenced chat image read rule. It mirrors `chat_assert_participant`: the
-- reader must be a non-revoked conversation member, hold the matching active
-- role membership, and carry no restricted/disabled membership in any role.
-- Other purpose helpers may be installed by later additive migrations; the
-- gateway dispatches to whichever exist.
CREATE FUNCTION hocalist.media_read_chat(p_user uuid, p_image uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM hocalist.conversation_messages msg
    JOIN hocalist.conversation_members cm ON cm.conversation_id = msg.conversation_id
    WHERE msg.attachment_media_ids ? p_image::text
      AND cm.user_id = p_user AND cm.revoked_at IS NULL
      AND EXISTS (
        SELECT 1 FROM hocalist.memberships m
        WHERE m.id = cm.profile_id AND m.user_id = p_user
          AND m.role = cm.role AND m.status = 'active')
      AND NOT EXISTS (
        SELECT 1 FROM hocalist.memberships r
        WHERE r.user_id = p_user AND r.status IN ('restricted','disabled')));
$$;

CREATE OR REPLACE FUNCTION hocalist.media_gateway(p_user uuid, p_action text, p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  m hocalist.media_images%ROWTYPE;
  image_id uuid;
  purpose text;
  n integer;
  v_allowed boolean;
BEGIN
  IF p_user IS NULL
     OR NOT EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id = p_user AND status = 'active')
     OR EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id = p_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501';
  END IF;
  INSERT INTO hocalist.media_windows(user_id, started_at, calls)
  VALUES (p_user, now(), 1)
  ON CONFLICT (user_id) DO UPDATE SET
    calls = CASE WHEN media_windows.started_at < now() - interval '1 minute' THEN 1 ELSE media_windows.calls + 1 END,
    started_at = CASE WHEN media_windows.started_at < now() - interval '1 minute' THEN now() ELSE media_windows.started_at END
  RETURNING calls INTO n;
  IF n > 60 THEN RAISE EXCEPTION 'media_rate_limit'; END IF;
  IF p_action = 'begin' THEN
    purpose := p_input->>'purpose';
    IF purpose IN ('offer','store') AND NOT EXISTS (
      SELECT 1 FROM hocalist.memberships WHERE user_id = p_user AND role = 'seller' AND status = 'active') THEN
      RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501';
    END IF;
    PERFORM 1 FROM hocalist.profiles WHERE id = p_user FOR UPDATE;
    SELECT * INTO m FROM hocalist.media_images
      WHERE owner_user_id = p_user AND intent_key = (p_input->>'key')::uuid;
    IF FOUND THEN
      IF m.purpose <> purpose OR m.content_hash <> p_input->>'hash' THEN
        RAISE EXCEPTION 'idempotency_conflict';
      END IF;
    ELSE
      IF (SELECT count(*) FROM hocalist.media_images
          WHERE owner_user_id = p_user AND created_at > now() - interval '1 hour') >= 60 THEN
        RAISE EXCEPTION 'media_rate_limit';
      END IF;
      INSERT INTO hocalist.media_images(owner_user_id, intent_key, purpose, content_hash)
      VALUES (p_user, (p_input->>'key')::uuid, purpose, p_input->>'hash')
      RETURNING * INTO m;
    END IF;
  ELSIF p_action = 'complete' THEN
    UPDATE hocalist.media_images
      SET state = 'ready', size_bytes = (p_input->>'size')::integer,
          width = (p_input->>'width')::integer, height = (p_input->>'height')::integer
      WHERE id = (p_input->>'id')::uuid AND owner_user_id = p_user
        AND state IN ('pending','ready')
      RETURNING * INTO m;
    IF NOT FOUND THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='P0002'; END IF;
  ELSIF p_action = 'read' THEN
    image_id := (p_input->>'id')::uuid;
    SELECT * INTO m FROM hocalist.media_images WHERE id = image_id AND state = 'ready';
    IF NOT FOUND THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='P0002'; END IF;
    IF m.owner_user_id <> p_user THEN
      v_allowed :=
        (m.purpose = 'store' AND EXISTS (
          SELECT 1 FROM hocalist.store_listings l
          JOIN hocalist.memberships s ON s.id = l.seller_profile_id
          WHERE l.image_media_ids ? image_id::text
            AND l.status = 'active' AND l.moderation_status = 'approved' AND s.status = 'active'))
        OR (m.purpose = 'offer' AND EXISTS (
          SELECT 1 FROM hocalist.offer_revisions r
          JOIN hocalist.offers o ON o.id = r.offer_id
          JOIN hocalist.requests q ON q.id = o.request_id
          WHERE r.image_media_ids ? image_id::text AND q.buyer_user_id = p_user));
      IF NOT v_allowed
         AND to_regprocedure('hocalist.media_read_chat(uuid,uuid)') IS NOT NULL THEN
        v_allowed := hocalist.media_read_chat(p_user, image_id);
      END IF;
      IF NOT v_allowed
         AND to_regprocedure('hocalist.media_read_profile(uuid,uuid)') IS NOT NULL THEN
        v_allowed := hocalist.media_read_profile(p_user, image_id);
      END IF;
      IF NOT v_allowed THEN
        RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501';
      END IF;
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023';
  END IF;
  RETURN jsonb_build_object(
    'id', m.id,
    'path', m.owner_user_id::text || '/' || m.id::text || '.jpg',
    'state', m.state);
END; $$;

-- ---------------------------------------------------------------------------
-- Grants and post-apply verification
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION hocalist.chat_validate_attachments()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.chat_send_attachment(uuid,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.media_read_chat(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.media_gateway(uuid,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_send_attachment(uuid,text,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.media_gateway(uuid,text,jsonb) TO service_role;

DO $hocalist_chat_attachment_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'hocalist.conversation_messages'::regclass
      AND attname = 'attachment_media_ids' AND attnotnull AND NOT attisdropped) THEN
    v_issues := array_append(v_issues, 'missing attachment_media_ids column');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'hocalist.conversation_messages'::regclass
      AND conname = 'chat_attachment_shape') THEN
    v_issues := array_append(v_issues, 'missing attachment shape constraint');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'hocalist.conversation_messages'::regclass
      AND tgname = 'chat_message_validate_attachments' AND NOT tgisinternal) THEN
    v_issues := array_append(v_issues, 'missing attachment validation trigger');
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.chat_send_attachment(uuid,text,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','hocalist.chat_send_attachment(uuid,text,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','hocalist.chat_validate_attachments()','EXECUTE')
     OR has_function_privilege('authenticated','hocalist.media_gateway(uuid,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'chat attachment grants are wrong');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist chat attachment post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_chat_attachment_postapply$;
COMMIT;

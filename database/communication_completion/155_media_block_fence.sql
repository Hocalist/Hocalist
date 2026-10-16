-- Chat attachment read fence for blocked recipients (allocation 155).
--
-- The reviewed chat 011 `media_read_chat` helper checks membership, matching
-- active role membership and account restriction, but not the conversation
-- block contract introduced by 150. A blocked counterpart could therefore keep
-- requesting read URLs for images already shared in that conversation.
--
-- This additive correction replaces the helper with the same policy plus one
-- directional fence: the member recorded as the *blocked* party of an active
-- block cannot read attachments in that conversation. The blocker keeps access
-- to their own history, exactly like the conversation read policy, and an image
-- owner keeps access through the gateway's owner short-circuit.
--
-- Ordering and lifetime:
-- * If chat 011 is already applied, this replaces its reviewed definition
--   (exact md5 guard; any other drift aborts).
-- * If chat 011 is not applied yet, this file does nothing and records a notice.
--   Apply chat 011 first (its own guard creates the helper), then run this file
--   again to install the fence. This file is safe to run standalone and is a
--   no-op when the helper is already fenced.
-- * Read URLs already issued before a block are not recalled by this check.
--   Their storage lifetime is bounded by the signed-URL expiry and the bucket
--   policy owned by the media package; a later permission check only prevents
--   newly issued reads.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $media_fence_guard$
DECLARE
  v_def text;
  v_hash text;
  -- Exact reviewed definitions (md5 of pg_get_functiondef, CR-normalized).
  -- Only these two bodies are accepted; a permissive body that merely mentions
  -- `conversation_blocks` (for example in a comment) is drift and is rejected
  -- before any mutation.
  v_legacy constant text := '6a87ca8a3b753bcf7e59b4b692cc10b3';
  v_corrected constant text := 'b1671c7e2e91a48ace319e3f94583e63';
BEGIN
  IF to_regclass('hocalist.conversation_messages') IS NULL
     OR to_regclass('hocalist.conversation_members') IS NULL
     OR to_regclass('hocalist.conversation_blocks') IS NULL THEN
    RAISE EXCEPTION 'Chat block/attachment foundation is missing';
  END IF;

  IF to_regprocedure('hocalist.media_read_chat(uuid,uuid)') IS NULL THEN
    RAISE NOTICE 'chat 011 is not applied; media_read_chat fence deferred until it is';
    RETURN;
  END IF;
  -- The helper can only exist when the media module is present; assert that
  -- explicitly before replacing anything.
  IF to_regclass('hocalist.media_images') IS NULL
     OR to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'media 100 foundation is missing for the chat attachment helper';
  END IF;

  v_def := pg_get_functiondef(to_regprocedure('hocalist.media_read_chat(uuid,uuid)'));
  v_hash := md5(replace(v_def, chr(13), ''));
  IF v_hash = v_corrected THEN
    RAISE NOTICE 'media_read_chat is already the reviewed corrected definition; nothing to do';
    RETURN;
  END IF;
  IF v_hash <> v_legacy THEN
    RAISE EXCEPTION 'Prerequisite drift: hocalist.media_read_chat(uuid,uuid)';
  END IF;

  EXECUTE $fenced$
CREATE OR REPLACE FUNCTION hocalist.media_read_chat(p_user uuid, p_image uuid)
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
        WHERE r.user_id = p_user AND r.status IN ('restricted','disabled'))
      AND NOT EXISTS (
        SELECT 1 FROM hocalist.conversation_blocks b
        WHERE b.conversation_id = msg.conversation_id
          AND b.revoked_at IS NULL
          AND b.blocked_user_id = p_user)
  );
$$;
$fenced$;

  -- Re-assert the reviewed grant shape (the replacement preserves ACLs, but a
  -- standalone re-run on a partially changed database must not widen access).
  REVOKE ALL ON FUNCTION hocalist.media_read_chat(uuid,uuid)
    FROM PUBLIC, anon, authenticated, service_role;
END
$media_fence_guard$;

DO $media_fence_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_hash text;
BEGIN
  IF to_regprocedure('hocalist.media_read_chat(uuid,uuid)') IS NOT NULL THEN
    v_hash := md5(replace(pg_get_functiondef(
      to_regprocedure('hocalist.media_read_chat(uuid,uuid)')), chr(13), ''));
    IF v_hash <> 'b1671c7e2e91a48ace319e3f94583e63' THEN
      v_issues := array_append(
        v_issues, 'media_read_chat is not the reviewed corrected definition');
    END IF;
    IF has_function_privilege('authenticated','hocalist.media_read_chat(uuid,uuid)','EXECUTE')
       OR has_function_privilege('anon','hocalist.media_read_chat(uuid,uuid)','EXECUTE')
       OR has_function_privilege('service_role','hocalist.media_read_chat(uuid,uuid)','EXECUTE') THEN
      v_issues := array_append(v_issues, 'media_read_chat must stay an internal helper');
    END IF;
  END IF;
  IF to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)') IS NOT NULL
     AND (NOT has_function_privilege('service_role','hocalist.media_gateway(uuid,text,jsonb)','EXECUTE')
       OR has_function_privilege('authenticated','hocalist.media_gateway(uuid,text,jsonb)','EXECUTE')) THEN
    v_issues := array_append(v_issues, 'media gateway grants changed');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist media fence post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$media_fence_postapply$;
COMMIT;

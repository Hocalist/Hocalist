-- Call lifecycle read/resume contract (allocation 152).
--
-- Additive to the deployed call signaling 110. It does not replace
-- `call_command`; it adds the missing read path the app needs for reconnect,
-- app resume and deterministic terminal handling:
--
-- * `call_status` returns the same participant-only call projection plus
--   `expires_at`, `server_now`, a server-computed `terminal` flag, the admin
--   switch state/revision and the newest signals after a cursor. It sweeps
--   expired ringing/accepted calls under the same advisory lock as
--   `call_command`, so the timeout outcome is deterministic regardless of
--   which participant polls first.
-- * Terminal states stay: ringing -> missed (timeout) or cancelled (caller
--   end); accepted -> ended (either side, timeout or the admin off switch);
--   ringing -> declined (callee). Re-enabling the switch never revives a
--   terminal call.
--
-- Blocking is already enforced through the 150 participant fence: a blocked
-- member and the blocker cannot invite, accept, decline or exchange signals
-- (`conversation_blocked`), while `call_status` remains limited to the two
-- participants so a client can always close its own media.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $call_status_guard$
BEGIN
  IF to_regclass('hocalist.calls') IS NULL
     OR to_regclass('hocalist.call_signals') IS NULL
     OR to_regclass('hocalist.call_settings') IS NULL
     OR to_regprocedure('hocalist.call_command(text,jsonb)') IS NULL
     OR to_regprocedure('hocalist.chat_assert_participant(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Call signaling 110 is missing';
  END IF;
  IF md5(replace(pg_get_functiondef(to_regprocedure('hocalist.call_command(text,jsonb)')),chr(13),''))
       <> '49221a424fc1c80032f56da8a71de9bd' THEN
    RAISE EXCEPTION 'Prerequisite drift: hocalist.call_command(text,jsonb)';
  END IF;
  IF to_regprocedure('hocalist.call_status(uuid,bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'Call status object already exists; review before applying';
  END IF;
END
$call_status_guard$;

CREATE FUNCTION hocalist.call_status(p_call_id uuid, p_cursor bigint DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  c hocalist.calls%ROWTYPE;
  s hocalist.call_settings%ROWTYPE;
  items jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF p_call_id IS NULL THEN
    RAISE EXCEPTION 'invalid_field: p_call_id' USING ERRCODE='22023';
  END IF;
  IF p_cursor IS NOT NULL AND p_cursor < 0 THEN
    RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id = v_user AND status = 'active')
     OR EXISTS (SELECT 1 FROM hocalist.memberships
                WHERE user_id = v_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'call_access_denied' USING ERRCODE='42501';
  END IF;
  -- Serialize with the call control plane so the timeout sweep and the call
  -- command cannot observe or write different states concurrently.
  PERFORM pg_advisory_xact_lock(110,1);
  UPDATE hocalist.calls SET state = CASE WHEN state = 'ringing' THEN 'missed' ELSE 'ended' END
    WHERE state IN ('ringing','accepted') AND expires_at <= now();
  DELETE FROM hocalist.call_signals s2 USING hocalist.calls d
    WHERE s2.call_id = d.id AND d.state NOT IN ('ringing','accepted');

  SELECT * INTO c FROM hocalist.calls WHERE id = p_call_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'call_not_found' USING ERRCODE='P0002';
  END IF;
  IF v_user NOT IN (c.caller_id, c.callee_id) THEN
    RAISE EXCEPTION 'call_access_denied' USING ERRCODE='42501';
  END IF;
  -- Read-only status keeps the participant check (an unrevoked conversation
  -- member plus an active role membership) so either participant can observe a
  -- terminal state and close media. Restricted/disabled accounts are denied by
  -- the account check above, exactly like the participant fence; a blocked
  -- member can still read status but cannot exchange signals or invites. Writes
  -- still go through the 150-fenced call command.
  PERFORM 1 FROM hocalist.conversation_members cm
    WHERE cm.conversation_id = c.conversation_id AND cm.user_id = v_user
      AND cm.revoked_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'call_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO s FROM hocalist.call_settings WHERE singleton;

  SELECT coalesce(jsonb_agg(jsonb_build_object('seq', sig.seq, 'kind', sig.kind, 'payload', sig.payload)
           ORDER BY sig.seq), '[]'::jsonb)
  INTO items
  FROM hocalist.call_signals sig
  WHERE sig.call_id = c.id AND sig.sender_id <> v_user
    AND sig.seq > coalesce(p_cursor, 0);

  RETURN jsonb_build_object(
    'call', jsonb_build_object(
      'id', c.id,
      'conversation_id', c.conversation_id,
      'caller_id', c.caller_id,
      'callee_id', c.callee_id,
      'state', c.state,
      'created_at', c.created_at,
      'expires_at', c.expires_at,
      'terminal', c.state NOT IN ('ringing','accepted')
    ),
    'signals', items,
    'server_now', now(),
    'enabled', coalesce(s.enabled, false),
    'settings_revision', coalesce(s.revision, 0)
  );
END; $$;

REVOKE ALL ON FUNCTION hocalist.call_status(uuid,bigint)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.call_status(uuid,bigint) TO authenticated;

DO $hocalist_call_status_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT has_function_privilege('authenticated','hocalist.call_status(uuid,bigint)','EXECUTE')
     OR has_function_privilege('anon','hocalist.call_status(uuid,bigint)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.call_status(uuid,bigint)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'call status grants are wrong');
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.call_command(text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.call_admin_settings(boolean,bigint)','EXECUTE')
     OR has_function_privilege('anon','hocalist.call_command(text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed call grants changed');
  END IF;
  IF position('terminal' in pg_get_functiondef(to_regprocedure('hocalist.call_status(uuid,bigint)'))) = 0 THEN
    v_issues := array_append(v_issues, 'call status terminal flag missing');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist call status post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_call_status_postapply$;
COMMIT;

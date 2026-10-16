-- Hocalist-owned, two-person WebRTC signaling. Media never enters this DB.
BEGIN;
CREATE TABLE hocalist.calls(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id),
 caller_id uuid NOT NULL REFERENCES hocalist.profiles(id),callee_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 intent_key uuid NOT NULL,state text NOT NULL DEFAULT 'ringing' CHECK(state IN ('ringing','accepted','declined','cancelled','ended','missed')),
 created_at timestamptz NOT NULL DEFAULT now(),expires_at timestamptz NOT NULL DEFAULT now()+interval '45 seconds',
 caller_seen_at timestamptz NOT NULL DEFAULT now(),callee_seen_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(caller_id,intent_key),CHECK(caller_id<>callee_id)
);
CREATE TABLE hocalist.call_signals(
 seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,call_id uuid NOT NULL REFERENCES hocalist.calls(id) ON DELETE CASCADE,
 sender_id uuid NOT NULL,intent_key uuid NOT NULL,kind text NOT NULL CHECK(kind IN ('offer','answer','candidate')),
 payload jsonb NOT NULL CHECK(octet_length(payload::text)<=65536),UNIQUE(call_id,sender_id,intent_key)
);
ALTER TABLE hocalist.calls ENABLE ROW LEVEL SECURITY;ALTER TABLE hocalist.call_signals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.calls,hocalist.call_signals FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE hocalist.call_signals_seq_seq FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE hocalist.call_settings (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 enabled boolean NOT NULL DEFAULT false, revision bigint NOT NULL DEFAULT 1,
 changed_by uuid, changed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.call_settings DEFAULT VALUES;
CREATE TABLE hocalist.call_settings_audit (
 revision bigint PRIMARY KEY, enabled boolean NOT NULL, changed_by uuid NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.call_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.call_settings_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.call_settings,hocalist.call_settings_audit FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hocalist.call_admin_settings(p_enabled boolean DEFAULT NULL,p_revision bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s hocalist.call_settings%ROWTYPE;
BEGIN
 PERFORM hocalist.marketplace_assert_admin(auth.uid());
 PERFORM pg_advisory_xact_lock(110,1);
 SELECT * INTO STRICT s FROM hocalist.call_settings WHERE singleton FOR UPDATE;
 IF p_enabled IS NOT NULL THEN
  IF p_revision IS DISTINCT FROM s.revision THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='40001'; END IF;
  IF s.enabled IS DISTINCT FROM p_enabled THEN
   UPDATE hocalist.call_settings SET enabled=p_enabled,revision=revision+1,changed_by=auth.uid(),changed_at=now()
    WHERE singleton RETURNING * INTO s;
   INSERT INTO hocalist.call_settings_audit(revision,enabled,changed_by) VALUES(s.revision,s.enabled,auth.uid());
   IF NOT s.enabled THEN
    UPDATE hocalist.calls SET state='ended' WHERE state IN ('ringing','accepted');
    DELETE FROM hocalist.call_signals;
   END IF;
  END IF;
 END IF;
 RETURN jsonb_build_object('enabled',s.enabled,'revision',s.revision);
END $$;
REVOKE ALL ON FUNCTION hocalist.call_admin_settings(boolean,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.call_admin_settings(boolean,bigint) TO authenticated;
CREATE FUNCTION hocalist.call_command(p_action text,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();c hocalist.calls%ROWTYPE;peer uuid;conv uuid;item hocalist.call_signals%ROWTYPE;items jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'unauthorized' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(p_input)<>'object' OR octet_length(p_input::text)>70000 THEN RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status='active')
  OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN RAISE EXCEPTION 'call_access_denied' USING ERRCODE='42501'; END IF;
 -- Serialize the small MVP control plane across invitations, busy checks and
 -- terminal cleanup. Revisit partitioning only with measured call volume.
 PERFORM pg_advisory_xact_lock(110,1);
 UPDATE hocalist.calls SET state=CASE WHEN state='ringing' THEN 'missed' ELSE 'ended' END
  WHERE state IN ('ringing','accepted') AND expires_at<=now();
 DELETE FROM hocalist.call_signals s USING hocalist.calls d WHERE s.call_id=d.id AND d.state NOT IN ('ringing','accepted');
 IF NOT coalesce((SELECT enabled FROM hocalist.call_settings WHERE singleton),false) THEN
  IF p_action='incoming' THEN RETURN jsonb_build_object('call',NULL,'enabled',false); END IF;
  IF p_action NOT IN ('poll','end') THEN RAISE EXCEPTION 'calls_disabled' USING ERRCODE='42501'; END IF;
 END IF;
 IF p_action='incoming' THEN
  SELECT * INTO c FROM hocalist.calls WHERE callee_id=u AND state='ringing' ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('call',NULL); END IF;
 ELSE
  IF p_action='invite' THEN
   conv:=(p_input->>'conversation_id')::uuid;
   PERFORM hocalist.chat_assert_participant(conv,u);
   IF NOT EXISTS(SELECT 1 FROM hocalist.meetings WHERE conversation_id=conv AND status='accepted') THEN RAISE EXCEPTION 'meeting_required'; END IF;
   SELECT user_id INTO peer FROM hocalist.conversation_members WHERE conversation_id=conv AND user_id<>u AND revoked_at IS NULL;
   PERFORM hocalist.chat_assert_participant(conv,peer);
   SELECT * INTO c FROM hocalist.calls WHERE caller_id=u AND intent_key=(p_input->>'key')::uuid;
   IF FOUND THEN
    IF c.conversation_id<>conv THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
   ELSE
    IF EXISTS(SELECT 1 FROM hocalist.calls WHERE state IN ('ringing','accepted') AND (caller_id IN (u,peer) OR callee_id IN (u,peer))) THEN
     RETURN jsonb_build_object('status','busy'); END IF;
    IF (SELECT count(*) FROM hocalist.calls WHERE caller_id=u AND created_at>now()-interval '1 hour')>=20 THEN RAISE EXCEPTION 'call_rate_limit'; END IF;
    INSERT INTO hocalist.calls(conversation_id,caller_id,callee_id,intent_key) VALUES(conv,u,peer,(p_input->>'key')::uuid) RETURNING * INTO c;
   END IF;
  ELSE
   SELECT * INTO c FROM hocalist.calls WHERE id=(p_input->>'call_id')::uuid;
   IF NOT FOUND THEN RAISE EXCEPTION 'call_not_found' USING ERRCODE='P0002'; END IF;
  END IF;
 END IF;
 IF u NOT IN (c.caller_id,c.callee_id) THEN RAISE EXCEPTION 'call_access_denied' USING ERRCODE='42501'; END IF;
 PERFORM hocalist.chat_assert_participant(c.conversation_id,u);
 IF NOT EXISTS(SELECT 1 FROM hocalist.conversations WHERE id=c.conversation_id AND status='open') THEN RAISE EXCEPTION 'conversation_closed'; END IF;
 -- Revocation on either side ends eligibility to exchange signaling.
 PERFORM hocalist.chat_assert_participant(c.conversation_id,CASE WHEN u=c.caller_id THEN c.callee_id ELSE c.caller_id END);
 IF p_action IN ('accept','decline') THEN
  IF u<>c.callee_id THEN RAISE EXCEPTION 'call_access_denied' USING ERRCODE='42501'; END IF;
  IF c.state='ringing' THEN
   UPDATE hocalist.calls SET state=CASE p_action WHEN 'accept' THEN 'accepted' ELSE 'declined' END,
    expires_at=now()+interval '90 seconds',caller_seen_at=now(),callee_seen_at=now() WHERE id=c.id RETURNING * INTO c;
  ELSIF NOT ((p_action='accept' AND c.state='accepted') OR (p_action='decline' AND c.state='declined')) THEN RAISE EXCEPTION 'call_finished'; END IF;
 ELSIF p_action='end' THEN
  UPDATE hocalist.calls SET state=CASE WHEN state='ringing' THEN 'cancelled' ELSE 'ended' END WHERE id=c.id AND state IN ('ringing','accepted') RETURNING * INTO c;
  IF NOT FOUND THEN SELECT * INTO c FROM hocalist.calls WHERE id=(p_input->>'call_id')::uuid; END IF;
 ELSIF p_action='signal' THEN
  IF c.state<>'accepted' THEN RAISE EXCEPTION 'call_not_accepted'; END IF;
  IF (p_input->>'kind'='offer' AND u<>c.caller_id) OR (p_input->>'kind'='answer' AND u<>c.callee_id) THEN RAISE EXCEPTION 'invalid_signal_role'; END IF;
  SELECT * INTO item FROM hocalist.call_signals WHERE call_id=c.id AND sender_id=u AND intent_key=(p_input->>'key')::uuid;
  IF FOUND THEN
   IF item.kind<>p_input->>'kind' OR item.payload IS DISTINCT FROM p_input->'payload' THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
  ELSE
   IF (SELECT count(*) FROM hocalist.call_signals WHERE call_id=c.id AND sender_id=u)>=256 THEN RAISE EXCEPTION 'signal_limit'; END IF;
   INSERT INTO hocalist.call_signals(call_id,sender_id,intent_key,kind,payload) VALUES(c.id,u,(p_input->>'key')::uuid,p_input->>'kind',p_input->'payload');
  END IF;
 ELSIF p_action NOT IN ('invite','incoming','poll') OR p_action IS NULL THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023';
 END IF;
 IF p_action='poll' AND c.state='accepted' THEN
  UPDATE hocalist.calls SET caller_seen_at=CASE WHEN caller_id=u THEN now() ELSE caller_seen_at END,
   callee_seen_at=CASE WHEN callee_id=u THEN now() ELSE callee_seen_at END WHERE id=c.id RETURNING * INTO c;
  UPDATE hocalist.calls SET expires_at=least(c.caller_seen_at,c.callee_seen_at)+interval '90 seconds' WHERE id=c.id;
 END IF;
 IF c.state NOT IN ('ringing','accepted') THEN DELETE FROM hocalist.call_signals WHERE call_id=c.id; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('seq',s.seq,'kind',s.kind,'payload',s.payload) ORDER BY s.seq),'[]'::jsonb) INTO items
  FROM hocalist.call_signals s WHERE s.call_id=c.id AND s.sender_id<>u AND s.seq>coalesce((p_input->>'cursor')::bigint,0);
 RETURN jsonb_build_object('call',jsonb_build_object('id',c.id,'conversation_id',c.conversation_id,'caller_id',c.caller_id,'callee_id',c.callee_id,'state',c.state),'signals',items);
END $$;
REVOKE ALL ON FUNCTION hocalist.call_command(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.call_command(text,jsonb) TO authenticated;
COMMIT;

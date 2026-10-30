-- Reuse participant threads; offers and fees remain separate deals.
-- Existing messages/history are preserved; legacy threads are not destructively merged.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)') AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('e9e39a2fb889dd31fcf4c9581e267be5','24d389f71f1c65d3e1a58202e51bd33f') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Pair chat definition drift: chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)') AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('dbbc3139676df6e2312b6622de7a17c0','9c4923568a5e5de6e82440b3f797df44') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Pair chat definition drift: meeting_propose(uuid,jsonb,text)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=to_regprocedure('hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)') AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Pair chat helper grants drift'; END IF;
 IF to_regprocedure('hocalist.chat_deals(uuid)') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.chat_deals(uuid)') AND md5(replace(prosrc,E'\r\n',E'\n'))='f14da1d9a8721f0445a146fe5fe1b59b' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Pair chat read drift'; END IF;

END $guard$;
CREATE OR REPLACE FUNCTION hocalist.chat_open_internal(
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

  -- Serialize all origins for the same exact participant set.
  PERFORM pg_advisory_xact_lock(hashtextextended((SELECT string_agg(e->>'user_id',',' ORDER BY e->>'user_id') FROM jsonb_array_elements(p_participants) e),209));
  SELECT c.id INTO v_id FROM hocalist.conversations c
  WHERE c.status='open'
    AND jsonb_array_length(p_participants)=2
    AND (SELECT count(*) FROM jsonb_array_elements(p_participants) e WHERE e->>'role'='buyer')=1
    AND (SELECT count(*) FROM jsonb_array_elements(p_participants) e WHERE e->>'role'='seller')=1
    AND NOT EXISTS(SELECT 1 FROM hocalist.conversation_members m WHERE m.conversation_id=c.id
      AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_participants) e WHERE (e->>'user_id')::uuid=m.user_id AND (e->>'profile_id')::uuid=m.profile_id AND e->>'role'=m.role))
    AND (SELECT array_agg(m.user_id ORDER BY m.user_id) FROM hocalist.conversation_members m
         WHERE m.conversation_id = c.id)
      = (SELECT array_agg((e->>'user_id')::uuid ORDER BY (e->>'user_id')::uuid)
         FROM jsonb_array_elements(p_participants) e)
  ORDER BY c.created_at,c.id LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  INSERT INTO hocalist.conversations(origin, request_id, offer_id, listing_id, discovery_topic_id)
  VALUES (p_origin, p_request, p_offer, p_listing, p_topic)
  RETURNING id INTO v_id;
  INSERT INTO hocalist.conversation_members(conversation_id, user_id, profile_id, role)
  SELECT v_id, (e->>'user_id')::uuid, (e->>'profile_id')::uuid, e->>'role'
  FROM jsonb_array_elements(p_participants) e;
  RETURN v_id;
END; $$;
CREATE OR REPLACE FUNCTION hocalist.meeting_propose(
  p_conversation uuid,
  p_input jsonb,
  p_key text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_conv hocalist.conversations%ROWTYPE;
  v_offer hocalist.offers%ROWTYPE;
  v_meeting hocalist.meetings%ROWTYPE;
  v_norm jsonb;
  v_hash text;
  v_replay jsonb;
  v_meeting_id uuid;
  v_seq integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid_field: p_key' USING ERRCODE='22023';
  END IF;
  IF p_conversation IS NULL OR p_input IS NULL
     OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_field: p_input' USING ERRCODE='22023';
  END IF;
  PERFORM hocalist.meeting_assert_conversation_member(p_conversation, v_user);
  SELECT * INTO v_conv FROM hocalist.conversations
    WHERE id = p_conversation FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'meeting_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_offer FROM hocalist.offers
    WHERE status='selected' AND conversation_id=p_conversation
      AND id=CASE WHEN p_input ? 'offer_id' THEN (p_input->>'offer_id')::uuid
       WHEN (SELECT count(*) FROM hocalist.offers WHERE conversation_id=p_conversation AND status='selected')=1
       THEN (SELECT id FROM hocalist.offers WHERE conversation_id=p_conversation AND status='selected' LIMIT 1) END;
  IF NOT FOUND OR v_offer.accepted_revision_id IS NULL THEN
    RAISE EXCEPTION 'meeting_offer_not_selected' USING ERRCODE='P0001';
  END IF;

  IF NOT EXISTS(SELECT 1 FROM hocalist.requests WHERE id=v_offer.request_id AND purchase_offer_id=v_offer.id) THEN
    RAISE EXCEPTION 'confirm_seller_before_meeting' USING ERRCODE='P0001';
  END IF;
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'conversation', p_conversation, 'input', p_input)::text,'UTF8')),'hex');
  v_replay := hocalist.meeting_receipt_begin(
    v_user, 'meeting.propose', p_key, v_hash);
  IF v_replay IS NOT NULL THEN
    RETURN v_replay;
  END IF;

  SELECT * INTO v_meeting FROM hocalist.meetings
    WHERE conversation_id = p_conversation AND offer_id = v_offer.id;
  IF FOUND THEN
    IF v_meeting.status = 'cancelled' THEN
      RAISE EXCEPTION 'meeting_cancelled' USING ERRCODE='P0001';
    END IF;
    IF v_meeting.accepted_revision_id IS NOT NULL
       OR v_meeting.status = 'accepted' THEN
      RAISE EXCEPTION 'meeting_already_exists' USING ERRCODE='P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM hocalist.meeting_schedule_revisions
               WHERE meeting_id = v_meeting.id AND status = 'proposed') THEN
      RAISE EXCEPTION 'meeting_reschedule_pending' USING ERRCODE='P0001';
    END IF;
    v_norm := hocalist.meeting_normalize_schedule(p_input);
    SELECT coalesce(max(sequence), 0) + 1 INTO v_seq
      FROM hocalist.meeting_schedule_revisions WHERE meeting_id = v_meeting.id;
    INSERT INTO hocalist.meeting_schedule_revisions(
      meeting_id, sequence, schedule_date, schedule_time, schedule_timezone,
      schedule_occurrence, schedule_offset_minutes, schedule_instant,
      place_choice, place_label, place_address, place_id, place_latitude, place_longitude, proposed_by_user_id)
    VALUES (
      v_meeting.id, v_seq,
      (v_norm->>'schedule_date')::date,
      (v_norm->>'schedule_time')::time,
      v_norm->>'schedule_timezone',
      v_norm->>'schedule_occurrence',
      (v_norm->>'schedule_offset_minutes')::integer,
      (v_norm->>'schedule_instant')::timestamptz,
      v_norm->>'place_choice',
      v_norm->>'place_label',
      v_norm->>'place_address',
      v_norm->>'place_id',
      (v_norm->>'place_latitude')::double precision,
      (v_norm->>'place_longitude')::double precision,
      v_user);
    UPDATE hocalist.meetings
      SET status = 'proposed', revision = revision + 1, updated_at = now()
      WHERE id = v_meeting.id;
    RETURN hocalist.meeting_receipt_store(
      v_user, 'meeting.propose', p_key, v_hash,
      hocalist.meeting_json(v_meeting.id));
  END IF;

  v_norm := hocalist.meeting_normalize_schedule(p_input);
  INSERT INTO hocalist.meetings(
    conversation_id, request_id, offer_id, buyer_user_id, seller_user_id)
  VALUES (
    p_conversation, v_offer.request_id, v_offer.id,
    v_offer.buyer_user_id, v_offer.seller_user_id)
  RETURNING id INTO v_meeting_id;

  INSERT INTO hocalist.meeting_schedule_revisions(
    meeting_id, sequence, schedule_date, schedule_time, schedule_timezone,
    schedule_occurrence, schedule_offset_minutes, schedule_instant,
    place_choice, place_label, place_address, place_id, place_latitude, place_longitude, proposed_by_user_id)
  VALUES (
    v_meeting_id, 1,
    (v_norm->>'schedule_date')::date,
    (v_norm->>'schedule_time')::time,
    v_norm->>'schedule_timezone',
    v_norm->>'schedule_occurrence',
    (v_norm->>'schedule_offset_minutes')::integer,
    (v_norm->>'schedule_instant')::timestamptz,
    v_norm->>'place_choice',
    v_norm->>'place_label',
    v_norm->>'place_address',
    v_norm->>'place_id',
      (v_norm->>'place_latitude')::double precision,
      (v_norm->>'place_longitude')::double precision,
    v_user);

  RETURN hocalist.meeting_receipt_store(
    v_user, 'meeting.propose', p_key, v_hash,
    hocalist.meeting_json(v_meeting_id));
END; $$;
CREATE OR REPLACE FUNCTION hocalist.chat_deals(p_conversation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.meeting_assert_conversation_member(p_conversation,auth.uid());
 RETURN jsonb_build_object('items',coalesce((SELECT jsonb_agg(hocalist.marketplace_offer_json(o.id) ORDER BY o.created_at,o.id)
   FROM hocalist.offers o WHERE o.conversation_id=p_conversation AND o.status='selected'),'[]'::jsonb),'next_cursor',null);
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_deals(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_deals(uuid) TO authenticated;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)') AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('24d389f71f1c65d3e1a58202e51bd33f') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Pair chat definition drift: chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)') AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('9c4923568a5e5de6e82440b3f797df44') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Pair chat definition drift: meeting_propose(uuid,jsonb,text)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=to_regprocedure('hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)') AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Pair chat helper grants drift'; END IF;
 IF to_regprocedure('hocalist.chat_deals(uuid)') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.chat_deals(uuid)') AND md5(replace(prosrc,E'\r\n',E'\n'))='f14da1d9a8721f0445a146fe5fe1b59b' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Pair chat read drift'; END IF;
 IF to_regprocedure('hocalist.chat_deals(uuid)') IS NULL OR NOT has_function_privilege('authenticated','hocalist.chat_deals(uuid)','EXECUTE') OR has_function_privilege('anon','hocalist.chat_deals(uuid)','EXECUTE') OR has_function_privilege('service_role','hocalist.chat_deals(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Pair chat read grants drift'; END IF;
END $guard$;
NOTIFY pgrst,'reload schema';
COMMIT;

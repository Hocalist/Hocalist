-- Accept the seller's stored offer terms without making the buyer propose them again.
-- Existing purchase selection, meeting response, expiry and notification rules remain authoritative.
BEGIN;
CREATE OR REPLACE FUNCTION hocalist.meeting_accept_offer(
  p_offer uuid, p_expected_offer_revision bigint,
  p_expected_meeting_revision bigint, p_key text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_offer hocalist.offers%ROWTYPE;
  v_terms hocalist.offer_revisions%ROWTYPE;
  v_meeting hocalist.meetings%ROWTYPE;
  v_pending hocalist.meeting_schedule_revisions%ROWTYPE;
  v_request hocalist.requests%ROWTYPE;
  v_hash text; v_replay jsonb; v_norm jsonb; v_result jsonb;
  v_meeting_id uuid; v_schedule_id uuid; v_inner_key text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_expected_offer_revision IS NULL OR p_expected_offer_revision < 1 THEN
    RAISE EXCEPTION 'invalid_field: p_key' USING ERRCODE='22023';
  END IF;
  PERFORM hocalist.marketplace_assert_role(v_user, 'buyer');
  SELECT * INTO v_offer FROM hocalist.offers WHERE id=p_offer AND buyer_user_id=v_user;
  IF NOT FOUND OR v_offer.seller_user_id=v_user THEN
    RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
  END IF;
  PERFORM hocalist.meeting_assert_conversation_member(v_offer.conversation_id,v_user);
  v_hash := encode(sha256(convert_to(jsonb_build_object('offer',p_offer,
    'offer_revision',p_expected_offer_revision,'meeting_revision',p_expected_meeting_revision)::text,'UTF8')),'hex');
  v_replay := hocalist.meeting_receipt_begin(v_user,'meeting.accept_offer',p_key,v_hash);
  IF v_replay IS NOT NULL THEN RETURN v_replay; END IF;
  -- Match the existing purchase-selection lock order.
  SELECT * INTO v_request FROM hocalist.requests WHERE id=v_offer.request_id FOR UPDATE;
  SELECT * INTO v_offer FROM hocalist.offers WHERE id=p_offer FOR UPDATE;
  IF v_offer.revision<>p_expected_offer_revision THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
  IF v_request.status<>'active' OR v_offer.status<>'selected' OR v_offer.accepted_revision_id IS NULL THEN
    RAISE EXCEPTION 'offer_not_selected' USING ERRCODE='P0001';
  END IF;
  PERFORM 1 FROM hocalist.conversations WHERE id=v_offer.conversation_id FOR UPDATE;
  SELECT * INTO v_meeting FROM hocalist.meetings WHERE offer_id=p_offer FOR UPDATE;
  IF FOUND THEN
    IF p_expected_meeting_revision IS NULL OR v_meeting.revision<>p_expected_meeting_revision THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    IF v_meeting.status='cancelled' THEN RAISE EXCEPTION 'meeting_cancelled' USING ERRCODE='P0001'; END IF;
    IF v_meeting.status='accepted' THEN
      RETURN hocalist.meeting_receipt_store(v_user,'meeting.accept_offer',p_key,v_hash,hocalist.meeting_json(v_meeting.id));
    END IF;
    SELECT * INTO v_pending FROM hocalist.meeting_schedule_revisions
      WHERE meeting_id=v_meeting.id AND status='proposed' ORDER BY sequence DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'meeting_not_open' USING ERRCODE='P0001'; END IF;
    IF v_pending.proposed_by_user_id<>v_offer.seller_user_id THEN
      RAISE EXCEPTION 'meeting_self_accept' USING ERRCODE='P0001';
    END IF;
    IF v_pending.schedule_instant<=now() THEN RAISE EXCEPTION 'meeting_time_passed' USING ERRCODE='P0001'; END IF;
  ELSE
    IF p_expected_meeting_revision IS NOT NULL THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    SELECT * INTO v_terms FROM hocalist.offer_revisions WHERE id=v_offer.accepted_revision_id AND offer_id=p_offer;
    IF NOT FOUND OR v_terms.proposed_by_user_id<>v_offer.seller_user_id THEN
      RAISE EXCEPTION 'offer_not_selected' USING ERRCODE='P0001';
    END IF;
    -- Never accept client-supplied time, location, price or participant data.
    v_norm := hocalist.meeting_normalize_schedule(to_jsonb(v_terms));
    IF (v_norm->>'schedule_instant')::timestamptz<=now() THEN
      RAISE EXCEPTION 'meeting_time_passed' USING ERRCODE='P0001';
    END IF;
  END IF;
  v_inner_key := 'accept-meeting-' || encode(sha256(convert_to(p_key,'UTF8')),'hex');
  PERFORM hocalist.marketplace_command('purchase.select',v_inner_key,
    jsonb_build_object('offer_id',p_offer,'expected_offer_revision',p_expected_offer_revision));
  IF v_meeting.id IS NOT NULL THEN
    v_result := hocalist.meeting_respond(v_meeting.id,true,v_meeting.revision,v_inner_key);
  ELSE
    INSERT INTO hocalist.meetings(conversation_id,request_id,offer_id,buyer_user_id,seller_user_id)
      VALUES(v_offer.conversation_id,v_offer.request_id,p_offer,v_user,v_offer.seller_user_id) RETURNING id INTO v_meeting_id;
    INSERT INTO hocalist.meeting_schedule_revisions(meeting_id,sequence,schedule_date,schedule_time,
      schedule_timezone,schedule_occurrence,schedule_offset_minutes,schedule_instant,
      place_choice,place_label,place_address,place_id,place_latitude,place_longitude,proposed_by_user_id,status,resolved_at)
    VALUES(v_meeting_id,1,(v_norm->>'schedule_date')::date,(v_norm->>'schedule_time')::time,
      v_norm->>'schedule_timezone',v_norm->>'schedule_occurrence',(v_norm->>'schedule_offset_minutes')::integer,
      (v_norm->>'schedule_instant')::timestamptz,v_norm->>'place_choice',v_norm->>'place_label',
      v_norm->>'place_address',v_norm->>'place_id',(v_norm->>'place_latitude')::double precision,
      (v_norm->>'place_longitude')::double precision,v_offer.seller_user_id,'accepted',now()) RETURNING id INTO v_schedule_id;
    UPDATE hocalist.meetings SET status='accepted',accepted_revision_id=v_schedule_id,
      meeting_expires_at=hocalist.marketplace_next_local_day_start((v_norm->>'schedule_date')::date,v_norm->>'schedule_timezone'),
      revision=revision+1,updated_at=now() WHERE id=v_meeting_id;
    v_result := hocalist.meeting_json(v_meeting_id);
  END IF;
  RETURN hocalist.meeting_receipt_store(v_user,'meeting.accept_offer',p_key,v_hash,v_result);
END; $$;
REVOKE ALL ON FUNCTION hocalist.meeting_accept_offer(uuid,bigint,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION hocalist.meeting_accept_offer(uuid,bigint,bigint,text) TO authenticated;
-- Preserve the installed reschedule function and all its checks; allow either
-- participant to counter the other's pending proposal through the same editor.
DO $patch$
DECLARE d text; changed text;
BEGIN
 d := pg_get_functiondef('hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)'::regprocedure);
 IF position('participant_counterproposal' IN d)=0 THEN
   IF position('seller_counterproposal' IN d)=0 THEN RAISE EXCEPTION 'Unexpected reschedule definition'; END IF;
   changed := regexp_replace(d,'v_user\s*=\s*v_row.seller_user_id\s+AND\s+EXISTS',
     'v_user IN (v_row.buyer_user_id,v_row.seller_user_id) AND EXISTS');
   IF changed=d THEN RAISE EXCEPTION 'Unexpected counterproposal guard'; END IF;
   d := regexp_replace(changed,'proposed_by_user_id\s*=\s*v_row.buyer_user_id','proposed_by_user_id<>v_user');
   IF d=changed THEN RAISE EXCEPTION 'Unexpected counterproposal author'; END IF;
   EXECUTE replace(d,'seller_counterproposal','participant_counterproposal');
 END IF;
END $patch$;
NOTIFY pgrst,'reload schema';
COMMIT;

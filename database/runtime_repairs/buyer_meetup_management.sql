BEGIN;

-- Preserve the existing meeting mutations and notifications. The wrapper
-- records the reason in the same transaction as the buyer's change.
CREATE OR REPLACE FUNCTION hocalist.meeting_buyer_manage(
  p_meeting uuid, p_expected_revision bigint, p_key text, p_action text,
  p_reason text, p_note text DEFAULT NULL, p_input jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  buyer uuid := auth.uid();
  seller uuid;
  reason_label text;
  note text := nullif(btrim(p_note), '');
  operation constant text := 'meeting.buyer_manage';
  request_hash text;
  inner_key text;
  outcome jsonb;
  event uuid;
BEGIN
  SELECT seller_user_id INTO seller
  FROM hocalist.meetings
  WHERE id = p_meeting AND buyer_user_id = buyer;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'meeting_access_denied' USING ERRCODE = '42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 OR
     p_action IS NULL OR p_action NOT IN ('reschedule', 'cancel') OR p_reason IS NULL OR
     (p_action = 'reschedule' AND jsonb_typeof(p_input) IS DISTINCT FROM 'object') OR
     (p_action = 'cancel' AND p_input IS NOT NULL) OR
     (note IS NOT NULL AND (p_reason <> 'other' OR length(note) > 180)) THEN
    RAISE EXCEPTION 'invalid_field: meetup_change' USING ERRCODE = '22023';
  END IF;
  reason_label := CASE
    WHEN p_reason = 'schedule_changed' THEN 'Schedule changed'
    WHEN p_reason = 'other' THEN 'Other'
    WHEN p_action = 'reschedule' AND p_reason = 'running_late' THEN 'Running late'
    WHEN p_action = 'reschedule' AND p_reason = 'transportation' THEN 'Transportation issue'
    WHEN p_action = 'cancel' AND p_reason = 'cant_get_there' THEN 'Cannot get there'
    WHEN p_action = 'cancel' AND p_reason = 'no_longer_needed' THEN 'No longer needed'
  END;
  IF reason_label IS NULL THEN
    RAISE EXCEPTION 'invalid_field: meetup_reason' USING ERRCODE = '22023';
  END IF;
  request_hash := encode(sha256(convert_to(jsonb_build_array(
    p_meeting, p_expected_revision, p_action, p_reason, note, p_input)::text, 'UTF8')), 'hex');
  outcome := hocalist.meeting_receipt_begin(buyer, operation, p_key, request_hash);
  IF outcome IS NOT NULL THEN RETURN outcome; END IF;

  inner_key := 'buyer-meetup-' || encode(sha256(convert_to(p_key, 'UTF8')), 'hex');
  IF p_action = 'reschedule' THEN
    outcome := hocalist.meeting_reschedule_propose(p_meeting, p_input, p_expected_revision, inner_key);
    event := md5('meeting:proposal:' || (outcome->'pending_schedule'->>'id'))::uuid;
  ELSE
    outcome := hocalist.meeting_cancel(p_meeting, p_expected_revision, inner_key);
    event := md5('meeting:status:' || p_meeting::text || ':' || (outcome->>'revision'))::uuid;
  END IF;

  UPDATE hocalist.notifications
  SET body = CASE WHEN p_action = 'cancel' THEN 'Meetup canceled. ' ELSE 'New meetup time proposed. ' END
      || 'Buyer reason: ' || reason_label || coalesce('. Note: ' || note, '.')
  WHERE user_id = seller AND event_key = event AND source_id = p_meeting;

  RETURN hocalist.meeting_receipt_store(buyer, operation, p_key, request_hash, outcome ||
    jsonb_build_object('buyer_change_reason', p_reason, 'buyer_change_note', note));
END;
$$;

REVOKE ALL ON FUNCTION hocalist.meeting_buyer_manage(uuid,bigint,text,text,text,text,jsonb)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION hocalist.meeting_buyer_manage(uuid,bigint,text,text,text,text,jsonb)
  TO authenticated;
NOTIFY pgrst, 'reload schema';

COMMIT;

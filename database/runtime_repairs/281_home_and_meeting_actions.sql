BEGIN;

CREATE TABLE IF NOT EXISTS hocalist.meeting_cancellation_reasons (
  meeting_id uuid PRIMARY KEY REFERENCES hocalist.meetings(id),
  actor uuid NOT NULL,
  operation_key text NOT NULL,
  reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.meeting_cancellation_reasons ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.meeting_cancellation_reasons FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION hocalist.meeting_cancel(
  p_meeting uuid, p_expected_revision bigint, p_key text, p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE result jsonb;
BEGIN
  IF p_reason IS NULL OR p_reason NOT IN (
    'I can''t make the destination','I can''t make the time requested',
    'Buyer keeps changing proposal','Unforeseen circumstances'
  ) THEN RAISE EXCEPTION 'invalid cancellation reason' USING ERRCODE='22023'; END IF;
  result := hocalist.meeting_cancel(p_meeting,p_expected_revision,p_key);
  INSERT INTO hocalist.meeting_cancellation_reasons(meeting_id,actor,operation_key,reason)
    VALUES (p_meeting,auth.uid(),p_key,p_reason) ON CONFLICT DO NOTHING;
  IF NOT EXISTS (SELECT 1 FROM hocalist.meeting_cancellation_reasons
    WHERE meeting_id=p_meeting AND actor=auth.uid() AND operation_key=p_key AND reason=p_reason)
    THEN RAISE EXCEPTION 'cancellation conflict' USING ERRCODE='22023'; END IF;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION hocalist.meeting_cancel(uuid,bigint,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION hocalist.meeting_cancel(uuid,bigint,text,text) TO authenticated;

-- Preserve the installed participant, eligibility, and audit predicates.
DO $patch$
DECLARE d text;
BEGIN
  -- Use the same activity timestamp for display order and the paging cursor.
  d := pg_get_functiondef('hocalist.marketplace_my_requests(text,integer,text)'::regprocedure);
  IF position('home_activity_at' IN d)=0 THEN
    IF position('hocalist.marketplace_request_json(r.id) AS row_json' IN d)=0 OR
       position('ORDER BY r.created_at DESC' IN d)=0 THEN RAISE EXCEPTION 'Unexpected buyer Home query'; END IF;
    d := replace(d,'r.created_at','greatest(r.created_at,(SELECT max(o.created_at) FROM hocalist.offers o WHERE o.request_id=r.id))');
    EXECUTE replace(d,'hocalist.marketplace_request_json(r.id) AS row_json',
      $new$(hocalist.marketplace_request_json(r.id) || jsonb_build_object('home_activity_at',
        greatest(r.created_at,(SELECT max(o.created_at) FROM hocalist.offers o WHERE o.request_id=r.id)))) AS row_json$new$);
  END IF;

  d := pg_get_functiondef('hocalist.marketplace_offer_json(uuid)'::regprocedure);
  IF position('request_minimum_minor' IN d)=0 THEN
    IF position('''request_id'', o.request_id' IN d)=0 THEN RAISE EXCEPTION 'Unexpected offer projection'; END IF;
    EXECUTE replace(d,'''request_id'', o.request_id','''request_id'', o.request_id, ''request_minimum_minor'', q.budget_min_minor');
  END IF;

  -- A seller can counter a buyer's pending time. Locking and replay checks in
  -- the existing procedure also cover replacement of the pending revision.
  d := pg_get_functiondef('hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)'::regprocedure);
  IF position('seller_counterproposal' IN d)=0 THEN
    IF position('IF v_row.status NOT IN (''accepted'',''reschedule_proposed'') THEN' IN d)=0 OR
       position('SET status = ''reschedule_proposed'',' IN d)=0 THEN
      RAISE EXCEPTION 'Unexpected reschedule definition';
    END IF;
    d := replace(d,'IF v_row.status NOT IN (''accepted'',''reschedule_proposed'') THEN',
      $new$-- seller_counterproposal
      IF v_user = v_row.seller_user_id AND EXISTS (
        SELECT 1 FROM hocalist.meeting_schedule_revisions
        WHERE meeting_id=p_meeting AND status='proposed' AND proposed_by_user_id=v_row.buyer_user_id
      ) THEN
        UPDATE hocalist.meeting_schedule_revisions SET status='superseded', resolved_at=now()
        WHERE meeting_id=p_meeting AND status='proposed';
      ELSIF v_row.status NOT IN ('accepted','reschedule_proposed') THEN$new$);
    EXECUTE replace(d,'SET status = ''reschedule_proposed'',',
      'SET status = CASE WHEN v_row.accepted_revision_id IS NULL THEN ''proposed'' ELSE ''reschedule_proposed'' END,');
  END IF;

  d := pg_get_functiondef('hocalist.chat_deals(uuid)'::regprocedure);
  IF position('request_status' IN d)=0 THEN
    IF position('hocalist.marketplace_offer_json(o.id)' IN d)=0 THEN RAISE EXCEPTION 'Unexpected chat deal projection'; END IF;
    EXECUTE replace(d,'hocalist.marketplace_offer_json(o.id)',
      $new$(hocalist.marketplace_offer_json(o.id) || jsonb_build_object('request_status',
        (SELECT r.status FROM hocalist.requests r WHERE r.id=o.request_id)))$new$);
  END IF;

  d := pg_get_functiondef('hocalist.marketplace_recommended_leads(integer)'::regprocedure);
  IF position('recommendations_require_paid_plan' IN d)=0 THEN
    IF position('WHERE r0.status' IN d)=0 OR
       position('PERFORM hocalist.marketplace_assert_role(v_user, ''seller'');' IN d)=0
       THEN RAISE EXCEPTION 'Unexpected recommendation query'; END IF;
    IF position('v_declared := hocalist.discovery_declared_category_ids(v_user);' IN d)=0 THEN
      RAISE EXCEPTION 'Unexpected recommendation categories';
    END IF;
    d := replace(d,'v_declared := hocalist.discovery_declared_category_ids(v_user);',
      $new$SELECT coalesce(array_agg(pc.category_id), ARRAY[]::uuid[]) INTO v_declared
        FROM hocalist.role_profile_categories pc
        JOIN hocalist.memberships m ON m.id=pc.membership_id
        WHERE m.user_id=v_user AND m.role='seller' AND m.status='active';$new$);
    d := replace(d,'WHERE r0.status','WHERE r0.category_id = ANY(v_declared) AND r0.status');
    EXECUTE replace(d,'PERFORM hocalist.marketplace_assert_role(v_user, ''seller'');',
      $new$PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
      IF coalesce(hocalist.marketplace_seller_plan(v_user)::text,'free') NOT IN ('pro','elite') THEN
        RAISE EXCEPTION 'recommendations_require_paid_plan' USING ERRCODE='42501';
      END IF;$new$);
  END IF;

  d := pg_get_functiondef('hocalist.admin_audit_feed(integer,text,text,uuid,text)'::regprocedure);
  IF position('meeting_cancellation_reasons' IN d)=0 THEN
    IF position('FROM hocalist.withdrawal_events e' IN d)=0 THEN RAISE EXCEPTION 'Unexpected audit feed'; END IF;
    d := replace(d,'''calls'',''withdrawals''','''calls'',''withdrawals'',''meetings''');
    EXECUTE replace(d,'FROM hocalist.withdrawal_events e',
      $new$FROM hocalist.withdrawal_events e
      UNION ALL SELECT md5('meeting.cancel:' || c.meeting_id::text),c.created_at,'meetings',
      'meeting.cancel',c.actor::text,c.meeting_id::text,c.reason,null FROM hocalist.meeting_cancellation_reasons c$new$);
  END IF;
END $patch$;
COMMIT;

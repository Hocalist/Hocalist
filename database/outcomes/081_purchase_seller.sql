-- Additive migration over reviewed 080: the buyer designates one final purchase
-- seller, only that seller can complete the PIN, a confirmed purchase closes
-- every other negotiation for the request, and the winning credit/reward
-- settlement runs through the optional commercial hooks.
--
-- Prerequisites: meetings 040 + outcomes 080 + marketplace 023 already applied.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.sale_confirmations') IS NULL THEN
    RAISE EXCEPTION 'sale confirmation 080 prerequisite missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist' AND table_name='requests' AND column_name='purchase_offer_id'
  ) THEN
    RAISE EXCEPTION 'marketplace multi-negotiation 023 prerequisite missing';
  END IF;
END; $guard$;

CREATE OR REPLACE FUNCTION hocalist.sale_pin(p_meeting uuid,p_action text,p_pin text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); m hocalist.meetings%ROWTYPE;
 s hocalist.request_pin_secrets%ROWTYPE; outcome hocalist.sale_confirmations%ROWTYPE;
 v_purchase uuid;
BEGIN
 m:=hocalist.meeting_assert_participant(p_meeting,u);
 IF p_action NOT IN ('display','verify','status') OR p_action IS NULL THEN
  RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023';
 END IF;
 IF (p_action='display' AND u<>m.buyer_user_id) OR (p_action='verify' AND u<>m.seller_user_id) THEN
  RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501';
 END IF;
 -- Match marketplace lock order; serialize all sellers for the request.
 PERFORM 1 FROM hocalist.requests WHERE id=m.request_id FOR UPDATE;
 PERFORM 1 FROM hocalist.meetings WHERE id=p_meeting FOR UPDATE;
 m:=hocalist.meeting_assert_participant(p_meeting,u);
 SELECT * INTO outcome FROM hocalist.sale_confirmations WHERE request_id=m.request_id;
 IF FOUND THEN
  IF outcome.meeting_id<>p_meeting THEN RETURN jsonb_build_object('status','completed_elsewhere'); END IF;
  RETURN jsonb_build_object('status','confirmed','outcome_id',outcome.id,'confirmed_at',outcome.confirmed_at);
 END IF;
 IF p_action='status' THEN RETURN jsonb_build_object('status','unconfirmed'); END IF;
 IF m.status<>'accepted' OR m.accepted_revision_id IS NULL THEN
  RETURN jsonb_build_object('status','meeting_not_accepted');
 END IF;
 IF m.meeting_expires_at IS NULL OR now()>=m.meeting_expires_at THEN
  RETURN jsonb_build_object('status','expired');
 END IF;
 IF p_action='display' THEN
  INSERT INTO hocalist.request_pin_secrets(request_id,meeting_id,schedule_revision_id)
   VALUES(m.request_id,m.id,m.accepted_revision_id)
   ON CONFLICT(request_id) DO UPDATE SET meeting_id=excluded.meeting_id,
    schedule_revision_id=excluded.schedule_revision_id,secret=gen_random_uuid()
   WHERE request_pin_secrets.meeting_id<>excluded.meeting_id
      OR request_pin_secrets.schedule_revision_id<>excluded.schedule_revision_id;
  SELECT * INTO s FROM hocalist.request_pin_secrets WHERE request_id=m.request_id;
  RETURN jsonb_build_object('status','ready','pin',hocalist.sale_pin_digits(s.secret),'expires_at',m.meeting_expires_at);
 END IF;
 -- Only the seller the buyer designated as the final purchase may complete the
 -- transaction. A different accepted negotiation cannot claim the sale.
 SELECT purchase_offer_id INTO v_purchase FROM hocalist.requests WHERE id=m.request_id;
 IF v_purchase IS NULL OR v_purchase<>m.offer_id THEN
  RETURN jsonb_build_object('status','purchase_seller_required');
 END IF;
 SELECT * INTO s FROM hocalist.request_pin_secrets WHERE request_id=m.request_id FOR UPDATE;
 IF NOT FOUND OR s.meeting_id<>m.id OR s.schedule_revision_id<>m.accepted_revision_id THEN
  RETURN jsonb_build_object('status','buyer_must_open_pin');
 END IF;
 IF s.attempts>=30 THEN RETURN jsonb_build_object('status','support_required'); END IF;
 IF s.locked_until>now() THEN RETURN jsonb_build_object('status','locked','retry_at',s.locked_until); END IF;
 IF p_pin IS NULL OR p_pin!~'^[0-9]{5}$' THEN RETURN jsonb_build_object('status','invalid_format'); END IF;
 IF s.locked_until IS NOT NULL THEN s.window_attempts:=0; END IF;
 IF p_pin<>hocalist.sale_pin_digits(s.secret) THEN
  UPDATE hocalist.request_pin_secrets SET attempts=attempts+1,
   window_attempts=s.window_attempts+1,
   locked_until=CASE WHEN s.window_attempts+1>=5 THEN now()+interval '15 minutes' ELSE NULL END
   WHERE request_id=m.request_id;
  -- A returned failure, not an exception: failed attempts must COMMIT.
  RETURN jsonb_build_object('status',CASE WHEN s.window_attempts+1>=5 THEN 'locked' ELSE 'incorrect' END);
 END IF;
 INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id)
  VALUES(m.request_id,m.id,m.offer_id,m.accepted_revision_id,m.buyer_user_id,m.seller_user_id) RETURNING * INTO outcome;
 -- One purchase per request: the winning negotiation completes, every other
 -- negotiation for this request closes with its conversation history intact.
 UPDATE hocalist.offers SET status='completed',revision=revision+1,updated_at=now()
  WHERE id=m.offer_id;
 UPDATE hocalist.offers SET status='declined',revision=revision+1,updated_at=now()
  WHERE request_id=m.request_id AND id<>m.offer_id AND status IN ('submitted','selected');
 UPDATE hocalist.meetings SET status='cancelled',revision=revision+1,updated_at=now()
  WHERE request_id=m.request_id AND id<>m.id AND status<>'cancelled';
 UPDATE hocalist.requests SET status='closed',revision=revision+1,updated_at=now() WHERE id=m.request_id;
 DELETE FROM hocalist.request_pin_secrets WHERE request_id=m.request_id;
 -- Winning fee difference and unused-reserve release. The helper is optional so
 -- the local foundation remains testable before the commercial module applies.
 IF to_regprocedure('hocalist.credit_settle_purchase(uuid)') IS NOT NULL THEN
  PERFORM hocalist.credit_settle_purchase(m.request_id);
 END IF;
 RETURN jsonb_build_object('status','confirmed','outcome_id',outcome.id,'confirmed_at',outcome.confirmed_at);
END $$;

REVOKE ALL ON FUNCTION hocalist.sale_pin(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.sale_pin(uuid,text,text) TO authenticated;

-- The meeting projection carries the buyer's final-purchase designation so
-- both sides can see who can complete the PIN.
CREATE OR REPLACE FUNCTION hocalist.meeting_json(p_meeting uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', m.id,
    'conversation_id', m.conversation_id,
    'request_id', m.request_id,
    'offer_id', m.offer_id,
    'buyer_user_id', m.buyer_user_id,
    'seller_user_id', m.seller_user_id,
    'status', m.status,
    'accepted_revision_id', m.accepted_revision_id,
    'meeting_expires_at', m.meeting_expires_at,
    'purchase_selected', q.purchase_offer_id = m.offer_id,
    'purchase_selected_at', q.purchase_selected_at,
    'revision', m.revision,
    'created_at', m.created_at,
    'updated_at', m.updated_at,
    -- Authorized summary tied to the offer revision the buyer accepted at
    -- selection time. It never substitutes a newer offer revision and stays
    -- null when the offer has no accepted revision.
    'offer_summary', (
      SELECT jsonb_build_object(
        'title', r.title,
        'price_minor', ar.price_minor,
        'currency_code', ar.currency_code,
        'revision_id', ar.id)
      FROM hocalist.offers o
      JOIN hocalist.offer_revisions ar ON ar.id = o.accepted_revision_id
      JOIN hocalist.requests r ON r.id = o.request_id
      WHERE o.id = m.offer_id
    ),
    'accepted_schedule', (
      SELECT hocalist.meeting_revision_json(r)
      FROM hocalist.meeting_schedule_revisions r
      WHERE r.id = m.accepted_revision_id
    ),
    'pending_schedule', (
      SELECT hocalist.meeting_revision_json(r)
      FROM hocalist.meeting_schedule_revisions r
      WHERE r.meeting_id = m.id AND r.status = 'proposed'
      ORDER BY r.sequence DESC LIMIT 1
    ),
    'revisions', coalesce((
      SELECT jsonb_agg(hocalist.meeting_revision_json(r) ORDER BY r.sequence)
      FROM hocalist.meeting_schedule_revisions r WHERE r.meeting_id = m.id
    ), '[]'::jsonb)
  )
  FROM hocalist.meetings m
  JOIN hocalist.requests q ON q.id = m.request_id
  WHERE m.id = p_meeting;
$$;
REVOKE ALL ON FUNCTION hocalist.meeting_json(uuid) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

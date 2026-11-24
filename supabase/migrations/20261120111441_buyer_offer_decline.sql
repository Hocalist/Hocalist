-- Buyer decline ends a negotiation, not the request or another seller's deal.
-- Existing fee settlement, meeting cancellation and notification helpers remain
-- authoritative. No new fee or automatic purchase confirmation is introduced.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE OR REPLACE FUNCTION hocalist.buyer_decline_offer(
  p_offer uuid, p_expected_revision bigint, p_key text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  o hocalist.offers%ROWTYPE;
  q hocalist.requests%ROWTYPE;
  m hocalist.meetings%ROWTYPE;
  payload jsonb;
  fingerprint text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  result jsonb;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  PERFORM hocalist.marketplace_assert_role(u,'buyer');
  IF EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  IF p_offer IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
    OR p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid_command' USING ERRCODE='22023';
  END IF;
  payload := jsonb_build_object('offer_id',p_offer,'expected_offer_revision',p_expected_revision);
  fingerprint := encode(sha256(convert_to(payload::text,'UTF8')),'hex');
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text || ':offer.decline:' || p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id=u AND operation='offer.decline' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>fingerprint THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT * INTO o FROM hocalist.offers WHERE id=p_offer AND buyer_user_id=u;
  IF NOT FOUND THEN RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501'; END IF;
  -- Same request -> offer lock order as offer selection.
  SELECT * INTO q FROM hocalist.requests WHERE id=o.request_id FOR UPDATE;
  SELECT * INTO o FROM hocalist.offers WHERE id=p_offer FOR UPDATE;
  IF o.status<>'declined' THEN
    IF o.status NOT IN ('submitted','selected') THEN RAISE EXCEPTION 'offer_not_open' USING ERRCODE='P0001'; END IF;
    IF o.revision<>p_expected_revision THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    IF EXISTS (SELECT 1 FROM hocalist.sale_confirmations WHERE request_id=q.id) THEN
      RAISE EXCEPTION 'sale_already_confirmed' USING ERRCODE='P0001';
    END IF;
    -- Confirmed meetings use the existing cancellation journey and reason.
    -- Lock before checking so a simultaneous acceptance cannot be overwritten.
    FOR m IN SELECT * FROM hocalist.meetings WHERE offer_id=o.id ORDER BY id FOR UPDATE LOOP
      IF m.status IN ('accepted','reschedule_proposed') THEN
        RAISE EXCEPTION 'meeting_details_required' USING ERRCODE='P0001';
      END IF;
      IF m.status='proposed' THEN
        PERFORM hocalist.meeting_cancel(m.id,m.revision,'decline-' || md5(p_key || m.id::text));
        INSERT INTO hocalist.meeting_cancellation_reasons(meeting_id,actor,operation_key,reason)
          VALUES(m.id,u,p_key,'Buyer declined offer') ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;
    UPDATE hocalist.offer_revisions SET status='rejected' WHERE offer_id=o.id AND status='proposed';
    UPDATE hocalist.requests SET purchase_offer_id=NULL,purchase_selected_at=NULL,updated_at=now()
      WHERE id=q.id AND purchase_offer_id=o.id;
    UPDATE hocalist.offers SET status='declined',revision=revision+1,updated_at=now() WHERE id=o.id;
    PERFORM hocalist.credit_release_offer(o.id);
    IF to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NOT NULL THEN
      IF hocalist.notification_recipient_allowed(o.seller_user_id) THEN
      PERFORM hocalist.notification_emit(o.seller_user_id,md5('offer:declined:' || o.id::text)::uuid,
        'new_offer',o.id,'Your offer was declined','The buyer declined this offer. Any conversation remains in Past deals.',
        'hocalist://offers/' || o.id::text,jsonb_build_object('event','offer_declined','offer_id',o.id,'request_id',q.id));
      END IF;
    END IF;
  END IF;
  result := hocalist.marketplace_offer_json(o.id);
  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'offer.decline',p_key,fingerprint,result);
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION hocalist.buyer_decline_offer(uuid,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.buyer_decline_offer(uuid,bigint,text) TO authenticated;
COMMIT;

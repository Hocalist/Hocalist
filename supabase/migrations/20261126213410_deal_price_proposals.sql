BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- Use the existing immutable terms history. A proposed price points at the
-- same deal and copies every non-price field from the latest accepted terms.
CREATE FUNCTION hocalist.chat_deal_price(
  p_offer uuid, p_expected_revision bigint, p_key text,
  p_price_minor bigint DEFAULT NULL, p_proposal uuid DEFAULT NULL,
  p_accept boolean DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  actor uuid := auth.uid();
  operation text := CASE WHEN p_proposal IS NULL THEN 'chat.price.propose' ELSE 'chat.price.respond' END;
  offer hocalist.offers%ROWTYPE;
  terms hocalist.offer_revisions%ROWTYPE;
  pending hocalist.offer_revisions%ROWTYPE;
  request_status text;
  input_hash text;
  replay jsonb;
BEGIN
  IF actor IS NULL OR p_offer IS NULL THEN
    RAISE EXCEPTION 'offer_access_denied' USING ERRCODE = '42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
    OR p_expected_revision IS NULL OR p_expected_revision < 1
    OR (p_proposal IS NULL AND (p_accept IS NOT NULL OR p_price_minor IS NULL
                              OR p_price_minor NOT BETWEEN 1 AND 999999999999999))
    OR (p_proposal IS NOT NULL AND (p_accept IS NULL OR p_price_minor IS NOT NULL)) THEN
    RAISE EXCEPTION 'invalid_price_proposal' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO offer FROM hocalist.offers WHERE id = p_offer
    AND actor IN (buyer_user_id, seller_user_id) AND conversation_id IS NOT NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'offer_access_denied' USING ERRCODE = '42501'; END IF;
  PERFORM hocalist.marketplace_assert_role(
    actor, CASE WHEN actor = offer.buyer_user_id THEN 'buyer' ELSE 'seller' END);
  PERFORM hocalist.meeting_assert_conversation_member(offer.conversation_id, actor);
  IF EXISTS (SELECT 1 FROM hocalist.conversation_blocks AS block
    WHERE block.conversation_id = offer.conversation_id AND block.revoked_at IS NULL
      AND actor IN (block.blocker_user_id, block.blocked_user_id)) THEN
    RAISE EXCEPTION 'conversation_blocked' USING ERRCODE = '42501';
  END IF;

  input_hash := encode(sha256(convert_to(jsonb_build_array(
    p_offer, p_expected_revision, p_price_minor, p_proposal, p_accept)::text, 'UTF8')), 'hex');
  replay := hocalist.meeting_receipt_begin(actor, operation, p_key, input_hash);
  IF replay IS NOT NULL THEN RETURN replay; END IF;

  -- Match the purchase flow's lock order and serialize proposal/response
  -- with purchase confirmation, closing a request and cancelling a meetup.
  SELECT status INTO request_status FROM hocalist.requests WHERE id = offer.request_id FOR UPDATE;
  SELECT * INTO offer FROM hocalist.offers WHERE id = p_offer FOR UPDATE;
  PERFORM 1 FROM hocalist.meetings WHERE offer_id = p_offer FOR UPDATE;
  IF offer.revision <> p_expected_revision THEN
    RAISE EXCEPTION 'revision_conflict' USING ERRCODE = 'P0001';
  END IF;
  IF request_status = 'closed' OR offer.status <> 'selected' OR offer.accepted_revision_id IS NULL
    OR EXISTS (SELECT 1 FROM hocalist.meetings WHERE offer_id = p_offer AND status = 'cancelled') THEN
    RAISE EXCEPTION 'price_deal_closed' USING ERRCODE = 'P0001';
  END IF;
  SELECT * INTO STRICT terms FROM hocalist.offer_revisions
    WHERE id = offer.accepted_revision_id AND offer_id = offer.id;
  SELECT * INTO pending FROM hocalist.offer_revisions
    WHERE offer_id = offer.id AND status = 'proposed' ORDER BY sequence DESC LIMIT 1;

  IF p_proposal IS NULL THEN
    IF pending.id IS NOT NULL THEN
      RAISE EXCEPTION 'price_proposal_pending' USING ERRCODE = 'P0001';
    END IF;
    IF p_price_minor = terms.price_minor THEN
      RAISE EXCEPTION 'invalid_price_proposal' USING ERRCODE = '22023';
    END IF;
    terms.id := gen_random_uuid();
    SELECT max(sequence) + 1 INTO terms.sequence FROM hocalist.offer_revisions WHERE offer_id = offer.id;
    terms.price_minor := p_price_minor;
    terms.proposed_by_user_id := actor;
    terms.status := 'proposed';
    terms.created_at := now();
    INSERT INTO hocalist.offer_revisions SELECT (terms).*;
  ELSE
    IF pending.id IS DISTINCT FROM p_proposal THEN
      RAISE EXCEPTION 'price_proposal_resolved' USING ERRCODE = 'P0001';
    END IF;
    IF pending.proposed_by_user_id = actor THEN
      RAISE EXCEPTION 'offer_access_denied' USING ERRCODE = '42501';
    END IF;
    IF p_accept THEN
      UPDATE hocalist.offer_revisions SET status = 'superseded' WHERE id = terms.id;
    END IF;
    UPDATE hocalist.offer_revisions SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END
      WHERE id = pending.id;
  END IF;

  UPDATE hocalist.offers SET revision = revision + 1, updated_at = now(),
    accepted_revision_id = CASE WHEN p_accept IS TRUE THEN pending.id ELSE accepted_revision_id END
    WHERE id = p_offer;
  RETURN hocalist.meeting_receipt_store(
    actor, operation, p_key, input_hash, hocalist.marketplace_offer_json(p_offer));
END;
$$;

REVOKE ALL ON FUNCTION hocalist.chat_deal_price(uuid, bigint, text, bigint, uuid, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_deal_price(uuid, bigint, text, bigint, uuid, boolean)
  TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

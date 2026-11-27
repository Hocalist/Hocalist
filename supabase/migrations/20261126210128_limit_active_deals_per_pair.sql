BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE INDEX offers_selected_pair_idx ON hocalist.offers (buyer_user_id, seller_user_id)
  WHERE status = 'selected';
CREATE INDEX meetings_cancelled_offer_idx ON hocalist.meetings (offer_id)
  WHERE status = 'cancelled';

CREATE FUNCTION hocalist.assert_active_deal_slot(
  p_buyer uuid, p_seller uuid, p_offer uuid
) RETURNS void LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  -- Different requests can be accepted at the same time. Lock the pair before
  -- counting so the second transaction sees the first one's committed deal.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('hocalist.active_deals:' || p_buyer::text || ':' || p_seller::text, 0)
  );
  IF EXISTS (
    SELECT 1
    FROM hocalist.offers AS offer
    JOIN hocalist.requests AS request ON request.id = offer.request_id
    WHERE offer.buyer_user_id = p_buyer
      AND offer.seller_user_id = p_seller
      AND offer.status = 'selected'
      AND offer.id <> p_offer
      AND request.status <> 'closed'
      AND NOT EXISTS (
        SELECT 1 FROM hocalist.meetings AS meeting
        WHERE meeting.offer_id = offer.id AND meeting.status = 'cancelled'
      )
    OFFSET 2 LIMIT 1
  ) THEN
    RAISE EXCEPTION 'active_deal_pair_limit' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

CREATE FUNCTION hocalist.check_new_active_deal()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status = 'selected' THEN
    RETURN NEW;
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.requests WHERE id = NEW.request_id AND status <> 'closed') THEN
    PERFORM hocalist.assert_active_deal_slot(NEW.buyer_user_id, NEW.seller_user_id, NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION hocalist.check_reopened_deals()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
  deal record;
BEGIN
  -- A closed request can retain accepted offers. Reopening it must reserve
  -- any slots it would restore. Acquire pair locks in a consistent order.
  FOR deal IN
    SELECT offer.id, offer.buyer_user_id, offer.seller_user_id
    FROM hocalist.offers AS offer
    WHERE offer.request_id = NEW.id AND offer.status = 'selected'
      AND NOT EXISTS (
        SELECT 1 FROM hocalist.meetings AS meeting
        WHERE meeting.offer_id = offer.id AND meeting.status = 'cancelled'
      )
    ORDER BY offer.buyer_user_id, offer.seller_user_id
  LOOP
    PERFORM hocalist.assert_active_deal_slot(deal.buyer_user_id, deal.seller_user_id, deal.id);
  END LOOP;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION hocalist.assert_active_deal_slot(uuid, uuid, uuid),
  hocalist.check_new_active_deal(), hocalist.check_reopened_deals()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER offers_check_pair_deal_limit
  BEFORE INSERT OR UPDATE OF status ON hocalist.offers FOR EACH ROW
  WHEN (NEW.status = 'selected') EXECUTE FUNCTION hocalist.check_new_active_deal();

CREATE TRIGGER requests_check_reopened_deal_limit
  BEFORE UPDATE OF status ON hocalist.requests FOR EACH ROW
  WHEN (OLD.status = 'closed' AND NEW.status <> 'closed')
  EXECUTE FUNCTION hocalist.check_reopened_deals();

COMMIT;

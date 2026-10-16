-- Additive Store and Hocatrends enquiry opener with origin isolation.
--
-- Buyers may open a discovery conversation from a published Store listing or
-- from a verified Hocatrends topic. The server resolves the counterpart,
-- verifies that the subject is publicly visible and that the seller currently
-- has a matching active membership, and only then delegates to the reviewed
-- `chat_open_internal` boundary. No targeting fee or buyer reward applies to
-- these origins, and no generic participant list can be supplied by a client.
--
-- Prerequisites: chat/010 (chat_open_internal), marketplace/020, and
-- discovery_completion/140 for the seller-profile helper.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regprocedure('hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)') IS NULL
     OR to_regclass('hocalist.store_listings') IS NULL
     OR to_regclass('hocalist.catalogue_categories') IS NULL THEN
    RAISE EXCEPTION 'chat 010 / marketplace 020 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.discovery_open_enquiry(text,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'discovery enquiry opener already installed';
  END IF;
END; $guard$;

CREATE FUNCTION hocalist.discovery_open_enquiry(p_key text, p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  v_buyer_profile uuid;
  v_origin text;
  v_listing hocalist.store_listings%ROWTYPE;
  v_topic uuid;
  v_seller_user uuid;
  v_seller_profile uuid;
  v_subject uuid;
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  v_conversation uuid;
  v_participants jsonb;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  SELECT id INTO v_buyer_profile FROM hocalist.memberships
    WHERE user_id = u AND role = 'buyer' AND status = 'active' LIMIT 1;
  IF v_buyer_profile IS NULL THEN
    RAISE EXCEPTION 'buyer_membership_required' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_enquiry' USING ERRCODE='22023';
  END IF;
  v_origin := p_input->>'origin';
  IF v_origin = 'store_listing' THEN
    IF p_input - ARRAY['origin','listing_id'] <> '{}'::jsonb
       OR p_input->>'listing_id' IS NULL
       OR (p_input->>'listing_id') !~ '^[0-9a-fA-F-]{36}$' THEN
      RAISE EXCEPTION 'invalid_enquiry' USING ERRCODE='22023';
    END IF;
    SELECT * INTO v_listing FROM hocalist.store_listings
      WHERE id = (p_input->>'listing_id')::uuid
        AND status = 'active' AND moderation_status = 'approved';
    IF NOT FOUND THEN RAISE EXCEPTION 'listing_not_found' USING ERRCODE='P0002'; END IF;
    v_seller_user := v_listing.seller_user_id;
    v_seller_profile := v_listing.seller_profile_id;
    v_subject := v_listing.id;
  ELSIF v_origin = 'hocatrends_enquiry' THEN
    IF p_input - ARRAY['origin','topic_id','seller_profile_id'] <> '{}'::jsonb
       OR p_input->>'topic_id' IS NULL
       OR p_input->>'seller_profile_id' IS NULL
       OR (p_input->>'topic_id') !~ '^[0-9a-fA-F-]{36}$'
       OR (p_input->>'seller_profile_id') !~ '^[0-9a-fA-F-]{36}$' THEN
      RAISE EXCEPTION 'invalid_enquiry' USING ERRCODE='22023';
    END IF;
    v_topic := (p_input->>'topic_id')::uuid;
    IF NOT EXISTS (SELECT 1 FROM hocalist.catalogue_categories
                   WHERE id = v_topic AND status = 'active') THEN
      RAISE EXCEPTION 'topic_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT m.user_id INTO v_seller_user FROM hocalist.memberships m
      WHERE m.id = (p_input->>'seller_profile_id')::uuid
        AND m.role = 'seller';
    IF NOT FOUND THEN RAISE EXCEPTION 'seller_not_found' USING ERRCODE='P0002'; END IF;
    IF EXISTS (SELECT 1 FROM hocalist.memberships m
               WHERE m.user_id = v_seller_user
                 AND m.status IN ('restricted','disabled')) THEN
      RAISE EXCEPTION 'seller_not_eligible' USING ERRCODE='P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM hocalist.memberships m
                   WHERE m.user_id = v_seller_user AND m.status = 'active') THEN
      RAISE EXCEPTION 'seller_not_eligible' USING ERRCODE='P0001';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM hocalist.store_listings l
      WHERE l.seller_user_id = v_seller_user
        AND l.seller_profile_id = (p_input->>'seller_profile_id')::uuid
        AND l.category_id = v_topic
        AND l.status = 'active' AND l.moderation_status = 'approved'
    ) THEN
      RAISE EXCEPTION 'seller_not_eligible' USING ERRCODE='P0001';
    END IF;
    v_seller_profile := (p_input->>'seller_profile_id')::uuid;
    v_subject := v_topic;
  ELSE
    RAISE EXCEPTION 'invalid_origin' USING ERRCODE='22023';
  END IF;
  IF v_seller_user = u THEN
    RAISE EXCEPTION 'enquiry_self' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = v_seller_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'seller_not_eligible' USING ERRCODE='P0001';
  END IF;

  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':discovery_enquiry:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id = u AND operation = 'discovery.open_enquiry' AND idempotency_key = p_key;
  IF FOUND THEN
    IF receipt.request_hash <> h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;

  v_participants := jsonb_build_array(
    jsonb_build_object('user_id', u, 'profile_id', v_buyer_profile, 'role', 'buyer'),
    jsonb_build_object('user_id', v_seller_user, 'profile_id', v_seller_profile, 'role', 'seller'));
  v_conversation := hocalist.chat_open_internal(
    v_origin,
    NULL,
    NULL,
    CASE WHEN v_origin = 'store_listing' THEN v_listing.id ELSE NULL END,
    CASE WHEN v_origin = 'hocatrends_enquiry' THEN v_topic ELSE NULL END,
    v_participants);
  INSERT INTO hocalist.marketplace_receipts(user_id, operation, idempotency_key, request_hash, result)
  VALUES (u, 'discovery.open_enquiry', p_key, h, jsonb_build_object(
    'conversation_id', v_conversation,
    'origin', v_origin,
    'subject_id', v_subject));
  RETURN jsonb_build_object(
    'conversation_id', v_conversation,
    'origin', v_origin,
    'subject_id', v_subject);
END $$;

REVOKE ALL ON FUNCTION hocalist.discovery_open_enquiry(text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.discovery_open_enquiry(text,jsonb) TO authenticated;
COMMIT;

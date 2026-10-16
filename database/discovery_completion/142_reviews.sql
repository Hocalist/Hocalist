-- Additive post-purchase review contract.
--
-- Eligibility comes only from a confirmed purchase (`sale_confirmations`): the
-- buyer of that outcome may create exactly one authoritative review per
-- request. Submission is idempotent; a replay with the same intent key and
-- payload returns the stored review, a changed payload on the same key is a
-- conflict, and a second review for the same outcome is refused. Moderation is
-- a recorded server decision with a reason; the public aggregate exposes only
-- published reviews and never a buyer identity beyond the consented label
-- helper.
--
-- Prerequisites: marketplace/020 + meetings/040 + outcomes/080 (sale
-- confirmations). Review submissions and reads stay behind
-- `kDiscoveryCompletionEnabled` in the app until this package is deployed.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.sale_confirmations') IS NULL
     OR to_regclass('hocalist.marketplace_receipts') IS NULL
     OR to_regprocedure('hocalist.marketplace_assert_role(uuid,text)') IS NULL
     OR to_regprocedure('hocalist.discovery_assert_active_member(uuid)') IS NULL THEN
    RAISE EXCEPTION 'outcomes 080 / marketplace 020 / discovery 140 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.outcome_reviews') IS NOT NULL THEN
    RAISE EXCEPTION 'reviews already installed';
  END IF;
END; $guard$;

CREATE TABLE hocalist.outcome_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE REFERENCES hocalist.requests(id),
  meeting_id uuid NOT NULL REFERENCES hocalist.meetings(id),
  offer_id uuid NOT NULL REFERENCES hocalist.offers(id),
  buyer_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  seller_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  seller_profile_id uuid NOT NULL REFERENCES hocalist.memberships(id),
  rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body text NOT NULL DEFAULT '' CHECK (length(body) <= 1500),
  status text NOT NULL DEFAULT 'published'
    CHECK (status IN ('published','hidden','removed')),
  moderation_reason text
    CHECK (moderation_reason IS NULL OR length(btrim(moderation_reason)) BETWEEN 1 AND 500),
  moderated_by uuid REFERENCES hocalist.profiles(id),
  moderated_at timestamptz,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT review_moderation_shape CHECK (
    (moderated_by IS NULL AND moderated_at IS NULL)
    OR (moderated_by IS NOT NULL AND moderation_reason IS NOT NULL)
  )
);
CREATE INDEX outcome_reviews_seller_public
  ON hocalist.outcome_reviews(seller_profile_id, created_at DESC, id DESC)
  WHERE status = 'published';
ALTER TABLE hocalist.outcome_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.outcome_reviews FROM PUBLIC, anon, authenticated, service_role;

-- Reviewer label is masked unless a separately reviewed public-profile
-- consent table exists and the buyer explicitly opted in. This wrapper keeps
-- the reviews package independently applicable before 143 ships.
CREATE FUNCTION hocalist.review_reviewer_label(p_user uuid)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_label text;
BEGIN
  IF to_regclass('hocalist.buyer_public_profile_consent') IS NOT NULL THEN
    EXECUTE
      'SELECT CASE WHEN c.is_public AND c.show_display_name
              THEN coalesce(nullif(btrim(rp.display_name), ''''), ''Hocalist buyer'')
              ELSE ''Hocalist buyer'' END
         FROM hocalist.buyer_public_profile_consent c
         LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = (
           SELECT m.id FROM hocalist.memberships m
           WHERE m.user_id = c.user_id AND m.role = ''buyer''
           ORDER BY m.created_at, m.id LIMIT 1)
        WHERE c.user_id = $1'
      INTO v_label USING p_user;
  END IF;
  RETURN coalesce(v_label, 'Hocalist buyer');
END $$;

CREATE FUNCTION hocalist.review_json(p_review uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', v.id,
    'request_id', v.request_id,
    'rating', v.rating,
    'body', v.body,
    'status', v.status,
    'revision', v.revision,
    'created_at', v.created_at,
    'updated_at', v.updated_at,
    'moderation_reason', CASE WHEN v.status = 'published' THEN NULL ELSE v.moderation_reason END)
  FROM hocalist.outcome_reviews v WHERE v.id = p_review;
$$;

-- Buyer eligibility and their authoritative review, if any.
CREATE FUNCTION hocalist.review_status(p_request uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  o hocalist.sale_confirmations%ROWTYPE;
  v hocalist.outcome_reviews%ROWTYPE;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u, 'buyer');
  IF p_request IS NULL THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023'; END IF;
  SELECT * INTO o FROM hocalist.sale_confirmations WHERE request_id = p_request;
  IF NOT FOUND OR o.buyer_user_id <> u THEN
    RETURN jsonb_build_object(
      'eligible', false,
      'reason', CASE WHEN NOT FOUND THEN 'not_confirmed' ELSE 'not_participant' END,
      'request_id', p_request,
      'review', NULL);
  END IF;
  SELECT * INTO v FROM hocalist.outcome_reviews WHERE request_id = p_request;
  RETURN jsonb_build_object(
    'eligible', true,
    'reason', 'confirmed_purchase',
    'request_id', p_request,
    'outcome_id', o.id,
    'review', CASE WHEN FOUND THEN hocalist.review_json(v.id) ELSE NULL END);
END $$;

-- One authoritative review per confirmed purchase. Idempotent by intent key.
CREATE FUNCTION hocalist.review_submit(p_key text, p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  o hocalist.sale_confirmations%ROWTYPE;
  existing hocalist.outcome_reviews%ROWTYPE;
  v hocalist.outcome_reviews%ROWTYPE;
  v_rating integer;
  v_body text;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u, 'buyer');
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
     OR p_input - ARRAY['request_id','rating','body'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'rating') <> 'number'
     OR (p_input->>'rating') !~ '^[1-5]$'
     OR jsonb_typeof(p_input->'body') IS DISTINCT FROM 'string'
     OR length(coalesce(p_input->>'body','')) > 1500 THEN
    RAISE EXCEPTION 'invalid_review' USING ERRCODE='22023';
  END IF;
  v_rating := (p_input->>'rating')::integer;
  v_body := btrim(coalesce(p_input->>'body',''));
  -- Authorization precedes the receipt so a restricted account can never
  -- replay a stored acknowledgement.
  SELECT * INTO o FROM hocalist.sale_confirmations
    WHERE request_id = (p_input->>'request_id')::uuid;
  IF NOT FOUND THEN RAISE EXCEPTION 'review_not_eligible' USING ERRCODE='P0001'; END IF;
  IF o.buyer_user_id <> u THEN RAISE EXCEPTION 'review_not_eligible' USING ERRCODE='42501'; END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':review:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id = u AND operation = 'review.submit' AND idempotency_key = p_key;
  IF FOUND THEN
    IF receipt.request_hash <> h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT * INTO o FROM hocalist.sale_confirmations
    WHERE request_id = (p_input->>'request_id')::uuid FOR UPDATE;
  IF NOT FOUND OR o.buyer_user_id <> u THEN
    RAISE EXCEPTION 'review_not_eligible' USING ERRCODE='42501';
  END IF;
  SELECT * INTO existing FROM hocalist.outcome_reviews WHERE request_id = o.request_id;
  IF FOUND THEN
    -- A retry with the same content is a replay; changed content is refused so
    -- one outcome never accumulates two authoritative reviews.
    IF existing.rating = v_rating AND existing.body = v_body THEN
      INSERT INTO hocalist.marketplace_receipts(user_id, operation, idempotency_key, request_hash, result)
      VALUES (u, 'review.submit', p_key, h, hocalist.review_json(existing.id));
      RETURN hocalist.review_json(existing.id);
    END IF;
    RAISE EXCEPTION 'review_exists' USING ERRCODE='P0001';
  END IF;
  INSERT INTO hocalist.outcome_reviews(
    request_id, meeting_id, offer_id, buyer_user_id, seller_user_id, seller_profile_id, rating, body)
  VALUES (o.request_id, o.meeting_id, o.offer_id, o.buyer_user_id, o.seller_user_id,
          (SELECT m.id FROM hocalist.memberships m
           WHERE m.user_id = o.seller_user_id AND m.role = 'seller' LIMIT 1),
          v_rating, v_body)
  RETURNING * INTO v;
  INSERT INTO hocalist.marketplace_receipts(user_id, operation, idempotency_key, request_hash, result)
  VALUES (u, 'review.submit', p_key, h, hocalist.review_json(v.id));
  RETURN hocalist.review_json(v.id);
END $$;

-- Buyer edit of their own authoritative review at an expected revision.
CREATE FUNCTION hocalist.review_update(p_key text, p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  v hocalist.outcome_reviews%ROWTYPE;
  v_rating integer;
  v_body text;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u, 'buyer');
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
     OR p_input - ARRAY['review_id','expected_revision','rating','body'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'rating') <> 'number'
     OR (p_input->>'rating') !~ '^[1-5]$'
     OR jsonb_typeof(p_input->'body') IS DISTINCT FROM 'string'
     OR length(coalesce(p_input->>'body','')) > 1500
     OR jsonb_typeof(p_input->'expected_revision') <> 'number' THEN
    RAISE EXCEPTION 'invalid_review' USING ERRCODE='22023';
  END IF;
  v_rating := (p_input->>'rating')::integer;
  v_body := btrim(coalesce(p_input->>'body',''));
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':review_update:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id = u AND operation = 'review.update' AND idempotency_key = p_key;
  IF FOUND THEN
    IF receipt.request_hash <> h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  UPDATE hocalist.outcome_reviews SET rating = v_rating, body = v_body,
    revision = revision + 1, updated_at = now()
  WHERE id = (p_input->>'review_id')::uuid AND buyer_user_id = u
    AND status <> 'removed'
    AND revision = (p_input->>'expected_revision')::bigint
  RETURNING * INTO v;
  IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
  INSERT INTO hocalist.marketplace_receipts(user_id, operation, idempotency_key, request_hash, result)
  VALUES (u, 'review.update', p_key, h, hocalist.review_json(v.id));
  RETURN hocalist.review_json(v.id);
END $$;

-- Recorded moderation decision. Admin-only; no automatic penalty is implied.
CREATE FUNCTION hocalist.review_moderate(p_key text, p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  v hocalist.outcome_reviews%ROWTYPE;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
     OR p_input - ARRAY['review_id','expected_revision','status','reason'] <> '{}'::jsonb
     OR p_input->>'status' NOT IN ('published','hidden','removed')
     OR jsonb_typeof(p_input->'reason') IS DISTINCT FROM 'string'
     OR length(btrim(p_input->>'reason')) NOT BETWEEN 1 AND 500
     OR jsonb_typeof(p_input->'expected_revision') <> 'number' THEN
    RAISE EXCEPTION 'invalid_moderation' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':review_moderate:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id = u AND operation = 'review.moderate' AND idempotency_key = p_key;
  IF FOUND THEN
    IF receipt.request_hash <> h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  UPDATE hocalist.outcome_reviews SET status = p_input->>'status',
    moderation_reason = btrim(p_input->>'reason'),
    moderated_by = u, moderated_at = now(),
    revision = revision + 1, updated_at = now()
  WHERE id = (p_input->>'review_id')::uuid
    AND revision = (p_input->>'expected_revision')::bigint
  RETURNING * INTO v;
  IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
  INSERT INTO hocalist.marketplace_receipts(user_id, operation, idempotency_key, request_hash, result)
  VALUES (u, 'review.moderate', p_key, h, hocalist.review_json(v.id));
  RETURN hocalist.review_json(v.id);
END $$;

-- Public seller reputation. Only published reviews and verified purchase
-- counts are aggregated; no buyer auth identity, contacts or exact address is
-- exposed. Reviewer labels stay masked until the buyer opts in through the
-- separately reviewed consent contract. A restricted or disabled target is
-- not publicly promotable, so its projection is withheld.
CREATE FUNCTION hocalist.seller_public_reputation(p_seller_profile uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  v_user uuid;
  v_sum integer;
  v_count integer;
BEGIN
  PERFORM hocalist.discovery_assert_active_member(u);
  IF p_seller_profile IS NULL THEN RAISE EXCEPTION 'invalid_profile' USING ERRCODE='22023'; END IF;
  SELECT m.user_id INTO v_user FROM hocalist.memberships m
    WHERE m.id = p_seller_profile AND m.role = 'seller';
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'seller_profile_id', p_seller_profile,
      'available', false,
      'reason', 'profile_not_found',
      'rating_sum', 0, 'rating_count', 0, 'completed_deals', 0,
      'reviews', '[]'::jsonb);
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships m2
             WHERE m2.user_id = v_user AND m2.status IN ('restricted','disabled')) THEN
    RETURN jsonb_build_object(
      'seller_profile_id', p_seller_profile,
      'available', false,
      'reason', 'target_unavailable',
      'rating_sum', 0, 'rating_count', 0, 'completed_deals', 0,
      'reviews', '[]'::jsonb);
  END IF;
  SELECT coalesce(sum(r.rating), 0)::integer, count(*)::integer
    INTO v_sum, v_count
    FROM hocalist.outcome_reviews r
    WHERE r.seller_profile_id = p_seller_profile AND r.status = 'published';
  RETURN jsonb_build_object(
    'seller_profile_id', p_seller_profile,
    'available', true,
    'reason', NULL,
    'rating_sum', v_sum,
    'rating_count', v_count,
    'completed_deals', (
      SELECT count(*)::integer FROM hocalist.sale_confirmations s
      WHERE s.seller_user_id = v_user),
    'reviews', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', r.id, 'rating', r.rating, 'body', r.body,
        'created_at', r.created_at,
        'reviewer_label', hocalist.review_reviewer_label(r.buyer_user_id))
        ORDER BY r.created_at DESC, r.id DESC)
      FROM (SELECT * FROM hocalist.outcome_reviews
            WHERE seller_profile_id = p_seller_profile AND status = 'published'
            ORDER BY created_at DESC, id DESC LIMIT 5) r), '[]'::jsonb));
END $$;

REVOKE ALL ON FUNCTION hocalist.review_reviewer_label(uuid), hocalist.review_json(uuid),
  hocalist.review_status(uuid), hocalist.review_submit(text,jsonb),
  hocalist.review_update(text,jsonb), hocalist.review_moderate(text,jsonb),
  hocalist.seller_public_reputation(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.review_status(uuid), hocalist.review_submit(text,jsonb),
  hocalist.review_update(text,jsonb), hocalist.seller_public_reputation(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.review_moderate(text,jsonb) TO authenticated;
COMMIT;

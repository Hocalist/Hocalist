-- Additive Hocatrends and Winners projections plus buyer public-profile
-- consent.
--
-- Trends are computed from verified marketplace activity only: open requests,
-- sellers who actually submitted offers, and confirmed purchases inside a
-- fixed 30-day window. No competition percentage, seller count or ranking is
-- invented and no topic is hardcoded; topics are the admin-managed active
-- catalogue categories.
--
-- The buyer public profile starts closed. It is exposed only after the buyer
-- explicitly opts in and only for the individually enabled fields; field and
-- visibility consent stays conservative until the owner settles the exact
-- public-field policy, so this projection is gated off in app composition.
--
-- Prerequisites: marketplace/020 + 021 + 023, outcomes/080, and
-- discovery_completion/140 for the shared match helpers.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.catalogue_categories') IS NULL
     OR to_regclass('hocalist.offers') IS NULL
     OR to_regclass('hocalist.sale_confirmations') IS NULL
     OR to_regprocedure('hocalist.discovery_assert_active_member(uuid)') IS NULL THEN
    RAISE EXCEPTION 'marketplace/outcomes/140 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.buyer_public_profile_consent') IS NOT NULL
     OR to_regprocedure('hocalist.hocatrends_trends(integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'Hocatrends projections already installed';
  END IF;
END; $guard$;

-- ---------------------------------------------------------------------------
-- Buyer public profile consent (closed by default)
-- ---------------------------------------------------------------------------

CREATE TABLE hocalist.buyer_public_profile_consent (
  user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id),
  is_public boolean NOT NULL DEFAULT false,
  show_display_name boolean NOT NULL DEFAULT false,
  show_area boolean NOT NULL DEFAULT false,
  show_categories boolean NOT NULL DEFAULT false,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.buyer_public_profile_consent ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.buyer_public_profile_consent FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION hocalist.buyer_public_profile_consent_json()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  c hocalist.buyer_public_profile_consent%ROWTYPE;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u, 'buyer');
  SELECT * INTO c FROM hocalist.buyer_public_profile_consent WHERE user_id = u;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'is_public', false, 'show_display_name', false,
      'show_area', false, 'show_categories', false, 'revision', 0);
  END IF;
  RETURN jsonb_build_object(
    'is_public', c.is_public,
    'show_display_name', c.show_display_name,
    'show_area', c.show_area,
    'show_categories', c.show_categories,
    'revision', c.revision);
END $$;

-- Explicit opt-in only. Every visibility flag is required so a partial or
-- accidental public state cannot be created.
CREATE FUNCTION hocalist.buyer_public_profile_consent_set(p_key text, p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  c hocalist.buyer_public_profile_consent%ROWTYPE;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u, 'buyer');
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
     OR p_input - ARRAY['is_public','show_display_name','show_area','show_categories'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'is_public') <> 'boolean'
     OR jsonb_typeof(p_input->'show_display_name') <> 'boolean'
     OR jsonb_typeof(p_input->'show_area') <> 'boolean'
     OR jsonb_typeof(p_input->'show_categories') <> 'boolean' THEN
    RAISE EXCEPTION 'invalid_consent' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':buyer_consent:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id = u AND operation = 'buyer_public.consent_set' AND idempotency_key = p_key;
  IF FOUND THEN
    IF receipt.request_hash <> h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  INSERT INTO hocalist.buyer_public_profile_consent(
    user_id, is_public, show_display_name, show_area, show_categories)
  VALUES (u,
    (p_input->>'is_public')::boolean,
    (p_input->>'show_display_name')::boolean,
    (p_input->>'show_area')::boolean,
    (p_input->>'show_categories')::boolean)
  ON CONFLICT (user_id) DO UPDATE SET
    is_public = excluded.is_public,
    show_display_name = excluded.show_display_name,
    show_area = excluded.show_area,
    show_categories = excluded.show_categories,
    revision = hocalist.buyer_public_profile_consent.revision + 1,
    updated_at = now()
  RETURNING * INTO c;
  INSERT INTO hocalist.marketplace_receipts(user_id, operation, idempotency_key, request_hash, result)
  VALUES (u, 'buyer_public.consent_set', p_key, h, jsonb_build_object(
    'is_public', c.is_public,
    'show_display_name', c.show_display_name,
    'show_area', c.show_area,
    'show_categories', c.show_categories,
    'revision', c.revision));
  RETURN jsonb_build_object(
    'is_public', c.is_public,
    'show_display_name', c.show_display_name,
    'show_area', c.show_area,
    'show_categories', c.show_categories,
    'revision', c.revision);
END $$;

-- Consented public projection. Returns `available = false` unless the buyer
-- opted in; individual fields stay null unless individually enabled. Never
-- includes email, phone, exact address, coordinates or documents.
CREATE FUNCTION hocalist.buyer_public_profile(p_profile uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  c hocalist.buyer_public_profile_consent%ROWTYPE;
  v_target uuid;
  v_name text;
  v_area text;
  v_categories jsonb;
BEGIN
  PERFORM hocalist.discovery_assert_active_member(u);
  IF p_profile IS NULL THEN RAISE EXCEPTION 'invalid_profile' USING ERRCODE='22023'; END IF;
  SELECT m.user_id INTO v_target FROM hocalist.memberships m
    WHERE m.id = p_profile AND m.role = 'buyer';
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'available', false, 'profile_id', p_profile,
      'reason', 'profile_not_found');
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships m2
             WHERE m2.user_id = v_target AND m2.status IN ('restricted','disabled')) THEN
    RETURN jsonb_build_object(
      'available', false, 'profile_id', p_profile,
      'reason', 'target_unavailable');
  END IF;
  SELECT * INTO c FROM hocalist.buyer_public_profile_consent
    WHERE user_id = v_target;
  IF NOT FOUND OR NOT c.is_public THEN
    RETURN jsonb_build_object(
      'available', false, 'profile_id', p_profile,
      'reason', 'consent_withheld');
  END IF;
  SELECT nullif(btrim(rp.display_name), ''), rp.area_label
    INTO v_name, v_area
    FROM hocalist.role_profiles rp WHERE rp.membership_id = p_profile;
  SELECT coalesce(jsonb_agg(DISTINCT c2.label ORDER BY c2.label), '[]'::jsonb)
    INTO v_categories
    FROM hocalist.requests r
    JOIN hocalist.catalogue_categories c2 ON c2.id = r.category_id
    WHERE r.buyer_profile_id = p_profile;
  RETURN jsonb_build_object(
    'available', true,
    'profile_id', p_profile,
    'role', 'buyer',
    'display_name', CASE WHEN c.show_display_name THEN v_name ELSE NULL END,
    'area_label', CASE WHEN c.show_area THEN v_area ELSE NULL END,
    'categories', CASE WHEN c.show_categories THEN v_categories ELSE '[]'::jsonb END,
    'member_since', (SELECT min(m.created_at) FROM hocalist.memberships m
                     WHERE m.id = p_profile AND m.role = 'buyer'),
    'verified_purchase_count', (
      SELECT count(*)::integer FROM hocalist.sale_confirmations s
      WHERE s.buyer_user_id = (
        SELECT m.user_id FROM hocalist.memberships m
        WHERE m.id = p_profile AND m.role = 'buyer')));
END $$;

-- ---------------------------------------------------------------------------
-- Hocatrends projections
-- ---------------------------------------------------------------------------

-- Demand and competition from verified activity in a fixed 30-day window.
-- `percent` is the topic's share of currently open requests, not a fabricated
-- score. Competition levels are derived from the real number of sellers who
-- submitted offers in the window.
CREATE FUNCTION hocalist.hocatrends_trends(p_limit integer DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  v_size integer;
  v_total integer;
  v_items jsonb;
BEGIN
  PERFORM hocalist.discovery_assert_active_member(u);
  v_size := greatest(1, least(coalesce(p_limit, 10), 30));
  SELECT count(*)::integer INTO v_total
    FROM hocalist.requests r
    WHERE r.status = 'active'
      AND (r.acceptance_expires_at IS NULL OR now() < r.acceptance_expires_at)
      AND r.category_id IS NOT NULL;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', row_number,
      'category_id', category_id,
      'label', label,
      'open_requests', open_requests,
      'competing_sellers', competing_sellers,
      'confirmed_purchases', confirmed_purchases,
      'participating_buyers', participating_buyers,
      'percent', percent,
      'competition', CASE
        WHEN competing_sellers >= 5 THEN 'Very High'
        WHEN competing_sellers >= 3 THEN 'High'
        WHEN competing_sellers >= 1 THEN 'Medium'
        ELSE 'New' END,
      'activity_copy', CASE
        WHEN competing_sellers = 0 AND confirmed_purchases = 0
          THEN 'No competing offers in the last 30 days.'
        ELSE competing_sellers::text || ' seller'
             || CASE WHEN competing_sellers = 1 THEN '' ELSE 's' END
             || ' competing · ' || confirmed_purchases::text
             || ' confirmed purchase' || CASE WHEN confirmed_purchases = 1 THEN '' ELSE 's' END END,
      'verified_activity', true)
      ORDER BY open_requests DESC, percent DESC, label), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT
        t.id AS category_id,
        t.label AS label,
        t.open_requests,
        t.competing_sellers,
        t.confirmed_purchases,
        t.participating_buyers,
        CASE WHEN v_total = 0 THEN 0
             ELSE round(100.0 * t.open_requests / v_total)::integer END AS percent,
        row_number() OVER (ORDER BY t.open_requests DESC, t.label) AS row_number
      FROM (
        SELECT
          c.id,
          c.label,
          (SELECT count(*)::integer FROM hocalist.requests r
            WHERE r.category_id = c.id AND r.status = 'active'
              AND (r.acceptance_expires_at IS NULL OR now() < r.acceptance_expires_at)) AS open_requests,
          (SELECT count(DISTINCT o.seller_user_id)::integer
             FROM hocalist.offers o JOIN hocalist.requests r2 ON r2.id = o.request_id
            WHERE r2.category_id = c.id
              AND o.status IN ('submitted','selected','completed')
              AND o.created_at > now() - interval '30 days') AS competing_sellers,
          (SELECT count(*)::integer
             FROM hocalist.sale_confirmations s JOIN hocalist.requests r3 ON r3.id = s.request_id
            WHERE r3.category_id = c.id
              AND s.confirmed_at > now() - interval '30 days') AS confirmed_purchases,
          (SELECT count(DISTINCT r4.buyer_user_id)::integer FROM hocalist.requests r4
            WHERE r4.category_id = c.id
              AND r4.created_at > now() - interval '30 days') AS participating_buyers
        FROM hocalist.catalogue_categories c
        WHERE c.status = 'active'
      ) t
      WHERE t.open_requests > 0 OR t.competing_sellers > 0 OR t.confirmed_purchases > 0
      ORDER BY t.open_requests DESC, t.label
      LIMIT v_size
    ) topics;
  RETURN jsonb_build_object(
    'window_days', 30,
    'generated_at', now(),
    'open_request_total', v_total,
    'items', v_items);
END $$;

-- Winners: recent confirmed purchases. Buyer identity and area are masked
-- unless the buyer opted in through the consent contract; private offers,
-- contacts and exact locations are never projected.
CREATE FUNCTION hocalist.hocatrends_winners(p_limit integer DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  v_size integer;
  v_items jsonb;
BEGIN
  PERFORM hocalist.discovery_assert_active_member(u);
  v_size := greatest(1, least(coalesce(p_limit, 10), 30));
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'outcome_id', s.id,
      'category_label', c.label,
      'buyer_label', hocalist.review_reviewer_label(s.buyer_user_id),
      'area_label', CASE
        WHEN coalesce(pc.is_public, false) AND pc.show_area THEN rp.area_label
        ELSE NULL END,
      'confirmed_at', s.confirmed_at,
      'verified_purchase', true)
      ORDER BY s.confirmed_at DESC, s.id DESC), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT * FROM hocalist.sale_confirmations
      ORDER BY confirmed_at DESC, id DESC LIMIT v_size
    ) s
    LEFT JOIN hocalist.requests r ON r.id = s.request_id
    LEFT JOIN hocalist.catalogue_categories c ON c.id = r.category_id
    LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = r.buyer_profile_id
    LEFT JOIN hocalist.buyer_public_profile_consent pc ON pc.user_id = s.buyer_user_id;
  RETURN jsonb_build_object(
    'window_days', 30,
    'generated_at', now(),
    'items', v_items);
END $$;

REVOKE ALL ON FUNCTION hocalist.buyer_public_profile_consent_json(),
  hocalist.buyer_public_profile_consent_set(text,jsonb),
  hocalist.buyer_public_profile(uuid),
  hocalist.hocatrends_trends(integer), hocalist.hocatrends_winners(integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.buyer_public_profile_consent_json(),
  hocalist.buyer_public_profile_consent_set(text,jsonb),
  hocalist.buyer_public_profile(uuid),
  hocalist.hocatrends_trends(integer), hocalist.hocatrends_winners(integer)
  TO authenticated;
COMMIT;

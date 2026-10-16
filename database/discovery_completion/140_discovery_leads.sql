-- Additive seller discovery reads over the reviewed marketplace foundation.
--
-- Scope: server-authorized filters and sorts, real cursor pagination, radius
-- discovery with approximate location only, and explainable matching inputs.
-- The seller lead projection never carries the buyer's exact address,
-- coordinates, contacts or another seller's offers.
--
-- Named prerequisites (applied in this order before this package):
--   marketplace/020 foundation, 021 request coordinates, 023 multi-negotiation
--   (discovery closes at the first-acceptance window). 023 is required because
--   the approved rule closes discovery at acceptance expiry while accepted
--   meetings survive; this file reads `acceptance_expires_at` directly.
--
-- Location policy: the seller's own declared discovery origin (approximate
-- area label plus optional coordinates and a service radius) is stored on the
-- seller's account. Distance is computed only when both the request and the
-- seller origin carry coordinates; otherwise the manual area-label fallback is
-- used and no distance is fabricated. US locations are preferred in ordering
-- without excluding other countries.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.requests') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regprocedure('hocalist.marketplace_assert_role(uuid,text)') IS NULL
     OR to_regclass('hocalist.marketplace_receipts') IS NULL THEN
    RAISE EXCEPTION 'marketplace 020 prerequisite missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist' AND table_name='requests' AND column_name='acceptance_expires_at'
  ) THEN
    RAISE EXCEPTION 'marketplace multi-negotiation 023 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.seller_discovery_origins') IS NOT NULL
     OR to_regprocedure('hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'discovery leads already installed';
  END IF;
END; $guard$;

-- ---------------------------------------------------------------------------
-- Seller discovery origin (owner-scoped, approximate)
-- ---------------------------------------------------------------------------

CREATE TABLE hocalist.seller_discovery_origins (
  seller_user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id),
  seller_profile_id uuid NOT NULL REFERENCES hocalist.memberships(id),
  area_label text CHECK (area_label IS NULL OR length(btrim(area_label)) BETWEEN 1 AND 150),
  latitude double precision,
  longitude double precision,
  radius_miles integer NOT NULL DEFAULT 25 CHECK (radius_miles BETWEEN 1 AND 500),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT discovery_origin_coordinates_pair CHECK (
    (latitude IS NULL AND longitude IS NULL)
    OR (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)
  )
);
ALTER TABLE hocalist.seller_discovery_origins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.seller_discovery_origins FROM PUBLIC, anon, authenticated, service_role;

-- Great-circle distance in statute miles. Immutable and side-effect free.
CREATE FUNCTION hocalist.discovery_distance_miles(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) RETURNS double precision
LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT 3958.7613 * 2 * asin(least(1.0, sqrt(
    power(sin(radians(p_lat2 - p_lat1) / 2), 2) +
    cos(radians(p_lat1)) * cos(radians(p_lat2)) *
      power(sin(radians(p_lng2 - p_lng1) / 2), 2)
  )));
$$;
REVOKE ALL ON FUNCTION hocalist.discovery_distance_miles(double precision,double precision,double precision,double precision)
  FROM PUBLIC, anon, authenticated, service_role;

-- Declared matching inputs for one seller: active and approved Store listing
-- category ids. Declared categories are server reads; the client never sends
-- its own matching terms.
CREATE FUNCTION hocalist.discovery_declared_category_ids(p_seller uuid)
RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(array_agg(DISTINCT l.category_id), ARRAY[]::uuid[])
  FROM hocalist.store_listings l
  WHERE l.seller_user_id = p_seller
    AND l.status = 'active'
    AND l.moderation_status = 'approved'
    AND l.category_id IS NOT NULL;
$$;

-- Shared authorization for the signed-in reads in this package: the caller
-- must be authenticated, must not hold any restricted/disabled membership and
-- must hold at least one active membership. Role-specific RPCs use
-- marketplace_assert_role instead; this helper is for both-role projections.
CREATE FUNCTION hocalist.discovery_assert_active_member(p_user uuid)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = p_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.memberships
                 WHERE user_id = p_user AND status = 'active') THEN
    RAISE EXCEPTION 'active_membership_required' USING ERRCODE='42501';
  END IF;
END $$;

CREATE FUNCTION hocalist.discovery_origin_json()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  o hocalist.seller_discovery_origins%ROWTYPE;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u, 'seller');
  SELECT * INTO o FROM hocalist.seller_discovery_origins WHERE seller_user_id = u;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('configured', false);
  END IF;
  RETURN jsonb_build_object(
    'configured', true,
    'area_label', o.area_label,
    'coordinates_present', o.latitude IS NOT NULL,
    'radius_miles', o.radius_miles,
    'revision', o.revision);
END $$;

-- Sets or replaces the signed-in seller's discovery origin. Coordinates are
-- optional and only ever their own; the client cannot set another seller's
-- origin because the identity comes from auth.uid().
CREATE FUNCTION hocalist.discovery_origin_set(p_key text, p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  m uuid;
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  v_area text;
  v_lat double precision;
  v_lng double precision;
  v_radius integer;
  v_revision bigint;
BEGIN
  m := hocalist.marketplace_assert_role(u, 'seller');
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
     OR p_input - ARRAY['area_label','latitude','longitude','radius_miles'] <> '{}'::jsonb THEN
    RAISE EXCEPTION 'invalid_origin' USING ERRCODE='22023';
  END IF;
  v_area := nullif(btrim(coalesce(p_input->>'area_label','')), '');
  IF v_area IS NOT NULL AND length(v_area) > 150 THEN
    RAISE EXCEPTION 'invalid_field: area_label' USING ERRCODE='22023';
  END IF;
  IF (p_input->>'latitude' IS NULL) <> (p_input->>'longitude' IS NULL) THEN
    RAISE EXCEPTION 'invalid_field: coordinates' USING ERRCODE='22023';
  END IF;
  IF p_input->>'latitude' IS NOT NULL THEN
    IF jsonb_typeof(p_input->'latitude') <> 'number'
       OR jsonb_typeof(p_input->'longitude') <> 'number' THEN
      RAISE EXCEPTION 'invalid_field: coordinates' USING ERRCODE='22023';
    END IF;
    v_lat := (p_input->>'latitude')::double precision;
    v_lng := (p_input->>'longitude')::double precision;
    IF v_lat NOT BETWEEN -90 AND 90 OR v_lng NOT BETWEEN -180 AND 180 THEN
      RAISE EXCEPTION 'invalid_field: coordinates' USING ERRCODE='22023';
    END IF;
  END IF;
  v_radius := 25;
  IF p_input ? 'radius_miles' AND jsonb_typeof(p_input->'radius_miles') <> 'null' THEN
    IF jsonb_typeof(p_input->'radius_miles') <> 'number'
       OR (p_input->>'radius_miles') !~ '^[0-9]{1,3}$' THEN
      RAISE EXCEPTION 'invalid_field: radius_miles' USING ERRCODE='22023';
    END IF;
    v_radius := (p_input->>'radius_miles')::integer;
    IF v_radius NOT BETWEEN 1 AND 500 THEN
      RAISE EXCEPTION 'invalid_field: radius_miles' USING ERRCODE='22023';
    END IF;
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':discovery_origin:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id = u AND operation = 'discovery.origin_set' AND idempotency_key = p_key;
  IF FOUND THEN
    IF receipt.request_hash <> h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  INSERT INTO hocalist.seller_discovery_origins(
    seller_user_id, seller_profile_id, area_label, latitude, longitude, radius_miles)
  VALUES (u, m, v_area, v_lat, v_lng, v_radius)
  ON CONFLICT (seller_user_id) DO UPDATE SET
    seller_profile_id = excluded.seller_profile_id,
    area_label = excluded.area_label,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    radius_miles = excluded.radius_miles,
    revision = hocalist.seller_discovery_origins.revision + 1,
    updated_at = now()
  RETURNING revision INTO v_revision;
  INSERT INTO hocalist.marketplace_receipts(user_id, operation, idempotency_key, request_hash, result)
  VALUES (u, 'discovery.origin_set', p_key, h, jsonb_build_object(
    'configured', true,
    'area_label', v_area,
    'coordinates_present', v_lat IS NOT NULL,
    'radius_miles', v_radius,
    'revision', v_revision));
  RETURN jsonb_build_object(
    'configured', true, 'area_label', v_area,
    'coordinates_present', v_lat IS NOT NULL,
    'radius_miles', v_radius, 'revision', v_revision);
END $$;

-- ---------------------------------------------------------------------------
-- Seller-safe lead projection with match and approximate distance
-- ---------------------------------------------------------------------------

-- Builds one seller-visible request projection. Distinct from
-- marketplace_lead_json so this package stays readable even when later
-- migrations change the buyer/owner serializer. It never selects latitude,
-- longitude, address lines, postal code or country-agnostic contacts.
CREATE FUNCTION hocalist.discovery_lead_json(
  p_request uuid,
  p_distance_miles double precision DEFAULT NULL,
  p_match integer DEFAULT NULL,
  p_match_reasons jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'request_id', r.id,
    'kind', r.kind,
    'title', r.title,
    'description', r.description,
    'condition', r.condition,
    'service_type', r.service_type,
    'quantity', r.quantity,
    'budget', jsonb_build_object(
      'minimum_minor', r.budget_min_minor,
      'maximum_minor', r.budget_max_minor,
      'currency', r.currency_code),
    'accepts_higher_offers', r.accepts_higher_offers,
    'category_id', r.category_id,
    'buyer_profile_id', r.buyer_profile_id,
    'buyer_display_name', coalesce(nullif(btrim(rp.display_name), ''), 'Hocalist member'),
    'area_label', coalesce(rp.area_label, r.city, r.region),
    'request_revision', r.revision,
    'acceptance_expires_at', r.acceptance_expires_at,
    'discovery_open', r.status = 'active'
      AND (r.acceptance_expires_at IS NULL OR now() < r.acceptance_expires_at),
    'published_at', r.created_at,
    'distance_miles', p_distance_miles,
    'match_percent', p_match,
    'match_reasons', coalesce(p_match_reasons, '[]'::jsonb),
    'verified_purchase_count', (
      SELECT count(*)::integer FROM hocalist.sale_confirmations s
      WHERE s.buyer_user_id = r.buyer_user_id)
  )
  FROM hocalist.requests r
  LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = r.buyer_profile_id
  WHERE r.id = p_request;
$$;

-- Server-authorized seller discovery. Filters, sorts, radius and cursor are
-- all applied server-side; the returned projection is the only lead shape a
-- seller can read. `p_cursor` encodes the active sort so a cursor from another
-- sort is rejected instead of silently returning wrong rows.
--
-- Sorts: newest | recommended | closest | budget.
-- recommended: explainable match (declared category 50, area overlap 30,
--   in-radius 20), then US priority, then recency. Requests with no
--   explainable match sort last and report a null match_percent.
-- closest: ascending distance when available; requests without coordinates
--   sort last and never carry a fabricated distance.
-- budget: highest maximum budget first; unknown budgets sort last.
CREATE FUNCTION hocalist.marketplace_discovery_leads(
  p_kind text DEFAULT NULL,
  p_category uuid DEFAULT NULL,
  p_area text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_cursor text DEFAULT NULL,
  p_sort text DEFAULT 'newest',
  p_radius_miles integer DEFAULT NULL,
  p_query text DEFAULT NULL,
  p_budget_min_minor bigint DEFAULT NULL,
  p_budget_max_minor bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_size integer;
  v_sort text := coalesce(nullif(btrim(p_sort), ''), 'newest');
  v_origin hocalist.seller_discovery_origins%ROWTYPE;
  v_radius integer;
  v_declared uuid[];
  v_seller_area text;
  v_query text;
  v_cursor_sort text;
  v_cursor_metric double precision;
  v_cursor_match integer;
  v_cursor_us integer;
  v_cursor_micros bigint;
  v_cursor_id uuid;
  v_rows jsonb;
  v_next text;
  v_last_metric double precision;
  v_last_match integer;
  v_last_us integer;
  v_last_micros bigint;
  v_last_id uuid;
  v_has_more boolean;
BEGIN
  PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
  IF p_kind IS NOT NULL AND p_kind NOT IN ('product','service') THEN
    RAISE EXCEPTION 'invalid_field: kind' USING ERRCODE='22023';
  END IF;
  IF p_area IS NOT NULL AND length(btrim(p_area)) NOT BETWEEN 1 AND 150 THEN
    RAISE EXCEPTION 'invalid_field: area' USING ERRCODE='22023';
  END IF;
  v_query := nullif(btrim(coalesce(p_query,'')), '');
  IF v_query IS NOT NULL AND length(v_query) > 160 THEN
    RAISE EXCEPTION 'invalid_field: query' USING ERRCODE='22023';
  END IF;
  IF p_radius_miles IS NOT NULL AND p_radius_miles NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'invalid_field: radius' USING ERRCODE='22023';
  END IF;
  IF v_sort NOT IN ('newest','recommended','closest','budget') THEN
    RAISE EXCEPTION 'invalid_field: sort' USING ERRCODE='22023';
  END IF;
  v_size := greatest(1, least(coalesce(p_limit, 50), 100));

  SELECT * INTO v_origin FROM hocalist.seller_discovery_origins WHERE seller_user_id = v_user;
  IF NOT FOUND THEN
    v_origin.radius_miles := NULL;
  END IF;
  v_radius := coalesce(p_radius_miles, v_origin.radius_miles);
  SELECT coalesce(rp.area_label, '') INTO v_seller_area
    FROM hocalist.memberships m
    LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = m.id
    WHERE m.user_id = v_user AND m.role = 'seller' AND m.status = 'active'
    LIMIT 1;
  v_seller_area := coalesce(v_seller_area, '');
  v_declared := hocalist.discovery_declared_category_ids(v_user);

  IF p_cursor IS NOT NULL THEN
    BEGIN
      v_cursor_sort := split_part(p_cursor, '|', 1);
      IF v_cursor_sort <> v_sort THEN
        RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023';
      END IF;
      IF v_sort = 'recommended' THEN
        v_cursor_match := split_part(p_cursor, '|', 2)::integer;
        v_cursor_us := split_part(p_cursor, '|', 3)::integer;
        v_cursor_micros := split_part(p_cursor, '|', 4)::bigint;
        v_cursor_id := split_part(p_cursor, '|', 5)::uuid;
      ELSIF v_sort = 'closest' THEN
        v_cursor_metric := split_part(p_cursor, '|', 2)::double precision;
        v_cursor_micros := split_part(p_cursor, '|', 3)::bigint;
        v_cursor_id := split_part(p_cursor, '|', 4)::uuid;
      ELSIF v_sort = 'budget' THEN
        v_cursor_metric := split_part(p_cursor, '|', 2)::double precision;
        v_cursor_micros := split_part(p_cursor, '|', 3)::bigint;
        v_cursor_id := split_part(p_cursor, '|', 4)::uuid;
      ELSE
        v_cursor_micros := split_part(p_cursor, '|', 2)::bigint;
        v_cursor_id := split_part(p_cursor, '|', 3)::uuid;
      END IF;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023';
    END;
  END IF;

  SELECT coalesce(jsonb_agg(row_json ORDER BY
      row_match DESC, row_us DESC, row_micros DESC, row_id DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      r.id AS row_id,
      (extract(epoch FROM r.created_at) * 1000000)::bigint AS row_micros,
      CASE WHEN r.country_code = 'US' THEN 1 ELSE 0 END AS row_us,
      -- Ordering score: -1 when nothing explainable matched, so unmatched
      -- requests sort last without turning into a fabricated 0% badge.
      coalesce(CASE
        WHEN r.category_id IS NOT NULL AND r.category_id = ANY(v_declared) THEN 50
        ELSE 0
      END
      + CASE
          WHEN v_seller_area <> '' AND (
            rp.area_label ILIKE '%' || v_seller_area || '%'
            OR v_seller_area ILIKE '%' || coalesce(rp.area_label, r.city, r.region, '') || '%'
            OR r.city ILIKE '%' || v_seller_area || '%'
            OR r.region ILIKE '%' || v_seller_area || '%')
          THEN 30 ELSE 0
        END
      + CASE
          WHEN v_radius IS NOT NULL AND v_origin.latitude IS NOT NULL
               AND r.latitude IS NOT NULL
               AND hocalist.discovery_distance_miles(
                     v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)
                   <= v_radius
          THEN 20 ELSE 0
        END, -1) AS row_match,
      CASE
        WHEN v_origin.latitude IS NOT NULL AND r.latitude IS NOT NULL THEN
          round(hocalist.discovery_distance_miles(
            v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)::numeric, 1)::double precision
        ELSE NULL
      END AS row_distance,
      hocalist.discovery_lead_json(
        r.id,
        CASE
          WHEN v_origin.latitude IS NOT NULL AND r.latitude IS NOT NULL THEN
            round(hocalist.discovery_distance_miles(
              v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)::numeric, 1)::double precision
          ELSE NULL
        END,
        NULLIF(
          CASE
            WHEN r.category_id IS NOT NULL AND r.category_id = ANY(v_declared) THEN 50
            ELSE 0
          END
          + CASE
              WHEN v_seller_area <> '' AND (
                rp.area_label ILIKE '%' || v_seller_area || '%'
                OR v_seller_area ILIKE '%' || coalesce(rp.area_label, r.city, r.region, '') || '%'
                OR r.city ILIKE '%' || v_seller_area || '%'
                OR r.region ILIKE '%' || v_seller_area || '%')
              THEN 30 ELSE 0
            END
          + CASE
              WHEN v_radius IS NOT NULL AND v_origin.latitude IS NOT NULL
                   AND r.latitude IS NOT NULL
                   AND hocalist.discovery_distance_miles(
                         v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)
                       <= v_radius
              THEN 20 ELSE 0
            END,
          0),
        (
          SELECT coalesce(jsonb_agg(reason), '[]'::jsonb) FROM (
            SELECT 'Matches your declared category'::text AS reason
              WHERE r.category_id IS NOT NULL AND r.category_id = ANY(v_declared)
            UNION ALL
            SELECT 'Inside your declared service area'
              WHERE v_seller_area <> '' AND (
                rp.area_label ILIKE '%' || v_seller_area || '%'
                OR v_seller_area ILIKE '%' || coalesce(rp.area_label, r.city, r.region, '') || '%'
                OR r.city ILIKE '%' || v_seller_area || '%'
                OR r.region ILIKE '%' || v_seller_area || '%')
            UNION ALL
            SELECT 'Within your service radius'
              WHERE v_radius IS NOT NULL AND v_origin.latitude IS NOT NULL
                AND r.latitude IS NOT NULL
                AND hocalist.discovery_distance_miles(
                      v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)
                    <= v_radius
          ) reasons
        )
      ) AS row_json
    FROM hocalist.requests r
    LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = r.buyer_profile_id
    WHERE r.status = 'active'
      AND (r.acceptance_expires_at IS NULL OR now() < r.acceptance_expires_at)
      AND r.buyer_user_id <> v_user
      AND (p_kind IS NULL OR r.kind = p_kind)
      AND (p_category IS NULL OR r.category_id = p_category)
      AND (v_query IS NULL OR r.title ILIKE '%' || v_query || '%'
           OR r.description ILIKE '%' || v_query || '%')
      AND (p_budget_min_minor IS NULL
           OR coalesce(r.budget_max_minor, r.budget_min_minor) >= p_budget_min_minor)
      AND (p_budget_max_minor IS NULL
           OR coalesce(r.budget_min_minor, r.budget_max_minor) <= p_budget_max_minor)
      AND (p_area IS NULL OR rp.area_label ILIKE '%' || btrim(p_area) || '%'
           OR r.city ILIKE '%' || btrim(p_area) || '%'
           OR r.region ILIKE '%' || btrim(p_area) || '%')
      AND (v_radius IS NULL OR v_origin.latitude IS NULL OR r.latitude IS NULL
           OR hocalist.discovery_distance_miles(
                v_origin.latitude, v_origin.longitude, r.latitude, r.longitude) <= v_radius)
      AND (
        p_cursor IS NULL
        OR (v_sort = 'newest' AND (
              (extract(epoch FROM r.created_at) * 1000000)::bigint, r.id
            ) < (v_cursor_micros, v_cursor_id))
        OR (v_sort = 'closest' AND (
              coalesce(round(hocalist.discovery_distance_miles(
                v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)::numeric, 1)::double precision,
                'Infinity'::double precision) > v_cursor_metric
              OR (coalesce(round(hocalist.discovery_distance_miles(
                v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)::numeric, 1)::double precision,
                'Infinity'::double precision) = v_cursor_metric
                AND ((extract(epoch FROM r.created_at) * 1000000)::bigint, r.id)
                    < (v_cursor_micros, v_cursor_id))))
        OR (v_sort = 'budget' AND (
              coalesce(r.budget_max_minor, -1)::double precision,
              (extract(epoch FROM r.created_at) * 1000000)::bigint, r.id
            ) < (v_cursor_metric, v_cursor_micros, v_cursor_id))
        OR (v_sort = 'recommended' AND (
              coalesce(
                CASE WHEN r.category_id IS NOT NULL AND r.category_id = ANY(v_declared) THEN 50 ELSE 0 END
                + CASE
                    WHEN v_seller_area <> '' AND (
                      rp.area_label ILIKE '%' || v_seller_area || '%'
                      OR v_seller_area ILIKE '%' || coalesce(rp.area_label, r.city, r.region, '') || '%'
                      OR r.city ILIKE '%' || v_seller_area || '%'
                      OR r.region ILIKE '%' || v_seller_area || '%')
                    THEN 30 ELSE 0
                  END
                + CASE
                    WHEN v_radius IS NOT NULL AND v_origin.latitude IS NOT NULL
                         AND r.latitude IS NOT NULL
                         AND hocalist.discovery_distance_miles(
                               v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)
                             <= v_radius
                    THEN 20 ELSE 0
                  END, -1),
              CASE WHEN r.country_code = 'US' THEN 1 ELSE 0 END,
              (extract(epoch FROM r.created_at) * 1000000)::bigint,
              r.id
            ) < (v_cursor_match, v_cursor_us, v_cursor_micros, v_cursor_id))
      )
    ORDER BY
      CASE WHEN v_sort = 'recommended' THEN coalesce(
        CASE WHEN r.category_id IS NOT NULL AND r.category_id = ANY(v_declared) THEN 50 ELSE 0 END
        + CASE
            WHEN v_seller_area <> '' AND (
              rp.area_label ILIKE '%' || v_seller_area || '%'
              OR v_seller_area ILIKE '%' || coalesce(rp.area_label, r.city, r.region, '') || '%'
              OR r.city ILIKE '%' || v_seller_area || '%'
              OR r.region ILIKE '%' || v_seller_area || '%')
            THEN 30 ELSE 0
          END
        + CASE
            WHEN v_radius IS NOT NULL AND v_origin.latitude IS NOT NULL
                 AND r.latitude IS NOT NULL
                 AND hocalist.discovery_distance_miles(
                       v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)
                     <= v_radius
            THEN 20 ELSE 0
          END, -1) END DESC,
      CASE WHEN v_sort = 'recommended' THEN CASE WHEN r.country_code = 'US' THEN 1 ELSE 0 END END DESC,
      CASE WHEN v_sort = 'closest' THEN coalesce(round(hocalist.discovery_distance_miles(
        v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)::numeric, 1)::double precision,
        'Infinity'::double precision) END ASC,
      CASE WHEN v_sort = 'budget' THEN coalesce(r.budget_max_minor, -1) END DESC,
      r.created_at DESC, r.id DESC
    LIMIT v_size
  ) rows;

  v_next := NULL;
  IF jsonb_array_length(v_rows) = v_size THEN
    SELECT
      CASE WHEN v_sort = 'recommended' THEN coalesce((v_rows->-1->>'match_percent')::integer, -1) END,
      CASE WHEN v_sort = 'recommended' THEN
        CASE WHEN (SELECT r.country_code = 'US' FROM hocalist.requests r
                   WHERE r.id = (v_rows->-1->>'request_id')::uuid)
             THEN 1 ELSE 0 END
      END,
      CASE WHEN v_sort IN ('closest','budget') THEN
        CASE WHEN v_sort = 'closest'
             THEN coalesce((v_rows->-1->>'distance_miles')::double precision, 'Infinity'::double precision)
             ELSE (SELECT coalesce(r.budget_max_minor, -1)::double precision
                   FROM hocalist.requests r WHERE r.id = (v_rows->-1->>'request_id')::uuid) END
      END,
      (extract(epoch FROM r.created_at) * 1000000)::bigint, r.id
      INTO v_last_match, v_last_us, v_last_metric, v_last_micros, v_last_id
      FROM hocalist.requests r WHERE r.id = (v_rows->-1->>'request_id')::uuid;
    v_last_match := coalesce(v_last_match, -1);
    v_last_us := coalesce(v_last_us, 0);
    SELECT EXISTS (
      SELECT 1 FROM hocalist.requests r
      LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = r.buyer_profile_id
      WHERE r.status = 'active'
        AND (r.acceptance_expires_at IS NULL OR now() < r.acceptance_expires_at)
        AND r.buyer_user_id <> v_user
        AND (p_kind IS NULL OR r.kind = p_kind)
        AND (p_category IS NULL OR r.category_id = p_category)
        AND (v_query IS NULL OR r.title ILIKE '%' || v_query || '%'
             OR r.description ILIKE '%' || v_query || '%')
        AND (p_budget_min_minor IS NULL
             OR coalesce(r.budget_max_minor, r.budget_min_minor) >= p_budget_min_minor)
        AND (p_budget_max_minor IS NULL
             OR coalesce(r.budget_min_minor, r.budget_max_minor) <= p_budget_max_minor)
        AND (p_area IS NULL OR rp.area_label ILIKE '%' || btrim(p_area) || '%'
             OR r.city ILIKE '%' || btrim(p_area) || '%'
             OR r.region ILIKE '%' || btrim(p_area) || '%')
        AND (v_radius IS NULL OR v_origin.latitude IS NULL OR r.latitude IS NULL
             OR hocalist.discovery_distance_miles(
                  v_origin.latitude, v_origin.longitude, r.latitude, r.longitude) <= v_radius)
        AND (
          (v_sort = 'newest' AND
             ((extract(epoch FROM r.created_at) * 1000000)::bigint, r.id) < (v_last_micros, v_last_id))
          OR (v_sort = 'closest' AND (
             coalesce(round(hocalist.discovery_distance_miles(
                v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)::numeric, 1)::double precision,
                'Infinity'::double precision) > coalesce(v_last_metric, 'Infinity'::double precision)
             OR (coalesce(round(hocalist.discovery_distance_miles(
                v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)::numeric, 1)::double precision,
                'Infinity'::double precision) = coalesce(v_last_metric, 'Infinity'::double precision)
               AND ((extract(epoch FROM r.created_at) * 1000000)::bigint, r.id)
                   < (v_last_micros, v_last_id))))
          OR (v_sort = 'budget' AND
             (coalesce(r.budget_max_minor, -1)::double precision,
              (extract(epoch FROM r.created_at) * 1000000)::bigint, r.id)
             < (coalesce(v_last_metric, -1), v_last_micros, v_last_id))
          OR (v_sort = 'recommended' AND
             (coalesce(
                CASE WHEN r.category_id IS NOT NULL AND r.category_id = ANY(v_declared) THEN 50 ELSE 0 END
                + CASE
                    WHEN v_seller_area <> '' AND (
                      rp.area_label ILIKE '%' || v_seller_area || '%'
                      OR v_seller_area ILIKE '%' || coalesce(rp.area_label, r.city, r.region, '') || '%'
                      OR r.city ILIKE '%' || v_seller_area || '%'
                      OR r.region ILIKE '%' || v_seller_area || '%')
                    THEN 30 ELSE 0
                  END
                + CASE
                    WHEN v_radius IS NOT NULL AND v_origin.latitude IS NOT NULL
                         AND r.latitude IS NOT NULL
                         AND hocalist.discovery_distance_miles(
                               v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)
                             <= v_radius
                    THEN 20 ELSE 0
                  END, -1),
              CASE WHEN r.country_code = 'US' THEN 1 ELSE 0 END,
              (extract(epoch FROM r.created_at) * 1000000)::bigint,
              r.id
             ) < (v_last_match, v_last_us, v_last_micros, v_last_id))
        )
    ) INTO v_has_more;
    IF v_has_more THEN
      v_next := CASE v_sort
        WHEN 'recommended' THEN
          'recommended|' || v_last_match::text || '|' || v_last_us::text || '|'
          || v_last_micros::text || '|' || v_last_id::text
        WHEN 'closest' THEN
          'closest|' || v_last_metric::text || '|' || v_last_micros::text || '|' || v_last_id::text
        WHEN 'budget' THEN
          'budget|' || v_last_metric::text || '|' || v_last_micros::text || '|' || v_last_id::text
        ELSE 'newest|' || v_last_micros::text || '|' || v_last_id::text
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'items', v_rows,
    'next_cursor', v_next,
    'sort', v_sort,
    'applied_radius_miles', v_radius,
    'distance_available', v_origin.latitude IS NOT NULL,
    'manual_area_fallback', v_origin.latitude IS NULL,
    'declared_category_count', coalesce(array_length(v_declared, 1), 0),
    'us_priority_applied', v_sort = 'recommended');
END $$;

-- Stable discovery ordering indexes. The existing request indexes order by
-- (status, created_at, id); these add the category-scoped candidate path.
CREATE INDEX requests_discovery_order
  ON hocalist.requests(created_at DESC, id DESC) WHERE status = 'active';
CREATE INDEX requests_discovery_category
  ON hocalist.requests(category_id, created_at DESC, id DESC) WHERE status = 'active';

REVOKE ALL ON FUNCTION hocalist.discovery_declared_category_ids(uuid),
  hocalist.discovery_assert_active_member(uuid),
  hocalist.discovery_origin_json(), hocalist.discovery_origin_set(text,jsonb),
  hocalist.discovery_lead_json(uuid,double precision,integer,jsonb),
  hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.discovery_origin_json(),
  hocalist.discovery_origin_set(text,jsonb),
  hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)
  TO authenticated;
COMMIT;

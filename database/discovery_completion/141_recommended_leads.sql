-- Additive recommended-leads read over discovery_completion/140.
--
-- The seller home "Recommended leads for you" section previously had no
-- projection and stayed permanently empty in real mode. This read returns
-- eligible requests explained by the seller's declared Store-listing
-- categories and declared service area/radius. Every returned card carries
-- its match reasons, so the UI never shows an unexplained percentage or a
-- fixed fixture.
--
-- Prerequisite: discovery_completion/140 (same package).
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regprocedure('hocalist.discovery_declared_category_ids(uuid)') IS NULL
     OR to_regprocedure('hocalist.discovery_lead_json(uuid,double precision,integer,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'discovery leads 140 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.marketplace_recommended_leads(integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'recommended leads already installed';
  END IF;
END; $guard$;

CREATE FUNCTION hocalist.marketplace_recommended_leads(p_limit integer DEFAULT 6)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_size integer;
  v_origin hocalist.seller_discovery_origins%ROWTYPE;
  v_radius integer;
  v_declared uuid[];
  v_declared_labels jsonb;
  v_seller_area text;
  v_has_basis boolean;
  v_items jsonb;
BEGIN
  PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
  v_size := greatest(1, least(coalesce(p_limit, 6), 20));
  SELECT * INTO v_origin FROM hocalist.seller_discovery_origins WHERE seller_user_id = v_user;
  IF NOT FOUND THEN
    v_origin.radius_miles := NULL;
  END IF;
  v_radius := v_origin.radius_miles;
  SELECT coalesce(rp.area_label, '') INTO v_seller_area
    FROM hocalist.memberships m
    LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = m.id
    WHERE m.user_id = v_user AND m.role = 'seller' AND m.status = 'active'
    LIMIT 1;
  v_seller_area := coalesce(v_seller_area, '');
  v_declared := hocalist.discovery_declared_category_ids(v_user);
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'label', c.label)
                            ORDER BY c.label, c.id), '[]'::jsonb)
    INTO v_declared_labels
    FROM hocalist.catalogue_categories c
    WHERE c.id = ANY(v_declared);
  v_has_basis := coalesce(array_length(v_declared, 1), 0) > 0
    OR v_seller_area <> ''
    OR v_radius IS NOT NULL;

  IF NOT v_has_basis THEN
    RETURN jsonb_build_object(
      'items', '[]'::jsonb,
      'basis', jsonb_build_object(
        'declared_categories', '[]'::jsonb,
        'area_label', NULL,
        'radius_miles', NULL),
      'unavailable_reason', 'no_matching_basis');
  END IF;

  SELECT coalesce(jsonb_agg(row_json ORDER BY row_match DESC, row_us DESC,
                            row_micros DESC, row_id DESC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT
      r.id AS row_id,
      (extract(epoch FROM r.created_at) * 1000000)::bigint AS row_micros,
      CASE WHEN r.country_code = 'US' THEN 1 ELSE 0 END AS row_us,
      coalesce(match_expr, -1) AS row_match,
      hocalist.discovery_lead_json(
        r.id,
        CASE
          WHEN v_origin.latitude IS NOT NULL AND r.latitude IS NOT NULL THEN
            round(hocalist.discovery_distance_miles(
              v_origin.latitude, v_origin.longitude, r.latitude, r.longitude)::numeric, 1)::double precision
          ELSE NULL
        END,
        match_expr,
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
    FROM (
      SELECT r0.*,
        (
          CASE WHEN r0.category_id IS NOT NULL AND r0.category_id = ANY(v_declared) THEN 50 ELSE 0 END
          + CASE
              WHEN v_seller_area <> '' AND (
                rp0.area_label ILIKE '%' || v_seller_area || '%'
                OR v_seller_area ILIKE '%' || coalesce(rp0.area_label, r0.city, r0.region, '') || '%'
                OR r0.city ILIKE '%' || v_seller_area || '%'
                OR r0.region ILIKE '%' || v_seller_area || '%')
              THEN 30 ELSE 0
            END
          + CASE
              WHEN v_radius IS NOT NULL AND v_origin.latitude IS NOT NULL
                   AND r0.latitude IS NOT NULL
                   AND hocalist.discovery_distance_miles(
                         v_origin.latitude, v_origin.longitude, r0.latitude, r0.longitude)
                       <= v_radius
              THEN 20 ELSE 0
            END
        ) AS match_order
      FROM hocalist.requests r0
      LEFT JOIN hocalist.role_profiles rp0 ON rp0.membership_id = r0.buyer_profile_id
      WHERE r0.status = 'active'
        AND (r0.acceptance_expires_at IS NULL OR now() < r0.acceptance_expires_at)
        AND r0.buyer_user_id <> v_user
    ) r
    LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = r.buyer_profile_id,
    LATERAL (SELECT NULLIF(r.match_order, 0) AS match_expr) scored
    WHERE match_expr IS NOT NULL
    LIMIT v_size
  ) rows;

  RETURN jsonb_build_object(
    'items', v_items,
    'basis', jsonb_build_object(
      'declared_categories', v_declared_labels,
      'area_label', nullif(v_seller_area, ''),
      'radius_miles', v_radius),
    'unavailable_reason', CASE
      WHEN jsonb_array_length(v_items) = 0 THEN 'no_eligible_matches'
      ELSE NULL END);
END $$;

REVOKE ALL ON FUNCTION hocalist.marketplace_recommended_leads(integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.marketplace_recommended_leads(integer)
  TO authenticated;
COMMIT;

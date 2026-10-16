-- Missing/blank buyer areas cannot match arbitrary seller service areas.
-- No records, signatures, authentication or privileges change.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid = to_regprocedure('hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)')
    AND md5(replace(p.prosrc, E'\r\n', E'\n')) = 'be33038e027379ba9ba64686b0f995ef'
    AND p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'Service-area function definition drift: marketplace_discovery_leads';
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)','EXECUTE')
    OR has_function_privilege('anon','hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)','EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)')
      AND (a.grantee = 0 OR a.is_grantable AND a.grantee <> p.proowner)) THEN
    RAISE EXCEPTION 'Service-area function privilege drift: marketplace_discovery_leads';
  END IF;
END;
$guard$;
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid = to_regprocedure('hocalist.marketplace_recommended_leads(integer)')
    AND md5(replace(p.prosrc, E'\r\n', E'\n')) = 'aa00ae988071499a8d5b6b716f0633d4'
    AND p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'Service-area function definition drift: marketplace_recommended_leads';
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.marketplace_recommended_leads(integer)','EXECUTE')
    OR has_function_privilege('anon','hocalist.marketplace_recommended_leads(integer)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_recommended_leads(integer)','EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.marketplace_recommended_leads(integer)')
      AND (a.grantee = 0 OR a.is_grantable AND a.grantee <> p.proowner)) THEN
    RAISE EXCEPTION 'Service-area function privilege drift: marketplace_recommended_leads';
  END IF;
END;
$guard$;
CREATE OR REPLACE FUNCTION hocalist.marketplace_discovery_leads(
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
            OR v_seller_area ILIKE '%' || coalesce(nullif(btrim(rp.area_label), ''), nullif(btrim(r.city), ''), nullif(btrim(r.region), '')) || '%'
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
                OR v_seller_area ILIKE '%' || coalesce(nullif(btrim(rp.area_label), ''), nullif(btrim(r.city), ''), nullif(btrim(r.region), '')) || '%'
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
                OR v_seller_area ILIKE '%' || coalesce(nullif(btrim(rp.area_label), ''), nullif(btrim(r.city), ''), nullif(btrim(r.region), '')) || '%'
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
                      OR v_seller_area ILIKE '%' || coalesce(nullif(btrim(rp.area_label), ''), nullif(btrim(r.city), ''), nullif(btrim(r.region), '')) || '%'
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
              OR v_seller_area ILIKE '%' || coalesce(nullif(btrim(rp.area_label), ''), nullif(btrim(r.city), ''), nullif(btrim(r.region), '')) || '%'
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
                      OR v_seller_area ILIKE '%' || coalesce(nullif(btrim(rp.area_label), ''), nullif(btrim(r.city), ''), nullif(btrim(r.region), '')) || '%'
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
CREATE OR REPLACE FUNCTION hocalist.marketplace_recommended_leads(p_limit integer DEFAULT 6)
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
                OR v_seller_area ILIKE '%' || coalesce(nullif(btrim(rp.area_label), ''), nullif(btrim(r.city), ''), nullif(btrim(r.region), '')) || '%'
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
                OR v_seller_area ILIKE '%' || coalesce(nullif(btrim(rp0.area_label), ''), nullif(btrim(r0.city), ''), nullif(btrim(r0.region), '')) || '%'
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
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid = to_regprocedure('hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)')
    AND md5(replace(p.prosrc, E'\r\n', E'\n')) = '6af696ce5ecd8cdbc359d158445a2ba4'
    AND p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'Service-area function definition drift: marketplace_discovery_leads';
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)','EXECUTE')
    OR has_function_privilege('anon','hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)','EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)')
      AND (a.grantee = 0 OR a.is_grantable AND a.grantee <> p.proowner)) THEN
    RAISE EXCEPTION 'Service-area function privilege drift: marketplace_discovery_leads';
  END IF;
END;
$guard$;
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid = to_regprocedure('hocalist.marketplace_recommended_leads(integer)')
    AND md5(replace(p.prosrc, E'\r\n', E'\n')) = '253d3460eee115115d91aa1577d13d36'
    AND p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'Service-area function definition drift: marketplace_recommended_leads';
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.marketplace_recommended_leads(integer)','EXECUTE')
    OR has_function_privilege('anon','hocalist.marketplace_recommended_leads(integer)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_recommended_leads(integer)','EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.marketplace_recommended_leads(integer)')
      AND (a.grantee = 0 OR a.is_grantable AND a.grantee <> p.proowner)) THEN
    RAISE EXCEPTION 'Service-area function privilege drift: marketplace_recommended_leads';
  END IF;
END;
$guard$;
COMMIT;

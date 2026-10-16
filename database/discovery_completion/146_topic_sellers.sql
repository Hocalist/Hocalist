-- Additive Hocatrends topic seller results.
--
-- Returns the sellers who currently have a published listing in a topic
-- (active catalogue category), with their public reputation aggregate. Used by
-- the signed-in Hocatrends seller results and by the enquiry opener, which
-- re-validates eligibility server-side. No coordinates, contacts or private
-- offers are projected.
--
-- Prerequisites: marketplace/020 + discovery_completion/142 (reviews).
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.store_listings') IS NULL
     OR to_regclass('hocalist.catalogue_categories') IS NULL
     OR to_regprocedure('hocalist.seller_public_reputation(uuid)') IS NULL
     OR to_regprocedure('hocalist.discovery_assert_active_member(uuid)') IS NULL THEN
    RAISE EXCEPTION 'marketplace/reviews/140 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.hocatrends_topic_sellers(uuid,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'Hocatrends topic sellers already installed';
  END IF;
END; $guard$;

CREATE FUNCTION hocalist.hocatrends_topic_sellers(
  p_topic uuid,
  p_limit integer DEFAULT 20
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  v_size integer;
BEGIN
  PERFORM hocalist.discovery_assert_active_member(u);
  IF p_topic IS NULL THEN RAISE EXCEPTION 'invalid_topic' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.catalogue_categories
                 WHERE id = p_topic AND status = 'active') THEN
    RAISE EXCEPTION 'topic_not_found' USING ERRCODE='P0002';
  END IF;
  v_size := greatest(1, least(coalesce(p_limit, 20), 50));
  RETURN jsonb_build_object(
    'topic_id', p_topic,
    'items', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'seller_profile_id', t.seller_profile_id,
        'seller_user_id', t.seller_user_id,
        'display_name', t.display_name,
        'area_label', t.area_label,
        'listing_id', t.listing_id,
        'listing_title', t.listing_title,
        'price_label', t.price_label,
        'rating_sum', t.rating_sum,
        'rating_count', t.rating_count,
        'completed_deals', t.completed_deals)
        ORDER BY t.rating_count DESC, t.rating_sum DESC,
                 t.confirmed_deals DESC, t.listing_title)
      FROM (
        SELECT
          l.seller_profile_id,
          l.seller_user_id,
          coalesce(nullif(btrim(rp.display_name), ''), 'Hocalist seller') AS display_name,
          rp.area_label,
          l.id AS listing_id,
          l.title AS listing_title,
          l.price_label AS price_label,
          coalesce(rep.rating_sum, 0) AS rating_sum,
          coalesce(rep.rating_count, 0) AS rating_count,
          coalesce((SELECT count(*)::integer FROM hocalist.sale_confirmations s
                    WHERE s.seller_user_id = l.seller_user_id), 0) AS completed_deals,
          (SELECT count(*) FROM hocalist.sale_confirmations s
           WHERE s.seller_user_id = l.seller_user_id) AS confirmed_deals
        FROM hocalist.store_listings l
        LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = l.seller_profile_id
        LEFT JOIN LATERAL (
          SELECT sum(r.rating)::integer AS rating_sum,
                 count(*)::integer AS rating_count
          FROM hocalist.outcome_reviews r
          WHERE r.seller_profile_id = l.seller_profile_id
            AND r.status = 'published'
        ) rep ON true
        WHERE l.category_id = p_topic
          AND l.status = 'active'
          AND l.moderation_status = 'approved'
          AND NOT EXISTS (
            SELECT 1 FROM hocalist.memberships m3
            WHERE m3.user_id = l.seller_user_id
              AND m3.status IN ('restricted','disabled'))
        ORDER BY l.created_at DESC, l.id DESC
        LIMIT v_size
      ) t), '[]'::jsonb));
END $$;

REVOKE ALL ON FUNCTION hocalist.hocatrends_topic_sellers(uuid,integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.hocatrends_topic_sellers(uuid,integer)
  TO authenticated;
COMMIT;


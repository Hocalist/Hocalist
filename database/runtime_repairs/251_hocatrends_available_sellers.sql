-- Read-only projection repair: current eligible sellers are separate from past activity.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
CREATE OR REPLACE FUNCTION hocalist.hocatrends_trends(p_limit integer DEFAULT 10)
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
      'available_sellers', available_sellers,
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
             || ' active in the last 30 days · ' || confirmed_purchases::text
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
        t.available_sellers,
        t.confirmed_purchases,
        t.participating_buyers,
        CASE WHEN v_total = 0 THEN 0
             ELSE round(100.0 * t.open_requests / v_total)::integer END AS percent,
        row_number() OVER (ORDER BY t.open_requests DESC, t.label) AS row_number
      FROM (
        SELECT
          c.id,
          c.label,
          (SELECT count(*)::integer FROM hocalist.discovery_topic_seller_candidates(c.id) eligible
            WHERE eligible.seller_user_id <> u) AS available_sellers,
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
REVOKE ALL ON FUNCTION hocalist.hocatrends_trends(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION hocalist.hocatrends_trends(integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

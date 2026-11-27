BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- All seller tiers share the same counting unit. Their limits are plan-owned.
CREATE OR REPLACE FUNCTION hocalist.weekly_target_usage(p_user uuid, p_week date)
RETURNS bigint LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT count(DISTINCT r.buyer_user_id)
  FROM hocalist.credit_targets t
  JOIN hocalist.requests r ON r.id = t.request_id
  WHERE t.user_id = p_user AND t.week_start = p_week;
$$;

CREATE OR REPLACE FUNCTION hocalist.weekly_target_quota_reached(
  p_user uuid, p_request uuid, p_week date, p_limit integer
) RETURNS boolean LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT hocalist.weekly_target_usage(p_user, p_week) >= p_limit
    AND NOT EXISTS (
      SELECT 1
      FROM hocalist.credit_targets t
      JOIN hocalist.requests r ON r.id = t.request_id
      JOIN hocalist.requests incoming ON incoming.id = p_request
        AND incoming.buyer_user_id = r.buyer_user_id
      WHERE t.user_id = p_user AND t.week_start = p_week
    );
$$;

CREATE FUNCTION hocalist.seller_buyer_history_internal(p_buyer uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = '' AS $$
  WITH outcomes AS (
    SELECT r.status, purchase.confirmed,
      purchase.confirmed OR r.status IN ('closed','cancelled','expired') OR (
        r.acceptance_expires_at <= now() AND NOT EXISTS (
          SELECT 1 FROM hocalist.meetings m WHERE m.request_id = r.id AND (
            (m.status IN ('accepted','reschedule_proposed') AND m.meeting_expires_at > now())
            OR (m.status = 'proposed' AND EXISTS (
              SELECT 1 FROM hocalist.meeting_schedule_revisions s
              WHERE s.meeting_id = m.id AND s.status = 'proposed' AND s.schedule_instant > now()
            ))
          )
        )
      ) IS TRUE AS concluded
    FROM hocalist.requests r
    CROSS JOIN LATERAL (SELECT EXISTS (
      SELECT 1 FROM hocalist.sale_confirmations s WHERE s.request_id = r.id AND s.buyer_user_id = p_buyer
    ) AS confirmed) purchase
    WHERE r.buyer_user_id = p_buyer
  ), totals AS (
    SELECT count(*) FILTER (WHERE concluded)::integer AS ended,
      count(*) FILTER (WHERE confirmed)::integer AS purchases,
      count(*) FILTER (WHERE status = 'active' AND NOT concluded)::integer AS ongoing
    FROM outcomes
  )
  SELECT jsonb_build_object('concluded_requests', ended, 'confirmed_purchases', purchases,
    'ongoing_requests', ongoing, 'completion_percent', round(purchases * 100.0 / nullif(ended, 0), 1))
  FROM totals;
$$;

-- Existing dashboard policy continues to require a relationship to the buyer.
CREATE OR REPLACE FUNCTION hocalist.seller_customer_insights(p_buyer uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE u uuid := auth.uid();
BEGIN
  PERFORM hocalist.marketplace_assert_role(u, 'seller');
  IF hocalist.marketplace_seller_plan(u) IS DISTINCT FROM 'elite' THEN
    RAISE EXCEPTION 'insights_plan_required' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.offers WHERE seller_user_id = u AND buyer_user_id = p_buyer)
    AND NOT EXISTS (SELECT 1 FROM hocalist.sale_confirmations WHERE seller_user_id = u AND buyer_user_id = p_buyer) THEN
    RAISE EXCEPTION 'customer_access_denied' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object('buyer_id', p_buyer) || hocalist.seller_buyer_history_internal(p_buyer);
END $$;

-- Before an offer, authorize by the eligible request, and expose only a
-- historical summary with enough completed history to be meaningful.
CREATE FUNCTION hocalist.seller_lead_insights(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE u uuid := auth.uid(); buyer uuid; history jsonb;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u, 'seller');
  IF hocalist.marketplace_seller_plan(u) IS DISTINCT FROM 'elite' THEN
    RAISE EXCEPTION 'insights_plan_required' USING ERRCODE = '42501';
  END IF;
  SELECT r.buyer_user_id INTO buyer FROM hocalist.requests r
  WHERE r.id = p_request AND r.status = 'active' AND r.buyer_user_id <> u
    AND (r.acceptance_expires_at IS NULL OR r.acceptance_expires_at > now());
  IF NOT FOUND THEN RAISE EXCEPTION 'request_access_denied' USING ERRCODE = '42501'; END IF;
  PERFORM hocalist.marketplace_request(p_request);
  history := hocalist.seller_buyer_history_internal(buyer);
  RETURN jsonb_build_object('request_id', p_request, 'history',
    CASE WHEN (history->>'concluded_requests')::integer >= 5 THEN history END);
END $$;

REVOKE ALL ON FUNCTION hocalist.seller_buyer_history_internal(uuid), hocalist.seller_lead_insights(uuid),
    hocalist.weekly_target_usage(uuid,date), hocalist.weekly_target_quota_reached(uuid,uuid,date,integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.seller_lead_insights(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';

COMMIT;

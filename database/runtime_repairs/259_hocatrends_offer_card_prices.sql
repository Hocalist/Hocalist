-- Align public Hocatrends card prices with explicitly opted-in offers.
-- Savings use the originating request's maximum budget (minimum if no maximum).
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
CREATE OR REPLACE FUNCTION hocalist.hocatrends_topic_sellers(p_topic uuid, p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE u uuid := auth.uid(); v_size integer;
BEGIN
  PERFORM hocalist.discovery_assert_active_member(u);
  IF p_topic IS NULL THEN RAISE EXCEPTION 'invalid_topic' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.catalogue_categories WHERE id=p_topic AND status='active') THEN
    RAISE EXCEPTION 'topic_not_found' USING ERRCODE='P0002';
  END IF;
  v_size := greatest(1, least(coalesce(p_limit,20),50));
  RETURN jsonb_build_object('topic_id',p_topic,'items',coalesce((
    SELECT jsonb_agg(to_jsonb(t) ORDER BY t.rating_count DESC,t.rating_sum DESC,t.completed_deals DESC,t.seller_profile_id)
    FROM (
      SELECT c.seller_profile_id,c.seller_user_id,
        coalesce(nullif(btrim(rp.display_name),''),'Hocalist seller') AS display_name,
        rp.area_label,l.id AS listing_id,offer_card.title AS listing_title,
        l.price_label,offer_card.price_minor AS offer_price_minor,
        offer_card.buyer_budget_minor,offer_card.currency_code,
        coalesce(rep.rating_sum,0) AS rating_sum,coalesce(rep.rating_count,0) AS rating_count,
        (SELECT count(*)::integer FROM hocalist.sale_confirmations s WHERE s.seller_user_id=c.seller_user_id) AS completed_deals
      FROM hocalist.discovery_topic_seller_candidates(p_topic) c
      LEFT JOIN hocalist.role_profiles rp ON rp.membership_id=c.seller_profile_id
      JOIN LATERAL (
        SELECT r.title,revision.price_minor,revision.currency_code,
          CASE WHEN revision.currency_code=r.currency_code
            THEN coalesce(r.budget_max_minor,r.budget_min_minor) END AS buyer_budget_minor
        FROM hocalist.offers o JOIN hocalist.requests r ON r.id=o.request_id
        JOIN LATERAL (
          SELECT rev.price_minor,rev.currency_code FROM hocalist.offer_revisions rev
          WHERE rev.offer_id=o.id AND (o.accepted_revision_id IS NULL OR rev.id=o.accepted_revision_id)
          ORDER BY rev.sequence DESC LIMIT 1
        ) revision ON true
        WHERE o.seller_profile_id=c.seller_profile_id AND o.seller_user_id=c.seller_user_id
          AND r.category_id=p_topic AND o.hocatrends_opt_in
          AND o.status IN ('submitted','selected','completed')
          AND o.created_at > now()-interval '30 days'
        ORDER BY o.created_at DESC,o.id DESC LIMIT 1
      ) offer_card ON true
      LEFT JOIN LATERAL (
        SELECT sl.id,sl.price_label FROM hocalist.store_listings sl
        WHERE sl.seller_profile_id=c.seller_profile_id AND sl.seller_user_id=c.seller_user_id
          AND sl.category_id=p_topic AND sl.status='active' AND sl.moderation_status='approved'
        ORDER BY sl.created_at DESC,sl.id DESC LIMIT 1
      ) l ON true
      LEFT JOIN LATERAL (
        SELECT sum(r.rating)::integer AS rating_sum,count(*)::integer AS rating_count
        FROM hocalist.outcome_reviews r WHERE r.seller_profile_id=c.seller_profile_id AND r.status='published'
      ) rep ON true
      WHERE c.seller_user_id <> u
      ORDER BY rating_count DESC,rating_sum DESC,completed_deals DESC,c.seller_profile_id LIMIT v_size
    ) t
  ),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION hocalist.hocatrends_topic_sellers(uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.hocatrends_topic_sellers(uuid,integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

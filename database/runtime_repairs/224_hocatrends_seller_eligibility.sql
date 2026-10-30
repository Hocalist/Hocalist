-- Include current category participants, not only Store listing owners.
-- The internal candidate set is shared by discovery and enquiry validation.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE OR REPLACE FUNCTION hocalist.discovery_topic_seller_candidates(p_topic uuid)
RETURNS TABLE(seller_profile_id uuid, seller_user_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT m.id, m.user_id
  FROM hocalist.memberships m
  WHERE m.role = 'seller' AND m.status = 'active'
    AND NOT EXISTS (SELECT 1 FROM hocalist.memberships blocked
      WHERE blocked.user_id = m.user_id AND blocked.status IN ('restricted','disabled'))
    AND (
      EXISTS (SELECT 1 FROM hocalist.store_listings l
        WHERE l.seller_profile_id = m.id AND l.seller_user_id = m.user_id
          AND l.category_id = p_topic AND l.status = 'active'
          AND l.moderation_status = 'approved')
      OR EXISTS (SELECT 1 FROM hocalist.offers o
        JOIN hocalist.requests r ON r.id = o.request_id
        WHERE o.seller_profile_id = m.id AND o.seller_user_id = m.user_id
          AND r.category_id = p_topic
          AND o.status IN ('submitted','selected','completed')
          AND o.created_at > now() - interval '30 days')
    );
$$;
REVOKE ALL ON FUNCTION hocalist.discovery_topic_seller_candidates(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION hocalist.hocatrends_topic_sellers(
  p_topic uuid, p_limit integer DEFAULT 20
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  v_size integer;
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
        rp.area_label,l.id AS listing_id,l.title AS listing_title,l.price_label,
        coalesce(rep.rating_sum,0) AS rating_sum,coalesce(rep.rating_count,0) AS rating_count,
        (SELECT count(*)::integer FROM hocalist.sale_confirmations s WHERE s.seller_user_id=c.seller_user_id) AS completed_deals
      FROM hocalist.discovery_topic_seller_candidates(p_topic) c
      LEFT JOIN hocalist.role_profiles rp ON rp.membership_id=c.seller_profile_id
      LEFT JOIN LATERAL (
        SELECT sl.id,sl.title,sl.price_label FROM hocalist.store_listings sl
        WHERE sl.seller_profile_id=c.seller_profile_id AND sl.seller_user_id=c.seller_user_id
          AND sl.category_id=p_topic AND sl.status='active' AND sl.moderation_status='approved'
        ORDER BY sl.created_at DESC,sl.id DESC LIMIT 1
      ) l ON true
      LEFT JOIN LATERAL (
        SELECT sum(r.rating)::integer AS rating_sum,count(*)::integer AS rating_count
        FROM hocalist.outcome_reviews r WHERE r.seller_profile_id=c.seller_profile_id AND r.status='published'
      ) rep ON true
      WHERE c.seller_user_id <> u
      ORDER BY rating_count DESC,rating_sum DESC,completed_deals DESC,c.seller_profile_id
      LIMIT v_size
    ) t
  ),'[]'::jsonb));
END $$;

-- Replace only the listing eligibility predicate, preserving later chat repairs.
DO $patch$
DECLARE
  definition text := replace(pg_get_functiondef('hocalist.discovery_open_enquiry(text,jsonb)'::regprocedure), chr(13), '');
  old_predicate text := $old$IF NOT EXISTS (
      SELECT 1 FROM hocalist.store_listings l
      WHERE l.seller_user_id = v_seller_user
        AND l.seller_profile_id = (p_input->>'seller_profile_id')::uuid
        AND l.category_id = v_topic
        AND l.status = 'active' AND l.moderation_status = 'approved'
    ) THEN$old$;
  new_predicate text := $new$IF NOT EXISTS (
      SELECT 1 FROM hocalist.discovery_topic_seller_candidates(v_topic) c
      WHERE c.seller_user_id = v_seller_user
        AND c.seller_profile_id = (p_input->>'seller_profile_id')::uuid
    ) THEN$new$;
BEGIN
  old_predicate := replace(old_predicate, chr(13), '');
  new_predicate := replace(new_predicate, chr(13), '');
  IF position(old_predicate IN definition)>0 THEN
    IF (length(definition)-length(replace(definition,old_predicate,'')))/length(old_predicate) <> 1 THEN
      RAISE EXCEPTION 'enquiry eligibility predicate is not unique';
    END IF;
    EXECUTE replace(definition,old_predicate,new_predicate);
  ELSIF position(new_predicate IN definition)=0 THEN
    RAISE EXCEPTION 'enquiry eligibility definition drift';
  END IF;
END $patch$;
NOTIFY pgrst, 'reload schema';
COMMIT;

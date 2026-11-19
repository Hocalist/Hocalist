-- Store is the public source of Hocatrends titles, photos and prices.
BEGIN;
SET LOCAL lock_timeout='5s';

ALTER TABLE hocalist.store_listings
  ADD COLUMN IF NOT EXISTS hocatrends_published boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS source_offer_id uuid REFERENCES hocalist.offers(id);
CREATE UNIQUE INDEX IF NOT EXISTS store_listing_source_offer ON hocalist.store_listings(source_offer_id)
  WHERE source_offer_id IS NOT NULL;

CREATE OR REPLACE FUNCTION hocalist.hocatrends_listing_preference(p_listing uuid,p_enabled boolean DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); l hocalist.store_listings%ROWTYPE; eligible boolean;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u,'seller');
  SELECT * INTO STRICT l FROM hocalist.store_listings WHERE id=p_listing AND seller_user_id=u FOR UPDATE;
  eligible := hocalist.marketplace_seller_plan(u) IN ('pro','elite')
    AND l.status<>'archived' AND jsonb_array_length(l.image_media_ids)>0;
  IF p_enabled IS TRUE AND NOT eligible THEN RAISE EXCEPTION 'hocatrends_not_eligible'; END IF;
  IF p_enabled IS NOT NULL AND p_enabled<>l.hocatrends_published THEN
    UPDATE hocalist.store_listings SET hocatrends_published=p_enabled WHERE id=l.id;
  END IF;
  RETURN jsonb_build_object('listing_id',l.id,'eligible',eligible,'enabled',coalesce(p_enabled,l.hocatrends_published));
END $$;

-- Both operations use the ordinary receipt, billing, ownership and moderation paths.
CREATE OR REPLACE FUNCTION hocalist.hocatrends_submit_store_offer(p_key text,p_offer jsonb,p_listing jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); offer_result jsonb; listing_result jsonb; input jsonb;
  r hocalist.requests%ROWTYPE; listing_images jsonb:=p_listing->'image_media_ids'; price numeric;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u,'seller');
  IF hocalist.marketplace_seller_plan(u) NOT IN ('pro','elite') THEN RAISE EXCEPTION 'hocatrends_not_eligible'; END IF;
  IF jsonb_typeof(listing_images) IS DISTINCT FROM 'array' OR jsonb_typeof(p_offer->'image_media_ids') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid_field: publication_photos' USING ERRCODE='22023';
  END IF;
  IF jsonb_array_length(listing_images) NOT BETWEEN 1 AND 10 OR jsonb_array_length(listing_images)<>jsonb_array_length(p_offer->'image_media_ids')
    OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(listing_images) WITH ORDINALITY x(id,n)
      WHERE NOT EXISTS (SELECT 1 FROM hocalist.media_images s JOIN hocalist.media_images o ON o.content_hash=s.content_hash
        WHERE s.id=x.id::uuid AND o.id=(p_offer->'image_media_ids'->>((x.n-1)::int))::uuid
          AND s.owner_user_id=u AND o.owner_user_id=u AND s.purpose='store' AND o.purpose='offer'
          AND s.state='ready' AND o.state='ready')) THEN
    RAISE EXCEPTION 'invalid_field: publication_photos' USING ERRCODE='22023';
  END IF;
  offer_result := hocalist.marketplace_command('offer.submit',p_key,p_offer);
  SELECT * INTO STRICT r FROM hocalist.requests WHERE id=(p_offer->>'request_id')::uuid;
  price := (p_offer->>'price_minor')::numeric/100;
  input:=jsonb_build_object('kind',r.kind,'title',p_listing->>'title','category_id',r.category_id,
    'price_label',CASE WHEN p_offer->>'currency_code'='USD' THEN '$' ELSE (p_offer->>'currency_code')||' ' END ||
      trim_scale(price)::text, 'image_media_ids',listing_images,'publish_intent','publish');
  IF p_listing ? 'category_answers' THEN input:=input||jsonb_build_object('category_answers',p_listing->'category_answers'); END IF;
  listing_result:=hocalist.marketplace_command('store.create','hc-offer-'||(offer_result->>'id'),input);
  -- Replaying a successful send must not republish a listing its owner later hid.
  UPDATE hocalist.store_listings SET source_offer_id=(offer_result->>'id')::uuid,hocatrends_published=true
    WHERE id=(listing_result->>'id')::uuid AND seller_user_id=u AND source_offer_id IS NULL;
  RETURN offer_result;
END $$;

CREATE OR REPLACE VIEW hocalist.hocatrends_public_listings AS
SELECT l.id,l.title,lower(btrim(l.title)) AS topic_title,l.category_id,c.label AS category_label,
       l.seller_profile_id,l.seller_user_id,l.price_label,l.image_media_ids,l.published_at,l.source_offer_id
FROM hocalist.store_listings l
JOIN hocalist.catalogue_categories c ON c.id=l.category_id AND c.status='active'
JOIN hocalist.memberships m ON m.id=l.seller_profile_id AND m.user_id=l.seller_user_id AND m.role='seller' AND m.status='active'
WHERE l.hocatrends_published AND l.status='active' AND l.moderation_status='approved'
  AND jsonb_array_length(l.image_media_ids)>0 AND hocalist.marketplace_seller_plan(m.user_id) IN ('pro','elite')
  AND NOT EXISTS(SELECT 1 FROM hocalist.memberships b WHERE b.user_id=m.user_id AND b.status IN ('disabled','restricted'));
REVOKE ALL ON hocalist.hocatrends_public_listings FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION hocalist.hocatrends_trends(p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM hocalist.discovery_assert_active_member(auth.uid());
  RETURN (WITH topics AS (
    SELECT category_id, category_label,topic_title,(array_agg(id ORDER BY published_at,id))[1] AS listing_id,
      (array_agg(image_media_ids->>0 ORDER BY published_at,id))[1] AS cover_photo_id,
      CASE WHEN count(DISTINCT price_label)=1 THEN min(price_label) END AS shared_price,
      min(title) AS label,count(*) AS listings,count(DISTINCT seller_profile_id) AS sellers,max(published_at) AS newest
    FROM hocalist.hocatrends_public_listings WHERE seller_user_id<>auth.uid()
    GROUP BY category_id,category_label,topic_title
  ), ranked AS (
    SELECT *,sum(listings) OVER() AS total,row_number() OVER(ORDER BY sellers DESC,newest DESC,listing_id) AS rank FROM topics
  )
  SELECT jsonb_build_object('window_days',0,'open_request_total',0,'items',coalesce(jsonb_agg(jsonb_build_object(
    'rank',rank,'category_id',category_id,'category_label',category_label,'listing_id',listing_id,
    'cover_photo_id',cover_photo_id,'price_label',CASE WHEN btrim(shared_price) ~ '^[0-9]+([.][0-9]{1,2})?$' THEN '$'||btrim(shared_price) ELSE shared_price END,
    'request_id',listing_id,'label',label,'open_requests',0,'competing_sellers',sellers,'available_sellers',sellers,'confirmed_purchases',0,
    'participating_buyers',0,'percent',round(100.0*listings/total),
    'competition',CASE WHEN sellers>=5 THEN 'Very High' WHEN sellers>=3 THEN 'High' ELSE 'Medium' END,
    'activity_copy',category_label||' · '||sellers||CASE WHEN sellers=1 THEN ' seller' ELSE ' sellers' END
  ) ORDER BY rank),'[]'::jsonb)) FROM ranked WHERE rank<=greatest(1,least(coalesce(p_limit,10),100)));
END $$;

CREATE OR REPLACE FUNCTION hocalist.hocatrends_topic_sellers(p_topic uuid,p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM hocalist.discovery_assert_active_member(auth.uid());
  RETURN (WITH topic AS (
    SELECT category_id,topic_title FROM hocalist.hocatrends_public_listings WHERE id=p_topic AND seller_user_id<>auth.uid()
  ), items AS (
    SELECT l.id AS listing_id,l.title AS listing_title,l.seller_profile_id,
      coalesce(nullif(btrim(rp.display_name),''),'Hocalist seller') AS display_name,CASE WHEN coalesce(visibility.show_area,true) THEN rp.area_label END AS area_label,
      CASE WHEN coalesce(visibility.show_business_address,true) AND q.buyer_user_id=auth.uid() AND business.latitude IS NOT NULL AND q.latitude IS NOT NULL THEN
        round(hocalist.discovery_distance_miles(business.latitude,business.longitude,q.latitude,q.longitude)::numeric,1) END AS distance_miles, replies.response_minutes,
      (to_jsonb(rp)->>'image_media_id')::uuid AS avatar_media_id,l.image_media_ids AS offer_image_media_ids,
      CASE WHEN btrim(l.price_label) ~ '^[0-9]+([.][0-9]{1,2})?$' THEN '$'||btrim(l.price_label) ELSE l.price_label END AS price_label,
      CASE WHEN btrim(l.price_label) ~ '^[$]?[0-9]{1,12}([.][0-9]{1,2})?$' THEN
        (replace(btrim(l.price_label),'$','')::numeric*100)::bigint END AS offer_price_minor,
      'USD' AS currency_code,CASE WHEN q.currency_code='USD' THEN coalesce(q.budget_max_minor,q.budget_min_minor) END AS buyer_budget_minor,
      coalesce(rep.rating_sum,0) AS rating_sum,rep.rating_count,
      (SELECT count(*) FROM hocalist.sale_confirmations sc WHERE sc.seller_user_id=l.seller_user_id) AS completed_deals,
      coalesce((SELECT v.status='approved' FROM hocalist.verification_submissions v
        WHERE v.user_id=l.seller_user_id ORDER BY v.created_at DESC,v.id LIMIT 1),false) AS verified
    FROM hocalist.hocatrends_public_listings l JOIN topic t USING(category_id,topic_title)
    LEFT JOIN hocalist.role_profiles rp ON rp.membership_id=l.seller_profile_id
    LEFT JOIN hocalist.offers o ON o.id=l.source_offer_id
    LEFT JOIN hocalist.requests q ON q.id=o.request_id
    LEFT JOIN hocalist.seller_profile_visibility_settings visibility ON visibility.user_id=l.seller_user_id
    LEFT JOIN hocalist.seller_business_addresses business ON business.user_id=l.seller_user_id
    LEFT JOIN LATERAL (
      SELECT CASE WHEN count(*)>=3 THEN greatest(1,ceil(percentile_cont(0.5) WITHIN GROUP(ORDER BY seconds)/60))::integer END AS response_minutes
      FROM (SELECT extract(epoch FROM sent_at-previous_at) AS seconds FROM (
        SELECT sender_user_id,sent_at,lag(sender_user_id) OVER w AS previous_sender,lag(sent_at) OVER w AS previous_at
        FROM hocalist.conversation_messages msg WHERE kind='text' AND sent_at>now()-interval '30 days'
          AND EXISTS(SELECT 1 FROM hocalist.conversation_members cm WHERE cm.conversation_id=msg.conversation_id AND cm.user_id=l.seller_user_id)
        WINDOW w AS (PARTITION BY conversation_id,offer_id,enquiry_id ORDER BY seq)
      ) turns WHERE sender_user_id=l.seller_user_id AND previous_sender<>sender_user_id AND sent_at>=previous_at) samples
    ) replies ON true
    CROSS JOIN LATERAL(SELECT sum(rating)::integer AS rating_sum,count(*)::integer AS rating_count
      FROM hocalist.outcome_reviews rev WHERE rev.seller_profile_id=l.seller_profile_id AND rev.status='published') rep
    WHERE l.seller_user_id<>auth.uid()
    ORDER BY rep.rating_count DESC,l.published_at DESC,l.id LIMIT greatest(1,least(coalesce(p_limit,20),100))
  )
  SELECT jsonb_build_object('topic_id',p_topic,'items',coalesce(jsonb_agg(to_jsonb(items)),'[]'::jsonb)) FROM items);
END $$;
REVOKE ALL ON FUNCTION hocalist.hocatrends_listing_preference(uuid,boolean), hocalist.hocatrends_submit_store_offer(text,jsonb,jsonb),
 hocalist.hocatrends_trends(integer), hocalist.hocatrends_topic_sellers(uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.hocatrends_listing_preference(uuid,boolean), hocalist.hocatrends_submit_store_offer(text,jsonb,jsonb),
 hocalist.hocatrends_trends(integer), hocalist.hocatrends_topic_sellers(uuid,integer) TO authenticated;
-- The gateway already authorizes private offer reads for the original buyer.
-- Public photos now use separately owned Store uploads and its moderation path.
CREATE OR REPLACE FUNCTION hocalist.media_read_hocatrends(p_user uuid,p_image uuid)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path='' AS 'SELECT false';
REVOKE ALL ON FUNCTION hocalist.media_read_hocatrends(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

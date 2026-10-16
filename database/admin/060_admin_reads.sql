-- Additive administrator-only read contracts. No writes or provider activation.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$
BEGIN
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL
     OR to_regclass('hocalist.stripe_test_subscriptions') IS NULL THEN
    RAISE EXCEPTION 'Admin reads require account, marketplace and TEST billing foundations';
  END IF;
  IF to_regprocedure('hocalist.admin_records(text,integer,uuid,text,text)') IS NOT NULL
     OR to_regprocedure('hocalist.admin_overview()') IS NOT NULL THEN
    RAISE EXCEPTION 'Admin read objects already exist; review before replacement';
  END IF;
END $guard$;

CREATE FUNCTION hocalist.admin_records(
  p_resource text, p_limit integer DEFAULT 50, p_cursor uuid DEFAULT NULL,
  p_query text DEFAULT NULL, p_status text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_rows jsonb; v_more boolean; v_cursor uuid;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF p_resource IS NULL OR p_resource NOT IN ('users','requests','offers','billing')
     OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
     OR length(coalesce(p_query,'')) > 100 OR length(coalesce(p_status,'')) > 40 THEN
    RAISE EXCEPTION 'invalid_admin_query' USING ERRCODE='22023';
  END IF;
  -- Static projections: no Auth email, contact address, message, token,
  -- payment-method detail, customer key, or checkout URL is exposed.
  WITH records AS (
    SELECT m.id, m.status, jsonb_build_array(m.id::text,
      coalesce(r.display_name,'Profile pending'), m.role, m.status,
      coalesce(r.area_label,''), m.created_at::text) AS cells
    FROM hocalist.memberships m LEFT JOIN hocalist.role_profiles r ON r.membership_id=m.id
    WHERE p_resource='users'
    UNION ALL
    SELECT r.id,r.status,jsonb_build_array(r.id::text,r.title,r.buyer_profile_id::text,
      coalesce(c.label,''),r.status,r.created_at::text)
    FROM hocalist.requests r LEFT JOIN hocalist.catalogue_categories c ON c.id=r.category_id
    WHERE p_resource='requests'
    UNION ALL
    SELECT o.id,o.status,jsonb_build_array(o.id::text,o.request_id::text,o.seller_profile_id::text,
      CASE WHEN v.id IS NULL THEN '' ELSE v.currency_code||' '||v.price_minor::text||' minor units' END,
      o.status,o.updated_at::text)
    FROM hocalist.offers o LEFT JOIN LATERAL (
      SELECT x.id,x.price_minor,x.currency_code FROM hocalist.offer_revisions x
      WHERE x.offer_id=o.id AND (o.accepted_revision_id IS NULL OR x.id=o.accepted_revision_id)
      ORDER BY x.sequence DESC LIMIT 1
    ) v ON true WHERE p_resource='offers'
    UNION ALL
    SELECT s.membership_id,s.provider_status,jsonb_build_array(s.membership_id::text,
      coalesce(s.plan_code,''),s.provider_status,coalesce(s.paid_until::text,''),
      CASE WHEN s.cancel_at_period_end THEN 'Cancels at period end' ELSE 'Renewal allowed' END,
      CASE WHEN s.requires_review THEN 'Needs review' ELSE 'No review flag' END)
    FROM hocalist.stripe_test_subscriptions s WHERE p_resource='billing'
  ), windowed AS (
    SELECT id,cells FROM records WHERE (p_cursor IS NULL OR id>p_cursor)
      AND (nullif(p_status,'') IS NULL OR status=p_status)
      AND (nullif(p_query,'') IS NULL OR strpos(lower(cells::text),lower(p_query))>0)
    ORDER BY id LIMIT p_limit+1
  ), visible AS (SELECT * FROM windowed ORDER BY id LIMIT p_limit)
  SELECT coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'cells',cells) ORDER BY id) FROM visible),'[]'::jsonb),
    (SELECT count(*)>p_limit FROM windowed), (SELECT id FROM visible ORDER BY id DESC LIMIT 1)
    INTO v_rows,v_more,v_cursor;
  RETURN jsonb_build_object('items',v_rows,'next_cursor',CASE WHEN v_more THEN v_cursor ELSE NULL END);
END $$;

CREATE FUNCTION hocalist.admin_overview()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  RETURN jsonb_build_object(
    'active_memberships',(SELECT count(*) FROM hocalist.memberships WHERE status='active'),
    'open_requests',(SELECT count(*) FROM hocalist.requests WHERE status='active'),
    'submitted_offers',(SELECT count(*) FROM hocalist.offers WHERE status='submitted'),
    'listings_in_review',(SELECT count(*) FROM hocalist.store_listings WHERE moderation_status='pending_review'),
    'test_subscriptions',(SELECT count(*) FROM hocalist.stripe_test_subscriptions));
END $$;

REVOKE ALL ON FUNCTION hocalist.admin_records(text,integer,uuid,text,text),hocalist.admin_overview()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_records(text,integer,uuid,text,text),hocalist.admin_overview()
  TO authenticated;
COMMIT;

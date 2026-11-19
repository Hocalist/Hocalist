-- Confirmed customers are saved privately by the seller; insights are factual,
-- not a predicted probability. No Auth contact data or buyer address is exposed.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE IF NOT EXISTS hocalist.seller_saved_customers (
  seller_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  buyer_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  saved boolean NOT NULL DEFAULT true,
  note text NOT NULL DEFAULT '' CHECK (length(note)<=2000),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(seller_user_id,buyer_user_id)
);
ALTER TABLE hocalist.seller_saved_customers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE hocalist.seller_saved_customers FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION hocalist.seller_customer_save(p_buyer uuid,p_saved boolean,p_note text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();
BEGIN
  PERFORM hocalist.marketplace_assert_role(u,'seller');
  IF hocalist.marketplace_seller_plan(u) NOT IN ('pro','elite') THEN
    RAISE EXCEPTION 'contacts_plan_required' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE seller_user_id=u AND buyer_user_id=p_buyer) THEN
    RAISE EXCEPTION 'confirmed_customer_required' USING ERRCODE='42501';
  END IF;
  IF p_saved IS NULL OR p_note IS NULL OR length(p_note)>2000 THEN
    RAISE EXCEPTION 'invalid_customer_note' USING ERRCODE='22023';
  END IF;
  INSERT INTO hocalist.seller_saved_customers(seller_user_id,buyer_user_id,saved,note)
    VALUES(u,p_buyer,p_saved,p_note)
    ON CONFLICT(seller_user_id,buyer_user_id) DO UPDATE SET saved=EXCLUDED.saved,note=EXCLUDED.note,updated_at=now();
  RETURN jsonb_build_object('buyer_id',p_buyer,'saved',p_saved,'note',p_note);
END $$;

CREATE OR REPLACE FUNCTION hocalist.seller_customers()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); plan text;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u,'seller');
  plan:=hocalist.marketplace_seller_plan(u);
  IF plan NOT IN ('pro','elite') THEN RAISE EXCEPTION 'contacts_plan_required' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('insights_available',plan='elite','items',coalesce((
    SELECT jsonb_agg(to_jsonb(item) ORDER BY item.last_purchase_at DESC,item.buyer_id) FROM (
      SELECT sales.buyer_user_id AS buyer_id,
        coalesce(nullif(btrim(rp.display_name),''),'Hocalist buyer') AS display_name,
        sales.purchase_count,sales.last_purchase_at,
        coalesce(saved.saved,false) AS saved,coalesce(saved.note,'') AS note
      FROM (SELECT buyer_user_id,count(*)::integer AS purchase_count,max(confirmed_at) AS last_purchase_at
        FROM hocalist.sale_confirmations WHERE seller_user_id=u GROUP BY buyer_user_id) sales
      LEFT JOIN hocalist.memberships m ON m.user_id=sales.buyer_user_id AND m.role='buyer'
      LEFT JOIN hocalist.role_profiles rp ON rp.membership_id=m.id
      LEFT JOIN hocalist.seller_saved_customers saved ON saved.seller_user_id=u AND saved.buyer_user_id=sales.buyer_user_id
    ) item
  ),'[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION hocalist.seller_customer_insights(p_buyer uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); ended integer; purchases integer; ongoing integer;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u,'seller');
  IF hocalist.marketplace_seller_plan(u)<>'elite' THEN RAISE EXCEPTION 'insights_plan_required' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM hocalist.offers WHERE seller_user_id=u AND buyer_user_id=p_buyer)
    AND NOT EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE seller_user_id=u AND buyer_user_id=p_buyer) THEN
    RAISE EXCEPTION 'customer_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT count(*) FILTER(WHERE r.status IN ('closed','cancelled','expired') OR sale.request_id IS NOT NULL)::integer,
    count(*) FILTER(WHERE sale.request_id IS NOT NULL)::integer,
    count(*) FILTER(WHERE r.status='active' AND sale.request_id IS NULL)::integer
  INTO ended,purchases,ongoing FROM hocalist.requests r
  LEFT JOIN (SELECT DISTINCT request_id FROM hocalist.sale_confirmations WHERE buyer_user_id=p_buyer) sale ON sale.request_id=r.id
  WHERE r.buyer_user_id=p_buyer;
  RETURN jsonb_build_object('buyer_id',p_buyer,'concluded_requests',ended,'confirmed_purchases',purchases,
    'ongoing_requests',ongoing,'completion_percent',CASE WHEN ended>0 THEN round(purchases*100.0/ended,1) ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION hocalist.seller_customer_save(uuid,boolean,text),hocalist.seller_customers(),hocalist.seller_customer_insights(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.seller_customer_save(uuid,boolean,text),hocalist.seller_customers(),hocalist.seller_customer_insights(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

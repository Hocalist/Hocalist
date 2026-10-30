-- Allow qualified, deferred Elite deals without collecting early. Existing access/privacy checks remain.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE OR REPLACE FUNCTION hocalist.credit_view_competing_offers(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); t hocalist.credit_targets%ROWTYPE;
BEGIN
 IF u IS NULL OR hocalist.marketplace_seller_plan(u)<>'elite'
 OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='seller' AND status='active')
 OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
 END IF;
 PERFORM 1 FROM hocalist.profiles WHERE id=u FOR UPDATE;
 SELECT x.* INTO t FROM hocalist.credit_targets x JOIN hocalist.offers o ON o.id=x.offer_id
 WHERE x.user_id=u AND x.request_id=p_request AND x.policy_plan='elite'
 AND (x.status='initial_charged' OR (x.elite_deferred_initial AND x.status='reserved' AND x.qualified_at IS NOT NULL)) AND o.status='selected' AND o.accepted_revision_id IS NOT NULL FOR UPDATE OF x;
 IF NOT FOUND THEN RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501'; END IF;
 UPDATE hocalist.credit_targets SET competitors_viewed_at=coalesce(competitors_viewed_at,now()) WHERE id=t.id;
 RETURN jsonb_build_object('refund_eligible',false,'offers',coalesce((SELECT jsonb_agg(jsonb_build_object(
  'price_minor',r.price_minor,'currency_code',r.currency_code) ORDER BY o.created_at,o.id)
  FROM hocalist.offers o JOIN LATERAL (SELECT price_minor,currency_code FROM hocalist.offer_revisions
    WHERE offer_id=o.id ORDER BY sequence DESC LIMIT 1) r ON true
  WHERE o.request_id=p_request AND o.seller_user_id<>u AND o.status IN ('submitted','selected')),'[]'::jsonb));
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;

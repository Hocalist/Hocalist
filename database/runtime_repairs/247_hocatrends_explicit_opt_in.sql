-- Owner decision: Pro/Elite sellers explicitly opt each offered item into Hocatrends.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $guard$ BEGIN
  IF to_regprocedure('hocalist.discovery_topic_seller_candidates(uuid)') IS NULL OR
     position('discovery_topic_seller_candidates' IN pg_get_functiondef('hocalist.discovery_open_enquiry(text,jsonb)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'Hocatrends shared eligibility prerequisite missing';
  END IF;
END $guard$;
ALTER TABLE hocalist.offers ADD COLUMN IF NOT EXISTS hocatrends_opt_in boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION hocalist.hocatrends_offer_preference(p_offer uuid, p_enabled boolean DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE u uuid := auth.uid(); item hocalist.offers%ROWTYPE; eligible boolean;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u,'seller');
  SELECT * INTO item FROM hocalist.offers WHERE id=p_offer AND seller_user_id=u FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501'; END IF;
  eligible := hocalist.marketplace_seller_plan(u) IN ('pro','elite')
    AND item.status IN ('submitted','selected','completed')
    AND item.created_at > now()-interval '30 days';
  IF p_enabled IS TRUE AND NOT eligible THEN
    RAISE EXCEPTION 'hocatrends_not_eligible' USING ERRCODE='P0001';
  END IF;
  IF p_enabled IS NOT NULL THEN
    UPDATE hocalist.offers SET hocatrends_opt_in=p_enabled WHERE id=item.id;
    item.hocatrends_opt_in:=p_enabled;
  END IF;
  RETURN jsonb_build_object('offer_id',item.id,'enabled',item.hocatrends_opt_in,'eligible',eligible);
END $$;
REVOKE ALL ON FUNCTION hocalist.hocatrends_offer_preference(uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.hocatrends_offer_preference(uuid,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION hocalist.discovery_topic_seller_candidates(p_topic uuid)
RETURNS TABLE(seller_profile_id uuid, seller_user_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT m.id,m.user_id FROM hocalist.memberships m
  WHERE m.role='seller' AND m.status='active'
    AND hocalist.marketplace_seller_plan(m.user_id) IN ('pro','elite')
    AND NOT EXISTS (SELECT 1 FROM hocalist.memberships blocked
      WHERE blocked.user_id=m.user_id AND blocked.status IN ('restricted','disabled'))
    AND EXISTS (SELECT 1 FROM hocalist.offers o JOIN hocalist.requests r ON r.id=o.request_id
      WHERE o.seller_profile_id=m.id AND o.seller_user_id=m.user_id
        AND r.category_id=p_topic AND o.hocatrends_opt_in
        AND o.status IN ('submitted','selected','completed')
        AND o.created_at > now()-interval '30 days');
$$;
REVOKE ALL ON FUNCTION hocalist.discovery_topic_seller_candidates(uuid) FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst, 'reload schema';
COMMIT;

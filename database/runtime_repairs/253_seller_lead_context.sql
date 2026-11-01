-- NOT DEPLOYED: live discovery projection already contains newer context fields. See LOCAL_CHANGELOG.
-- Complete seller-safe request context without changing request authorization.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
CREATE OR REPLACE FUNCTION hocalist.marketplace_lead_context(p_request uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT jsonb_build_object(
   'area_label', CASE WHEN r.use_home_address THEN
     coalesce(nullif(btrim(r.city),''),nullif(btrim(r.region),''),nullif(btrim(pc.city),''),nullif(btrim(pc.region),''),nullif(btrim(rp.area_label),''))
     ELSE coalesce(nullif(btrim(r.city),''),nullif(btrim(r.region),''),nullif(btrim(rp.area_label),'')) END,
   'preferred_meetup_label', nullif(btrim(rp.preferred_meetup_type),''),
   'last_completed_item_label', (
     SELECT to_char(max(s.confirmed_at) AT TIME ZONE 'UTC','Mon DD, YYYY') FROM hocalist.sale_confirmations s
     WHERE s.buyer_user_id=r.buyer_user_id),
   'distance_miles', CASE WHEN r.latitude IS NOT NULL AND r.longitude IS NOT NULL
     AND origin.latitude IS NOT NULL AND origin.longitude IS NOT NULL
     THEN hocalist.discovery_distance_miles(origin.latitude,origin.longitude,r.latitude,r.longitude) END)
 FROM hocalist.requests r
 LEFT JOIN hocalist.role_profiles rp ON rp.membership_id=r.buyer_profile_id
 LEFT JOIN hocalist.profile_contacts pc ON pc.user_id=r.buyer_user_id
 LEFT JOIN hocalist.seller_discovery_origins origin ON origin.seller_user_id=auth.uid()
 WHERE r.id=p_request;
$$;
REVOKE ALL ON FUNCTION hocalist.marketplace_lead_context(uuid) FROM PUBLIC,anon,authenticated,service_role;
-- Extend existing projections, retaining additive fields and access controls.
DO $patch$
DECLARE signature text; definition text; marker text := E'\n  FROM hocalist.requests r'; addition text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['hocalist.marketplace_lead_json(uuid)',
 'hocalist.discovery_lead_json(uuid,double precision,integer,jsonb)'] LOOP
   definition := replace(pg_get_functiondef(signature::regprocedure),chr(13),'');
   IF position('hocalist.marketplace_lead_context(r.id)' IN definition)>0 THEN CONTINUE; END IF;
   IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
     RAISE EXCEPTION 'Lead context projection drift: %', signature;
   END IF;
   addition := ' || hocalist.marketplace_lead_context(r.id)';
   IF signature LIKE 'hocalist.discovery_lead_json%' THEN
     addition := ' || (hocalist.marketplace_lead_context(r.id) - ''distance_miles'')';
   END IF;
   EXECUTE replace(definition,marker,addition || marker);
 END LOOP;
END $patch$;
NOTIFY pgrst,'reload schema';
COMMIT;


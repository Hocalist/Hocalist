-- Shared seller business location. Exact address remains owner-only.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $guard$ BEGIN
 IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='hocalist.business_address(jsonb,text)'::regprocedure) IS DISTINCT FROM '84aa67ef2ec472b0c7b1a0ea4ca05770' THEN
 RAISE EXCEPTION 'Business address prerequisite drift'; END IF;
END $guard$;
ALTER TABLE hocalist.seller_business_addresses ADD COLUMN latitude double precision,
 ADD COLUMN longitude double precision,
 ADD CONSTRAINT business_coordinates_valid CHECK ((latitude IS NULL AND longitude IS NULL) OR
 (latitude IS NOT NULL AND longitude IS NOT NULL AND latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180));
CREATE OR REPLACE FUNCTION hocalist.business_address(p_input jsonb DEFAULT NULL,p_key text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r hocalist.seller_business_addresses%ROWTYPE; member hocalist.memberships%ROWTYPE;
BEGIN
 SELECT * INTO member FROM hocalist.memberships WHERE user_id=auth.uid() AND role='seller' FOR UPDATE;
 IF NOT FOUND OR member.status<>'active' THEN
  RAISE EXCEPTION 'address_access_denied' USING ERRCODE='42501';
 END IF;
 INSERT INTO hocalist.seller_business_addresses(user_id) VALUES(auth.uid()) ON CONFLICT DO NOTHING;
 SELECT * INTO r FROM hocalist.seller_business_addresses WHERE user_id=auth.uid() FOR UPDATE;
 IF p_input IS NOT NULL THEN
  IF p_key IS NULL OR length(p_key) NOT BETWEEN 1 AND 200 OR jsonb_typeof(p_input)<>'object' OR EXISTS(
   SELECT 1 FROM jsonb_object_keys(p_input) k WHERE k NOT IN('expected_revision','address_line1','address_line2','city','region','postal_code','country_code','latitude','longitude')) THEN
   RAISE EXCEPTION 'invalid_address';
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_each(p_input) e WHERE e.key NOT IN('expected_revision','latitude','longitude')
    AND jsonb_typeof(e.value) NOT IN('string','null')) THEN RAISE EXCEPTION 'invalid_address'; END IF;
  IF (p_input ? 'latitude') <> (p_input ? 'longitude') OR
    EXISTS(SELECT 1 FROM jsonb_each(p_input) e WHERE e.key IN('latitude','longitude') AND jsonb_typeof(e.value) NOT IN('number','null')) THEN
    RAISE EXCEPTION 'invalid_coordinates'; END IF;
  IF r.last_key=p_key THEN
   IF r.last_input IS DISTINCT FROM p_input THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
  ELSE
   IF (p_input->>'expected_revision')::bigint IS DISTINCT FROM r.revision THEN RAISE EXCEPTION 'revision_conflict'; END IF;
   UPDATE hocalist.seller_business_addresses SET
    address_line1=CASE WHEN p_input?'address_line1' THEN nullif(btrim(p_input->>'address_line1'),'') ELSE r.address_line1 END,
    address_line2=CASE WHEN p_input?'address_line2' THEN nullif(btrim(p_input->>'address_line2'),'') ELSE r.address_line2 END,
    city=CASE WHEN p_input?'city' THEN nullif(btrim(p_input->>'city'),'') ELSE r.city END,
    region=CASE WHEN p_input?'region' THEN nullif(btrim(p_input->>'region'),'') ELSE r.region END,
    postal_code=CASE WHEN p_input?'postal_code' THEN nullif(btrim(p_input->>'postal_code'),'') ELSE r.postal_code END,
    country_code=CASE WHEN p_input?'country_code' THEN nullif(upper(btrim(p_input->>'country_code')),'') ELSE r.country_code END,
    latitude=CASE WHEN p_input?'latitude' THEN (p_input->>'latitude')::double precision ELSE NULL END,
    longitude=CASE WHEN p_input?'longitude' THEN (p_input->>'longitude')::double precision ELSE NULL END,
    revision=r.revision+1,updated_at=now(),last_key=p_key,last_input=p_input
   WHERE user_id=auth.uid() RETURNING * INTO r;
  END IF;
 END IF;
 RETURN to_jsonb(r)-'last_key'-'last_input';
END $$;

CREATE FUNCTION hocalist.sync_business_location() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m uuid; area text; radius integer;
BEGIN
 SELECT id INTO m FROM hocalist.memberships WHERE user_id=NEW.user_id AND role='seller';
 IF m IS NULL THEN RETURN NEW; END IF;
 area:=coalesce(nullif(btrim(NEW.city),''),nullif(btrim(NEW.region),''));
 UPDATE hocalist.role_profiles SET area_label=area,revision=revision+1,updated_at=now()
 WHERE membership_id=m AND area_label IS DISTINCT FROM area;
 SELECT greatest(1,least(coalesce(service_radius_miles,25),500)) INTO radius FROM hocalist.role_profiles WHERE membership_id=m;
 INSERT INTO hocalist.seller_discovery_origins(seller_user_id,seller_profile_id,area_label,latitude,longitude,radius_miles)
 VALUES(NEW.user_id,m,area,NEW.latitude,NEW.longitude,coalesce(radius,25))
 ON CONFLICT(seller_user_id) DO UPDATE SET area_label=excluded.area_label,
 latitude=excluded.latitude,longitude=excluded.longitude,radius_miles=excluded.radius_miles,
 revision=hocalist.seller_discovery_origins.revision+1,updated_at=now()
 WHERE coalesce(current_setting('hocalist.location_backfill',true),'off') <> 'on'
    OR hocalist.seller_discovery_origins.latitude IS NULL;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION hocalist.sync_business_location() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER sync_business_location AFTER INSERT OR UPDATE ON hocalist.seller_business_addresses
 FOR EACH ROW EXECUTE FUNCTION hocalist.sync_business_location();
CREATE FUNCTION hocalist.sync_seller_service_radius() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.service_radius_miles IS DISTINCT FROM OLD.service_radius_miles THEN
  UPDATE hocalist.seller_discovery_origins SET radius_miles=greatest(1,least(coalesce(NEW.service_radius_miles,25),500)),
  revision=revision+1,updated_at=now() WHERE seller_profile_id=NEW.membership_id;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION hocalist.sync_seller_service_radius() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER sync_seller_service_radius AFTER UPDATE ON hocalist.role_profiles
 FOR EACH ROW EXECUTE FUNCTION hocalist.sync_seller_service_radius();
-- Existing addresses immediately provide an approximate area; coordinates are
-- resolved through the existing Places service when their owner opens the app.
SELECT set_config('hocalist.location_backfill','on',true);
UPDATE hocalist.seller_business_addresses SET updated_at=updated_at;
NOTIFY pgrst,'reload schema';
COMMIT;


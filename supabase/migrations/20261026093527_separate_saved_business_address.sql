BEGIN;
SET LOCAL lock_timeout='5s';
CREATE TABLE hocalist.seller_business_addresses (
 user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
 address_line1 text CHECK(length(address_line1)<=300), address_line2 text CHECK(length(address_line2)<=300),
 city text CHECK(length(city)<=150), region text CHECK(length(region)<=150),
 postal_code text CHECK(length(postal_code)<=40), country_code text CHECK(country_code ~ '^[A-Z]{2}$'),
 revision bigint NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 last_key text, last_input jsonb
);
ALTER TABLE hocalist.seller_business_addresses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.seller_business_addresses FROM PUBLIC,anon,authenticated,service_role;
-- Preserve the address formerly entered through the business-labelled editor.
INSERT INTO hocalist.seller_business_addresses(user_id,address_line1,address_line2,city,region,postal_code,country_code)
 SELECT c.user_id,c.address_line1,c.address_line2,c.city,c.region,c.postal_code,c.country_code
 FROM hocalist.profile_contacts c WHERE EXISTS(
  SELECT 1 FROM hocalist.memberships r WHERE r.user_id=c.user_id AND r.role='seller');
CREATE FUNCTION hocalist.business_address(p_input jsonb DEFAULT NULL,p_key text DEFAULT NULL) RETURNS jsonb
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
   SELECT 1 FROM jsonb_object_keys(p_input) k WHERE k NOT IN('expected_revision','address_line1','address_line2','city','region','postal_code','country_code')) THEN
   RAISE EXCEPTION 'invalid_address';
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_each(p_input) e WHERE e.key<>'expected_revision'
    AND jsonb_typeof(e.value) NOT IN('string','null')) THEN RAISE EXCEPTION 'invalid_address'; END IF;
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
    revision=r.revision+1,updated_at=now(),last_key=p_key,last_input=p_input
   WHERE user_id=auth.uid() RETURNING * INTO r;
  END IF;
 END IF;
 RETURN to_jsonb(r)-'last_key'-'last_input';
END $$;
REVOKE ALL ON FUNCTION hocalist.business_address(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.business_address(jsonb,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

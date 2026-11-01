-- Read-only deployment checks; no user addresses or coordinates are returned.
SELECT name, to_regprocedure(name) IS NOT NULL AS present
FROM (VALUES ('hocalist.marketplace_lead_json(uuid)'),
 ('hocalist.discovery_lead_json(uuid,double precision,integer,jsonb)'),
 ('hocalist.business_address(jsonb,text)'),
 ('hocalist.marketplace_normalize_request(jsonb)')) AS signatures(name);
SELECT md5(replace(prosrc,chr(13),'')) AS business_address_definition
FROM pg_proc WHERE oid=to_regprocedure('hocalist.business_address(jsonb,text)');
SELECT count(*) AS business_addresses,
 count(*) FILTER(WHERE nullif(btrim(city),'') IS NOT NULL) AS addresses_with_city
FROM hocalist.seller_business_addresses;

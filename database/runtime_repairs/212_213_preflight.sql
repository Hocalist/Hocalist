-- Read-only prerequisite inventory. Never prints credentials or user records.
SELECT to_regclass('hocalist.native_billing_receipts') IS NULL AS native_receipts_not_installed,
 NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist'
  AND table_name='requests' AND column_name='image_media_ids') AS request_photos_not_installed;
SELECT signature, p.oid IS NOT NULL AS installed, p.prosecdef AS security_definer,
 p.proconfig, md5(replace(p.prosrc,chr(13),'')) AS source_digest
FROM (VALUES
 ('hocalist.marketplace_normalize_request(jsonb)'),
 ('hocalist.marketplace_command(text,text,jsonb)'),
 ('hocalist.marketplace_request_json(uuid)'),
 ('hocalist.marketplace_lead_json(uuid)'),
 ('hocalist.discovery_lead_json(uuid,double precision,integer,jsonb)'),
 ('hocalist.marketplace_request(uuid)'),
 ('hocalist.marketplace_assert_role(uuid,text)'),
 ('hocalist.media_gateway(uuid,text,jsonb)')
) AS expected(signature) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(signature);
SELECT conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint
WHERE conrelid='hocalist.media_images'::regclass AND conname='media_images_purpose_check';

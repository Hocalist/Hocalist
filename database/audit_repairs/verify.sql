-- Read-only exact-body and access verification.
DO $verify$
DECLARE item record;
BEGIN
 FOR item IN SELECT * FROM (VALUES
    ('hocalist.marketplace_request(uuid)','51efa3d9f195d455007d9367c9ca10c3'),
    ('hocalist.marketplace_offer_json(uuid)','c1c75ad309e343bef0a88b67f1558617'),
    ('hocalist.marketplace_lead_json(uuid)','1bff944a220727b9cfa4ecf1f800f369'),
    ('hocalist.commercial_deal_summary()','b03aaf562a3ecaad1668fc8b077d0894'),
    ('hocalist.public_store(uuid)','835a68879c14c720b7e8ea46e909c0d2')
 ) AS functions(signature,hash) LOOP
  IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid=to_regprocedure(item.signature)) IS DISTINCT FROM item.hash THEN
   RAISE EXCEPTION 'Audit repair verification drift: %',item.signature;
  END IF;
 END LOOP;
 IF has_function_privilege('anon','hocalist.commercial_deal_summary()','EXECUTE') OR
    NOT has_function_privilege('authenticated','hocalist.commercial_deal_summary()','EXECUTE') OR
    NOT has_function_privilege('anon','hocalist.public_store(uuid)','EXECUTE') OR
    has_function_privilege('anon','hocalist.marketplace_request(uuid)','EXECUTE') OR
    has_function_privilege('authenticated','hocalist.marketplace_offer_json(uuid)','EXECUTE') OR
    has_function_privilege('anon','hocalist.marketplace_lead_json(uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'Audit repair grant drift';
 END IF;
END $verify$;

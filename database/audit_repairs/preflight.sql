-- Read-only prerequisite checks; no user records are changed.
DO $guard$
DECLARE item record;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('hocalist.marketplace_request(uuid)', 'edb014a6987ac4f669845c43bd0276e7'),
    ('hocalist.marketplace_offer_json(uuid)', '8e8e44b15f9012a0579c97f438f1af91'),
    ('hocalist.marketplace_lead_json(uuid)', '2a60bdd929941d7e0e522191f4c3cf71')
  ) AS functions(signature, hash) LOOP
    IF to_regprocedure(item.signature) IS NULL OR
       (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid=to_regprocedure(item.signature)) IS DISTINCT FROM item.hash THEN
      RAISE EXCEPTION 'Audit prerequisite drift: %',item.signature;
    END IF;
  END LOOP;
  IF to_regprocedure('hocalist.chat_assert_participant(uuid,uuid)') IS NULL OR
     to_regclass('hocalist.sale_confirmations') IS NULL THEN
    RAISE EXCEPTION 'Audit repairs require reviewed chat and sale confirmations';
  END IF;
END $guard$;

BEGIN READ ONLY;
DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)')
    AND md5(replace(p.prosrc,E'\r\n',E'\n'))='fca41fb639dc7be3dfc9d760e31ba5da' AND p.prosecdef
    AND p.proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Credit subscription definition drift: stripe_test_deposit_begin'; END IF;
  IF has_function_privilege('anon','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)') AND a.grantee=0)
    OR NOT has_function_privilege('service_role','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Credit subscription privilege drift: stripe_test_deposit_begin'; END IF;
END; $guard$;
DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('hocalist.website_purchase_status(uuid)')
    AND md5(replace(p.prosrc,E'\r\n',E'\n'))='4485d9a51716e2cf97dcd57e29774ec6' AND p.prosecdef
    AND p.proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Credit subscription definition drift: website_purchase_status'; END IF;
  IF has_function_privilege('anon','hocalist.website_purchase_status(uuid)','EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.website_purchase_status(uuid)') AND a.grantee=0)
    OR NOT has_function_privilege('authenticated','hocalist.website_purchase_status(uuid)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.website_purchase_status(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Credit subscription privilege drift: website_purchase_status'; END IF;
END; $guard$;
ROLLBACK;

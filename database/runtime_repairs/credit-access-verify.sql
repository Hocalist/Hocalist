BEGIN READ ONLY;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)') AND md5(replace(prosrc,E'\r\n',E'\n'))='106b32e6f04a41980c9216fd42298c2f' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Credit access definition drift: stripe_test_deposit_begin'; END IF;
 IF has_function_privilege('anon','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE') OR has_function_privilege('authenticated','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE') OR NOT has_function_privilege('service_role','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE') OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(p.proacl) a WHERE p.oid=to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)') AND a.grantee=0) THEN RAISE EXCEPTION 'Credit access privilege drift'; END IF;
END $guard$;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.website_purchase_status(uuid)') AND md5(replace(prosrc,E'\r\n',E'\n'))='4df64adccebebc55c30f77087ead853f' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Credit access definition drift: website_purchase_status'; END IF;
 IF has_function_privilege('anon','hocalist.website_purchase_status(uuid)','EXECUTE') OR has_function_privilege('service_role','hocalist.website_purchase_status(uuid)','EXECUTE') OR NOT has_function_privilege('authenticated','hocalist.website_purchase_status(uuid)','EXECUTE') OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(p.proacl) a WHERE p.oid=to_regprocedure('hocalist.website_purchase_status(uuid)') AND a.grantee=0) THEN RAISE EXCEPTION 'Credit access privilege drift'; END IF;
END $guard$;
ROLLBACK;

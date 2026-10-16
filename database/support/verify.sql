BEGIN READ ONLY;
DO $verify$ DECLARE t text;r text;p text;BEGIN
IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='hocalist.support_assert_user()'::regprocedure AND prosecdef AND proconfig=ARRAY['search_path=""']::text[]) IS DISTINCT FROM 'f1bcfdd50812fee2328581518fcc074d' THEN RAISE EXCEPTION 'Support function mismatch: support_assert_user'; END IF;
IF has_function_privilege('anon','hocalist.support_assert_user()','EXECUTE') OR has_function_privilege('service_role','hocalist.support_assert_user()','EXECUTE') OR has_function_privilege('authenticated','hocalist.support_assert_user()','EXECUTE') IS DISTINCT FROM false THEN RAISE EXCEPTION 'Support function grants changed'; END IF;
IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='hocalist.support_reasons(boolean)'::regprocedure AND prosecdef AND proconfig=ARRAY['search_path=""']::text[]) IS DISTINCT FROM '26834ed4dcde51e79689bd560aab4c7b' THEN RAISE EXCEPTION 'Support function mismatch: support_reasons'; END IF;
IF has_function_privilege('anon','hocalist.support_reasons(boolean)','EXECUTE') OR has_function_privilege('service_role','hocalist.support_reasons(boolean)','EXECUTE') OR has_function_privilege('authenticated','hocalist.support_reasons(boolean)','EXECUTE') IS DISTINCT FROM true THEN RAISE EXCEPTION 'Support function grants changed'; END IF;
IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='hocalist.support_list(integer,uuid,boolean)'::regprocedure AND prosecdef AND proconfig=ARRAY['search_path=""']::text[]) IS DISTINCT FROM 'f9efdfad08485539d72458e9a0e69c10' THEN RAISE EXCEPTION 'Support function mismatch: support_list'; END IF;
IF has_function_privilege('anon','hocalist.support_list(integer,uuid,boolean)','EXECUTE') OR has_function_privilege('service_role','hocalist.support_list(integer,uuid,boolean)','EXECUTE') OR has_function_privilege('authenticated','hocalist.support_list(integer,uuid,boolean)','EXECUTE') IS DISTINCT FROM true THEN RAISE EXCEPTION 'Support function grants changed'; END IF;
IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='hocalist.support_command(text,text,jsonb)'::regprocedure AND prosecdef AND proconfig=ARRAY['search_path=""']::text[]) IS DISTINCT FROM 'fbbe97f57c9d31179c58d735b48acdb5' THEN RAISE EXCEPTION 'Support function mismatch: support_command'; END IF;
IF has_function_privilege('anon','hocalist.support_command(text,text,jsonb)','EXECUTE') OR has_function_privilege('service_role','hocalist.support_command(text,text,jsonb)','EXECUTE') OR has_function_privilege('authenticated','hocalist.support_command(text,text,jsonb)','EXECUTE') IS DISTINCT FROM true THEN RAISE EXCEPTION 'Support function grants changed'; END IF;

FOREACH t IN ARRAY ARRAY['support_reasons','support_cases','support_receipts','support_case_events'] LOOP
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=('hocalist.'||t)::regclass AND relrowsecurity) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=('hocalist.'||t)::regclass) THEN RAISE EXCEPTION 'Support table policy changed'; END IF;
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
 FOREACH p IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
 IF has_table_privilege(r,'hocalist.'||t,p) THEN RAISE EXCEPTION 'Support table exposed'; END IF;
 END LOOP;END LOOP;
END LOOP;
END; $verify$;
SELECT 'support verification passed' AS result;
COMMIT;

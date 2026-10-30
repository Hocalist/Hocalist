BEGIN READ ONLY;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)') AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('24d389f71f1c65d3e1a58202e51bd33f') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Pair chat definition drift: chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)') AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('9c4923568a5e5de6e82440b3f797df44') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Pair chat definition drift: meeting_propose(uuid,jsonb,text)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=to_regprocedure('hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)') AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Pair chat helper grants drift'; END IF;
 IF to_regprocedure('hocalist.chat_deals(uuid)') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.chat_deals(uuid)') AND md5(replace(prosrc,E'\r\n',E'\n'))='f14da1d9a8721f0445a146fe5fe1b59b' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Pair chat read drift'; END IF;
 IF to_regprocedure('hocalist.chat_deals(uuid)') IS NULL OR NOT has_function_privilege('authenticated','hocalist.chat_deals(uuid)','EXECUTE') OR has_function_privilege('anon','hocalist.chat_deals(uuid)','EXECUTE') OR has_function_privilege('service_role','hocalist.chat_deals(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Pair chat read grants drift'; END IF;
END $guard$;
COMMIT;

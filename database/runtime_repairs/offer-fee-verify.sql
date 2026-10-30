BEGIN READ ONLY;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.credit_authorize_target(uuid,uuid,uuid)')
   AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('6541227983a62e308dae9e9fb803f16f')
   AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN
   RAISE EXCEPTION 'Offer fee definition drift: credit_authorize_target(uuid,uuid,uuid)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=to_regprocedure('hocalist.credit_authorize_target(uuid,uuid,uuid)') AND a.privilege_type='EXECUTE'
   AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Offer fee helper grants drift: credit_authorize_target(uuid,uuid,uuid)'; END IF;
END $guard$;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.credit_qualify_conversation(uuid)')
   AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('58bfa4a6866674fc3af8f42290c89007')
   AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN
   RAISE EXCEPTION 'Offer fee definition drift: credit_qualify_conversation(uuid)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=to_regprocedure('hocalist.credit_qualify_conversation(uuid)') AND a.privilege_type='EXECUTE'
   AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Offer fee helper grants drift: credit_qualify_conversation(uuid)'; END IF;
END $guard$;
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.conversation_messages'::regclass
  AND tgname='chat_message_credit_qualify' AND NOT tgisinternal) THEN
  RAISE EXCEPTION 'Message fee trigger remains'; END IF;
END $guard$;
COMMIT;

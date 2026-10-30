BEGIN READ ONLY;
DO $verify$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.chat_signal_on_meeting_progress()') AND md5(replace(prosrc,E'\r\n',E'\n'))='01a628ad0c85fa5d796324d08dfcc283' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Meeting progress signal definition drift'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.meetings'::regclass AND tgname='chat_signal_meeting_progress'
   AND tgfoid=to_regprocedure('hocalist.chat_signal_on_meeting_progress()') AND tgtype=21 AND tgenabled='O') OR
    NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.sale_confirmations'::regclass AND tgname='chat_signal_purchase_progress'
   AND tgfoid=to_regprocedure('hocalist.chat_signal_on_meeting_progress()') AND tgtype=5 AND tgenabled='O') THEN
  RAISE EXCEPTION 'Meeting progress signal trigger drift'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  WHERE p.oid=to_regprocedure('hocalist.chat_signal_on_meeting_progress()') AND a.grantee<>p.proowner AND a.privilege_type='EXECUTE') THEN
  RAISE EXCEPTION 'Meeting progress signal grants drift'; END IF;
END $verify$;
COMMIT;

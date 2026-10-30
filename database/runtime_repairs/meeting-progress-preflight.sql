BEGIN READ ONLY;
DO $guard$ BEGIN
 IF to_regclass('hocalist.chat_change_signals') IS NULL OR
    to_regclass('hocalist.meetings') IS NULL OR
    to_regclass('hocalist.sale_confirmations') IS NULL THEN
  RAISE EXCEPTION 'Meeting progress signal prerequisites missing'; END IF;
 IF to_regprocedure('hocalist.chat_signal_on_meeting_progress()') IS NOT NULL AND
   NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.chat_signal_on_meeting_progress()')
    AND md5(replace(prosrc,E'\r\n',E'\n'))='01a628ad0c85fa5d796324d08dfcc283' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN
  RAISE EXCEPTION 'Meeting progress signal definition drift'; END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE
   (tgrelid='hocalist.meetings'::regclass AND tgname='chat_signal_meeting_progress') OR
   (tgrelid='hocalist.sale_confirmations'::regclass AND tgname='chat_signal_purchase_progress')) AND
   to_regprocedure('hocalist.chat_signal_on_meeting_progress()') IS NULL THEN
  RAISE EXCEPTION 'Meeting progress signal trigger drift'; END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE
  ((tgrelid='hocalist.meetings'::regclass AND tgname='chat_signal_meeting_progress' AND tgtype<>21) OR
   (tgrelid='hocalist.sale_confirmations'::regclass AND tgname='chat_signal_purchase_progress' AND tgtype<>5) OR
   (tgname IN ('chat_signal_meeting_progress','chat_signal_purchase_progress') AND
    tgrelid IN ('hocalist.meetings'::regclass,'hocalist.sale_confirmations'::regclass) AND
    (tgfoid IS DISTINCT FROM to_regprocedure('hocalist.chat_signal_on_meeting_progress()') OR tgenabled<>'O')))) THEN
  RAISE EXCEPTION 'Meeting progress signal trigger drift'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  WHERE p.oid=to_regprocedure('hocalist.chat_signal_on_meeting_progress()') AND a.grantee<>p.proowner AND a.privilege_type='EXECUTE') THEN
  RAISE EXCEPTION 'Meeting progress signal grants drift'; END IF;
END $guard$;
COMMIT;

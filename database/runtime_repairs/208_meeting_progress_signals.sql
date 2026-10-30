-- Emit only the already-authorized conversation identifier on meeting progress.
-- No PIN, message, payment or participant data is added to Realtime.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
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
CREATE OR REPLACE FUNCTION hocalist.chat_signal_on_meeting_progress()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_conversation uuid;
BEGIN
 IF TG_TABLE_NAME='sale_confirmations' THEN
  SELECT conversation_id INTO v_conversation FROM hocalist.meetings WHERE id=NEW.meeting_id;
 ELSE
  v_conversation := NEW.conversation_id;
 END IF;
 IF v_conversation IS NOT NULL THEN
  INSERT INTO hocalist.chat_change_signals(conversation_id) VALUES(v_conversation);
  DELETE FROM hocalist.chat_change_signals WHERE conversation_id=v_conversation
    AND created_at < now()-interval '15 minutes';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_signal_on_meeting_progress() FROM PUBLIC,anon,authenticated,service_role;
DO $triggers$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.meetings'::regclass AND tgname='chat_signal_meeting_progress') THEN
  CREATE TRIGGER chat_signal_meeting_progress AFTER INSERT OR UPDATE ON hocalist.meetings
   FOR EACH ROW EXECUTE FUNCTION hocalist.chat_signal_on_meeting_progress();
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.sale_confirmations'::regclass AND tgname='chat_signal_purchase_progress') THEN
  CREATE TRIGGER chat_signal_purchase_progress AFTER INSERT ON hocalist.sale_confirmations
   FOR EACH ROW EXECUTE FUNCTION hocalist.chat_signal_on_meeting_progress();
 END IF;
END $triggers$;
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

-- Emit private invalidation only; no offer details or notification contents.
BEGIN;
DO $$ BEGIN
 IF to_regprocedure('hocalist.chat_signal_on_offer_change()') IS NOT NULL AND NOT EXISTS(
 SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.chat_signal_on_offer_change()')
 AND md5(replace(prosrc,E'\r\n',E'\n'))='65207051f026810c254480c329297d67' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN
 RAISE EXCEPTION 'Offer signal definition drift'; END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE NOT tgisinternal AND
 ((tgrelid='hocalist.offers'::regclass AND tgname='chat_signal_offer_change') OR
 (tgrelid='hocalist.offer_revisions'::regclass AND tgname='chat_signal_offer_revision')) AND
 (tgtype<>21 OR tgenabled<>'O' OR tgfoid IS DISTINCT FROM to_regprocedure('hocalist.chat_signal_on_offer_change()'))) THEN
 RAISE EXCEPTION 'Offer signal trigger drift'; END IF;
END $$;

CREATE OR REPLACE FUNCTION hocalist.chat_signal_on_offer_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c uuid;
BEGIN
 IF TG_TABLE_NAME='offers' THEN
  c := NEW.conversation_id;
 ELSE
  SELECT conversation_id INTO c FROM hocalist.offers WHERE id=NEW.offer_id;
 END IF;
 IF c IS NOT NULL THEN
  INSERT INTO hocalist.chat_change_signals(conversation_id) VALUES(c);
  DELETE FROM hocalist.chat_change_signals WHERE conversation_id=c AND created_at<now()-interval '1 day';
 END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION hocalist.chat_signal_on_offer_change() FROM PUBLIC,anon,authenticated,service_role;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.offers'::regclass AND tgname='chat_signal_offer_change') THEN
  CREATE TRIGGER chat_signal_offer_change AFTER INSERT OR UPDATE ON hocalist.offers
   FOR EACH ROW EXECUTE FUNCTION hocalist.chat_signal_on_offer_change();
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.offer_revisions'::regclass AND tgname='chat_signal_offer_revision') THEN
  CREATE TRIGGER chat_signal_offer_revision AFTER INSERT OR UPDATE ON hocalist.offer_revisions
   FOR EACH ROW EXECUTE FUNCTION hocalist.chat_signal_on_offer_change();
 END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
-- Enrich the already-authorized message reads; no direct table access is granted.
DO $receipt_projection$
DECLARE signature text; definition text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['hocalist.chat_messages(uuid,integer,uuid)','hocalist.chat_deal_messages(uuid,uuid,integer,uuid)'] LOOP
  SELECT pg_get_functiondef(to_regprocedure(signature)) INTO definition;
  IF definition IS NULL OR strpos(definition,'to_jsonb(page)')=0 THEN
   RAISE EXCEPTION 'Message projection prerequisite drift: %',signature;
  END IF;
  IF strpos(definition,'read_by_counterpart')=0 THEN
   definition:=replace(definition,'to_jsonb(page)',
    $expr$(to_jsonb(page) || jsonb_build_object('read_by_counterpart',
      page.sender_user_id=auth.uid() AND EXISTS (
        SELECT 1 FROM hocalist.conversation_members other_member
        LEFT JOIN hocalist.chat_deal_reads deal_read
          ON deal_read.conversation_id=other_member.conversation_id
          AND deal_read.user_id=other_member.user_id AND deal_read.offer_id=page.offer_id
        WHERE other_member.conversation_id=page.conversation_id
          AND other_member.user_id<>page.sender_user_id
          AND greatest(other_member.last_read_seq,coalesce(deal_read.last_read_seq,0))>=page.seq
      )))$expr$);
   EXECUTE definition;
  END IF;
 END LOOP;
END $receipt_projection$;
-- A read change hints participants to refetch, using the existing private signal.
CREATE OR REPLACE FUNCTION hocalist.chat_signal_on_read()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_OP='UPDATE' AND NEW.last_read_seq<=OLD.last_read_seq THEN RETURN NEW; END IF;
 IF NEW.last_read_seq>0 THEN
  INSERT INTO hocalist.chat_change_signals(conversation_id) VALUES(NEW.conversation_id);
  DELETE FROM hocalist.chat_change_signals WHERE conversation_id=NEW.conversation_id
    AND created_at<now()-interval '15 minutes';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_signal_on_read() FROM PUBLIC,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS chat_signal_deal_read ON hocalist.chat_deal_reads;
CREATE TRIGGER chat_signal_deal_read AFTER INSERT OR UPDATE OF last_read_seq ON hocalist.chat_deal_reads
 FOR EACH ROW EXECUTE FUNCTION hocalist.chat_signal_on_read();
DROP TRIGGER IF EXISTS chat_signal_member_read ON hocalist.conversation_members;
CREATE TRIGGER chat_signal_member_read AFTER UPDATE OF last_read_seq ON hocalist.conversation_members
 FOR EACH ROW EXECUTE FUNCTION hocalist.chat_signal_on_read();
DO $search_unread$
DECLARE definition text;
BEGIN
 IF to_regprocedure('hocalist.chat_search_inbox(text,integer,text)') IS NOT NULL THEN
  SELECT pg_get_functiondef(to_regprocedure('hocalist.chat_search_inbox(text,integer,text)')) INTO definition;
  IF strpos(definition,'m.seq > self.last_read_seq')>0 THEN
   EXECUTE replace(definition,'m.seq > self.last_read_seq',
    'm.seq > greatest(self.last_read_seq,coalesce((SELECT dr.last_read_seq FROM hocalist.chat_deal_reads dr WHERE dr.conversation_id=m.conversation_id AND dr.offer_id=m.offer_id AND dr.user_id=v_user),0))');
  ELSIF strpos(definition,'chat_deal_reads')=0 THEN
   RAISE EXCEPTION 'Search unread prerequisite drift';
  END IF;
 END IF;
END $search_unread$;
NOTIFY pgrst,'reload schema';
COMMIT;

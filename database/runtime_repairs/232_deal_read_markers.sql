BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE hocalist.chat_deal_reads (
 conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id),
 offer_id uuid NOT NULL REFERENCES hocalist.offers(id),
 user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 last_read_seq bigint NOT NULL CHECK(last_read_seq>=0),
 PRIMARY KEY(conversation_id,offer_id,user_id)
);
ALTER TABLE hocalist.chat_deal_reads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.chat_deal_reads FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hocalist.chat_deal_mark_read(p_conversation uuid,p_offer uuid,p_last_read uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_seq bigint; unread integer;
BEGIN
 PERFORM hocalist.chat_assert_deal(p_conversation,p_offer);
 SELECT seq INTO v_seq FROM hocalist.conversation_messages WHERE id=p_last_read
  AND conversation_id=p_conversation AND offer_id=p_offer;
 IF NOT FOUND THEN RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023'; END IF;
 INSERT INTO hocalist.chat_deal_reads(conversation_id,offer_id,user_id,last_read_seq)
 VALUES(p_conversation,p_offer,auth.uid(),v_seq)
 ON CONFLICT(conversation_id,offer_id,user_id) DO UPDATE SET last_read_seq=greatest(hocalist.chat_deal_reads.last_read_seq,excluded.last_read_seq);
 SELECT count(*)::integer INTO unread FROM hocalist.conversation_messages m
 JOIN hocalist.conversation_members self ON self.conversation_id=m.conversation_id AND self.user_id=auth.uid()
 WHERE m.conversation_id=p_conversation AND m.sender_user_id<>auth.uid()
 AND m.seq>greatest(coalesce((SELECT r.last_read_seq FROM hocalist.chat_deal_reads r
   WHERE r.conversation_id=m.conversation_id AND r.offer_id=m.offer_id AND r.user_id=auth.uid()),0),self.last_read_seq);
 RETURN jsonb_build_object('unread_count',unread);
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_deal_mark_read(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_deal_mark_read(uuid,uuid,uuid) TO authenticated;
DO $inbox$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.chat_inbox(integer,text)')) INTO d;
 IF strpos(d,'m.seq > self.last_read_seq')=0 THEN RAISE EXCEPTION 'Inbox read marker definition drift'; END IF;
 EXECUTE replace(d,'m.seq > self.last_read_seq',
 'm.seq > greatest(coalesce((SELECT dr.last_read_seq FROM hocalist.chat_deal_reads dr WHERE dr.conversation_id=m.conversation_id AND dr.offer_id=m.offer_id AND dr.user_id=v_user),0),self.last_read_seq)');
END $inbox$;
NOTIFY pgrst,'reload schema';
COMMIT;

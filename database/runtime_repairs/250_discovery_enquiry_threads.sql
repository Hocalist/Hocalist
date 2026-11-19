-- Store/Hocatrends messages have an explicit, fee-free context inside the
-- existing participant chat. Historical unassigned messages are not guessed.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE IF NOT EXISTS hocalist.chat_enquiries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id),
 origin text NOT NULL CHECK(origin IN ('store_listing','hocatrends_enquiry')),
 subject_id uuid NOT NULL,
 label text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(conversation_id,origin,subject_id)
);
ALTER TABLE hocalist.chat_enquiries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.chat_enquiries FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE hocalist.conversation_messages ADD COLUMN IF NOT EXISTS enquiry_id uuid REFERENCES hocalist.chat_enquiries(id);
CREATE INDEX IF NOT EXISTS conversation_messages_enquiry_seq ON hocalist.conversation_messages(conversation_id,enquiry_id,seq DESC);
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='hocalist.conversation_messages'::regclass AND conname='message_single_context') THEN
  ALTER TABLE hocalist.conversation_messages ADD CONSTRAINT message_single_context CHECK(offer_id IS NULL OR enquiry_id IS NULL);
 END IF;
END $$;

CREATE OR REPLACE FUNCTION hocalist.chat_assert_enquiry(p_conversation uuid,p_enquiry uuid)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.chat_assert_participant(p_conversation,auth.uid());
 IF NOT EXISTS(SELECT 1 FROM hocalist.chat_enquiries WHERE id=p_enquiry AND conversation_id=p_conversation) THEN
  RAISE EXCEPTION 'enquiry_access_denied' USING ERRCODE='42501';
 END IF;
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_assert_enquiry(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS hocalist.chat_enquiry_reads (
 conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id),
 enquiry_id uuid NOT NULL REFERENCES hocalist.chat_enquiries(id),
 user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 last_read_seq bigint NOT NULL CHECK(last_read_seq>=0),
 PRIMARY KEY(conversation_id,enquiry_id,user_id)
);
ALTER TABLE hocalist.chat_enquiry_reads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.chat_enquiry_reads FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION hocalist.chat_enquiry_read_seq(p_conversation uuid,p_enquiry uuid,p_user uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce((SELECT last_read_seq FROM hocalist.chat_enquiry_reads
 WHERE conversation_id=p_conversation AND enquiry_id=p_enquiry AND user_id=p_user),0);
$$;
REVOKE ALL ON FUNCTION hocalist.chat_enquiry_read_seq(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Called only after the existing discovery opener's eligibility checks.
CREATE OR REPLACE FUNCTION hocalist.chat_ensure_enquiry(p_conversation uuid,p_origin text,p_subject uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result uuid; title text;
BEGIN
 PERFORM hocalist.chat_assert_participant(p_conversation,auth.uid());
 IF p_origin='store_listing' THEN
  SELECT l.title INTO title FROM hocalist.store_listings l WHERE l.id=p_subject;
 ELSIF p_origin='hocatrends_enquiry' THEN
  SELECT c.label INTO title FROM hocalist.catalogue_categories c WHERE c.id=p_subject;
 ELSE RAISE EXCEPTION 'invalid_origin' USING ERRCODE='22023';
 END IF;
 IF title IS NULL THEN RAISE EXCEPTION 'enquiry_subject_missing'; END IF;
 INSERT INTO hocalist.chat_enquiries(conversation_id,origin,subject_id,label)
 VALUES(p_conversation,p_origin,p_subject,title)
 ON CONFLICT(conversation_id,origin,subject_id) DO UPDATE SET label=excluded.label
 RETURNING id INTO result;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_ensure_enquiry(uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $opener$
DECLARE d text; marker text:='''subject_id'', v_subject';
BEGIN
 SELECT pg_get_functiondef('hocalist.discovery_open_enquiry(text,jsonb)'::regprocedure) INTO d;
 IF strpos(d,'chat_ensure_enquiry')=0 THEN
  IF strpos(d,marker)=0 OR strpos(d,'RETURN receipt.result;')=0 THEN RAISE EXCEPTION 'Discovery opener definition drift'; END IF;
  d:=replace(d,marker,marker||', ''enquiry_id'', hocalist.chat_ensure_enquiry(v_conversation,v_origin,v_subject)');
  d:=replace(d,'RETURN receipt.result;',
   'RETURN receipt.result || jsonb_build_object(''enquiry_id'',hocalist.chat_ensure_enquiry((receipt.result->>''conversation_id'')::uuid,v_origin,v_subject));');
  EXECUTE d;
 END IF;
END $opener$;

-- Insert before the existing deal fallback/payment gate, preserving that gate.
DO $scope$
DECLARE d text; marker text:='v_offer:=nullif(current_setting(''hocalist.chat_deal'',true),'''')::uuid;';
BEGIN
 SELECT pg_get_functiondef('hocalist.chat_scope_new_message()'::regprocedure) INTO d;
 IF strpos(d,'hocalist.chat_enquiry')=0 THEN
  IF strpos(d,marker)=0 THEN RAISE EXCEPTION 'Chat scope definition drift'; END IF;
  EXECUTE replace(d,marker,$insert$
 IF nullif(current_setting('hocalist.chat_enquiry',true),'') IS NOT NULL THEN
  NEW.enquiry_id:=current_setting('hocalist.chat_enquiry',true)::uuid;
  PERFORM hocalist.chat_assert_enquiry(NEW.conversation_id,NEW.enquiry_id);
  IF NEW.sender_user_id IS DISTINCT FROM auth.uid() OR nullif(current_setting('hocalist.chat_deal',true),'') IS NOT NULL THEN
   RAISE EXCEPTION 'enquiry_access_denied' USING ERRCODE='42501';
  END IF;
  NEW.offer_id:=NULL;
  RETURN NEW;
 END IF;
 NEW.enquiry_id:=NULL;
 $insert$||marker);
 END IF;
END $scope$;

CREATE OR REPLACE FUNCTION hocalist.chat_enquiries(p_conversation uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.chat_assert_participant(p_conversation,auth.uid());
 RETURN jsonb_build_object('items',(SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.created_at DESC,e.id),'[]'::jsonb)
 FROM hocalist.chat_enquiries e WHERE conversation_id=p_conversation));
END $$;

CREATE OR REPLACE FUNCTION hocalist.chat_enquiry_send(p_conversation uuid,p_enquiry uuid,p_key text,p_text text,p_media_ids jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb; previous text:=current_setting('hocalist.chat_enquiry',true); previous_deal text:=current_setting('hocalist.chat_deal',true);
BEGIN
 PERFORM hocalist.chat_assert_enquiry(p_conversation,p_enquiry);
 PERFORM set_config('hocalist.chat_enquiry',p_enquiry::text,true);
 PERFORM set_config('hocalist.chat_deal','',true);
 IF p_media_ids='[]'::jsonb THEN v:=hocalist.chat_send(p_conversation,p_key,p_text);
 ELSE v:=hocalist.chat_send_attachment(p_conversation,p_key,p_text,p_media_ids); END IF;
 IF v->>'enquiry_id' IS DISTINCT FROM p_enquiry::text OR v->>'offer_id' IS NOT NULL THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
 PERFORM set_config('hocalist.chat_enquiry',coalesce(previous,''),true);
 PERFORM set_config('hocalist.chat_deal',coalesce(previous_deal,''),true);
 RETURN v;
END $$;

CREATE OR REPLACE FUNCTION hocalist.chat_enquiry_messages(p_conversation uuid,p_enquiry uuid,p_page_size integer DEFAULT 50,p_before_message uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_size integer:=greatest(1,least(coalesce(p_page_size,50),100)); before_seq bigint; items jsonb; next_id text;
BEGIN
 PERFORM hocalist.chat_assert_enquiry(p_conversation,p_enquiry);
 IF p_before_message IS NOT NULL THEN
  SELECT seq INTO before_seq FROM hocalist.conversation_messages WHERE id=p_before_message AND conversation_id=p_conversation AND enquiry_id=p_enquiry;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023'; END IF;
 END IF;
 SELECT coalesce(jsonb_agg((to_jsonb(page)||jsonb_build_object('read_by_counterpart',
  page.sender_user_id=auth.uid() AND EXISTS(SELECT 1 FROM hocalist.conversation_members other_member
   WHERE other_member.conversation_id=page.conversation_id AND other_member.user_id<>page.sender_user_id
   AND greatest(other_member.last_read_seq,hocalist.chat_enquiry_read_seq(page.conversation_id,page.enquiry_id,other_member.user_id))>=page.seq)))
  ORDER BY page.seq),'[]'::jsonb) INTO items
 FROM (SELECT * FROM hocalist.conversation_messages WHERE conversation_id=p_conversation AND enquiry_id=p_enquiry
 AND (before_seq IS NULL OR seq<before_seq) ORDER BY seq DESC LIMIT v_size) page;
 IF jsonb_array_length(items)=v_size AND EXISTS(SELECT 1 FROM hocalist.conversation_messages
 WHERE conversation_id=p_conversation AND enquiry_id=p_enquiry AND seq<(items->0->>'seq')::bigint) THEN next_id:=items->0->>'id'; END IF;
 RETURN jsonb_build_object('items',items,'next_cursor',next_id);
END $$;
CREATE OR REPLACE FUNCTION hocalist.chat_enquiry_mark_read(p_conversation uuid,p_enquiry uuid,p_last_read uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_seq bigint; unread integer;
BEGIN
 PERFORM hocalist.chat_assert_enquiry(p_conversation,p_enquiry);
 SELECT seq INTO v_seq FROM hocalist.conversation_messages WHERE id=p_last_read
 AND conversation_id=p_conversation AND enquiry_id=p_enquiry;
 IF NOT FOUND THEN RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023'; END IF;
 INSERT INTO hocalist.chat_enquiry_reads(conversation_id,enquiry_id,user_id,last_read_seq)
 VALUES(p_conversation,p_enquiry,auth.uid(),v_seq)
 ON CONFLICT(conversation_id,enquiry_id,user_id) DO UPDATE SET last_read_seq=greatest(hocalist.chat_enquiry_reads.last_read_seq,excluded.last_read_seq);
 SELECT count(*)::integer INTO unread FROM hocalist.conversation_messages m
 JOIN hocalist.conversation_members self ON self.conversation_id=m.conversation_id AND self.user_id=auth.uid()
 WHERE m.conversation_id=p_conversation AND m.sender_user_id<>auth.uid()
 AND m.seq>greatest(self.last_read_seq,hocalist.chat_enquiry_read_seq(m.conversation_id,m.enquiry_id,auth.uid()),
 coalesce((SELECT r.last_read_seq FROM hocalist.chat_deal_reads r WHERE r.conversation_id=m.conversation_id AND r.offer_id=m.offer_id AND r.user_id=auth.uid()),0));
 RETURN jsonb_build_object('unread_count',unread);
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_enquiry_mark_read(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_enquiry_mark_read(uuid,uuid,uuid) TO authenticated;
DO $reads$
DECLARE signature text; d text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['hocalist.chat_inbox(integer,text)','hocalist.chat_search_inbox(text,integer,text)','hocalist.chat_deal_mark_read(uuid,uuid,uuid)'] LOOP
  IF to_regprocedure(signature) IS NULL THEN CONTINUE; END IF;
  SELECT pg_get_functiondef(to_regprocedure(signature)) INTO d;
  IF strpos(d,'chat_enquiry_read_seq')=0 THEN
   IF strpos(d,'self.last_read_seq')=0 THEN RAISE EXCEPTION 'Unread projection drift: %',signature; END IF;
   EXECUTE replace(d,'self.last_read_seq','greatest(self.last_read_seq,hocalist.chat_enquiry_read_seq(m.conversation_id,m.enquiry_id,auth.uid()))');
  END IF;
 END LOOP;
 IF to_regprocedure('hocalist.chat_signal_on_read()') IS NOT NULL THEN
  DROP TRIGGER IF EXISTS chat_signal_enquiry_read ON hocalist.chat_enquiry_reads;
  CREATE TRIGGER chat_signal_enquiry_read AFTER INSERT OR UPDATE OF last_read_seq ON hocalist.chat_enquiry_reads
   FOR EACH ROW EXECUTE FUNCTION hocalist.chat_signal_on_read();
 END IF;
END $reads$;
DO $notification$
DECLARE d text; marker text:='''message_id'', NEW.id';
BEGIN
 IF to_regprocedure('hocalist.notification_on_message_insert()') IS NOT NULL THEN
  SELECT pg_get_functiondef('hocalist.notification_on_message_insert()'::regprocedure) INTO d;
  IF strpos(d,'''enquiry_id''')=0 THEN
   IF strpos(d,marker)=0 THEN RAISE EXCEPTION 'Message notification definition drift'; END IF;
   EXECUTE replace(d,marker,marker||', ''enquiry_id'', NEW.enquiry_id');
  END IF;
 END IF;
END $notification$;
REVOKE ALL ON FUNCTION hocalist.chat_enquiries(uuid),hocalist.chat_enquiry_send(uuid,uuid,text,text,jsonb),hocalist.chat_enquiry_messages(uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_enquiries(uuid),hocalist.chat_enquiry_send(uuid,uuid,text,text,jsonb),hocalist.chat_enquiry_messages(uuid,uuid,integer,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

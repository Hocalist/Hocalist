-- Deal-scoped threads within one participant conversation. Historical messages
-- with no reliable deal identity remain unassigned; they are never guessed.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
ALTER TABLE hocalist.conversation_messages ADD COLUMN offer_id uuid REFERENCES hocalist.offers(id);
CREATE INDEX conversation_messages_deal_seq ON hocalist.conversation_messages(conversation_id,offer_id,seq DESC);
ALTER TABLE hocalist.credit_targets ADD COLUMN reply_qualification_enabled boolean NOT NULL DEFAULT false;
CREATE FUNCTION hocalist.credit_mark_reply_policy()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN NEW.reply_qualification_enabled:=true; RETURN NEW; END $$;
REVOKE ALL ON FUNCTION hocalist.credit_mark_reply_policy() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER credit_mark_reply_policy BEFORE INSERT ON hocalist.credit_targets
 FOR EACH ROW EXECUTE FUNCTION hocalist.credit_mark_reply_policy();

CREATE FUNCTION hocalist.chat_assert_deal(p_conversation uuid,p_offer uuid)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.chat_assert_participant(p_conversation,auth.uid());
 IF p_offer IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.offers o
   WHERE o.id=p_offer AND o.conversation_id=p_conversation
   AND auth.uid() IN (o.buyer_user_id,o.seller_user_id)) THEN
   RAISE EXCEPTION 'deal_access_denied' USING ERRCODE='42501';
 END IF;
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_assert_deal(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION hocalist.chat_scope_new_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_offer uuid; n integer;
BEGIN
 IF NEW.kind='system_notice' THEN RETURN NEW; END IF;
 v_offer:=nullif(current_setting('hocalist.chat_deal',true),'')::uuid;
 IF v_offer IS NULL THEN
   SELECT count(*),(array_agg(id))[1] INTO n,v_offer FROM hocalist.offers WHERE conversation_id=NEW.conversation_id;
   IF n>1 THEN RAISE EXCEPTION 'select_deal_before_sending' USING ERRCODE='P0001'; END IF;
 END IF;
 IF v_offer IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hocalist.offers WHERE id=v_offer
   AND conversation_id=NEW.conversation_id AND NEW.sender_user_id IN (buyer_user_id,seller_user_id)) THEN
   RAISE EXCEPTION 'deal_access_denied' USING ERRCODE='42501';
 END IF;
 NEW.offer_id:=v_offer;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_scope_new_message() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER chat_scope_new_message BEFORE INSERT ON hocalist.conversation_messages
 FOR EACH ROW EXECUTE FUNCTION hocalist.chat_scope_new_message();

CREATE FUNCTION hocalist.chat_deal_send(p_conversation uuid,p_offer uuid,p_key text,p_text text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb; previous text:=current_setting('hocalist.chat_deal',true);
BEGIN
 PERFORM hocalist.chat_assert_deal(p_conversation,p_offer);
 PERFORM set_config('hocalist.chat_deal',p_offer::text,true);
 v:=hocalist.chat_send(p_conversation,p_key,p_text);
 IF v->>'offer_id' IS DISTINCT FROM p_offer::text THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
 PERFORM set_config('hocalist.chat_deal',coalesce(previous,''),true);
 RETURN v;
END $$;

CREATE FUNCTION hocalist.chat_deal_messages(p_conversation uuid,p_offer uuid,p_page_size integer DEFAULT 50,p_before_message uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_size integer:=greatest(1,least(coalesce(p_page_size,50),100)); before_seq bigint; items jsonb; next_id text;
BEGIN
 PERFORM hocalist.chat_assert_deal(p_conversation,p_offer);
 IF p_before_message IS NOT NULL THEN
   SELECT seq INTO before_seq FROM hocalist.conversation_messages WHERE id=p_before_message
     AND conversation_id=p_conversation AND offer_id=p_offer;
   IF NOT FOUND THEN RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023'; END IF;
 END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.seq),'[]'::jsonb) INTO items
 FROM (SELECT * FROM hocalist.conversation_messages WHERE conversation_id=p_conversation AND offer_id=p_offer
   AND (before_seq IS NULL OR seq<before_seq) ORDER BY seq DESC LIMIT v_size) page;
 IF jsonb_array_length(items)=v_size AND EXISTS(SELECT 1 FROM hocalist.conversation_messages
    WHERE conversation_id=p_conversation AND offer_id=p_offer AND seq<(items->0->>'seq')::bigint) THEN next_id:=items->0->>'id'; END IF;
 RETURN jsonb_build_object('items',items,'next_cursor',next_id);
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_deal_send(uuid,uuid,text,text),hocalist.chat_deal_messages(uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_deal_send(uuid,uuid,text,text),hocalist.chat_deal_messages(uuid,uuid,integer,uuid) TO authenticated;
CREATE FUNCTION hocalist.chat_deal_send_attachment(p_conversation uuid,p_offer uuid,p_key text,p_text text,p_media_ids jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb; previous text:=current_setting('hocalist.chat_deal',true);
BEGIN
 PERFORM hocalist.chat_assert_deal(p_conversation,p_offer);
 PERFORM set_config('hocalist.chat_deal',p_offer::text,true);
 v:=hocalist.chat_send_attachment(p_conversation,p_key,p_text,p_media_ids);
 IF v->>'offer_id' IS DISTINCT FROM p_offer::text THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
 PERFORM set_config('hocalist.chat_deal',coalesce(previous,''),true);
 RETURN v;
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_deal_send_attachment(uuid,uuid,text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_deal_send_attachment(uuid,uuid,text,text,jsonb) TO authenticated;

-- Sending an offer reserves funds; the buyer's first reply charges its initial
-- fee. Profile lock serializes sends, retries and ledger changes for a seller.
DO $charge$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_authorize_target(uuid,uuid,uuid)')) INTO d;
 IF strpos(d,'IF t.status=''reserved'' THEN')=0 THEN RAISE EXCEPTION 'Offer fee definition drift'; END IF;
 d:=replace(d,'IF t.status=''reserved'' THEN
    PERFORM hocalist.credit_settle_internal(v_id,''initial'');
  END IF;','');
 IF strpos(d,'PERFORM hocalist.credit_settle_internal(v_id,''initial'');')>0 THEN RAISE EXCEPTION 'Offer fee replacement failed'; END IF;
 EXECUTE d;
END $charge$;
CREATE FUNCTION hocalist.chat_qualify_deal_reply()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o hocalist.offers%ROWTYPE; t hocalist.credit_targets%ROWTYPE;
BEGIN
 IF NEW.kind='system_notice' OR NEW.offer_id IS NULL THEN RETURN NEW; END IF;
 SELECT * INTO o FROM hocalist.offers WHERE id=NEW.offer_id;
 IF NEW.sender_user_id<>o.buyer_user_id OR NEW.sent_at<o.created_at OR (o.status NOT IN ('submitted','selected') AND NOT (o.status='completed' AND EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE offer_id=o.id))) THEN RETURN NEW; END IF;
 IF NOT EXISTS(SELECT 1 FROM hocalist.offer_revisions r WHERE r.offer_id=o.id
     AND r.proposed_by_user_id=o.seller_user_id AND length(btrim(r.message))>0 AND r.created_at<=NEW.sent_at)
   AND NOT EXISTS(SELECT 1 FROM hocalist.conversation_messages m WHERE m.offer_id=o.id
     AND m.sender_user_id=o.seller_user_id AND m.kind<>'system_notice' AND m.seq<NEW.seq) THEN RETURN NEW; END IF;
 PERFORM 1 FROM hocalist.profiles WHERE id=o.seller_user_id FOR UPDATE;
 SELECT * INTO t FROM hocalist.credit_targets WHERE offer_id=o.id AND status='reserved' AND reply_qualification_enabled FOR UPDATE;
 IF FOUND THEN
   UPDATE hocalist.credit_targets SET qualified_at=coalesce(qualified_at,NEW.sent_at) WHERE id=t.id;
   PERFORM hocalist.credit_settle_internal(t.id,'initial');
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_qualify_deal_reply() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER chat_qualify_deal_reply AFTER INSERT ON hocalist.conversation_messages
 FOR EACH ROW EXECUTE FUNCTION hocalist.chat_qualify_deal_reply();
-- A reply in another deal within the same participant chat must not block
-- withdrawal eligibility for this offer. Unassigned historical text is not
-- guessed into a newer deal.
DO $refund_scope$
DECLARE d text;
BEGIN
 IF to_regprocedure('hocalist.credit_policy_release(uuid)') IS NOT NULL THEN
  SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_policy_release(uuid)')) INTO d;
  IF strpos(d,'m.conversation_id=o.conversation_id')=0 THEN RAISE EXCEPTION 'Refund reply scope definition drift'; END IF;
  EXECUTE replace(d,'m.conversation_id=o.conversation_id','m.conversation_id=o.conversation_id AND m.offer_id=o.id');
 END IF;
END $refund_scope$;
DO $notification$
DECLARE d text;
BEGIN
 IF to_regprocedure('hocalist.notification_on_message_insert()') IS NOT NULL THEN
  SELECT pg_get_functiondef(to_regprocedure('hocalist.notification_on_message_insert()')) INTO d;
  IF strpos(d,'''message_id'', NEW.id')=0 THEN RAISE EXCEPTION 'Message notification definition drift'; END IF;
  EXECUTE replace(d,'''message_id'', NEW.id','''message_id'', NEW.id, ''offer_id'', NEW.offer_id');
 END IF;
END $notification$;
NOTIFY pgrst,'reload schema';
COMMIT;

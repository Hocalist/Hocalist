-- Failed targeting payments pause only their deal's new user messages.
-- Reads, other deals, pending/processing payments and historical targets remain
-- accessible. The buyer reply that qualifies the initial charge is retained.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $gate$
DECLARE d text; marker text:='NEW.offer_id:=v_offer;';
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.chat_scope_new_message()')) INTO d;
 IF d IS NULL OR strpos(d,marker)=0 THEN RAISE EXCEPTION 'Chat payment gate definition drift'; END IF;
 EXECUTE replace(d,marker,marker||$check$
 IF EXISTS(SELECT 1 FROM hocalist.credit_targets t JOIN hocalist.paygo_charges j ON j.target_id=t.id
   WHERE t.offer_id=v_offer AND t.funding_kind='paygo' AND t.reply_qualification_enabled
   AND t.status NOT IN ('released','refunded') AND j.state IN ('requires_action','requires_payment_method','review')) THEN
   RAISE EXCEPTION 'deal_payment_required' USING ERRCODE='P0001';
 END IF;
 $check$);
END $gate$;
NOTIFY pgrst,'reload schema';
COMMIT;

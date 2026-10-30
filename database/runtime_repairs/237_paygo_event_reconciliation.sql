-- Durable signed-event receipts and bounded worker selection. No schedule is
-- activated here, and no event payload can grant funds without provider readback.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE hocalist.paygo_charges ADD COLUMN next_check_at timestamptz NOT NULL DEFAULT now();
CREATE TABLE hocalist.paygo_provider_events(
 event_id text PRIMARY KEY CHECK(event_id ~ '^evt_[A-Za-z0-9]+$'),
 event_type text NOT NULL CHECK(event_type IN ('payment_intent.succeeded','payment_intent.payment_failed','payment_intent.processing','payment_intent.canceled')),
 object_id text NOT NULL CHECK(object_id ~ '^pi_[A-Za-z0-9]+$'),
 provider_created bigint NOT NULL CHECK(provider_created>0),
 received_at timestamptz NOT NULL DEFAULT now(),
 processed_at timestamptz
);
CREATE INDEX paygo_provider_events_pending ON hocalist.paygo_provider_events(object_id) WHERE processed_at IS NULL;
ALTER TABLE hocalist.paygo_provider_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.paygo_provider_events FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hocalist.receive_stripe_test_paygo_event(p_account text,p_event_id text,p_type text,p_object_id text,p_created bigint,p_livemode boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old hocalist.paygo_provider_events%ROWTYPE; inserted boolean;
BEGIN
 IF p_account IS DISTINCT FROM 'acct_1Le6hqDmHEV44E5Y' OR p_livemode IS DISTINCT FROM false THEN RAISE EXCEPTION 'invalid_provider_account'; END IF;
 INSERT INTO hocalist.paygo_provider_events(event_id,event_type,object_id,provider_created) VALUES(p_event_id,p_type,p_object_id,p_created) ON CONFLICT(event_id) DO NOTHING;
 inserted:=FOUND;
 IF NOT inserted THEN
   SELECT * INTO STRICT old FROM hocalist.paygo_provider_events WHERE event_id=p_event_id;
   IF old.event_type IS DISTINCT FROM p_type OR old.object_id IS DISTINCT FROM p_object_id OR old.provider_created IS DISTINCT FROM p_created THEN RAISE EXCEPTION 'event_identity_conflict'; END IF;
 END IF;
 UPDATE hocalist.paygo_charges SET next_check_at=now() WHERE payment_intent_id=p_object_id AND state NOT IN ('succeeded','canceled','review');
 UPDATE hocalist.paygo_provider_events SET processed_at=now() WHERE event_id=p_event_id AND EXISTS(SELECT 1 FROM hocalist.paygo_charges WHERE payment_intent_id=p_object_id AND state IN ('succeeded','canceled'));
 RETURN inserted;
END $$;
CREATE FUNCTION hocalist.paygo_next_charge()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j hocalist.paygo_charges%ROWTYPE;
BEGIN
 IF NOT (SELECT enabled FROM hocalist.paygo_collection_policy WHERE singleton) THEN RETURN NULL; END IF;
 SELECT cj.* INTO j FROM hocalist.paygo_charges cj
 WHERE cj.next_check_at<=now() AND (
   cj.state IN ('queued','pending','processing') OR (cj.state IN ('requires_action','requires_payment_method') AND EXISTS(
     SELECT 1 FROM hocalist.paygo_provider_events e WHERE e.object_id=cj.payment_intent_id AND e.processed_at IS NULL)))
 AND (cj.phase='initial' OR EXISTS(SELECT 1 FROM hocalist.paygo_charges initial WHERE initial.target_id=cj.target_id AND initial.phase='initial' AND initial.state='succeeded'))
 ORDER BY cj.next_check_at,cj.created_at,cj.id LIMIT 1 FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN RETURN NULL; END IF;
 UPDATE hocalist.paygo_charges SET next_check_at=now()+interval '1 minute' WHERE id=j.id;
 RETURN jsonb_build_object('id',j.id);
END $$;
DO $finish$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.paygo_charge_finish(uuid,text,text,bigint,text)')) INTO d;
 IF strpos(d,'UPDATE hocalist.paygo_charges SET state=p_state,updated_at=now() WHERE id=j.id;')=0 THEN RAISE EXCEPTION 'Collection finish definition drift'; END IF;
 EXECUTE replace(d,'UPDATE hocalist.paygo_charges SET state=p_state,updated_at=now() WHERE id=j.id;',
 'UPDATE hocalist.paygo_charges SET state=p_state,updated_at=now(),next_check_at=now()+interval ''1 minute'' WHERE id=j.id;
 UPDATE hocalist.paygo_provider_events SET processed_at=now() WHERE object_id=j.payment_intent_id AND processed_at IS NULL;');
END $finish$;
REVOKE ALL ON FUNCTION hocalist.receive_stripe_test_paygo_event(text,text,text,text,bigint,boolean),hocalist.paygo_next_charge() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.receive_stripe_test_paygo_event(text,text,text,text,bigint,boolean),hocalist.paygo_next_charge() TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

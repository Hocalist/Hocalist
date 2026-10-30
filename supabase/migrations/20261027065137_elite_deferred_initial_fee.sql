-- New reservations only: preserve historical charges and provider intents.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
ALTER TABLE hocalist.credit_targets ADD COLUMN elite_deferred_initial boolean NOT NULL DEFAULT false;
ALTER TABLE hocalist.credit_targets ADD COLUMN elite_settlement_checked_at timestamptz;
CREATE INDEX credit_targets_elite_due ON hocalist.credit_targets(elite_settlement_checked_at NULLS FIRST,created_at,id)
 WHERE elite_deferred_initial AND qualified_at IS NOT NULL AND status IN ('reserved','initial_charged');
CREATE FUNCTION hocalist.credit_elite_timing_snapshot()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 NEW.elite_deferred_initial := hocalist.marketplace_seller_plan(NEW.user_id)='elite';
 RETURN NEW;
END $$;
CREATE TRIGGER credit_elite_timing_snapshot BEFORE INSERT ON hocalist.credit_targets
FOR EACH ROW EXECUTE FUNCTION hocalist.credit_elite_timing_snapshot();

-- Preserve the reviewed settlement engine; recursive winning settlement calls
-- the public internal wrapper again, so both funding modes share this gate.
DO $copy$ DECLARE d text; BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_settle_internal(uuid,text)')) INTO d;
 IF d IS NULL OR strpos(d,'credit_settle_prepaid_internal')=0 THEN RAISE EXCEPTION 'Paygo settlement prerequisite missing'; END IF;
 EXECUTE replace(d,'FUNCTION hocalist.credit_settle_internal(','FUNCTION hocalist.credit_settle_before_elite_timing(');
END $copy$;
CREATE OR REPLACE FUNCTION hocalist.credit_settle_internal(p_target uuid,p_action text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t hocalist.credit_targets%ROWTYPE; due boolean; purchased boolean; waive boolean;
BEGIN
 IF p_action IS NULL OR p_action NOT IN ('initial','win','release','refund') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM hocalist.profiles WHERE id=(SELECT user_id FROM hocalist.credit_targets WHERE id=p_target) FOR UPDATE;
 SELECT * INTO STRICT t FROM hocalist.credit_targets WHERE id=p_target FOR UPDATE;
 IF t.elite_deferred_initial AND p_action='win' AND NOT EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE request_id=t.request_id AND offer_id=t.offer_id AND seller_user_id=t.user_id) THEN
   RAISE EXCEPTION 'purchase_confirmation_required';
 END IF;
 IF t.elite_deferred_initial AND p_action='win' AND t.qualified_at IS NULL THEN
   RETURN jsonb_build_object('id',t.id,'status','awaiting_buyer_reply');
 END IF;
 IF NOT t.elite_deferred_initial OR t.status IN ('won','refunded','released') OR p_action NOT IN ('initial','release') THEN
   RETURN hocalist.credit_settle_before_elite_timing(p_target,p_action);
 END IF;
 SELECT EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE request_id=t.request_id),
   EXISTS(SELECT 1 FROM hocalist.requests WHERE id=t.request_id AND acceptance_expires_at<=now())
 INTO purchased,due;
 -- No purchase on this request: an eligible Elite seller owes no initial fee.
 -- Keep the reservation while an existing meeting can still complete; the
 -- existing reconciliation engine decides when it is safe to release it.
 waive := NOT purchased AND t.competitors_viewed_at IS NULL;
 IF p_action='initial' THEN
   IF t.qualified_at IS NULL OR (NOT purchased AND (NOT due OR waive)) THEN
     RETURN jsonb_build_object('id',t.id,'status','awaiting_elite_settlement','charged_minor',t.charged_minor);
   END IF;
 ELSE
   IF t.qualified_at IS NOT NULL AND NOT purchased AND NOT due THEN
     RETURN jsonb_build_object('id',t.id,'status','awaiting_elite_settlement','charged_minor',t.charged_minor);
   END IF;
   IF t.qualified_at IS NOT NULL AND (purchased OR NOT waive) THEN
     PERFORM hocalist.credit_settle_internal(t.id,'initial');
     -- Do not finalize a card-funded target before its pending provider result:
     -- doing so would discard the debit when Stripe later reports success.
     IF t.funding_kind='paygo' AND NOT EXISTS(SELECT 1 FROM hocalist.paygo_charges
       WHERE target_id=t.id AND phase='initial' AND state='succeeded') THEN
       RETURN jsonb_build_object('id',t.id,'status','awaiting_initial_payment');
     END IF;
   ELSIF waive THEN
     RETURN hocalist.credit_settle_before_elite_timing(t.id,'refund');
   END IF;
 END IF;
 RETURN hocalist.credit_settle_before_elite_timing(p_target,p_action);
END $$;

-- Reuse both existing reconciliation entry points. This is not a new cron.
-- The worker processes due targets even when a valid meeting keeps its reserve.
DO $hooks$ DECLARE d text; BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_reconcile_target_internal(uuid)')) INTO d;
 IF strpos(d,'SELECT * INTO t FROM hocalist.credit_targets WHERE id=p_target;')=0 THEN RAISE EXCEPTION 'Reconciliation definition drift'; END IF;
 d:=replace(d,'SELECT * INTO t FROM hocalist.credit_targets WHERE id=p_target;',
 'PERFORM hocalist.credit_settle_internal(p_target,''initial'') FROM hocalist.credit_targets WHERE id=p_target AND elite_deferred_initial AND status IN (''reserved'',''initial_charged'');
 SELECT * INTO t FROM hocalist.credit_targets WHERE id=p_target;');
 EXECUTE d;
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_reconcile_internal(uuid)')) INTO d;
 IF strpos(d,'IF t.offer_id IS NULL THEN CONTINUE; END IF;')=0 THEN RAISE EXCEPTION 'Wallet reconciliation definition drift'; END IF;
 EXECUTE replace(d,'IF t.offer_id IS NULL THEN CONTINUE; END IF;',
 'IF t.offer_id IS NULL THEN CONTINUE; END IF;
 IF t.elite_deferred_initial AND t.status IN (''reserved'',''initial_charged'') THEN PERFORM hocalist.credit_settle_internal(t.id,''initial''); END IF;');
END $hooks$;
-- Fair, bounded processing of new Elite targets only. Payment-provider calls
-- remain in the existing separately gated card collector.
CREATE FUNCTION hocalist.credit_elite_due_sweep(p_limit integer DEFAULT 200)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE target uuid; examined integer:=0;
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'invalid_limit'; END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended('hocalist:elite_due_sweep',0)) THEN RETURN 0; END IF;
 FOR target IN SELECT t.id FROM hocalist.credit_targets t
   WHERE t.elite_deferred_initial AND t.qualified_at IS NOT NULL AND t.status IN ('reserved','initial_charged')
     AND (EXISTS(SELECT 1 FROM hocalist.requests r WHERE r.id=t.request_id AND r.acceptance_expires_at<=now())
       OR EXISTS(SELECT 1 FROM hocalist.sale_confirmations s WHERE s.request_id=t.request_id))
   ORDER BY t.elite_settlement_checked_at NULLS FIRST,t.created_at,t.id LIMIT p_limit
 LOOP
   PERFORM hocalist.credit_reconcile_target_internal(target);
   UPDATE hocalist.credit_targets SET elite_settlement_checked_at=now() WHERE id=target;
   examined:=examined+1;
 END LOOP;
 RETURN examined;
END $$;
REVOKE ALL ON FUNCTION hocalist.credit_elite_due_sweep(integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.credit_elite_due_sweep(integer) TO service_role;
REVOKE ALL ON FUNCTION hocalist.credit_elite_timing_snapshot(),hocalist.credit_settle_before_elite_timing(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

-- TEST-only collection foundation. The runtime gate remains off until the
-- complete recovery, credit-reuse and customer UI journey is verified.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE hocalist.paygo_collection_policy(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 enabled boolean NOT NULL DEFAULT false
);
INSERT INTO hocalist.paygo_collection_policy DEFAULT VALUES;
CREATE TABLE hocalist.paygo_plan_rates(
 plan_code text PRIMARY KEY CHECK(plan_code IN ('free','pro','elite')),
 initial_minor bigint NOT NULL CHECK(initial_minor>=50),
 winning_minor bigint NOT NULL CHECK(winning_minor>=initial_minor),
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 CHECK(winning_minor=initial_minor OR winning_minor-initial_minor>=50)
);
INSERT INTO hocalist.paygo_plan_rates(plan_code,initial_minor,winning_minor)
 VALUES('free',200,500),('pro',190,475),('elite',180,450);
ALTER TABLE hocalist.credit_targets ALTER COLUMN batch_id DROP NOT NULL;
ALTER TABLE hocalist.credit_targets ADD COLUMN funding_kind text NOT NULL DEFAULT 'prepaid' CHECK(funding_kind IN ('prepaid','paygo'));
ALTER TABLE hocalist.credit_targets ADD CONSTRAINT credit_target_funding CHECK(batch_id IS NOT NULL OR funding_kind='paygo');
ALTER TABLE hocalist.credit_batches ADD COLUMN funding_kind text NOT NULL DEFAULT 'prepaid' CHECK(funding_kind IN ('prepaid','paygo'));
ALTER TABLE hocalist.credit_batches ADD COLUMN external_funded_minor bigint CHECK(external_funded_minor>=0);
CREATE TABLE hocalist.paygo_charges(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 target_id uuid NOT NULL REFERENCES hocalist.credit_targets(id),
 phase text NOT NULL CHECK(phase IN ('initial','win')),
 fee_minor bigint NOT NULL CHECK(fee_minor>=50),
 amount_minor bigint NOT NULL CHECK(amount_minor=0 OR amount_minor>=50),
 allocation_decided boolean NOT NULL DEFAULT false,
 retry_generation integer NOT NULL DEFAULT 0 CHECK(retry_generation>=0),
 customer_id text NOT NULL,
 payment_method_id text NOT NULL,
 payment_intent_id text UNIQUE CHECK(payment_intent_id ~ '^pi_[A-Za-z0-9]+$'),
 state text NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','pending','requires_action','requires_payment_method','processing','succeeded','canceled','review')),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(target_id,phase)
);
CREATE TABLE hocalist.paygo_credit_allocations(
 charge_id uuid NOT NULL REFERENCES hocalist.paygo_charges(id),
 batch_id uuid NOT NULL REFERENCES hocalist.credit_batches(id),
 amount_minor bigint NOT NULL CHECK(amount_minor>0),
 state text NOT NULL DEFAULT 'reserved' CHECK(state IN ('reserved','consumed','released')),
 PRIMARY KEY(charge_id,batch_id)
);
ALTER TABLE hocalist.paygo_collection_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.paygo_plan_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.paygo_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.paygo_credit_allocations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.paygo_collection_policy,hocalist.paygo_plan_rates,hocalist.paygo_charges,hocalist.paygo_credit_allocations FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION hocalist.paygo_allocate_credits(p_charge uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j hocalist.paygo_charges%ROWTYPE; t hocalist.credit_targets%ROWTYPE; b hocalist.credit_batches%ROWTYPE; needed bigint; available bigint; take bigint;
BEGIN
 SELECT * INTO STRICT j FROM hocalist.paygo_charges WHERE id=p_charge FOR UPDATE;
 IF j.allocation_decided THEN RETURN; END IF;
 IF j.state<>'queued' OR j.payment_intent_id IS NOT NULL THEN RAISE EXCEPTION 'allocation_closed'; END IF;
 SELECT * INTO STRICT t FROM hocalist.credit_targets WHERE id=j.target_id;
 SELECT coalesce(sum(balance_minor-reserved_minor),0) INTO available FROM hocalist.credit_batches WHERE user_id=t.user_id AND funding_kind='paygo' AND id IS DISTINCT FROM t.batch_id;
 needed:=least(j.fee_minor,available);
 -- Never create a below-minimum card charge. Unused credits remain available.
 IF j.fee_minor-needed BETWEEN 1 AND 49 THEN needed:=greatest(0,j.fee_minor-50); END IF;
 UPDATE hocalist.paygo_charges SET amount_minor=fee_minor-needed,allocation_decided=true WHERE id=j.id;
 FOR b IN SELECT * FROM hocalist.credit_batches WHERE user_id=t.user_id AND funding_kind='paygo' AND balance_minor>reserved_minor AND id IS DISTINCT FROM t.batch_id ORDER BY created_at,id FOR UPDATE LOOP
   EXIT WHEN needed=0;
   take:=least(needed,b.balance_minor-b.reserved_minor);
   UPDATE hocalist.credit_batches SET reserved_minor=reserved_minor+take WHERE id=b.id;
   INSERT INTO hocalist.paygo_credit_allocations(charge_id,batch_id,amount_minor) VALUES(j.id,b.id,take);
   INSERT INTO hocalist.credit_entries(batch_id,target_id,kind,amount_minor,reserve_delta_minor) VALUES(b.id,t.id,'reserve',0,take);
   needed:=needed-take;
 END LOOP;
 IF needed<>0 THEN RAISE EXCEPTION 'allocation_balance_changed'; END IF;
END $$;
CREATE FUNCTION hocalist.paygo_release_credits(p_charge uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a hocalist.paygo_credit_allocations%ROWTYPE; target uuid;
BEGIN
 SELECT target_id INTO STRICT target FROM hocalist.paygo_charges WHERE id=p_charge;
 FOR a IN SELECT * FROM hocalist.paygo_credit_allocations WHERE charge_id=p_charge AND state='reserved' ORDER BY batch_id FOR UPDATE LOOP
   UPDATE hocalist.credit_batches SET reserved_minor=reserved_minor-a.amount_minor WHERE id=a.batch_id;
   INSERT INTO hocalist.credit_entries(batch_id,target_id,kind,amount_minor,reserve_delta_minor) VALUES(a.batch_id,target,'release',0,-a.amount_minor);
   UPDATE hocalist.paygo_credit_allocations SET state='released' WHERE charge_id=a.charge_id AND batch_id=a.batch_id;
 END LOOP;
END $$;

CREATE FUNCTION hocalist.paygo_reserve_target(p_user uuid,p_request uuid,p_offer uuid,p_week date,p_limit integer)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t hocalist.credit_targets%ROWTYPE; r hocalist.paygo_plan_rates%ROWTYPE; plan text; late boolean;
BEGIN
 PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
 IF NOT (SELECT enabled FROM hocalist.paygo_collection_policy WHERE singleton) THEN RAISE EXCEPTION 'insufficient_single_batch'; END IF;
 IF NOT EXISTS(SELECT 1 FROM hocalist.offers WHERE id=p_offer AND request_id=p_request AND seller_user_id=p_user) THEN RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501'; END IF;
 PERFORM hocalist.marketplace_assert_role(p_user,'seller');
 IF EXISTS(SELECT 1 FROM hocalist.stripe_test_customers sc JOIN hocalist.memberships sm ON sm.id=sc.membership_id WHERE sm.user_id=p_user AND sc.requires_review) THEN RAISE EXCEPTION 'billing_review_required'; END IF;
 SELECT * INTO t FROM hocalist.credit_targets WHERE user_id=p_user AND request_id=p_request;
 IF FOUND THEN RETURN t.id; END IF;
 IF p_limit IS NULL OR p_limit<1 OR p_week IS NULL OR (SELECT count(*) FROM hocalist.credit_targets WHERE user_id=p_user AND week_start=p_week)>=p_limit THEN RAISE EXCEPTION 'weekly_target_limit'; END IF;
 IF NOT EXISTS(SELECT 1 FROM hocalist.paygo_payment_methods WHERE user_id=p_user AND revoked_at IS NULL) THEN RAISE EXCEPTION 'payment_permission_required'; END IF;
 plan:=hocalist.marketplace_seller_plan(p_user);
 SELECT * INTO STRICT r FROM hocalist.paygo_plan_rates WHERE plan_code=plan;
 SELECT acceptance_expires_at>now() AND acceptance_expires_at<=now()+make_interval(hours=>(SELECT late_window_hours FROM hocalist.target_fee_policy WHERE singleton)) INTO late FROM hocalist.requests WHERE id=p_request;
 INSERT INTO hocalist.credit_targets(user_id,request_id,offer_id,batch_id,funding_kind,initial_minor,winning_minor,reserved_minor,week_start,rate_version)
 VALUES(p_user,p_request,p_offer,NULL,'paygo',CASE WHEN late THEN (SELECT late_total_minor FROM hocalist.target_fee_policy WHERE singleton) ELSE r.initial_minor END,
 CASE WHEN late THEN (SELECT late_total_minor FROM hocalist.target_fee_policy WHERE singleton) ELSE r.winning_minor END,0,p_week,
 CASE WHEN late THEN 'paygo-late-v'||(SELECT revision FROM hocalist.target_fee_policy WHERE singleton)::text ELSE 'paygo:'||plan||':'||r.revision::text END) RETURNING * INTO t;
 RETURN t.id;
END $$;

-- Preserve the existing prepaid settlement behind the same public-to-helper
-- boundary. All existing callers retain the original function identity.
DO $copy$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_settle_internal(uuid,text)')) INTO d;
 IF d IS NULL OR strpos(d,'balance_minor=balance_minor-charge')=0 THEN RAISE EXCEPTION 'Prepaid settlement definition drift'; END IF;
 EXECUTE replace(d,'FUNCTION hocalist.credit_settle_internal(','FUNCTION hocalist.credit_settle_prepaid_internal(');
END $copy$;
CREATE OR REPLACE FUNCTION hocalist.credit_settle_internal(p_target uuid,p_action text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t hocalist.credit_targets%ROWTYPE; m hocalist.paygo_payment_methods%ROWTYPE; amount bigint; job uuid;
BEGIN
 PERFORM 1 FROM hocalist.profiles WHERE id=(SELECT user_id FROM hocalist.credit_targets WHERE id=p_target) FOR UPDATE;
 SELECT * INTO STRICT t FROM hocalist.credit_targets WHERE id=p_target FOR UPDATE;
 IF t.funding_kind='prepaid' THEN RETURN hocalist.credit_settle_prepaid_internal(p_target,p_action); END IF;
 IF p_action IS NULL OR p_action NOT IN ('initial','win','release','refund') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
 IF p_action='win' AND NOT EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE request_id=t.request_id AND offer_id=t.offer_id AND seller_user_id=t.user_id) THEN RAISE EXCEPTION 'purchase_confirmation_required'; END IF;
 IF p_action='release' THEN
   UPDATE hocalist.credit_targets SET status='released' WHERE id=t.id AND status IN ('reserved','initial_charged');
 ELSIF p_action='refund' THEN
   IF EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE request_id=t.request_id) THEN RAISE EXCEPTION 'confirmed_purchase_not_refundable'; END IF;
   IF t.charged_minor>0 THEN
     UPDATE hocalist.credit_batches SET balance_minor=balance_minor+t.charged_minor WHERE id=t.batch_id;
     INSERT INTO hocalist.credit_entries(batch_id,target_id,kind,amount_minor,reserve_delta_minor) VALUES(t.batch_id,t.id,'refund',t.charged_minor,0);
   END IF;
   UPDATE hocalist.credit_targets SET status='refunded',charged_minor=0 WHERE id=t.id;
   -- Bound provider intents must still be reconciled, even after a refund.
   UPDATE hocalist.paygo_charges SET state='canceled',updated_at=now() WHERE target_id=t.id AND payment_intent_id IS NULL AND state='queued';
   FOR job IN SELECT id FROM hocalist.paygo_charges WHERE target_id=t.id AND state='canceled' LOOP PERFORM hocalist.paygo_release_credits(job); END LOOP;
 ELSIF t.status NOT IN ('won','refunded','released') THEN
   IF t.qualified_at IS NULL THEN RETURN jsonb_build_object('id',t.id,'status','awaiting_buyer_reply'); END IF;
   SELECT * INTO m FROM hocalist.paygo_payment_methods WHERE user_id=t.user_id AND revoked_at IS NULL;
   IF NOT FOUND THEN RETURN jsonb_build_object('id',t.id,'status','payment_permission_required'); END IF;
   IF p_action='initial' THEN amount:=t.initial_minor;
   ELSE
     -- Purchase completion can precede the provider response to the initial
     -- charge. Queue both phases; the worker serializes them.
     PERFORM hocalist.credit_settle_internal(t.id,'initial');
     amount:=t.winning_minor-t.initial_minor;
   END IF;
   IF amount>0 THEN
     INSERT INTO hocalist.paygo_charges(target_id,phase,fee_minor,amount_minor,customer_id,payment_method_id)
     VALUES(t.id,p_action,amount,amount,m.customer_id,m.payment_method_id) ON CONFLICT(target_id,phase) DO NOTHING;
     SELECT id INTO STRICT job FROM hocalist.paygo_charges WHERE target_id=t.id AND phase=p_action;
     PERFORM hocalist.paygo_allocate_credits(job);
   ELSIF p_action='win' AND t.charged_minor=t.winning_minor THEN
     UPDATE hocalist.credit_targets SET status='won' WHERE id=t.id;
   END IF;
 END IF;
 SELECT * INTO t FROM hocalist.credit_targets WHERE id=t.id;
 RETURN jsonb_build_object('id',t.id,'status',t.status,'charged_minor',t.charged_minor);
END $$;
DO $reserve$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_reserve_internal(uuid,uuid,uuid,date,integer)')) INTO d;
 IF strpos(d,'WHERE user_id=p_user AND balance_minor-reserved_minor')=0 THEN RAISE EXCEPTION 'Reservation definition drift'; END IF;
 EXECUTE replace(d,'WHERE user_id=p_user AND balance_minor-reserved_minor','WHERE user_id=p_user AND funding_kind=''prepaid'' AND balance_minor-reserved_minor');
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_authorize_target(uuid,uuid,uuid)')) INTO d;
 IF strpos(d,'v_id := hocalist.credit_reserve_internal(p_user, p_request, p_offer, v_week, v_limit);')=0 THEN RAISE EXCEPTION 'Authorization definition drift'; END IF;
 EXECUTE replace(d,'v_id := hocalist.credit_reserve_internal(p_user, p_request, p_offer, v_week, v_limit);',
 'BEGIN
 v_id := hocalist.credit_reserve_internal(p_user, p_request, p_offer, v_week, v_limit);
 EXCEPTION WHEN raise_exception THEN
 IF SQLERRM NOT IN (''insufficient_single_batch'',''targeting_fee_unconfigured'') THEN RAISE; END IF;
 v_id := hocalist.paygo_reserve_target(p_user,p_request,p_offer,v_week,v_limit);
 END;');
END $reserve$;

CREATE FUNCTION hocalist.paygo_charge_context(p_charge uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE j hocalist.paygo_charges%ROWTYPE; t hocalist.credit_targets%ROWTYPE;
BEGIN
 SELECT * INTO STRICT j FROM hocalist.paygo_charges WHERE id=p_charge;
 SELECT * INTO STRICT t FROM hocalist.credit_targets WHERE id=j.target_id;
 IF j.state IN ('succeeded','canceled','review') THEN RETURN jsonb_build_object('id',j.id,'state',j.state); END IF;
 IF j.phase='win' AND NOT EXISTS(SELECT 1 FROM hocalist.paygo_charges WHERE target_id=t.id AND phase='initial' AND state='succeeded') THEN RETURN jsonb_build_object('id',j.id,'state','waiting_for_initial'); END IF;
 -- An already-bound intent must be checked even if permission was revoked:
 -- the request could have succeeded before its response was lost.
 IF j.payment_intent_id IS NULL THEN
   IF NOT (SELECT enabled FROM hocalist.paygo_collection_policy WHERE singleton) THEN RAISE EXCEPTION 'collection_disabled'; END IF;
   PERFORM hocalist.marketplace_assert_role(t.user_id,'seller');
   IF EXISTS(SELECT 1 FROM hocalist.stripe_test_customers sc WHERE sc.customer_id=j.customer_id AND sc.requires_review) THEN RAISE EXCEPTION 'billing_review_required'; END IF;
   IF j.amount_minor>0 AND NOT EXISTS(SELECT 1 FROM hocalist.paygo_payment_methods WHERE user_id=t.user_id AND revoked_at IS NULL AND customer_id=j.customer_id AND payment_method_id=j.payment_method_id) THEN RAISE EXCEPTION 'payment_permission_required'; END IF;
 END IF;
 RETURN to_jsonb(j)||jsonb_build_object('user_id',t.user_id,'request_id',t.request_id,'offer_id',t.offer_id,
 'may_confirm',(SELECT enabled FROM hocalist.paygo_collection_policy WHERE singleton)
 AND EXISTS(SELECT 1 FROM hocalist.paygo_payment_methods WHERE user_id=t.user_id AND revoked_at IS NULL AND customer_id=j.customer_id AND payment_method_id=j.payment_method_id)
 AND EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=t.user_id AND role='seller' AND status='active')
 AND NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=t.user_id AND status IN ('restricted','disabled'))
 AND NOT EXISTS(SELECT 1 FROM hocalist.stripe_test_customers sc WHERE sc.customer_id=j.customer_id AND sc.requires_review));
 -- Provider and billing-review holds are checked again before confirmation.
END $$;
CREATE FUNCTION hocalist.paygo_charge_bind(p_charge uuid,p_intent text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j hocalist.paygo_charges%ROWTYPE;
BEGIN
 SELECT * INTO STRICT j FROM hocalist.paygo_charges WHERE id=p_charge FOR UPDATE;
 IF p_intent IS NULL OR p_intent !~ '^pi_[A-Za-z0-9]+$' OR j.state NOT IN ('queued','pending') THEN RAISE EXCEPTION 'invalid_payment_binding'; END IF;
 IF j.payment_intent_id IS NOT NULL AND j.payment_intent_id<>p_intent THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
 UPDATE hocalist.paygo_charges SET payment_intent_id=p_intent,state='pending',updated_at=now() WHERE id=j.id;
END $$;
CREATE FUNCTION hocalist.paygo_charge_finish(p_charge uuid,p_intent text,p_customer text,p_amount bigint,p_state text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j hocalist.paygo_charges%ROWTYPE; t hocalist.credit_targets%ROWTYPE; b uuid; debit bigint; a hocalist.paygo_credit_allocations%ROWTYPE; credits bigint;
BEGIN
 PERFORM 1 FROM hocalist.profiles WHERE id=(SELECT ct.user_id FROM hocalist.paygo_charges cj JOIN hocalist.credit_targets ct ON ct.id=cj.target_id WHERE cj.id=p_charge) FOR UPDATE;
 SELECT * INTO STRICT j FROM hocalist.paygo_charges WHERE id=p_charge FOR UPDATE;
 SELECT * INTO STRICT t FROM hocalist.credit_targets WHERE id=j.target_id FOR UPDATE;
 IF j.payment_intent_id IS DISTINCT FROM p_intent OR j.customer_id IS DISTINCT FROM p_customer OR j.amount_minor IS DISTINCT FROM p_amount THEN RAISE EXCEPTION 'payment_identity_mismatch'; END IF;
 IF j.state='succeeded' THEN RETURN; END IF;
 IF p_state NOT IN ('requires_action','requires_payment_method','processing','succeeded','canceled','review','pending') OR p_state IS NULL THEN RAISE EXCEPTION 'invalid_payment_state'; END IF;
 IF j.state IN ('canceled','review') THEN RAISE EXCEPTION 'charge_closed'; END IF;
 IF p_state='succeeded' THEN
   SELECT coalesce(sum(amount_minor),0) INTO credits FROM hocalist.paygo_credit_allocations WHERE charge_id=j.id AND state='reserved';
   IF credits+j.amount_minor<>j.fee_minor THEN RAISE EXCEPTION 'funding_mismatch'; END IF;
   IF j.phase='win' AND NOT EXISTS(SELECT 1 FROM hocalist.paygo_charges WHERE target_id=t.id AND phase='initial' AND state='succeeded') THEN RAISE EXCEPTION 'initial_payment_required'; END IF;
   b:=t.batch_id;
   IF b IS NULL THEN
     INSERT INTO hocalist.credit_batches(user_id,deposit_reference,original_minor,balance_minor,reserved_minor,initial_fee_minor,winning_total_minor,rate_version,funding_kind,external_funded_minor)
     VALUES(t.user_id,'paygo:'||j.id::text,j.fee_minor,j.fee_minor,0,t.initial_minor,t.winning_minor,t.rate_version,'paygo',j.amount_minor) RETURNING id INTO b;
     UPDATE hocalist.credit_targets SET batch_id=b WHERE id=t.id;
   ELSE
     UPDATE hocalist.credit_batches SET original_minor=original_minor+j.fee_minor,balance_minor=balance_minor+j.fee_minor,external_funded_minor=external_funded_minor+j.amount_minor WHERE id=b;
   END IF;
   FOR a IN SELECT * FROM hocalist.paygo_credit_allocations WHERE charge_id=j.id AND state='reserved' ORDER BY batch_id FOR UPDATE LOOP
     UPDATE hocalist.credit_batches SET balance_minor=balance_minor-a.amount_minor,reserved_minor=reserved_minor-a.amount_minor WHERE id=a.batch_id;
     INSERT INTO hocalist.credit_entries(batch_id,target_id,kind,amount_minor,reserve_delta_minor) VALUES(a.batch_id,t.id,'transfer_out',-a.amount_minor,-a.amount_minor);
     UPDATE hocalist.paygo_credit_allocations SET state='consumed' WHERE charge_id=a.charge_id AND batch_id=a.batch_id;
   END LOOP;
   IF j.amount_minor>0 THEN INSERT INTO hocalist.credit_entries(batch_id,target_id,kind,amount_minor,reserve_delta_minor) VALUES(b,t.id,'deposit',j.amount_minor,0); END IF;
   IF credits>0 THEN INSERT INTO hocalist.credit_entries(batch_id,target_id,kind,amount_minor,reserve_delta_minor) VALUES(b,t.id,'transfer_in',credits,0); END IF;
   debit:=CASE WHEN t.status='refunded' THEN 0 ELSE j.fee_minor END;
   IF debit>0 THEN
     UPDATE hocalist.credit_batches SET balance_minor=balance_minor-debit WHERE id=b;
     INSERT INTO hocalist.credit_entries(batch_id,target_id,kind,amount_minor,reserve_delta_minor) VALUES(b,t.id,j.phase,-debit,0);
     UPDATE hocalist.credit_targets SET charged_minor=charged_minor+debit,
       status=CASE WHEN status='released' THEN status WHEN j.phase='win' THEN 'won' ELSE 'initial_charged' END WHERE id=t.id;
   END IF;
 END IF;
 IF p_state='canceled' THEN PERFORM hocalist.paygo_release_credits(j.id); END IF;
 UPDATE hocalist.paygo_charges SET state=p_state,updated_at=now() WHERE id=j.id;
 IF p_state='succeeded' AND EXISTS(SELECT 1 FROM hocalist.credit_targets WHERE id=t.id AND status NOT IN ('refunded','released')) AND EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE request_id=t.request_id AND offer_id=t.offer_id AND seller_user_id=t.user_id) THEN
   PERFORM hocalist.credit_settle_purchase(t.request_id);
 END IF;
END $$;
CREATE FUNCTION hocalist.paygo_charge_for_user(p_user uuid,p_charge uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.marketplace_assert_role(p_user,'seller');
 IF NOT EXISTS(SELECT 1 FROM hocalist.paygo_charges cj JOIN hocalist.credit_targets ct ON ct.id=cj.target_id WHERE cj.id=p_charge AND ct.user_id=p_user) THEN RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
 RETURN hocalist.paygo_charge_context(p_charge);
END $$;
CREATE FUNCTION hocalist.paygo_charge_retry(p_user uuid,p_charge uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j hocalist.paygo_charges%ROWTYPE; m hocalist.paygo_payment_methods%ROWTYPE;
BEGIN
 PERFORM hocalist.marketplace_assert_role(p_user,'seller');
 PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
 SELECT cj.* INTO j FROM hocalist.paygo_charges cj JOIN hocalist.credit_targets ct ON ct.id=cj.target_id WHERE cj.id=p_charge AND ct.user_id=p_user FOR UPDATE OF cj;
 IF NOT FOUND THEN RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
 IF j.state<>'requires_payment_method' OR j.payment_intent_id IS NULL OR j.retry_generation>=20 THEN RAISE EXCEPTION 'payment_not_retryable'; END IF;
 SELECT * INTO STRICT m FROM hocalist.paygo_payment_methods WHERE user_id=p_user AND revoked_at IS NULL AND customer_id=j.customer_id;
 UPDATE hocalist.paygo_charges SET payment_method_id=m.payment_method_id,retry_generation=retry_generation+1,state='pending',updated_at=now() WHERE id=j.id;
END $$;
CREATE OR REPLACE FUNCTION hocalist.paygo_payment_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.marketplace_assert_role(auth.uid(),'seller');
 RETURN jsonb_build_object('authorised',EXISTS(SELECT 1 FROM hocalist.paygo_payment_methods WHERE user_id=auth.uid() AND revoked_at IS NULL),'consent_version','paygo-v1',
 'charges',coalesce((SELECT jsonb_agg(to_jsonb(page)) FROM (
   SELECT cj.id,cj.phase,cj.fee_minor,cj.amount_minor,cj.state,q.title AS request_title,cj.created_at
   FROM hocalist.paygo_charges cj JOIN hocalist.credit_targets ct ON ct.id=cj.target_id JOIN hocalist.requests q ON q.id=ct.request_id
   WHERE ct.user_id=auth.uid() AND cj.state NOT IN ('succeeded','canceled') ORDER BY cj.created_at DESC,cj.id LIMIT 20
 )page),'[]'::jsonb));
END $$;
DO $wallet$
DECLARE d text;
BEGIN
 IF to_regprocedure('hocalist.commercial_credit_wallet()') IS NOT NULL THEN
   SELECT pg_get_functiondef(to_regprocedure('hocalist.commercial_credit_wallet()')) INTO d;
   IF strpos(d,'sum(original_minor)')=0 THEN RAISE EXCEPTION 'Wallet deposit total definition drift'; END IF;
   EXECUTE replace(d,'sum(original_minor)','sum(coalesce(external_funded_minor,original_minor))');
   SELECT pg_get_functiondef(to_regprocedure('hocalist.commercial_credit_wallet()')) INTO d;
   IF strpos(d,'''id'',b.id,''original_minor'',b.original_minor')=0 OR strpos(d,'''currency'',''HC'',')=0 THEN RAISE EXCEPTION 'Wallet funding projection definition drift'; END IF;
   d:=replace(d,'''id'',b.id,''original_minor'',b.original_minor','''id'',b.id,''funding_kind'',b.funding_kind,''original_minor'',b.original_minor');
   d:=replace(d,'''currency'',''HC'',','''currency'',''HC'',''paygo'',(SELECT jsonb_build_object(''enabled'',p.enabled,''authorised'',EXISTS(SELECT 1 FROM hocalist.paygo_payment_methods WHERE user_id=u AND revoked_at IS NULL),''initial_minor'',r.initial_minor,''winning_minor'',r.winning_minor,''late_window_hours'',f.late_window_hours,''late_total_minor'',f.late_total_minor) FROM hocalist.paygo_collection_policy p CROSS JOIN hocalist.paygo_plan_rates r CROSS JOIN hocalist.target_fee_policy f WHERE p.singleton AND f.singleton AND r.plan_code=hocalist.marketplace_seller_plan(u)),');
   EXECUTE d;
 END IF;
END $wallet$;
REVOKE ALL ON FUNCTION hocalist.paygo_reserve_target(uuid,uuid,uuid,date,integer),hocalist.paygo_allocate_credits(uuid),hocalist.paygo_release_credits(uuid),hocalist.credit_settle_prepaid_internal(uuid,text),hocalist.paygo_charge_context(uuid),hocalist.paygo_charge_bind(uuid,text),hocalist.paygo_charge_finish(uuid,text,text,bigint,text),hocalist.paygo_charge_for_user(uuid,uuid),hocalist.paygo_charge_retry(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.paygo_charge_context(uuid),hocalist.paygo_charge_bind(uuid,text),hocalist.paygo_charge_finish(uuid,text,text,bigint,text),hocalist.paygo_charge_for_user(uuid,uuid),hocalist.paygo_charge_retry(uuid,uuid) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

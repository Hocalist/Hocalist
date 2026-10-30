-- Below-20 standard-rate deposits. Disabled until the coordinated TEST release.
-- Existing deposit snapshots remain immutable. Small deposits can be pooled
-- only with the exact same rates; internal transfers never count as revenue.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE TABLE hocalist.standard_wallet_policy(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 enabled boolean NOT NULL DEFAULT false,
 minimum_minor bigint NOT NULL DEFAULT 50 CHECK(minimum_minor>=50),
 maximum_minor bigint NOT NULL DEFAULT 1999 CHECK(maximum_minor<2000 AND maximum_minor>=minimum_minor)
);
INSERT INTO hocalist.standard_wallet_policy DEFAULT VALUES;
ALTER TABLE hocalist.standard_wallet_policy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.standard_wallet_policy FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE hocalist.credit_batches DROP CONSTRAINT credit_batches_funding_kind_check;
ALTER TABLE hocalist.credit_batches ADD CONSTRAINT credit_batches_funding_kind_check CHECK(funding_kind IN ('prepaid','paygo','standard'));
ALTER TABLE hocalist.stripe_test_checkouts ADD COLUMN standard_deposit boolean NOT NULL DEFAULT false;
ALTER TABLE hocalist.stripe_test_checkouts DROP CONSTRAINT stripe_test_checkout_kind_shape;
ALTER TABLE hocalist.stripe_test_checkouts ADD CONSTRAINT stripe_test_checkout_kind_shape CHECK(
 (kind='subscription' AND plan_code IS NOT NULL AND credit_option_id IS NULL AND NOT standard_deposit)
 OR (kind='credit_deposit' AND plan_code IS NULL AND credit_initial_minor IS NOT NULL
 AND credit_winning_minor IS NOT NULL AND credit_rate_version IS NOT NULL
 AND ((credit_option_id IS NOT NULL AND NOT standard_deposit)
 OR (credit_option_id IS NULL AND standard_deposit AND amount_minor BETWEEN 50 AND 1999)))
);

DO $begin$
DECLARE d text; marker text:='SELECT * INTO o FROM hocalist.credit_deposit_options_for_user(p_user) WHERE id=p_option AND active;';
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)')) INTO d;
 IF d IS NULL OR strpos(d,marker)=0 OR strpos(d,'o.id, o.initial_fee_minor')=0 THEN RAISE EXCEPTION 'Standard deposit begin definition drift'; END IF;
 -- Fix SQL NULL comparison before introducing nullable option ids.
 d:=replace(d,'c.credit_option_id<>p_option','c.credit_option_id IS DISTINCT FROM p_option');
 EXECUTE d;
 d:=replace(d,'FUNCTION hocalist.stripe_test_deposit_begin(p_user uuid, p_option uuid, p_key uuid)',
 'FUNCTION hocalist.stripe_test_standard_deposit_begin(p_user uuid, p_amount bigint, p_key uuid)');
 d:=replace(d,'c.credit_option_id IS DISTINCT FROM p_option','NOT c.standard_deposit OR c.amount_minor IS DISTINCT FROM p_amount');
 d:=replace(d,marker,$select$
 IF NOT EXISTS(SELECT 1 FROM hocalist.standard_wallet_policy WHERE singleton AND enabled AND p_amount BETWEEN minimum_minor AND maximum_minor) THEN RAISE EXCEPTION 'standard_deposit_unavailable'; END IF;
 SELECT NULL::uuid AS id,p_amount AS amount_minor,r.initial_minor AS initial_fee_minor,r.winning_minor AS winning_total_minor,
 'standard:'||r.plan_code||':'||r.revision::text AS rate_version INTO o
 FROM hocalist.paygo_plan_rates r WHERE r.plan_code=hocalist.marketplace_seller_plan(p_user);
 $select$);
 d:=replace(d,'credit_option_id, credit_initial_minor','standard_deposit, credit_option_id, credit_initial_minor');
 d:=replace(d,'o.id, o.initial_fee_minor','true, o.id, o.initial_fee_minor');
 d:=replace(d,'''option_id'',c.credit_option_id','''standard_deposit'',c.standard_deposit,''option_id'',c.credit_option_id');
 EXECUTE d;
 -- Copy the trusted accounting helper, retaining provider-reference fencing.
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text)')) INTO d;
 IF strpos(d,'OR p_win>p_amount')=0 THEN RAISE EXCEPTION 'Standard ledger definition drift'; END IF;
 d:=replace(d,'FUNCTION hocalist.credit_deposit_internal(','FUNCTION hocalist.standard_deposit_internal(');
 d:=replace(d,'OR p_win>p_amount','OR p_amount>=2000');
 d:=replace(d,'b.user_id<>p_user','b.funding_kind<>''standard'' OR b.user_id<>p_user');
 d:=replace(d,'initial_fee_minor,winning_total_minor,rate_version)','initial_fee_minor,winning_total_minor,rate_version,funding_kind)');
 d:=replace(d,'p_initial,p_win,p_rate)','p_initial,p_win,p_rate,''standard'')');
 EXECUTE d;
 SELECT pg_get_functiondef(to_regprocedure('hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text)')) INTO d;
 IF d IS NULL OR strpos(d,'v_batch := hocalist.credit_deposit_internal(')=0 THEN RAISE EXCEPTION 'Standard deposit finish definition drift'; END IF;
 d:=replace(d,'v_batch := hocalist.credit_deposit_internal(',
 'IF c.standard_deposit THEN v_batch := hocalist.standard_deposit_internal(v_user,v_reference,c.amount_minor,c.credit_initial_minor,c.credit_winning_minor,c.credit_rate_version); ELSE v_batch := hocalist.credit_deposit_internal(');
 d:=replace(d,'c.credit_initial_minor, c.credit_winning_minor, c.credit_rate_version);',
 'c.credit_initial_minor, c.credit_winning_minor, c.credit_rate_version); END IF;');
 EXECUTE d;
END $begin$;

-- Aggregate only unreserved standard funds with identical immutable rates.
-- Original provider deposits and their ledger entries are retained.
CREATE FUNCTION hocalist.standard_wallet_pool(p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE g record; b hocalist.credit_batches%ROWTYPE; pool uuid; amount bigint;
BEGIN
 PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
 FOR g IN SELECT initial_fee_minor,winning_total_minor,rate_version
 FROM hocalist.credit_batches WHERE user_id=p_user AND funding_kind='standard' AND balance_minor>reserved_minor
 GROUP BY initial_fee_minor,winning_total_minor,rate_version
 HAVING count(*)>1
 ORDER BY min(created_at),rate_version LOOP
   SELECT sum(balance_minor-reserved_minor) INTO amount FROM hocalist.credit_batches WHERE user_id=p_user AND funding_kind='standard'
    AND initial_fee_minor=g.initial_fee_minor AND winning_total_minor=g.winning_total_minor AND rate_version=g.rate_version;
   INSERT INTO hocalist.credit_batches(user_id,deposit_reference,original_minor,balance_minor,initial_fee_minor,winning_total_minor,rate_version,funding_kind,external_funded_minor)
   VALUES(p_user,'standard-pool:'||gen_random_uuid()::text,amount,0,g.initial_fee_minor,g.winning_total_minor,g.rate_version,'standard',0) RETURNING id INTO pool;
   FOR b IN SELECT * FROM hocalist.credit_batches WHERE user_id=p_user AND funding_kind='standard' AND id<>pool AND balance_minor>reserved_minor
    AND initial_fee_minor=g.initial_fee_minor AND winning_total_minor=g.winning_total_minor AND rate_version=g.rate_version ORDER BY created_at,id FOR UPDATE LOOP
     amount:=b.balance_minor-b.reserved_minor;
     UPDATE hocalist.credit_batches SET balance_minor=reserved_minor WHERE id=b.id;
     UPDATE hocalist.credit_batches SET balance_minor=balance_minor+amount WHERE id=pool;
     INSERT INTO hocalist.credit_entries(batch_id,kind,amount_minor,reserve_delta_minor) VALUES(b.id,'transfer_out',-amount,0),(pool,'transfer_in',amount,0);
   END LOOP;
 END LOOP;
END $$;
DO $reserve$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_reserve_internal(uuid,uuid,uuid,date,integer)')) INTO d;
 IF strpos(d,'funding_kind=''prepaid''')=0 THEN RAISE EXCEPTION 'Standard reserve definition drift'; END IF;
 d:=replace(d,'funding_kind=''prepaid''','funding_kind IN (''prepaid'',''standard'')');
 d:=replace(d,'SELECT * INTO b FROM hocalist.credit_batches','PERFORM hocalist.standard_wallet_pool(p_user); SELECT * INTO b FROM hocalist.credit_batches');
 EXECUTE d;
 SELECT pg_get_functiondef(to_regprocedure('hocalist.website_purchase_status(uuid)')) INTO d;
 IF strpos(d,'''account'', jsonb_build_object(')=0 THEN RAISE EXCEPTION 'Standard status definition drift'; END IF;
 EXECUTE replace(d,'''account'', jsonb_build_object(','''standard_deposits_enabled'',(SELECT enabled FROM hocalist.standard_wallet_policy WHERE singleton),''account'', jsonb_build_object(');
 SELECT pg_get_functiondef(to_regprocedure('hocalist.website_purchase_status(uuid)')) INTO d;
 d:=replace(d,'''option_id'', c.credit_option_id','''standard_deposit'',c.standard_deposit,''option_id'', c.credit_option_id');
 EXECUTE d;
 SELECT pg_get_functiondef(to_regprocedure('hocalist.stripe_test_pending_checkout(uuid)')) INTO d;
 IF d IS NULL THEN RAISE EXCEPTION 'Standard pending definition drift'; END IF;
 EXECUTE replace(d,'''option_id'',c.credit_option_id','''standard_deposit'',c.standard_deposit,''amount_minor'',c.amount_minor,''option_id'',c.credit_option_id');
END $reserve$;
REVOKE ALL ON FUNCTION hocalist.stripe_test_standard_deposit_begin(uuid,bigint,uuid),hocalist.standard_deposit_internal(uuid,text,bigint,bigint,bigint,text),hocalist.standard_wallet_pool(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.stripe_test_standard_deposit_begin(uuid,bigint,uuid) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

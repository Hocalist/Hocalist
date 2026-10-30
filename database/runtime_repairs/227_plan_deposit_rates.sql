-- New deposits use the seller's verified plan. Existing snapshots are immutable.
-- Standard-rate funding is deliberately not introduced by this repair.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

CREATE TABLE hocalist.credit_plan_deposit_rates (
 plan_code text NOT NULL CHECK (plan_code IN ('free','pro','elite')),
 amount_minor bigint NOT NULL CHECK (amount_minor IN (2000,4000)),
 initial_fee_minor bigint NOT NULL CHECK (initial_fee_minor>=0),
 winning_total_minor bigint NOT NULL CHECK (winning_total_minor>=initial_fee_minor AND winning_total_minor<=amount_minor),
 rate_version text NOT NULL CHECK(length(btrim(rate_version)) BETWEEN 1 AND 100),
 revision bigint NOT NULL DEFAULT 1 CHECK (revision>0),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(plan_code,amount_minor)
);
ALTER TABLE hocalist.credit_plan_deposit_rates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.credit_plan_deposit_rates FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO hocalist.credit_plan_deposit_rates(plan_code,amount_minor,initial_fee_minor,winning_total_minor,rate_version) VALUES
 ('free',2000,195,475,'plan-pack-v1'),('free',4000,185,450,'plan-pack-v1'),
 ('pro',2000,175,460,'plan-pack-v1'),('pro',4000,165,450,'plan-pack-v1'),
 ('elite',2000,155,375,'plan-pack-v1'),('elite',4000,145,325,'plan-pack-v1');

-- This private projection preserves option IDs and existing client contracts.
CREATE FUNCTION hocalist.credit_deposit_options_for_user(p_user uuid)
RETURNS TABLE(id uuid,amount_minor bigint,initial_fee_minor bigint,winning_total_minor bigint,
 rate_version text,active boolean,revision bigint,sort_order integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT o.id,o.amount_minor,r.initial_fee_minor,r.winning_total_minor,
 left(r.rate_version,60)||':'||r.plan_code||':'||r.revision::text,o.active,greatest(o.revision,r.revision),o.sort_order
 FROM hocalist.credit_deposit_options o
 JOIN hocalist.credit_plan_deposit_rates r ON r.amount_minor=o.amount_minor
 AND r.plan_code=hocalist.marketplace_seller_plan(p_user)
 WHERE o.active
$$;
REVOKE ALL ON FUNCTION hocalist.credit_deposit_options_for_user(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Preserve function identity/ACLs and fail closed if the expected source changes.
DO $repair$
DECLARE d text; old text; target text;
BEGIN
 target := 'hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)';
 SELECT pg_get_functiondef(to_regprocedure(target)) INTO d;
 old := 'SELECT * INTO o FROM hocalist.credit_deposit_options WHERE id=p_option AND active;';
 IF d IS NULL OR strpos(d,old)=0 THEN RAISE EXCEPTION 'Deposit begin definition drift'; END IF;
 d := replace(d,'o hocalist.credit_deposit_options%ROWTYPE;','o record;');
 d := replace(d,old,'SELECT * INTO o FROM hocalist.credit_deposit_options_for_user(p_user) WHERE id=p_option AND active;');
 EXECUTE d;
 FOREACH target IN ARRAY ARRAY['hocalist.credit_wallet()','hocalist.commercial_credit_wallet()','hocalist.website_purchase_status(uuid)'] LOOP
   IF to_regprocedure(target) IS NULL THEN CONTINUE; END IF;
   SELECT pg_get_functiondef(to_regprocedure(target)) INTO d;
   old := 'FROM hocalist.credit_deposit_options WHERE active';
   IF strpos(d,old)=0 THEN RAISE EXCEPTION 'Wallet definition drift: %',target; END IF;
   EXECUTE replace(d,old,'FROM hocalist.credit_deposit_options_for_user(u) WHERE active');
 END LOOP;
END $repair$;

-- Reuse the existing authenticated admin command, receipt and MFA guard.
DO $admin$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_admin_command(text,text,jsonb)')) INTO d;
 IF d IS NULL OR strpos(d,'''deposit_option.set'',''deposit_option.retire'',''reward_policy.set''')=0
 OR strpos(d,'IF p_operation=''deposit_option.set'' THEN')=0 THEN
   RAISE EXCEPTION 'Credit admin definition drift';
 END IF;
 d:=replace(d,'''deposit_option.set'',''deposit_option.retire'',''reward_policy.set''',
 '''deposit_option.set'',''deposit_option.retire'',''reward_policy.set'',''plan_deposit_rate.set''');
 d:=replace(d,'IF p_operation=''deposit_option.set'' THEN',$branch$
 IF p_operation='plan_deposit_rate.set' THEN
   IF p_input - ARRAY['plan_code','amount_minor','initial_fee_minor','winning_total_minor','rate_version','expected_revision'] <> '{}'::jsonb
     OR p_input->>'expected_revision' IS NULL THEN
     RAISE EXCEPTION 'invalid_option' USING ERRCODE='22023';
   END IF;
   UPDATE hocalist.credit_plan_deposit_rates SET
     initial_fee_minor=(p_input->>'initial_fee_minor')::bigint,
     winning_total_minor=(p_input->>'winning_total_minor')::bigint,
     rate_version=btrim(p_input->>'rate_version'),revision=revision+1,updated_at=now()
   WHERE plan_code=p_input->>'plan_code' AND amount_minor=(p_input->>'amount_minor')::bigint
     AND revision=(p_input->>'expected_revision')::bigint;
   IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
   result:=jsonb_build_object('plan_code',p_input->>'plan_code','amount_minor',(p_input->>'amount_minor')::bigint);
 ELSIF p_operation='deposit_option.set' THEN
   IF (p_input->>'amount_minor')::bigint NOT IN (2000,4000) THEN
     RAISE EXCEPTION 'Only approved 20 and 40 HC deposits are available' USING ERRCODE='22023';
   END IF;
 $branch$);
 EXECUTE d;
 IF to_regprocedure('hocalist.admin_commercial_config()') IS NOT NULL THEN
   SELECT pg_get_functiondef(to_regprocedure('hocalist.admin_commercial_config()')) INTO d;
   IF strpos(d,'RETURN jsonb_build_object(')=0 THEN RAISE EXCEPTION 'Admin read definition drift'; END IF;
   EXECUTE replace(d,'RETURN jsonb_build_object(',$read$
   RETURN jsonb_build_object('plan_deposit_rates',
     (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.plan_code,r.amount_minor) FROM hocalist.credit_plan_deposit_rates r),
   $read$);
 END IF;
END $admin$;
NOTIFY pgrst,'reload schema';
COMMIT;

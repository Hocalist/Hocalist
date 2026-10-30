-- Approved prepaid discount bands. Amounts are published by admin, never
-- supplied as a price by the checkout browser. No below-20 wallet invented.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE OR REPLACE FUNCTION hocalist.credit_deposit_options_for_user(p_user uuid)
RETURNS TABLE(id uuid,amount_minor bigint,initial_fee_minor bigint,winning_total_minor bigint,
 rate_version text,active boolean,revision bigint,sort_order integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT o.id,o.amount_minor,r.initial_fee_minor,r.winning_total_minor,
 left(r.rate_version,60)||':'||r.plan_code||':'||r.revision::text,o.active,greatest(o.revision,r.revision),o.sort_order
 FROM hocalist.credit_deposit_options o
 JOIN hocalist.credit_plan_deposit_rates r
 ON r.amount_minor=CASE WHEN o.amount_minor>=4000 THEN 4000 WHEN o.amount_minor>=2000 THEN 2000 ELSE NULL END
 AND r.plan_code=hocalist.marketplace_seller_plan(p_user)
 WHERE o.active
$$;
DO $admin$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_admin_command(text,text,jsonb)')) INTO d;
 IF strpos(d,'(p_input->>''amount_minor'')::bigint NOT IN (2000,4000)')=0 THEN
  RAISE EXCEPTION 'Deposit band admin prerequisite drift'; END IF;
 d:=replace(d,'(p_input->>''amount_minor'')::bigint NOT IN (2000,4000)','(p_input->>''amount_minor'')::bigint < 2000');
 d:=replace(d,'Only approved 20 and 40 HC deposits are available','Prepaid deposits start at 20 HC');
 EXECUTE d;
END $admin$;
NOTIFY pgrst,'reload schema';
COMMIT;

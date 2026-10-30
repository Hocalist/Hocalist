-- Authenticated plan comparison uses published rates for all three tiers.
-- Read-only projection: no charge, rate change or activation.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $comparison$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.website_purchase_status(uuid)')) INTO d;
 IF d IS NULL OR strpos(d,'''account'', jsonb_build_object(')=0 THEN RAISE EXCEPTION 'Plan fee comparison definition drift'; END IF;
 EXECUTE replace(d,'''account'', jsonb_build_object(',$projection$
 'plan_fee_rates',(SELECT jsonb_agg(jsonb_build_object('plan_code',s.plan_code,'initial_minor',s.initial_minor,'winning_minor',s.winning_minor,
 'deposits',coalesce((SELECT jsonb_agg(jsonb_build_object('amount_minor',r.amount_minor,'initial_fee_minor',r.initial_fee_minor,'winning_total_minor',r.winning_total_minor) ORDER BY r.amount_minor)
 FROM hocalist.credit_plan_deposit_rates r WHERE r.plan_code=s.plan_code AND EXISTS(SELECT 1 FROM hocalist.credit_deposit_options o WHERE o.active AND o.amount_minor=r.amount_minor)),'[]'::jsonb)) ORDER BY s.plan_code) FROM hocalist.paygo_plan_rates s),
 'account', jsonb_build_object(
 $projection$);
END $comparison$;
NOTIFY pgrst,'reload schema';
COMMIT;

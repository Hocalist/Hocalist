-- Administrators manage future standard rates through the existing audited,
-- MFA-protected command. This does not enable collection or reprice targets.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $admin$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_admin_command(text,text,jsonb)')) INTO d;
 IF d IS NULL OR strpos(d,'''plan_deposit_rate.set''')=0 OR strpos(d,'IF p_operation=''plan_deposit_rate.set'' THEN')=0 THEN RAISE EXCEPTION 'Plan rate admin definition drift'; END IF;
 d:=replace(d,'''plan_deposit_rate.set''','''plan_deposit_rate.set'',''paygo_plan_rate.set''');
 -- The operation-list replacement above also touches the equality test.
 d:=replace(d,'IF p_operation=''plan_deposit_rate.set'',''paygo_plan_rate.set'' THEN',$branch$
 IF p_operation='paygo_plan_rate.set' THEN
   IF p_input - ARRAY['plan_code','initial_minor','winning_minor','expected_revision'] <> '{}'::jsonb OR p_input->>'expected_revision' IS NULL THEN RAISE EXCEPTION 'invalid_option' USING ERRCODE='22023'; END IF;
   UPDATE hocalist.paygo_plan_rates SET initial_minor=(p_input->>'initial_minor')::bigint,winning_minor=(p_input->>'winning_minor')::bigint,revision=revision+1
   WHERE plan_code=p_input->>'plan_code' AND revision=(p_input->>'expected_revision')::bigint;
   IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
   result:=jsonb_build_object('plan_code',p_input->>'plan_code');
 ELSIF p_operation='plan_deposit_rate.set' THEN
 $branch$);
 EXECUTE d;
 SELECT pg_get_functiondef(to_regprocedure('hocalist.admin_commercial_config()')) INTO d;
 IF d IS NULL OR strpos(d,'RETURN jsonb_build_object(')=0 THEN RAISE EXCEPTION 'Commercial config definition drift'; END IF;
 EXECUTE replace(d,'RETURN jsonb_build_object(',
 'RETURN jsonb_build_object(''paygo_plan_rates'',(SELECT jsonb_agg(to_jsonb(r) ORDER BY r.plan_code) FROM hocalist.paygo_plan_rates r),');
END $admin$;
NOTIFY pgrst,'reload schema';
COMMIT;

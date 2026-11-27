-- Extend the existing response without replacing profile visibility checks.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $profile_plan$
DECLARE
  target regprocedure := to_regprocedure('hocalist.seller_profile_public(uuid)');
  definition text := pg_get_functiondef(target);
  old_return constant text := 'RETURN jsonb_build_object(''available'',true,';
  new_return constant text := 'RETURN jsonb_build_object(''available'',true,''plan_code'',hocalist.marketplace_seller_plan(u),';
BEGIN
  IF to_regprocedure('hocalist.marketplace_seller_plan(uuid)') IS NULL
     OR definition IS NULL
     OR (strpos(definition, old_return) = 0 AND strpos(definition, new_return) = 0) THEN
    RAISE EXCEPTION 'Seller profile contract drift: review before applying';
  END IF;
  IF strpos(definition, new_return) = 0 THEN
    EXECUTE replace(definition, old_return, new_return);
  END IF;
END $profile_plan$;
NOTIFY pgrst, 'reload schema';
COMMIT;

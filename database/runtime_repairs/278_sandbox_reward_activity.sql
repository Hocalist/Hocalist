-- Return the original grant independently of the remaining withdrawable balance.
DO $patch$
DECLARE
  definition text := pg_get_functiondef('hocalist.commercial_reward_wallet()'::regprocedure);
  anchor text := '''earned_minor'',coalesce((select amount_minor from hocalist.sandbox_reward_credits where buyer_id=u),v_earned)';
BEGIN
  IF strpos(definition, '''test_credit_minor''') > 0 THEN RETURN; END IF;
  IF strpos(definition, anchor) = 0 THEN RAISE EXCEPTION 'Unexpected reward wallet definition'; END IF;
  EXECUTE replace(definition, anchor, anchor || ', ''test_credit_minor'',(select amount_minor from hocalist.sandbox_reward_credits where buyer_id=u)');
END $patch$;

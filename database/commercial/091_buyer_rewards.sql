-- Separate buyer reward ledger. No payout execution or automatic accrual.
BEGIN;
CREATE TABLE hocalist.buyer_rewards (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 outcome_id uuid NOT NULL UNIQUE REFERENCES hocalist.sale_confirmations(id),
 target_id uuid NOT NULL UNIQUE REFERENCES hocalist.credit_targets(id),
 buyer_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 amount_minor bigint NOT NULL CHECK(amount_minor>0),
 rule_version text NOT NULL CHECK(length(rule_version) BETWEEN 1 AND 100),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.buyer_rewards ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.buyer_rewards FROM PUBLIC,anon,authenticated,service_role;
-- Only a subsequently approved settlement path may execute this helper.
-- Rates and late-window qualification are deliberately not inferred here.
CREATE FUNCTION hocalist.reward_accrue_internal(p_outcome uuid,p_target uuid,p_amount bigint,p_rule text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE outcome hocalist.sale_confirmations%ROWTYPE;target hocalist.credit_targets%ROWTYPE;reward hocalist.buyer_rewards%ROWTYPE;
BEGIN
 IF p_amount IS NULL OR p_amount<=0 OR p_rule IS NULL OR length(btrim(p_rule)) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_reward'; END IF;
 SELECT * INTO STRICT outcome FROM hocalist.sale_confirmations WHERE id=p_outcome;
 -- Same lock as credit settlement: never accrue concurrently with a refund.
 PERFORM 1 FROM hocalist.profiles WHERE id=outcome.seller_user_id FOR UPDATE;
 SELECT * INTO target FROM hocalist.credit_targets WHERE id=p_target;
 IF NOT FOUND OR target.request_id<>outcome.request_id OR target.user_id<>outcome.seller_user_id
  OR target.status<>'won' OR target.charged_minor<>target.winning_minor OR target.charged_minor<=0 THEN
  RAISE EXCEPTION 'collected_sale_fee_required'; END IF;
 SELECT * INTO reward FROM hocalist.buyer_rewards WHERE outcome_id=p_outcome;
 IF FOUND THEN
  IF reward.target_id<>p_target OR reward.amount_minor<>p_amount OR reward.rule_version<>p_rule THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
  RETURN reward.id;
 END IF;
 INSERT INTO hocalist.buyer_rewards(outcome_id,target_id,buyer_user_id,amount_minor,rule_version)
 VALUES(p_outcome,p_target,outcome.buyer_user_id,p_amount,p_rule) RETURNING * INTO reward;
 RETURN reward.id;
END $$;
CREATE FUNCTION hocalist.reward_wallet() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();
BEGIN
 IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='buyer' AND status='active')
  OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('currency','USD','withdrawals_enabled',false,
  'earned_minor',coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r JOIN hocalist.credit_targets t ON t.id=r.target_id WHERE r.buyer_user_id=u AND t.status='won'),0),
  'items',coalesce((SELECT jsonb_agg(x.data ORDER BY x.created_at DESC,x.id DESC) FROM (
   SELECT r.id,r.created_at,jsonb_build_object('id',r.id,'amount_minor',r.amount_minor,'created_at',r.created_at,
    'status',CASE WHEN t.status='won' THEN 'earned' ELSE 'held' END) AS data
   FROM hocalist.buyer_rewards r JOIN hocalist.credit_targets t ON t.id=r.target_id
   WHERE r.buyer_user_id=u ORDER BY r.created_at DESC,r.id DESC LIMIT 50) x),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION hocalist.reward_accrue_internal(uuid,uuid,bigint,text),hocalist.reward_wallet() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.reward_wallet() TO authenticated;
COMMIT;

-- Only server functions using the service role may bind an authenticated buyer
-- to a Stripe recipient. Keep sandbox and live namespaces distinct.
CREATE TABLE IF NOT EXISTS hocalist.stripe_reward_recipients (
 user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 environment text NOT NULL CHECK(environment IN ('sandbox','live')),
 recipient_id text NOT NULL CHECK(recipient_id LIKE 'acct_%'),
 PRIMARY KEY(user_id,environment), UNIQUE(environment,recipient_id)
);
ALTER TABLE hocalist.stripe_reward_recipients ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.stripe_reward_recipients FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON hocalist.stripe_reward_recipients TO service_role;

CREATE OR REPLACE FUNCTION hocalist.stripe_reward_destination_internal(p_withdrawal uuid, p_environment text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('recipient',r.recipient_id,'created_at',w.created_at)
 FROM hocalist.withdrawal_requests w JOIN hocalist.stripe_reward_recipients r
 ON r.user_id=w.user_id AND r.environment=p_environment WHERE w.id=p_withdrawal
$$;
REVOKE ALL ON FUNCTION hocalist.stripe_reward_destination_internal(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION hocalist.stripe_reward_destination_internal(uuid,text) TO service_role;

-- Shared-project sandbox support. Credit allocation, provider activation and
-- worker credentials are explicit operations and are not seeded by this file.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS hocalist.sandbox_reward_credits (
  buyer_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0)
);
ALTER TABLE hocalist.sandbox_reward_credits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.sandbox_reward_credits FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION hocalist.sandbox_reward_available(p_user uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT greatest(0, c.amount_minor - coalesce((
    SELECT sum(w.amount_minor) FROM hocalist.withdrawal_requests w
    WHERE w.user_id=c.buyer_id AND w.provider='stripe_global_sandbox'
      AND w.status IN ('processing','paid')
  ),0)) FROM hocalist.sandbox_reward_credits c WHERE c.buyer_id=p_user
$$;
REVOKE ALL ON FUNCTION hocalist.sandbox_reward_available(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION hocalist.guard_sandbox_reward_request()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM hocalist.sandbox_reward_credits WHERE buyer_id=NEW.user_id) THEN
    IF TG_OP='INSERT' THEN
      NEW.provider := 'stripe_global_sandbox';
    ELSIF OLD.provider='stripe_global_sandbox' AND (
      NEW.provider IS DISTINCT FROM OLD.provider OR NEW.user_id<>OLD.user_id OR
      NEW.amount_minor<>OLD.amount_minor OR
      (NEW.status='paid' AND coalesce(NEW.provider_reference,'') !~ '^poi_')
    ) THEN
      RAISE EXCEPTION 'sandbox_payout_binding_required';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE OR REPLACE TRIGGER sandbox_reward_request BEFORE INSERT OR UPDATE ON hocalist.withdrawal_requests
FOR EACH ROW EXECUTE FUNCTION hocalist.guard_sandbox_reward_request();

CREATE OR REPLACE FUNCTION hocalist.guard_sandbox_reward_attempt()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM hocalist.withdrawal_requests w WHERE w.id=NEW.withdrawal_id
    AND w.provider='stripe_global_sandbox') <> (NEW.provider_key='stripe_global_sandbox') THEN
    RAISE EXCEPTION 'sandbox_payout_binding_required';
  END IF;
  RETURN NEW;
END $$;
CREATE OR REPLACE TRIGGER sandbox_reward_attempt BEFORE INSERT OR UPDATE ON hocalist.payout_attempts
FOR EACH ROW EXECUTE FUNCTION hocalist.guard_sandbox_reward_attempt();

-- Preserve the deployed Hocalist eligibility, corrections and admission rules.
DO $setup$
DECLARE d text; a text;
BEGIN
  SELECT pg_get_functiondef('hocalist.withdrawal_available_minor(uuid)'::regprocedure) INTO d;
  IF position('sandbox_reward_available' IN d)=0 THEN
    IF position('SELECT greatest(0,' IN d)=0 OR position('commercial_reward_hold_minor(p_user));' IN d)=0
      THEN RAISE EXCEPTION 'available definition mismatch'; END IF;
    EXECUTE replace(replace(d,'SELECT greatest(0,','SELECT coalesce(hocalist.sandbox_reward_available(p_user),greatest(0,'),
      'commercial_reward_hold_minor(p_user));','commercial_reward_hold_minor(p_user)));');
  END IF;
  SELECT pg_get_functiondef('hocalist.commercial_reward_wallet()'::regprocedure) INTO d;
  IF position('sandbox_reward_credits' IN d)=0 THEN
    a := '''available_minor'',greatest(0,v_earned-v_processing-v_paid-v_holds)';
    IF position(a IN d)=0 THEN RAISE EXCEPTION 'wallet definition mismatch'; END IF;
    EXECUTE replace(replace(d,a,'''available_minor'',hocalist.withdrawal_available_minor(u)'),
      '''earned_minor'',v_earned','''earned_minor'',coalesce((select amount_minor from hocalist.sandbox_reward_credits where buyer_id=u),v_earned)');
  END IF;
  SELECT pg_get_functiondef('hocalist.payout_claim_internal(integer,text)'::regprocedure) INTO d;
  IF position('stripe_global_sandbox' IN d)=0 THEN
    a := 'WHERE w.status=''processing''';
    IF position(a IN d)=0 THEN RAISE EXCEPTION 'claim definition mismatch'; END IF;
    EXECUTE replace(d,a,a||' AND (w.provider IS NOT DISTINCT FROM ''stripe_global_sandbox'') = (pol.provider_key=''stripe_global_sandbox'')');
  END IF;
END $setup$;

CREATE OR REPLACE FUNCTION hocalist.sandbox_payout_execution_guard()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT jsonb_build_object('ready',
    EXISTS (SELECT 1 FROM hocalist.payout_policy WHERE singleton AND execution_enabled
      AND provider_key='stripe_global_sandbox')
    AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.payout_attempts'::regclass
      AND tgname='sandbox_reward_attempt' AND tgenabled='O')
    AND NOT EXISTS (SELECT 1 FROM hocalist.withdrawal_requests w
      LEFT JOIN hocalist.sandbox_reward_credits c ON c.buyer_id=w.user_id
      WHERE w.provider='stripe_global_sandbox' AND c.buyer_id IS NULL))
$$;
CREATE OR REPLACE FUNCTION hocalist.stripe_reward_destination_internal(p_withdrawal uuid,p_environment text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT jsonb_build_object('recipient',r.recipient_id,'created_at',w.created_at)
  FROM hocalist.withdrawal_requests w JOIN hocalist.stripe_reward_recipients r
    ON r.user_id=w.user_id AND r.environment=p_environment
  JOIN hocalist.sandbox_reward_credits c ON c.buyer_id=w.user_id
  WHERE w.id=p_withdrawal AND w.status='processing' AND w.provider='stripe_global_sandbox'
    AND p_environment='sandbox'
$$;
REVOKE ALL ON FUNCTION hocalist.sandbox_payout_execution_guard(),hocalist.stripe_reward_destination_internal(uuid,text)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION hocalist.sandbox_payout_execution_guard(),hocalist.stripe_reward_destination_internal(uuid,text)
TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

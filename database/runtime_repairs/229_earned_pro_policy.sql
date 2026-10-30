-- Approved seven-sale following-month benefit. UTC is the platform calendar,
-- consistent with the existing weekly capacity clock; editable by admin policy.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
UPDATE hocalist.entitlement_policy SET earned_pro_threshold=7,
 calendar_timezone=coalesce(calendar_timezone,'UTC'),
 paid_overlap='paid_priority',annual_enabled=true,trial_days=14,
 policy_version='approved-commercial-v1',revision=revision+1,updated_at=now()
WHERE singleton;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM hocalist.entitlement_policy WHERE singleton) THEN
  RAISE EXCEPTION 'Entitlement policy prerequisite missing';
 END IF;
END $$;
-- Annual checkout/trial creation still requires a verified provider catalogue;
-- these policy flags do not manufacture prices or grant unpaid subscriptions.
NOTIFY pgrst,'reload schema';
COMMIT;

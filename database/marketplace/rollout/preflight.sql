-- Hocalist marketplace rollout preflight. READ-ONLY: safe to run repeatedly.
--
-- Validates the deployed account 003/004 baseline and aborts on any drift or
-- pre-existing marketplace object. The DO block is textually identical to the
-- guard in apply.sql; database/marketplace/tests/marketplace_rollout.test.mjs
-- asserts it. Chat 010 is expected to be deployed first.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $marketplace_guard$
BEGIN
  IF to_regclass('hocalist.profiles') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regclass('hocalist.role_profiles') IS NULL
     OR to_regclass('hocalist.profile_contacts') IS NULL
     OR to_regprocedure('hocalist.account_command(text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Account foundation 002/003/004 is missing';
  END IF;
  IF to_regclass('hocalist.requests') IS NOT NULL
     OR to_regclass('hocalist.offers') IS NOT NULL
     OR to_regclass('hocalist.store_listings') IS NOT NULL
     OR to_regprocedure('hocalist.marketplace_command(text,text,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'Marketplace objects already exist; review before applying';
  END IF;
END
$marketplace_guard$;
ROLLBACK;
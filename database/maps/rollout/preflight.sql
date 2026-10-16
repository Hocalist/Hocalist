-- Hocalist Places gateway rollout preflight. READ-ONLY: safe to run repeatedly.
--
-- Validates the deployed account 003/004 baseline and aborts on any
-- pre-existing places gateway object. The DO block is textually identical to
-- the guard in apply.sql; database/maps/tests/places_rollout.test.mjs asserts
-- it.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $places_guard$
BEGIN
  IF to_regclass('hocalist.profiles') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regprocedure('hocalist.account_command(text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Account foundation is missing';
  END IF;
  IF to_regclass('hocalist.places_search_sessions') IS NOT NULL
     OR to_regprocedure('hocalist.places_gate(uuid,text,uuid,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Places gateway objects already exist; review before applying';
  END IF;
END
$places_guard$;
SELECT 'places preflight passed' AS status;
COMMIT;

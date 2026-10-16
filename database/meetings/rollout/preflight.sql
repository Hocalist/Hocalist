-- Hocalist meeting rollout preflight. READ-ONLY: safe to run repeatedly.
--
-- Validates the deployed account 003/004, chat 010 and marketplace 020
-- baseline and aborts on any pre-existing meeting object. The DO block is
-- textually identical to the guard in apply.sql; database/meetings/tests/
-- meetings_rollout.test.mjs asserts it.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $meeting_guard$
BEGIN
  IF to_regclass('hocalist.profiles') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regclass('hocalist.conversations') IS NULL
     OR to_regclass('hocalist.conversation_members') IS NULL
     OR to_regclass('hocalist.offers') IS NULL
     OR to_regprocedure('hocalist.account_command(text,text,jsonb)') IS NULL
     OR to_regprocedure('hocalist.marketplace_valid_timezone(text)') IS NULL
     OR to_regprocedure('hocalist.marketplace_next_local_day_start(date,text)') IS NULL THEN
    RAISE EXCEPTION 'Account/chat/marketplace foundation is missing';
  END IF;
  IF to_regclass('hocalist.meetings') IS NOT NULL
     OR to_regclass('hocalist.meeting_receipts') IS NOT NULL
     OR to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)') IS NOT NULL
     OR to_regprocedure('hocalist.meeting_propose(uuid,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'Meeting objects already exist; review before applying';
  END IF;
END
$meeting_guard$;
SELECT 'meeting preflight passed' AS status;
COMMIT;

-- Hocalist notification inbox rollout preflight. READ-ONLY: safe to run repeatedly.
--
-- Validates the deployed account 003/004 and push 007 baseline, and aborts on
-- any pre-existing notification inbox object. The DO block is textually
-- identical to the guard in apply.sql; database/notifications/tests/
-- notifications_rollout.test.mjs asserts it.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $notification_guard$
BEGIN
  IF to_regclass('hocalist.profiles') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regclass('hocalist.notifications') IS NULL
     OR to_regclass('hocalist.push_devices') IS NULL
     OR to_regclass('hocalist.push_deliveries') IS NULL
     OR to_regprocedure('hocalist.notification_enqueue(uuid,uuid,text,uuid)') IS NULL
     OR to_regprocedure('hocalist.account_command(text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Account/push foundation 003/004/007 is missing';
  END IF;
  IF to_regclass('hocalist.notification_preferences') IS NOT NULL
     OR to_regprocedure('hocalist.notification_inbox(integer,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Notification inbox objects already exist; review before applying';
  END IF;
END
$notification_guard$;
SELECT 'notification inbox preflight passed' AS status;
COMMIT;

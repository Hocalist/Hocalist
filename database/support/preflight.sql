-- Private support cases. No automatic account penalties or financial action.
BEGIN READ ONLY;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL THEN RAISE EXCEPTION 'Marketplace admin prerequisite missing'; END IF;
 IF to_regclass('hocalist.support_cases') IS NOT NULL THEN RAISE EXCEPTION 'Support already installed'; END IF;
END; $guard$;
COMMIT;

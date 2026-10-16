-- Hocalist notification inbox containment: grants-only withdrawal.
--
-- Revokes client execution of the notification inbox RPCs without deleting
-- rows or changing the deployed push queue. Keep it for rollback decisions; it
-- is not a schema rollback.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
REVOKE EXECUTE ON FUNCTION hocalist.notification_inbox(integer,text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION hocalist.notification_mark_read(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION hocalist.notification_mark_all_read() FROM authenticated;
REVOKE EXECUTE ON FUNCTION hocalist.notification_preferences() FROM authenticated;
REVOKE EXECUTE ON FUNCTION hocalist.notification_preferences_update(jsonb) FROM authenticated;
COMMIT;

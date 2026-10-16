-- Hocalist meeting containment: grants-only withdrawal.
--
-- Revokes client execution of the meeting RPCs without deleting rows. Keep it
-- for rollback decisions; it is not a schema rollback.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
REVOKE EXECUTE ON FUNCTION hocalist.meeting_propose(uuid,jsonb,text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION hocalist.meeting_respond(uuid,boolean,bigint,text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION hocalist.meeting_cancel(uuid,bigint,text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION hocalist.meeting_detail(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION hocalist.meeting_list(text,integer,text) FROM authenticated;
COMMIT;

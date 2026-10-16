-- Containment for a suspicious apply: remove every client capability the
-- upgrade added without deleting ledger, review or withdrawal history.
-- Replaced function bodies stay in place; this is not a destructive rollback.
BEGIN;
REVOKE ALL ON FUNCTION hocalist.credit_wallet() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.reward_wallet() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.credit_admin_command(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.withdrawal_status() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.withdrawal_request(text,bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.admin_withdrawal_queue(integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.credit_deposit_status() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.verification_submit(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.verification_status() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.account_health_status() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.restriction_appeal_submit(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.admin_trust_queue(integer) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.admin_trust_command(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.marketplace_command(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.stripe_test_deposit_begin(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.stripe_test_deposit_bind(uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.withdrawal_settle_internal(uuid,text,text,text,text) FROM service_role;
GRANT EXECUTE ON FUNCTION hocalist.marketplace_command(text,text,jsonb) TO authenticated;
COMMIT;

-- Containment for a suspicious apply: remove every client capability the
-- account-completion bundle added without deleting consent, export, request,
-- category or evidence history. Replaced function bodies stay in place; this
-- is not a destructive rollback.
BEGIN;
REVOKE ALL ON FUNCTION hocalist.account_lifecycle_status() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.account_consent_record(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.account_export_request(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.account_export_read(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.account_deletion_request(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.account_deletion_cancel(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.admin_account_lifecycle_command(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.seller_profile_categories() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.member_seller_categories(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.profile_categories_update(text,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.review_evidence_attach(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.review_evidence_detach(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.report_evidence_attach(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.report_evidence_detach(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.admin_review_evidence(integer) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.admin_evidence_hold(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.media_cleanup_plan(integer) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.media_cleanup_apply(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.media_gateway(uuid,text,jsonb) TO service_role;

COMMIT;

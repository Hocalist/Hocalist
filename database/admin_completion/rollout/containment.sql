-- Containment for a suspicious apply: remove every administrator read this
-- bundle added. No table, row, ledger or audit history is deleted.
BEGIN;
REVOKE ALL ON FUNCTION hocalist.admin_commercial_config() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.admin_review_queue(integer,text,text,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.admin_evidence_reference(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.admin_failed_events(integer,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.admin_failed_event_detail(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.admin_audit_feed(integer,text,text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

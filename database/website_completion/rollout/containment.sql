-- Containment for a suspicious apply: remove the public waitlist intake and
-- the service-role portal helper without deleting stored signups.
-- The waitlist table and its history stay in place; this is not a
-- destructive rollback and not a repair script for arbitrary drift.
BEGIN;
REVOKE ALL ON FUNCTION hocalist.website_waitlist_join(text,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.website_purchase_status(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.stripe_test_portal_access(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.website_waitlist_configure(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.website_waitlist_set_caps(integer,integer) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION hocalist.website_checkout_context(text) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

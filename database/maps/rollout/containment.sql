-- Hocalist Places gateway containment: grants-only withdrawal.
--
-- Revokes service-role execution of the gateway RPCs without deleting rows, so
-- the deployed hocalist-places Edge Function can no longer gate, record or
-- resolve provider calls. Disabling the Edge Function itself (or removing the
-- HOCALIST_GOOGLE_PLACES_SERVER_API_KEY secret and the enabled flag) is the
-- outer kill switch. Keep this file for rollback decisions; it is not a schema
-- rollback.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
REVOKE EXECUTE ON FUNCTION hocalist.places_gate(uuid,text,uuid,text,text)
  FROM service_role;
REVOKE EXECUTE ON FUNCTION hocalist.places_record_suggestions(uuid,uuid,text[])
  FROM service_role;
REVOKE EXECUTE ON FUNCTION hocalist.places_resolve_session(uuid,uuid)
  FROM service_role;
REVOKE EXECUTE ON FUNCTION hocalist.places_release_session(uuid,uuid)
  FROM service_role;
COMMIT;

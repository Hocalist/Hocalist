-- Reversible access withdrawal. Leaves all existing data and functions intact.
BEGIN;
REVOKE ALL ON FUNCTION hocalist.admin_records(text,integer,uuid,text,text),hocalist.admin_overview()
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

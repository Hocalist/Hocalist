-- Withdraw the support API without deleting reports or audit history.
BEGIN;
REVOKE ALL ON FUNCTION hocalist.support_reasons(boolean),hocalist.support_list(integer,uuid,boolean),hocalist.support_command(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

BEGIN READ ONLY;
DO $verify$ BEGIN
IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='hocalist.marketplace_normalize_request(jsonb)'::regprocedure) IS DISTINCT FROM 'bf6547d36878420357cfa004e4b4a7a7' THEN RAISE EXCEPTION 'coordinate function mismatch: marketplace_normalize_request'; END IF;
IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='hocalist.marketplace_request_json(uuid)'::regprocedure) IS DISTINCT FROM 'cc5ac511f0e9a1f44fda0464a796ef05' THEN RAISE EXCEPTION 'coordinate function mismatch: marketplace_request_json'; END IF;
IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='hocalist.marketplace_command(text,text,jsonb)'::regprocedure) IS DISTINCT FROM '806d4372a5906fd1b6581db8ef006db7' THEN RAISE EXCEPTION 'coordinate function mismatch: marketplace_command'; END IF;

IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='hocalist.requests'::regclass AND conname='request_coordinates_valid' AND convalidated) THEN RAISE EXCEPTION 'coordinate constraint missing'; END IF;
IF has_table_privilege('authenticated','hocalist.requests','SELECT') OR has_table_privilege('anon','hocalist.requests','SELECT') THEN RAISE EXCEPTION 'request table exposed'; END IF;
IF has_function_privilege('authenticated','hocalist.marketplace_request_json(uuid)','EXECUTE') OR has_function_privilege('anon','hocalist.marketplace_request_json(uuid)','EXECUTE') THEN RAISE EXCEPTION 'private serializer exposed'; END IF;
END; $verify$;
SELECT 'request coordinate verification passed' AS result;
COMMIT;

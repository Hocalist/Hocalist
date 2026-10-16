-- Buyer-owned coordinates. Additive migration over reviewed 020; no new grants.
-- Exact function-body guards prevent overwriting subsequent marketplace changes.
BEGIN READ ONLY;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='hocalist.marketplace_normalize_request(jsonb)'::regprocedure) IS DISTINCT FROM '69e5965a288407d4ab0da7adb3caa4c2' THEN
    RAISE EXCEPTION 'Request coordinate baseline drift: marketplace_normalize_request';
  END IF;
  IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='hocalist.marketplace_request_json(uuid)'::regprocedure) IS DISTINCT FROM '49afd7897098d9464420fc054af5d72b' THEN
    RAISE EXCEPTION 'Request coordinate baseline drift: marketplace_request_json';
  END IF;
  IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='hocalist.marketplace_command(text,text,jsonb)'::regprocedure) IS DISTINCT FROM 'ce5eb87875e44cb4e8ef651f0b805112' THEN
    RAISE EXCEPTION 'Request coordinate baseline drift: marketplace_command';
  END IF;
END; $guard$;
COMMIT;

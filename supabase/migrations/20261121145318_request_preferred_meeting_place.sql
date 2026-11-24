-- Request-specific meeting preference. Exact addresses retain existing privacy.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

ALTER TABLE hocalist.requests ADD COLUMN IF NOT EXISTS prefer_meet_here boolean NOT NULL DEFAULT false;

DO $patch$
DECLARE target regprocedure; original text; body text; definition text;
BEGIN
  target := coalesce(to_regprocedure('hocalist.marketplace_normalize_request_before_questions(jsonb)'),
    to_regprocedure('hocalist.marketplace_normalize_request(jsonb)'));
  SELECT prosrc, pg_get_functiondef(oid) INTO original, definition FROM pg_proc WHERE oid=target;
  IF original IS NULL THEN RAISE EXCEPTION 'Request normalizer missing'; END IF;
  IF position('request_meeting_preference_v1' in original)>0 THEN RETURN; END IF;
  IF position('''use_home_address'',' in original)=0 OR position('''use_home_address'', v_use_home,' in original)=0 THEN
    RAISE EXCEPTION 'Request normalizer changed; review before applying';
  END IF;
  body := replace(original, '''use_home_address'',', '''prefer_meet_here'',''use_home_address'',');
  -- The whitelist replacement also touches the output key: restore and add its value.
  body := replace(body, '''prefer_meet_here'',''use_home_address'', v_use_home,',
    '''prefer_meet_here'',coalesce((p_input->>''prefer_meet_here'')::boolean,false),''use_home_address'', v_use_home,');
  body := replace(body, 'BEGIN', 'BEGIN
    -- request_meeting_preference_v1
    IF p_input ? ''prefer_meet_here'' AND jsonb_typeof(p_input->''prefer_meet_here'') <> ''boolean'' THEN
      RAISE EXCEPTION ''invalid_field: prefer_meet_here'' USING ERRCODE=''22023'';
    END IF;');
  EXECUTE replace(definition,original,body);
END $patch$;

DO $patch$
DECLARE original text; body text; definition text;
BEGIN
  SELECT prosrc, pg_get_functiondef(oid) INTO original, definition FROM pg_proc
    WHERE oid='hocalist.marketplace_command(text,text,jsonb)'::regprocedure;
  IF position('request_meeting_preference_v1' in original)>0 THEN RETURN; END IF;
  IF position('v_result := hocalist.marketplace_request_json(v_id);' in original)=0 THEN
    RAISE EXCEPTION 'Request command changed; review before applying';
  END IF;
  body := replace(original, 'v_result := hocalist.marketplace_request_json(v_id);', '
    -- request_meeting_preference_v1: after existing owner/revision checks, before cached response.
    IF p_operation IN (''request.create'',''request.update'') AND p_input ? ''prefer_meet_here'' THEN
      UPDATE hocalist.requests SET prefer_meet_here=(v_norm->>''prefer_meet_here'')::boolean
        WHERE id=v_id AND buyer_user_id=v_user;
    END IF;
    v_result := hocalist.marketplace_request_json(v_id);');
  EXECUTE replace(definition,original,body);
END $patch$;

DO $patch$
DECLARE original text; body text; definition text;
BEGIN
  SELECT prosrc, pg_get_functiondef(oid) INTO original, definition FROM pg_proc
    WHERE oid='hocalist.marketplace_request_json(uuid)'::regprocedure;
  IF position('''prefer_meet_here''' in original)>0 THEN RETURN; END IF;
  IF position('''use_home_address'', r.use_home_address,' in original)=0 THEN
    RAISE EXCEPTION 'Request projection changed; review before applying';
  END IF;
  body := replace(original, '''use_home_address'', r.use_home_address,',
    '''prefer_meet_here'',r.prefer_meet_here,''use_home_address'', r.use_home_address,');
  EXECUTE replace(definition,original,body);
END $patch$;

DO $patch$
DECLARE fn record; body text; changed integer := 0;
BEGIN
  FOR fn IN SELECT oid, prosrc, pg_get_functiondef(oid) AS definition FROM pg_proc
    WHERE pronamespace='hocalist'::regnamespace AND proname IN ('marketplace_lead_json','discovery_lead_json')
  LOOP
    IF position('request_meeting_preference_v1' in fn.prosrc)>0 THEN CONTINUE; END IF;
    IF position('''buyer_display_name'',' in fn.prosrc)=0 THEN
      RAISE EXCEPTION 'Seller projection changed; review before applying';
    END IF;
    -- This key follows the earlier profile-level key, overriding it per request.
    -- No private street, coordinates or saved place identifiers are exposed.
    body := replace(fn.prosrc, '''buyer_display_name'',', '
      /* request_meeting_preference_v1 */
      ''preferred_meetup_label'',CASE WHEN r.prefer_meet_here THEN ''Buyer’s requested location''
        ELSE nullif(btrim(rp.preferred_meetup_type),'''') END,
      ''buyer_display_name'',');
    EXECUTE replace(fn.definition,fn.prosrc,body);
    changed := changed+1;
  END LOOP;
END $patch$;
COMMIT;

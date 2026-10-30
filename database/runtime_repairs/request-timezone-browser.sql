BEGIN;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_normalize_request(jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('4c03c5d16c8ea6a9f169e921edf6a952', 'bf6547d36878420357cfa004e4b4a7a7') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_normalize_request'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_request_json(uuid)') AND md5(replace(prosrc,chr(13),'')) IN ('87344e90fca44ea903a38569fdbd8692', '10fd3c2b23bbba9178052c664d6c4e1e') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_request_json'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('e45fec459978cff4442c7d7ad84f524c', 'c4d2d6dfc061a8fd588577547a91b9b5') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_command'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_lead_json(uuid)') AND md5(replace(prosrc,chr(13),'')) IN ('49648feb929fee5f0b72a149372a1a34', '1bff944a220727b9cfa4ecf1f800f369', '0171b14f5cad3774b07f94ea12bba15d') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_lead_json'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.discovery_lead_json(uuid,double precision,integer,jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('1d6fc727511724f91e0cdffc647652e4', '5f6e35abb8033228ac01f13bff3abb77', '79bdc43e98f636bb785e03350e469882') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: discovery_lead_json'; END IF;
END $guard$;
ALTER TABLE hocalist.requests ADD COLUMN IF NOT EXISTS location_timezone text CHECK(location_timezone IS NULL OR hocalist.marketplace_valid_timezone(location_timezone));
DO $patch$ DECLARE original text; body text; definition text; BEGIN
 SELECT prosrc,pg_get_functiondef(oid) INTO original,definition FROM pg_proc WHERE oid='hocalist.marketplace_normalize_request(jsonb)'::regprocedure;
 IF md5(replace(original,chr(13),''))='4c03c5d16c8ea6a9f169e921edf6a952' THEN RETURN; END IF;
 body:=original;

 body:=replace(body,'''latitude'',''longitude''];','''latitude'',''longitude'',''location_timezone''];');
 body:=replace(body,'BEGIN','BEGIN
  IF p_input->>''location_timezone'' IS NOT NULL AND NOT hocalist.marketplace_valid_timezone(p_input->>''location_timezone'') THEN
    RAISE EXCEPTION ''invalid_field: location_timezone'' USING ERRCODE=''22023'';
  END IF;');
 body:=replace(body,'''latitude'', p_input->''latitude'',','''location_timezone'', p_input->>''location_timezone'', ''latitude'', p_input->''latitude'',');

 EXECUTE replace(definition,original,body);
END $patch$;
DO $patch$ DECLARE original text; body text; definition text; BEGIN
 SELECT prosrc,pg_get_functiondef(oid) INTO original,definition FROM pg_proc WHERE oid='hocalist.marketplace_request_json(uuid)'::regprocedure;
 IF md5(replace(original,chr(13),''))='87344e90fca44ea903a38569fdbd8692' THEN RETURN; END IF;
 body:=original;

 body:=replace(body,'''use_home_address'', r.use_home_address,','''use_home_address'', r.use_home_address, ''timezone_id'', r.location_timezone,');

 EXECUTE replace(definition,original,body);
END $patch$;
DO $patch$ DECLARE original text; body text; definition text; BEGIN
 SELECT prosrc,pg_get_functiondef(oid) INTO original,definition FROM pg_proc WHERE oid='hocalist.marketplace_command(text,text,jsonb)'::regprocedure;
 IF md5(replace(original,chr(13),''))='e45fec459978cff4442c7d7ad84f524c' THEN RETURN; END IF;
 body:=original;

 body:=replace(body,'country_code, latitude, longitude)','country_code, latitude, longitude, location_timezone)');
 body:=replace(body,'(v_norm->>''longitude'')::double precision)','(v_norm->>''longitude'')::double precision, v_norm->>''location_timezone'')');
 body:=replace(body,'latitude = (v_norm->>''latitude'')::double precision,','location_timezone = v_norm->>''location_timezone'',
      latitude = (v_norm->>''latitude'')::double precision,');

 EXECUTE replace(definition,original,body);
END $patch$;
DO $patch$ DECLARE original text; body text; definition text; BEGIN
 SELECT prosrc,pg_get_functiondef(oid) INTO original,definition FROM pg_proc WHERE oid='hocalist.marketplace_lead_json(uuid)'::regprocedure;
 IF md5(replace(original,chr(13),''))='49648feb929fee5f0b72a149372a1a34' THEN RETURN; END IF;
 body:=original;
 IF md5(replace(original,chr(13),''))='0171b14f5cad3774b07f94ea12bba15d' THEN body:=replace(body,'coalesce(rp.area_label, r.city, r.region)','CASE WHEN r.use_home_address THEN rp.area_label ELSE coalesce(nullif(btrim(r.city),''''),nullif(btrim(r.region),''''),rp.area_label) END'); ELSE
 body:=replace(body,'''request_revision'', r.revision,','''location_timezone'', r.location_timezone, ''request_revision'', r.revision,');
 body:=replace(body,'coalesce(rp.area_label, r.city, r.region)','CASE WHEN r.use_home_address THEN rp.area_label ELSE coalesce(nullif(btrim(r.city),''''),nullif(btrim(r.region),''''),rp.area_label) END');
 END IF;
 EXECUTE replace(definition,original,body);
END $patch$;
DO $patch$ DECLARE original text; body text; definition text; BEGIN
 SELECT prosrc,pg_get_functiondef(oid) INTO original,definition FROM pg_proc WHERE oid='hocalist.discovery_lead_json(uuid,double precision,integer,jsonb)'::regprocedure;
 IF md5(replace(original,chr(13),''))='1d6fc727511724f91e0cdffc647652e4' THEN RETURN; END IF;
 body:=original;
 IF md5(replace(original,chr(13),''))='79bdc43e98f636bb785e03350e469882' THEN body:=replace(body,'coalesce(rp.area_label, r.city, r.region)','CASE WHEN r.use_home_address THEN rp.area_label ELSE coalesce(nullif(btrim(r.city),''''),nullif(btrim(r.region),''''),rp.area_label) END'); ELSE
 body:=replace(body,'''request_revision'', r.revision,','''location_timezone'', r.location_timezone, ''request_revision'', r.revision,');
 body:=replace(body,'coalesce(rp.area_label, r.city, r.region)','CASE WHEN r.use_home_address THEN rp.area_label ELSE coalesce(nullif(btrim(r.city),''''),nullif(btrim(r.region),''''),rp.area_label) END');
 END IF;
 EXECUTE replace(definition,original,body);
END $patch$;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_normalize_request(jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('4c03c5d16c8ea6a9f169e921edf6a952') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_normalize_request'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_request_json(uuid)') AND md5(replace(prosrc,chr(13),'')) IN ('87344e90fca44ea903a38569fdbd8692') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_request_json'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('e45fec459978cff4442c7d7ad84f524c') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_command'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_lead_json(uuid)') AND md5(replace(prosrc,chr(13),'')) IN ('49648feb929fee5f0b72a149372a1a34') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_lead_json'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.discovery_lead_json(uuid,double precision,integer,jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('1d6fc727511724f91e0cdffc647652e4') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: discovery_lead_json'; END IF;
END $guard$;
NOTIFY pgrst,'reload schema'; COMMIT;

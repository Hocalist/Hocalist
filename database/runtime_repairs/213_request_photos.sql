-- Request photographs share the request's audience; storage remains private.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
ALTER TABLE hocalist.requests ADD COLUMN image_media_ids jsonb NOT NULL DEFAULT '[]'::jsonb
 CHECK(jsonb_typeof(image_media_ids)='array' AND jsonb_array_length(image_media_ids)<=10);
ALTER TABLE hocalist.media_images DROP CONSTRAINT media_images_purpose_check;
ALTER TABLE hocalist.media_images ADD CONSTRAINT media_images_purpose_check
 CHECK(purpose IN ('offer','store','profile','chat','review','report','request'));

CREATE FUNCTION hocalist.validate_request_photos() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item jsonb;
BEGIN
 IF jsonb_typeof(NEW.image_media_ids)<>'array' OR jsonb_array_length(NEW.image_media_ids)>10 THEN
  RAISE EXCEPTION 'invalid_request_photos' USING ERRCODE='22023'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(NEW.image_media_ids) LOOP
  IF jsonb_typeof(item)<>'string' OR NOT EXISTS(
   SELECT 1 FROM hocalist.media_images WHERE id::text=item#>>'{}'
    AND owner_user_id=NEW.buyer_user_id AND purpose='request' AND state='ready') THEN
   RAISE EXCEPTION 'invalid_media_reference' USING ERRCODE='22023'; END IF;
 END LOOP;
 IF (SELECT count(DISTINCT value) FROM jsonb_array_elements(NEW.image_media_ids))<>jsonb_array_length(NEW.image_media_ids) THEN
  RAISE EXCEPTION 'duplicate_request_photo' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_request_photos BEFORE INSERT OR UPDATE OF image_media_ids ON hocalist.requests
 FOR EACH ROW EXECUTE FUNCTION hocalist.validate_request_photos();
REVOKE ALL ON FUNCTION hocalist.validate_request_photos() FROM PUBLIC,anon,authenticated,service_role;

-- Reuse the exact authenticated request read rather than duplicating its evolving
-- eligibility rules. The verified gateway identity is scoped and restored here.
CREATE FUNCTION hocalist.media_read_request(p_user uuid,p_image uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE request_id uuid; previous_sub text; previous_claims text; allowed boolean:=false;
BEGIN
 previous_sub:=current_setting('request.jwt.claim.sub',true);
 previous_claims:=current_setting('request.jwt.claims',true);
 PERFORM set_config('request.jwt.claim.sub',p_user::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',p_user,'role','authenticated')::text,true);
 FOR request_id IN SELECT id FROM hocalist.requests WHERE image_media_ids ? p_image::text LOOP
  BEGIN
   PERFORM hocalist.marketplace_request(request_id);
   allowed:=true; EXIT;
  EXCEPTION WHEN insufficient_privilege OR no_data_found THEN NULL;
  END;
 END LOOP;
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
 PERFORM set_config('request.jwt.claims',coalesce(previous_claims,''),true);
 RETURN allowed;
END $$;
REVOKE ALL ON FUNCTION hocalist.media_read_request(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Guarded edits preserve the installed fee, receipt, lifecycle and media logic.
DO $patch$
DECLARE definition text; old_body text; body text; signature text;
BEGIN
 SELECT prosrc,pg_get_functiondef(oid) INTO old_body,definition FROM pg_proc
  WHERE oid='hocalist.marketplace_normalize_request(jsonb)'::regprocedure AND prosecdef;
 IF old_body IS NULL OR strpos(old_body,'''location_timezone''];')=0 THEN RAISE EXCEPTION 'request normalizer drift'; END IF;
 body:=replace(old_body,'''location_timezone''];','''location_timezone'',''image_media_ids''];');
 -- The existing normalized object is extended without relaxing other fields.
 body:=replace(body,'''location_timezone'', p_input->>''location_timezone''', '''image_media_ids'',coalesce(p_input->''image_media_ids'',''[]''::jsonb),''location_timezone'', p_input->>''location_timezone''');
 IF body=old_body OR strpos(body,'''image_media_ids'',coalesce')=0 THEN RAISE EXCEPTION 'request normalization patch failed'; END IF;
 EXECUTE replace(definition,old_body,body);

 SELECT prosrc,pg_get_functiondef(oid) INTO old_body,definition FROM pg_proc
  WHERE oid='hocalist.marketplace_command(text,text,jsonb)'::regprocedure AND prosecdef;
 IF old_body IS NULL OR strpos(old_body,'longitude, location_timezone)')=0 OR
    strpos(old_body,'location_timezone = v_norm->>''location_timezone'',')=0 THEN RAISE EXCEPTION 'request command drift'; END IF;
 body:=replace(old_body,'longitude, location_timezone)','longitude, location_timezone, image_media_ids)');
 body:=replace(body,'v_norm->>''location_timezone'')','v_norm->>''location_timezone'', coalesce(v_norm->''image_media_ids'',''[]''::jsonb))');
 body:=replace(body,'location_timezone = v_norm->>''location_timezone'',',
  'image_media_ids = CASE WHEN p_input ? ''image_media_ids'' THEN v_norm->''image_media_ids'' ELSE image_media_ids END, location_timezone = v_norm->>''location_timezone'',');
 EXECUTE replace(definition,old_body,body);

 FOREACH signature IN ARRAY ARRAY['hocalist.marketplace_request_json(uuid)',
  'hocalist.marketplace_lead_json(uuid)','hocalist.discovery_lead_json(uuid,double precision,integer,jsonb)'] LOOP
  SELECT prosrc,pg_get_functiondef(oid) INTO old_body,definition FROM pg_proc WHERE oid=signature::regprocedure AND prosecdef;
  IF old_body IS NULL OR strpos(old_body,'''description'', r.description,')=0 THEN RAISE EXCEPTION 'request projection drift: %',signature; END IF;
  body:=replace(old_body,'''description'', r.description,','''description'', r.description, ''image_media_ids'', r.image_media_ids,');
  EXECUTE replace(definition,old_body,body);
 END LOOP;

 SELECT prosrc,pg_get_functiondef(oid) INTO old_body,definition FROM pg_proc
  WHERE oid='hocalist.media_gateway(uuid,text,jsonb)'::regprocedure AND prosecdef;
 IF old_body IS NULL OR strpos(old_body,'''chat'',''review'',''report'')')=0 OR
    strpos(old_body,'IF NOT v_allowed THEN')=0 THEN RAISE EXCEPTION 'media gateway drift'; END IF;
 body:=replace(old_body,'''chat'',''review'',''report'')','''chat'',''review'',''report'',''request'')');
 body:=replace(body,'PERFORM 1 FROM hocalist.profiles WHERE id = p_user FOR UPDATE;',
  'IF purpose=''request'' THEN PERFORM hocalist.marketplace_assert_role(p_user,''buyer''); END IF;
   PERFORM 1 FROM hocalist.profiles WHERE id = p_user FOR UPDATE;');
 IF strpos(body,'purpose=''request''')=0 THEN RAISE EXCEPTION 'media buyer guard patch failed'; END IF;
 body:=replace(body,'IF NOT v_allowed THEN',
  'IF NOT v_allowed AND m.purpose=''request'' THEN v_allowed:=hocalist.media_read_request(p_user,image_id); END IF;
   IF NOT v_allowed THEN');
 EXECUTE replace(definition,old_body,body);
END $patch$;
NOTIFY pgrst,'reload schema';
COMMIT;

-- Purchase-review photos are separate from confidential account review evidence.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
ALTER TABLE hocalist.outcome_reviews ADD COLUMN image_media_ids jsonb NOT NULL DEFAULT '[]'::jsonb
 CHECK(jsonb_typeof(image_media_ids)='array' AND jsonb_array_length(image_media_ids)<=4);
ALTER TABLE hocalist.media_images DROP CONSTRAINT media_images_purpose_check;
ALTER TABLE hocalist.media_images ADD CONSTRAINT media_images_purpose_check
 CHECK(purpose IN ('offer','store','profile','chat','review','report','request','purchase_review'));

CREATE FUNCTION hocalist.validate_purchase_review_photos() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item jsonb;
BEGIN
 IF jsonb_typeof(NEW.image_media_ids)<>'array' OR jsonb_array_length(NEW.image_media_ids)>4 THEN
  RAISE EXCEPTION 'invalid_review_photos' USING ERRCODE='22023'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(NEW.image_media_ids) LOOP
  IF jsonb_typeof(item)<>'string' OR NOT EXISTS(
   SELECT 1 FROM hocalist.media_images WHERE id::text=item#>>'{}'
    AND owner_user_id=NEW.buyer_user_id AND purpose='purchase_review' AND state='ready') THEN
   RAISE EXCEPTION 'invalid_media_reference' USING ERRCODE='22023'; END IF;
 END LOOP;
 IF (SELECT count(DISTINCT value) FROM jsonb_array_elements(NEW.image_media_ids))<>jsonb_array_length(NEW.image_media_ids) THEN
  RAISE EXCEPTION 'duplicate_review_photo' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_purchase_review_photos BEFORE INSERT OR UPDATE OF image_media_ids ON hocalist.outcome_reviews
 FOR EACH ROW EXECUTE FUNCTION hocalist.validate_purchase_review_photos();
REVOKE ALL ON FUNCTION hocalist.validate_purchase_review_photos() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION hocalist.media_read_purchase_review(p_user uuid,p_image uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.discovery_assert_active_member(p_user);
 RETURN EXISTS(SELECT 1 FROM hocalist.outcome_reviews r
  WHERE r.status='published' AND r.image_media_ids ? p_image::text
   AND NOT EXISTS(SELECT 1 FROM hocalist.memberships m WHERE m.user_id=r.seller_user_id AND m.status IN ('restricted','disabled')));
END $$;
REVOKE ALL ON FUNCTION hocalist.media_read_purchase_review(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $patch$
DECLARE definition text; original text; body text; signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['hocalist.review_json(uuid)','hocalist.seller_public_reputation(uuid)',
  'hocalist.review_submit(text,jsonb)','hocalist.review_update(text,jsonb)','hocalist.media_gateway(uuid,text,jsonb)'] LOOP
  SELECT prosrc,pg_get_functiondef(oid) INTO original,definition FROM pg_proc WHERE oid=signature::regprocedure AND prosecdef;
  IF original IS NULL THEN RAISE EXCEPTION 'missing protected function: %',signature; END IF;
  body:=original;
  CASE signature
   WHEN 'hocalist.review_json(uuid)' THEN
    body:=replace(body,'''body'', v.body,','''body'', v.body, ''image_media_ids'', v.image_media_ids,');
   WHEN 'hocalist.seller_public_reputation(uuid)' THEN
    body:=replace(body,'''body'', r.body,','''body'', r.body, ''image_media_ids'', r.image_media_ids,');
   WHEN 'hocalist.review_submit(text,jsonb)' THEN
    body:=replace(body,'''request_id'',''rating'',''body'']','''request_id'',''rating'',''body'',''image_media_ids'']');
    body:=replace(body,'existing.body = v_body THEN','existing.body = v_body AND existing.image_media_ids=coalesce(p_input->''image_media_ids'',''[]''::jsonb) THEN');
    body:=replace(body,'seller_profile_id, rating, body)','seller_profile_id, rating, body, image_media_ids)');
    body:=replace(body,'v_rating, v_body)','v_rating, v_body, coalesce(p_input->''image_media_ids'',''[]''::jsonb))');
   WHEN 'hocalist.review_update(text,jsonb)' THEN
    body:=replace(body,'''expected_revision'',''rating'',''body'']','''expected_revision'',''rating'',''body'',''image_media_ids'']');
    body:=replace(body,'SET rating = v_rating, body = v_body,','SET rating = v_rating, body = v_body, image_media_ids=CASE WHEN p_input ? ''image_media_ids'' THEN p_input->''image_media_ids'' ELSE image_media_ids END,');
   ELSE
    body:=replace(body,'''report'',''request'')','''report'',''request'',''purchase_review'')');
    body:=replace(body,'PERFORM 1 FROM hocalist.profiles WHERE id = p_user FOR UPDATE;',
     'IF purpose=''purchase_review'' THEN PERFORM hocalist.marketplace_assert_role(p_user,''buyer''); END IF;
      PERFORM 1 FROM hocalist.profiles WHERE id = p_user FOR UPDATE;');
    body:=replace(body,'IF NOT v_allowed THEN',
     'IF NOT v_allowed AND m.purpose=''purchase_review'' THEN v_allowed:=hocalist.media_read_purchase_review(p_user,image_id); END IF;
      IF NOT v_allowed THEN');
  END CASE;
  IF body=original THEN RAISE EXCEPTION 'function body drift: %',signature; END IF;
  EXECUTE replace(definition,original,body);
 END LOOP;
 IF to_regprocedure('hocalist.media_referenced(uuid)') IS NOT NULL THEN
  SELECT prosrc,pg_get_functiondef(oid) INTO original,definition FROM pg_proc
   WHERE oid='hocalist.media_referenced(uuid)'::regprocedure AND prosecdef;
  IF original IS NULL OR strpos(original,'RETURN false;')=0 THEN RAISE EXCEPTION 'media reference drift'; END IF;
  body:=replace(original,'RETURN false;',
   'IF EXISTS(SELECT 1 FROM hocalist.outcome_reviews WHERE image_media_ids ? p_image::text) THEN RETURN true; END IF; RETURN false;');
  EXECUTE replace(definition,original,body);
 END IF;
END $patch$;
NOTIFY pgrst,'reload schema';
COMMIT;

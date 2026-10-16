-- Private image metadata. Bytes are accepted only through the authenticated,
-- bounded image gateway and re-encoded before entering the private bucket.
BEGIN;
CREATE TABLE hocalist.media_images(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), owner_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 intent_key uuid NOT NULL, purpose text NOT NULL CHECK(purpose IN ('offer','store','profile','chat')),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','ready','rejected')),
 size_bytes integer CHECK(size_bytes BETWEEN 1 AND 4194304),
 width integer CHECK(width BETWEEN 1 AND 2048),height integer CHECK(height BETWEEN 1 AND 2048),
 content_hash text NOT NULL CHECK(content_hash~'^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(owner_user_id,intent_key)
);
ALTER TABLE hocalist.media_images ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.media_images FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE hocalist.media_windows(user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id),started_at timestamptz NOT NULL,calls integer NOT NULL);
ALTER TABLE hocalist.media_windows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.media_windows FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hocalist.media_gateway(p_user uuid,p_action text,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m hocalist.media_images%ROWTYPE; image_id uuid;purpose text;n integer;
BEGIN
 IF p_user IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status='active')
  OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501'; END IF;
 INSERT INTO hocalist.media_windows(user_id,started_at,calls) VALUES(p_user,now(),1)
 ON CONFLICT(user_id) DO UPDATE SET
  calls=CASE WHEN media_windows.started_at<now()-interval '1 minute' THEN 1 ELSE media_windows.calls+1 END,
  started_at=CASE WHEN media_windows.started_at<now()-interval '1 minute' THEN now() ELSE media_windows.started_at END RETURNING calls INTO n;
 IF n>60 THEN RAISE EXCEPTION 'media_rate_limit'; END IF;
 IF p_action='begin' THEN
  purpose:=p_input->>'purpose';
  IF purpose IN ('offer','store') AND NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND role='seller' AND status='active') THEN
   RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
  SELECT * INTO m FROM hocalist.media_images WHERE owner_user_id=p_user AND intent_key=(p_input->>'key')::uuid;
  IF FOUND THEN
   IF m.purpose<>purpose OR m.content_hash<>p_input->>'hash' THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
  ELSE
   IF (SELECT count(*) FROM hocalist.media_images WHERE owner_user_id=p_user AND created_at>now()-interval '1 hour')>=60 THEN RAISE EXCEPTION 'media_rate_limit'; END IF;
   INSERT INTO hocalist.media_images(owner_user_id,intent_key,purpose,content_hash)
    VALUES(p_user,(p_input->>'key')::uuid,purpose,p_input->>'hash') RETURNING * INTO m;
  END IF;
 ELSIF p_action='complete' THEN
  UPDATE hocalist.media_images SET state='ready',size_bytes=(p_input->>'size')::integer,width=(p_input->>'width')::integer,height=(p_input->>'height')::integer
   WHERE id=(p_input->>'id')::uuid AND owner_user_id=p_user AND state IN ('pending','ready') RETURNING * INTO m;
  IF NOT FOUND THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='P0002'; END IF;
 ELSIF p_action='read' THEN
  image_id:=(p_input->>'id')::uuid;
  SELECT * INTO m FROM hocalist.media_images WHERE id=image_id AND state='ready';
  IF NOT FOUND THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='P0002'; END IF;
  IF m.owner_user_id<>p_user AND NOT (
   (m.purpose='store' AND EXISTS(SELECT 1 FROM hocalist.store_listings l JOIN hocalist.memberships s ON s.id=l.seller_profile_id
    WHERE l.image_media_ids ? image_id::text AND l.status='active' AND l.moderation_status='approved' AND s.status='active'))
   OR (m.purpose='offer' AND EXISTS(SELECT 1 FROM hocalist.offer_revisions r JOIN hocalist.offers o ON o.id=r.offer_id
    JOIN hocalist.requests q ON q.id=o.request_id WHERE r.image_media_ids ? image_id::text AND q.buyer_user_id=p_user))
  ) THEN RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501'; END IF;
 ELSE RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
 RETURN jsonb_build_object('id',m.id,'path',m.owner_user_id::text||'/'||m.id::text||'.jpg','state',m.state);
END $$;
-- References must be real, ready, owned assets of the appropriate purpose.
CREATE FUNCTION hocalist.media_validate_references() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE owner_id uuid; v_purpose text; item text;
BEGIN
 IF TG_TABLE_NAME='store_listings' THEN
  SELECT user_id INTO owner_id FROM hocalist.memberships WHERE id=NEW.seller_profile_id;v_purpose:='store';
 ELSE
  SELECT seller_user_id INTO owner_id FROM hocalist.offers WHERE id=NEW.offer_id;v_purpose:='offer';
 END IF;
 FOR item IN SELECT jsonb_array_elements_text(NEW.image_media_ids) LOOP
  IF NOT EXISTS(SELECT 1 FROM hocalist.media_images WHERE id=item::uuid AND owner_user_id=owner_id AND state='ready' AND media_images.purpose=v_purpose) THEN
   RAISE EXCEPTION 'invalid_media_reference' USING ERRCODE='22023'; END IF;
 END LOOP;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_store_media BEFORE INSERT OR UPDATE OF image_media_ids ON hocalist.store_listings FOR EACH ROW EXECUTE FUNCTION hocalist.media_validate_references();
CREATE TRIGGER validate_offer_media BEFORE INSERT ON hocalist.offer_revisions FOR EACH ROW EXECUTE FUNCTION hocalist.media_validate_references();
REVOKE ALL ON FUNCTION hocalist.media_gateway(uuid,text,jsonb),hocalist.media_validate_references() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.media_gateway(uuid,text,jsonb) TO service_role;
COMMIT;


-- Read-only Store photo review, restricted to existing admitted administrators.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE OR REPLACE FUNCTION hocalist.admin_store_image_reference(p_submission uuid,p_media uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.marketplace_assert_admin(auth.uid());
 RETURN jsonb_build_object('reference_ok',EXISTS(
 SELECT 1 FROM hocalist.store_listings l JOIN hocalist.media_images m
 ON l.image_media_ids ? m.id::text AND m.owner_user_id=l.seller_user_id
 WHERE l.id=p_submission AND m.id=p_media AND m.purpose='store' AND m.state='ready'
 AND l.moderation_status='pending_review' AND l.status<>'archived'));
END $$;
CREATE OR REPLACE FUNCTION hocalist.admin_store_image(p_submission uuid,p_media uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT coalesce((hocalist.admin_store_image_reference(p_submission,p_media)->>'reference_ok')::boolean,false) THEN
 RAISE EXCEPTION 'store_photo_not_found' USING ERRCODE='P0002'; END IF;
 RETURN (SELECT jsonb_build_object('id',id,'owner_user_id',owner_user_id,'state',state)
 FROM hocalist.media_images WHERE id=p_media);
END $$;
REVOKE ALL ON FUNCTION hocalist.admin_store_image_reference(uuid,uuid),hocalist.admin_store_image(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_store_image_reference(uuid,uuid),hocalist.admin_store_image(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

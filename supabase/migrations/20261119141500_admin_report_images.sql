-- Private feedback screenshots use the exact admitted administrator/case reference.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE OR REPLACE FUNCTION hocalist.admin_report_image(p_submission uuid,p_media uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE image jsonb;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  SELECT jsonb_build_object('id',m.id,'owner_user_id',m.owner_user_id,'state',m.state)
  INTO image
  FROM hocalist.review_evidence_links e
  JOIN hocalist.media_images m ON m.id=e.media_id
  WHERE e.case_id=p_submission AND m.id=p_media AND m.state='ready';
  IF image IS NULL THEN
    RAISE EXCEPTION 'report_photo_not_found' USING ERRCODE='P0002';
  END IF;
  RETURN image;
END $$;
REVOKE ALL ON FUNCTION hocalist.admin_report_image(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_report_image(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

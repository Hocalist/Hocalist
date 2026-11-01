-- Preserve the reviewer's verified JWT context for private evidence reads.
-- No storage URLs, bucket grants, account memberships or records are changed.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE OR REPLACE FUNCTION hocalist.admin_evidence_image(p_submission uuid,p_media uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE reference jsonb; image hocalist.media_images%ROWTYPE;
BEGIN
  -- Reuses the current administrator/MFA gate; never trusts a supplied user ID.
  reference := hocalist.admin_evidence_reference(p_submission,p_media);
  IF coalesce((reference->>'reference_ok')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'evidence_not_found' USING ERRCODE='P0002';
  END IF;
  SELECT mi.* INTO image FROM hocalist.media_images mi
    JOIN hocalist.review_evidence_links l ON l.media_id=mi.id
    JOIN hocalist.verification_submissions s ON s.id=l.submission_id
    WHERE l.submission_id=p_submission AND mi.id=p_media
      AND mi.purpose='review' AND mi.state='ready'
      AND mi.owner_user_id=s.user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'evidence_not_found' USING ERRCODE='P0002'; END IF;
  RETURN jsonb_build_object('id',image.id,'owner_user_id',image.owner_user_id,'state',image.state);
END $$;
REVOKE ALL ON FUNCTION hocalist.admin_evidence_image(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_evidence_image(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

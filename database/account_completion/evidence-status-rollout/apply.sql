BEGIN;
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='hocalist' AND p.proname='verification_status'
      AND p.pronargs=0 AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']
      AND md5(replace(p.prosrc,chr(13),''))='7086470d368f30a6271c9dc8a9189f76') THEN
    RAISE EXCEPTION 'Preflight: verification_status definition drift';
  END IF;
  IF has_function_privilege('anon','hocalist.verification_status()','EXECUTE')
     OR has_function_privilege('service_role','hocalist.verification_status()','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.verification_status()','EXECUTE') THEN
    RAISE EXCEPTION 'Preflight: verification_status privilege drift';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p, LATERAL aclexplode(p.proacl) a
    WHERE p.oid='hocalist.verification_status()'::regprocedure
      AND a.grantee <> p.proowner
      AND (a.grantee <> (SELECT oid FROM pg_roles WHERE rolname='authenticated')
        OR a.privilege_type <> 'EXECUTE' OR a.is_grantable))
    OR (SELECT proacl IS NULL FROM pg_proc WHERE oid='hocalist.verification_status()'::regprocedure) THEN
    RAISE EXCEPTION 'Preflight: verification_status ACL drift';
  END IF;
END $guard$;
CREATE OR REPLACE FUNCTION hocalist.verification_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object(
    'email_phone', hocalist.trust_contact_verified(u),
    'items',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',v.id,'kind',v.kind,'status',v.status,'note',v.note,
      'evidence_count',jsonb_array_length(v.evidence_media_ids),
      'evidence_media_ids',v.evidence_media_ids,
      'decision_reason',v.decision_reason,'revision',v.revision,
      'created_at',v.created_at,'decided_at',v.decided_at)
      ORDER BY v.created_at DESC,v.id DESC) FROM hocalist.verification_submissions v WHERE v.user_id=u),'[]'::jsonb));
END $$;
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='hocalist' AND p.proname='verification_status'
      AND p.pronargs=0 AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']
      AND md5(replace(p.prosrc,chr(13),''))='cbf9f714f4e30511688c936b91f0886e') THEN
    RAISE EXCEPTION 'Verify: verification_status definition drift';
  END IF;
  IF has_function_privilege('anon','hocalist.verification_status()','EXECUTE')
     OR has_function_privilege('service_role','hocalist.verification_status()','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.verification_status()','EXECUTE') THEN
    RAISE EXCEPTION 'Verify: verification_status privilege drift';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p, LATERAL aclexplode(p.proacl) a
    WHERE p.oid='hocalist.verification_status()'::regprocedure
      AND a.grantee <> p.proowner
      AND (a.grantee <> (SELECT oid FROM pg_roles WHERE rolname='authenticated')
        OR a.privilege_type <> 'EXECUTE' OR a.is_grantable))
    OR (SELECT proacl IS NULL FROM pg_proc WHERE oid='hocalist.verification_status()'::regprocedure) THEN
    RAISE EXCEPTION 'Verify: verification_status ACL drift';
  END IF;
END $guard$;
COMMIT;

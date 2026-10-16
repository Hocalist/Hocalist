BEGIN READ ONLY;
DO $guard$ BEGIN
IF to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)')),chr(13),''))<>'aaee68ae358c131da1aaeacc355aa6ae' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.media_gateway(uuid,text,jsonb)'; END IF;
IF to_regclass('hocalist.account_consent_documents') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: account_consent_documents'; END IF;
IF to_regclass('hocalist.account_consents') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: account_consents'; END IF;
IF to_regclass('hocalist.account_export_requests') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: account_export_requests'; END IF;
IF to_regclass('hocalist.account_exports') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: account_exports'; END IF;
IF to_regclass('hocalist.account_deletion_requests') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: account_deletion_requests'; END IF;
IF to_regclass('hocalist.role_profile_categories') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: role_profile_categories'; END IF;
IF to_regclass('hocalist.review_evidence_links') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: review_evidence_links'; END IF;
IF to_regclass('hocalist.evidence_audit') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: evidence_audit'; END IF;
IF to_regclass('hocalist.evidence_holds') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: evidence_holds'; END IF;
IF to_regclass('hocalist.media_cleanup_audit') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: media_cleanup_audit'; END IF;
END $guard$;
ROLLBACK;

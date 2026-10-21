-- Activate only with the deployed bootstrap enrolment flow and policy required.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $$ BEGIN
  IF to_regprocedure('hocalist.admin_mfa_enrollment_eligible()') IS NULL THEN
    RAISE EXCEPTION 'admin_mfa_bootstrap_required';
  END IF;
END $$;
CREATE OR REPLACE FUNCTION hocalist.marketplace_is_admin(p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p_user IS NOT NULL AND p_user = auth.uid()
     AND coalesce(auth.jwt()->>'aal', '') = 'aal2'
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p_user AND u.email_confirmed_at IS NOT NULL AND u.deleted_at IS NULL)
     AND EXISTS (SELECT 1 FROM hocalist.platform_admins WHERE user_id = p_user)
     AND NOT EXISTS (SELECT 1 FROM hocalist.memberships
                     WHERE user_id = p_user AND status IN ('restricted','disabled'));
$$;
COMMIT;

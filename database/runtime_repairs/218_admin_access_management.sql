-- Verified-account administrator management. Managers require AAL2.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
CREATE TABLE hocalist.admin_access_managers (
  user_id uuid PRIMARY KEY REFERENCES hocalist.platform_admins(user_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE hocalist.admin_access_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid NOT NULL,
  target_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN ('grant','revoke')),
  request_key uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(actor_id,request_key)
);
ALTER TABLE hocalist.admin_access_managers ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.admin_access_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.admin_access_managers,hocalist.admin_access_audit FROM PUBLIC,anon,authenticated,service_role;
-- Bootstrap eligibility reveals only the caller's own status, never directory data.
CREATE FUNCTION hocalist.admin_mfa_enrollment_eligible() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM hocalist.platform_admins a JOIN auth.users u ON u.id=a.user_id
   WHERE a.user_id=auth.uid() AND u.email_confirmed_at IS NOT NULL AND u.deleted_at IS NULL)
 AND NOT EXISTS(SELECT 1 FROM hocalist.memberships m WHERE m.user_id=auth.uid() AND m.status IN ('restricted','disabled'));
$$;
CREATE FUNCTION hocalist.admin_access_list() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=auth.uid();
BEGIN
 PERFORM hocalist.marketplace_assert_admin(actor);
 IF coalesce(auth.jwt()->>'aal','') <> 'aal2' THEN RAISE EXCEPTION 'admin_mfa_required' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object(
  'can_manage',EXISTS(SELECT 1 FROM hocalist.admin_access_managers WHERE user_id=actor),
  'items',coalesce((SELECT jsonb_agg(jsonb_build_object('user_id',a.user_id,'email',u.email,'granted_at',a.granted_at,
    'manager',EXISTS(SELECT 1 FROM hocalist.admin_access_managers m WHERE m.user_id=a.user_id),
    'mfa_ready',EXISTS(SELECT 1 FROM auth.mfa_factors f WHERE f.user_id=a.user_id AND f.status='verified')) ORDER BY a.granted_at,a.user_id)
    FROM hocalist.platform_admins a JOIN auth.users u ON u.id=a.user_id),'[]'::jsonb),
  'history',coalesce((SELECT jsonb_agg(to_jsonb(v)) FROM (SELECT e.id,e.action,e.created_at,u.email AS target_email
    FROM hocalist.admin_access_audit e LEFT JOIN auth.users u ON u.id=e.target_id ORDER BY e.created_at DESC,e.id DESC LIMIT 20) v),'[]'::jsonb));
END $$;
CREATE FUNCTION hocalist.admin_access_command(p_action text,p_email text,p_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=auth.uid(); target uuid; v_email text:=lower(btrim(p_email)); receipt hocalist.admin_access_audit%ROWTYPE;
BEGIN
 PERFORM hocalist.marketplace_assert_admin(actor);
 IF coalesce(auth.jwt()->>'aal','') <> 'aal2' OR NOT EXISTS(SELECT 1 FROM hocalist.admin_access_managers WHERE user_id=actor)
 THEN RAISE EXCEPTION 'admin_access_manager_required' USING ERRCODE='42501'; END IF;
 IF p_action NOT IN ('grant','revoke') OR p_action IS NULL OR p_key IS NULL OR v_email IS NULL OR length(v_email)>254 OR position('@' IN v_email)<2
 THEN RAISE EXCEPTION 'invalid_admin_access_input' USING ERRCODE='22023'; END IF;
 LOCK TABLE hocalist.platform_admins IN SHARE ROW EXCLUSIVE MODE;
 SELECT CASE WHEN count(*)=1 THEN (array_agg(u.id))[1] ELSE NULL END INTO target FROM auth.users u JOIN hocalist.profiles p ON p.id=u.id
 WHERE lower(u.email)=v_email AND u.email_confirmed_at IS NOT NULL AND u.deleted_at IS NULL;
 IF target IS NULL THEN RAISE EXCEPTION 'verified_hocalist_account_required' USING ERRCODE='22023'; END IF;
 SELECT * INTO receipt FROM hocalist.admin_access_audit WHERE actor_id=actor AND request_key=p_key;
 IF FOUND THEN
  IF receipt.target_id<>target OR receipt.action<>p_action THEN RAISE EXCEPTION 'admin_access_retry_conflict' USING ERRCODE='22023'; END IF;
  RETURN jsonb_build_object('ok',true,'action',receipt.action,'user_id',target);
 END IF;
 IF EXISTS(SELECT 1 FROM hocalist.memberships m WHERE m.user_id=target AND m.status IN ('restricted','disabled'))
 THEN RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501'; END IF;
 IF p_action='grant' THEN
  INSERT INTO hocalist.platform_admins(user_id,granted_by) VALUES(target,actor) ON CONFLICT(user_id) DO NOTHING;
 ELSE
  IF target=actor OR EXISTS(SELECT 1 FROM hocalist.admin_access_managers WHERE user_id=target)
  THEN RAISE EXCEPTION 'protected_administrator' USING ERRCODE='42501'; END IF;
  DELETE FROM hocalist.platform_admins WHERE user_id=target;
 END IF;
 INSERT INTO hocalist.admin_access_audit(actor_id,target_id,action,request_key) VALUES(actor,target,p_action,p_key);
 RETURN jsonb_build_object('ok',true,'action',p_action,'user_id',target);
END $$;
REVOKE ALL ON FUNCTION hocalist.admin_mfa_enrollment_eligible(),hocalist.admin_access_list(),hocalist.admin_access_command(text,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_mfa_enrollment_eligible(),hocalist.admin_access_list(),hocalist.admin_access_command(text,text,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

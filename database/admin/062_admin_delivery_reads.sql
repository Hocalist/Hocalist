-- Additive administrator-only push-delivery operations read (062, draft).
--
-- Bounded queue health for the deployed push bridge (032): status counts,
-- oldest pending age and the most recent failures. No push token, device
-- secret, notification title/body or recipient contact is projected, and the
-- read never triggers delivery.
--
-- Not an instruction to apply to a live project. Generate a guarded rollout
-- bundle and obtain coordinating review before applying.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $admin_delivery_guard$
BEGIN
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL
     OR to_regclass('hocalist.push_deliveries') IS NULL
     OR to_regclass('hocalist.push_devices') IS NULL
     OR to_regclass('hocalist.notifications') IS NULL THEN
    RAISE EXCEPTION 'Admin delivery reads require admin and deployed push foundations';
  END IF;
  IF to_regprocedure('hocalist.admin_delivery_overview()') IS NOT NULL THEN
    RAISE EXCEPTION 'Admin delivery read object already exists; review before replacement';
  END IF;
END
$admin_delivery_guard$;

CREATE FUNCTION hocalist.admin_delivery_overview()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_recent jsonb;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id,
      'kind', f.kind,
      'user_id', f.user_id,
      'attempts', f.attempts,
      'last_error', f.last_error,
      'available_at', f.available_at
    ) ORDER BY f.available_at DESC, f.id DESC), '[]'::jsonb)
    INTO v_recent
    FROM (
      SELECT d.id,
        n.kind,
        n.user_id,
        d.attempts,
        left(coalesce(d.last_error, ''), 200) AS last_error,
        d.available_at
      FROM hocalist.push_deliveries d
      JOIN hocalist.notifications n ON n.id = d.notification_id
      WHERE d.status = 'failed'
      ORDER BY d.available_at DESC, d.id DESC
      LIMIT 20
    ) f;
  RETURN jsonb_build_object(
    'pending', (SELECT count(*) FROM hocalist.push_deliveries WHERE status = 'pending'),
    'sending', (SELECT count(*) FROM hocalist.push_deliveries WHERE status = 'sending'),
    'accepted', (SELECT count(*) FROM hocalist.push_deliveries WHERE status = 'accepted'),
    'skipped', (SELECT count(*) FROM hocalist.push_deliveries WHERE status = 'skipped'),
    'failed', (SELECT count(*) FROM hocalist.push_deliveries WHERE status = 'failed'),
    'failed_last_24h', (SELECT count(*) FROM hocalist.push_deliveries
      WHERE status = 'failed' AND available_at > now() - interval '24 hours'),
    'oldest_pending_at', (SELECT min(available_at) FROM hocalist.push_deliveries
      WHERE status = 'pending'),
    'recent_failures', v_recent);
END; $$;

REVOKE ALL ON FUNCTION hocalist.admin_delivery_overview()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_delivery_overview() TO authenticated;

DO $hocalist_admin_delivery_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT has_function_privilege('authenticated','hocalist.admin_delivery_overview()','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_delivery_overview()','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_delivery_overview()','EXECUTE') THEN
    v_issues := array_append(v_issues, 'admin delivery read grants are wrong');
  END IF;
  IF has_table_privilege('authenticated','hocalist.push_deliveries','SELECT')
     OR has_table_privilege('authenticated','hocalist.push_devices','SELECT') THEN
    v_issues := array_append(v_issues, 'push tables became client-readable');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist admin delivery post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_admin_delivery_postapply$;
COMMIT;

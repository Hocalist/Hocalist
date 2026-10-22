-- Read-only workspace analytics. No fee, access, or provider-setting changes.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
 IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL
 OR to_regclass('hocalist.support_cases') IS NULL
 OR to_regclass('hocalist.withdrawal_requests') IS NULL THEN
 RAISE EXCEPTION 'admin_workspace_prerequisites_missing'; END IF;
 IF to_regprocedure('hocalist.admin_workspace_metrics()') IS NOT NULL THEN
 RAISE EXCEPTION 'admin_workspace_metrics_already_exists'; END IF;
END $$;
CREATE FUNCTION hocalist.admin_workspace_metrics() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE first_day date := (now() AT TIME ZONE 'UTC')::date-6;
 series jsonb; summaries jsonb; recent jsonb;
BEGIN
 PERFORM hocalist.marketplace_assert_admin(auth.uid());
 -- Defence in depth: the new read never accepts a password-only session.
 IF coalesce(auth.jwt()->>'aal','') <> 'aal2' THEN
 RAISE EXCEPTION 'admin_mfa_required' USING ERRCODE='42501'; END IF;
 WITH days AS (SELECT first_day+i AS day FROM generate_series(0,6) i),
 requests AS (SELECT (created_at AT TIME ZONE 'UTC')::date AS day,count(*) AS n
 FROM hocalist.requests WHERE created_at >= (first_day::timestamp AT TIME ZONE 'UTC')
 AND created_at <= now() AND status<>'draft' GROUP BY 1),
 offers AS (SELECT (created_at AT TIME ZONE 'UTC')::date AS day,count(*) AS n
 FROM hocalist.offers WHERE created_at >= (first_day::timestamp AT TIME ZONE 'UTC')
 AND created_at <= now() GROUP BY 1)
 SELECT jsonb_agg(jsonb_build_object('date',d.day,'requests',coalesce(r.n,0),'offers',coalesce(o.n,0)) ORDER BY d.day)
 INTO series FROM days d LEFT JOIN requests r USING(day) LEFT JOIN offers o USING(day);
 WITH counts AS (
 SELECT 'users' AS resource,status,count(*) AS n FROM hocalist.memberships GROUP BY status
 UNION ALL SELECT 'requests',status,count(*) FROM hocalist.requests GROUP BY status
 UNION ALL SELECT 'offers',status,count(*) FROM hocalist.offers GROUP BY status
 UNION ALL SELECT 'billing',provider_status,count(*) FROM hocalist.stripe_test_subscriptions GROUP BY provider_status
 ), groups AS (SELECT resource,jsonb_object_agg(status,n) AS states,sum(n)::bigint AS total FROM counts GROUP BY resource)
 SELECT coalesce(jsonb_object_agg(resource,jsonb_build_object('total',total,'statuses',states)),'{}'::jsonb) INTO summaries FROM groups;
 SELECT coalesce(jsonb_agg(x.item ORDER BY x.created_at DESC,x.id DESC),'[]'::jsonb) INTO recent FROM (
 SELECT r.id,r.created_at,jsonb_build_object('id',r.id,'title',r.title,'buyer',coalesce(p.display_name,'Profile pending'),
 'category',coalesce(c.label,'Uncategorised'),'status',r.status,'created_at',r.created_at,
 'offers',(SELECT count(*) FROM hocalist.offers o WHERE o.request_id=r.id)) AS item
 FROM hocalist.requests r LEFT JOIN hocalist.role_profiles p ON p.membership_id=r.buyer_profile_id
 LEFT JOIN hocalist.catalogue_categories c ON c.id=r.category_id WHERE r.status<>'draft'
 ORDER BY r.created_at DESC,r.id DESC LIMIT 6) x;
 RETURN jsonb_build_object('generated_at',now(),'timezone','UTC','series',series,'resources',summaries,'recent_requests',recent,
 'queues',jsonb_build_object('listings',(SELECT count(*) FROM hocalist.store_listings WHERE moderation_status='pending_review'),
 'reports',(SELECT count(*) FROM hocalist.support_cases WHERE status IN ('open','in_review')),
 'withdrawals',(SELECT count(*) FROM hocalist.withdrawal_requests WHERE status='processing')),
 'periods',jsonb_build_object(
 'requests_current',(SELECT count(*) FROM hocalist.requests WHERE status<>'draft' AND created_at >= (first_day::timestamp AT TIME ZONE 'UTC') AND created_at<=now()),
 'requests_previous',(SELECT count(*) FROM hocalist.requests WHERE status<>'draft' AND created_at >= ((first_day-7)::timestamp AT TIME ZONE 'UTC') AND created_at < (first_day::timestamp AT TIME ZONE 'UTC')),
 'offers_current',(SELECT count(*) FROM hocalist.offers WHERE created_at >= (first_day::timestamp AT TIME ZONE 'UTC') AND created_at<=now()),
 'offers_previous',(SELECT count(*) FROM hocalist.offers WHERE created_at >= ((first_day-7)::timestamp AT TIME ZONE 'UTC') AND created_at < (first_day::timestamp AT TIME ZONE 'UTC'))));
END $$;
REVOKE ALL ON FUNCTION hocalist.admin_workspace_metrics() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_workspace_metrics() TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

-- Prepared locally. Read-only monthly totals for the authenticated seller.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE INDEX IF NOT EXISTS credit_targets_user_created_idx ON hocalist.credit_targets(user_id,created_at);
CREATE INDEX IF NOT EXISTS sale_confirmations_seller_confirmed_idx ON hocalist.sale_confirmations(seller_user_id,confirmed_at);
CREATE FUNCTION hocalist.seller_home_summary() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid:=auth.uid(); tz text; start_at timestamptz; end_at timestamptz;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u,'seller');
  SELECT calendar_timezone INTO tz FROM hocalist.entitlement_policy WHERE singleton;
  -- Reporting only: never configure/activate the billing/earned-Pro policy.
  -- The response declares UTC explicitly when that policy has no calendar.
  tz:=coalesce(tz,'UTC');
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=tz) THEN
    RAISE EXCEPTION 'seller_home_calendar_unavailable' USING ERRCODE='55000'; END IF;
  start_at:=date_trunc('month',now() AT TIME ZONE tz) AT TIME ZONE tz;
  end_at:=(date_trunc('month',now() AT TIME ZONE tz)+interval '1 month') AT TIME ZONE tz;
  RETURN jsonb_build_object('month_start',start_at,'month_end',end_at,'timezone',tz,
    'leads_targeted',(SELECT count(*) FROM hocalist.credit_targets WHERE user_id=u AND created_at>=start_at AND created_at<end_at),
    'deals_closed',(SELECT count(*) FROM hocalist.sale_confirmations WHERE seller_user_id=u AND confirmed_at>=start_at AND confirmed_at<end_at));
END $$;
REVOKE ALL ON FUNCTION hocalist.seller_home_summary() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.seller_home_summary() TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

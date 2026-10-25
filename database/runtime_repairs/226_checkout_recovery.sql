-- Restore checkout admission after provider-verified expiry; expose pending
-- subscriptions in the owner's billing view, not just credit deposits.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.website_purchase_status(uuid)') AND md5(replace(prosrc,E'\r\n',E'\n'))='4df64adccebebc55c30f77087ead853f' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Billing status definition drift'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.stripe_test_checkout_expire(uuid,text,text)') AND md5(replace(prosrc,E'\r\n',E'\n'))='aa65b9af6e72a605d493d9aae7f4c95c' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Checkout expiry definition drift'; END IF;
END $guard$;
CREATE FUNCTION hocalist.stripe_test_pending_checkout(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE m hocalist.memberships%ROWTYPE;
BEGIN
 SELECT * INTO m FROM hocalist.memberships WHERE user_id=p_user AND role='seller';
 IF NOT FOUND OR m.status<>'active' OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status IN ('restricted','disabled')) THEN RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM hocalist.stripe_test_customers WHERE membership_id=m.id AND requires_review) THEN RAISE EXCEPTION 'billing_review_required' USING ERRCODE='P0001'; END IF;
 RETURN (SELECT jsonb_build_object('checkout_id',c.id,'membership_id',m.id,
   'kind',c.kind,'plan_code',c.plan_code,'option_id',c.credit_option_id,
   'request_key',c.request_key,'session_id',c.session_id,'customer_id',sc.customer_id)
 FROM hocalist.stripe_test_checkouts c LEFT JOIN hocalist.stripe_test_customers sc ON sc.membership_id=c.membership_id
 WHERE c.membership_id=m.id AND c.state IN ('creating','open') ORDER BY c.created_at DESC,c.id DESC LIMIT 1);
END $$;
REVOKE ALL ON FUNCTION hocalist.stripe_test_pending_checkout(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION hocalist.stripe_test_pending_checkout(uuid) TO service_role;
CREATE OR REPLACE FUNCTION hocalist.website_purchase_status(p_checkout uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  m hocalist.memberships%ROWTYPE;
  v_selected jsonb;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.profiles WHERE id = u) THEN
    RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO m FROM hocalist.memberships
    WHERE user_id = u AND role = 'seller';
  -- Any restricted or disabled membership, in either role, blocks the website
  -- purchase surfaces exactly as it blocks checkout begin.
  IF NOT FOUND OR m.status <> 'active'
     OR EXISTS(SELECT 1 FROM hocalist.memberships
               WHERE user_id = u AND status IN ('restricted', 'disabled')) THEN
    RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501';
  END IF;

  IF true THEN
    SELECT jsonb_build_object(
        'id', c.id,
        'kind', c.kind,
        'state', c.state,
        'amount_minor', c.amount_minor,
        'currency', 'usd',
        'created_at', c.created_at,
        'expires_at', c.expires_at,
        'credited_at', b.created_at,
        'batch_id', c.credit_batch_id,
        'plan_code', c.plan_code,
        'option_id', c.credit_option_id)
      INTO v_selected
      FROM hocalist.stripe_test_checkouts c
      LEFT JOIN hocalist.credit_batches b ON b.id = c.credit_batch_id
      WHERE c.membership_id = m.id AND (c.id = p_checkout OR (p_checkout IS NULL AND c.state IN ('creating','open')))
      ORDER BY c.created_at DESC,c.id DESC LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'account', jsonb_build_object('membership_id', m.id),
    'plans', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'code', code, 'amount_minor', amount_minor,
        'currency', currency, 'enabled', enabled) ORDER BY amount_minor)
      FROM hocalist.stripe_test_plans), '[]'::jsonb),
    'options', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'amount_minor', amount_minor,
        'initial_fee_minor', initial_fee_minor,
        'winning_total_minor', winning_total_minor,
        'rate_version', rate_version, 'sort_order', sort_order)
        ORDER BY sort_order, amount_minor)
      FROM hocalist.credit_deposit_options WHERE active), '[]'::jsonb),
    'credit_purchase_allowed', NOT EXISTS (SELECT 1 FROM hocalist.stripe_test_customers sc WHERE sc.membership_id=m.id AND sc.requires_review),
    'subscription', (
      SELECT jsonb_build_object(
        'plan', s.plan_code, 'provider_status', s.provider_status,
        'paid_until', s.paid_until, 'cancel_at_period_end', s.cancel_at_period_end,
        'requires_review', s.requires_review, 'updated_at', s.updated_at)
      FROM hocalist.stripe_test_subscriptions s WHERE s.membership_id = m.id),
    'deposits', coalesce((
      SELECT jsonb_agg(entry ORDER BY entry->>'created_at' DESC)
      FROM (
        SELECT jsonb_build_object(
          'id', c.id, 'kind', c.kind, 'state', c.state,
          'amount_minor', c.amount_minor, 'currency', 'usd',
          'created_at', c.created_at, 'expires_at', c.expires_at,
          'credited_at', b.created_at, 'batch_id', c.credit_batch_id,
          'option_id', c.credit_option_id) AS entry
        FROM hocalist.stripe_test_checkouts c
        LEFT JOIN hocalist.credit_batches b ON b.id = c.credit_batch_id
        WHERE c.membership_id = m.id AND c.kind = 'credit_deposit'
        ORDER BY c.created_at DESC, c.id DESC
        LIMIT 20) recent), '[]'::jsonb),
    'selected', v_selected,
    'requires_review', coalesce((
      SELECT requires_review FROM hocalist.stripe_test_customers
      WHERE membership_id = m.id), false));
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;

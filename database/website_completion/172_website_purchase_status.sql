-- Additive website purchase read: one authoritative projection of the signed-in
-- seller's plan catalogue, credit-pack catalogue, exact checkout state and
-- subscription state. The browser never receives a price or a completion time
-- from anywhere else; the return page resolves one exact checkout by id and
-- never infers a result from a URL.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.stripe_test_plans') IS NULL
     OR to_regclass('hocalist.stripe_test_customers') IS NULL
     OR to_regclass('hocalist.stripe_test_subscriptions') IS NULL
     OR to_regclass('hocalist.credit_deposit_options') IS NULL
     OR to_regclass('hocalist.credit_batches') IS NULL THEN
    RAISE EXCEPTION 'Stripe TEST / credit foundation prerequisite missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist' AND table_name='stripe_test_checkouts'
      AND column_name='kind'
  ) THEN
    RAISE EXCEPTION 'Deposit checkout 094 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.website_purchase_status(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Website purchase status already installed';
  END IF;
END; $guard$;

CREATE FUNCTION hocalist.website_purchase_status(p_checkout uuid DEFAULT NULL)
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

  IF p_checkout IS NOT NULL THEN
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
      WHERE c.id = p_checkout AND c.membership_id = m.id;
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

REVOKE ALL ON FUNCTION hocalist.website_purchase_status(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.website_purchase_status(uuid) TO authenticated;
COMMIT;

-- Credit deposits do not require a paid subscription. Seller/safety checks remain.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)') AND md5(replace(prosrc,E'\r\n',E'\n'))='fca41fb639dc7be3dfc9d760e31ba5da' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Credit access definition drift: stripe_test_deposit_begin'; END IF;
 IF has_function_privilege('anon','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE') OR has_function_privilege('authenticated','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE') OR NOT has_function_privilege('service_role','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE') OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(p.proacl) a WHERE p.oid=to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)') AND a.grantee=0) THEN RAISE EXCEPTION 'Credit access privilege drift'; END IF;
END $guard$;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.website_purchase_status(uuid)') AND md5(replace(prosrc,E'\r\n',E'\n'))='4485d9a51716e2cf97dcd57e29774ec6' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Credit access definition drift: website_purchase_status'; END IF;
 IF has_function_privilege('anon','hocalist.website_purchase_status(uuid)','EXECUTE') OR has_function_privilege('service_role','hocalist.website_purchase_status(uuid)','EXECUTE') OR NOT has_function_privilege('authenticated','hocalist.website_purchase_status(uuid)','EXECUTE') OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(p.proacl) a WHERE p.oid=to_regprocedure('hocalist.website_purchase_status(uuid)') AND a.grantee=0) THEN RAISE EXCEPTION 'Credit access privilege drift'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION hocalist.stripe_test_deposit_begin(p_user uuid, p_option uuid, p_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  m hocalist.memberships%ROWTYPE;
  c hocalist.stripe_test_checkouts%ROWTYPE;
  o hocalist.credit_deposit_options%ROWTYPE;
  v_customer text;
BEGIN
  PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO m FROM hocalist.memberships WHERE user_id=p_user AND role='seller' FOR UPDATE;
  IF NOT FOUND OR m.status<>'active'
     OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
  IF p_key IS NULL THEN RAISE EXCEPTION 'invalid_option_or_key' USING ERRCODE='22023'; END IF;
  -- Recovery first: the saved checkout carries the original intent snapshot.
  SELECT * INTO c FROM hocalist.stripe_test_checkouts
    WHERE membership_id=m.id AND request_key=p_key FOR UPDATE;
  IF FOUND THEN
    IF c.kind<>'credit_deposit' OR c.credit_option_id<>p_option THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    IF c.state IN ('complete','expired') THEN
      RAISE EXCEPTION 'checkout_closed' USING ERRCODE='P0001'; END IF;
  ELSE
    -- New checkout: validate the current catalogue and account state.
    SELECT * INTO o FROM hocalist.credit_deposit_options WHERE id=p_option AND active;
    IF NOT FOUND THEN RAISE EXCEPTION 'invalid_option_or_key' USING ERRCODE='22023'; END IF;
    IF EXISTS(SELECT 1 FROM hocalist.stripe_test_customers WHERE membership_id=m.id AND requires_review) THEN
      RAISE EXCEPTION 'billing_review_required' USING ERRCODE='P0001'; END IF;
    IF EXISTS(SELECT 1 FROM hocalist.stripe_test_checkouts
              WHERE membership_id=m.id AND state IN ('creating','open')) THEN
      RAISE EXCEPTION 'checkout_pending' USING ERRCODE='P0001'; END IF;
    INSERT INTO hocalist.stripe_test_checkouts(
      membership_id, request_key, plan_code, price_id, amount_minor, kind,
      credit_option_id, credit_initial_minor, credit_winning_minor, credit_rate_version)
    VALUES (m.id, p_key, NULL, NULL, o.amount_minor, 'credit_deposit',
      o.id, o.initial_fee_minor, o.winning_total_minor, o.rate_version)
    RETURNING * INTO c;
  END IF;
  IF c.state='creating' AND c.created_at<now()-interval '25 minutes' THEN
    RAISE EXCEPTION 'checkout_reconciliation_required' USING ERRCODE='P0001'; END IF;
  SELECT customer_id INTO v_customer FROM hocalist.stripe_test_customers WHERE membership_id=m.id;
  RETURN jsonb_build_object('checkout_id',c.id,'membership_id',m.id,'customer_id',v_customer,
    'option_id',c.credit_option_id,'amount_minor',c.amount_minor,'currency','usd',
    'initial_fee_minor',c.credit_initial_minor,'winning_total_minor',c.credit_winning_minor,
    'rate_version',c.credit_rate_version,'session_id',c.session_id,'session_url',c.session_url,
    'expires_at',floor(extract(epoch FROM c.expires_at)),'state',c.state);
END $$;
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
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)') AND md5(replace(prosrc,E'\r\n',E'\n'))='106b32e6f04a41980c9216fd42298c2f' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Credit access definition drift: stripe_test_deposit_begin'; END IF;
 IF has_function_privilege('anon','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE') OR has_function_privilege('authenticated','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE') OR NOT has_function_privilege('service_role','hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)','EXECUTE') OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(p.proacl) a WHERE p.oid=to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)') AND a.grantee=0) THEN RAISE EXCEPTION 'Credit access privilege drift'; END IF;
END $guard$;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.website_purchase_status(uuid)') AND md5(replace(prosrc,E'\r\n',E'\n'))='4df64adccebebc55c30f77087ead853f' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Credit access definition drift: website_purchase_status'; END IF;
 IF has_function_privilege('anon','hocalist.website_purchase_status(uuid)','EXECUTE') OR has_function_privilege('service_role','hocalist.website_purchase_status(uuid)','EXECUTE') OR NOT has_function_privilege('authenticated','hocalist.website_purchase_status(uuid)','EXECUTE') OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(p.proacl) a WHERE p.oid=to_regprocedure('hocalist.website_purchase_status(uuid)') AND a.grantee=0) THEN RAISE EXCEPTION 'Credit access privilege drift'; END IF;
END $guard$;
NOTIFY pgrst,'reload schema';
COMMIT;

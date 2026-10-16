-- Additive website credit checkout over the reviewed Stripe TEST foundation
-- (005 receipt + 006 subscription checkouts). Provider-neutral and local:
-- no Stripe call, no secret and no entitlement is granted here.
--
-- Flow: the website server creates an account-bound checkout with
-- `stripe_test_deposit_begin` (rates are snapshotted from the admin-managed
-- deposit option), binds the provider customer/session with
-- `stripe_test_deposit_bind`, and only a server process that has verified a
-- signed provider event may call `stripe_test_deposit_finish`. A redirect or
-- success URL can never create a batch: `finish` validates the paid amount
-- against the option and is idempotent by provider reference.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.stripe_test_checkouts') IS NULL
     OR to_regclass('hocalist.stripe_test_customers') IS NULL THEN
    RAISE EXCEPTION 'Stripe TEST subscription foundation 006 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.credit_batches') IS NULL
     OR to_regprocedure('hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text)') IS NULL THEN
    RAISE EXCEPTION 'Credit batch foundation 090 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.credit_deposit_options') IS NULL THEN
    RAISE EXCEPTION 'Deposit option configuration 092 prerequisite missing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist' AND table_name='stripe_test_checkouts' AND column_name='kind'
  ) THEN
    RAISE EXCEPTION 'Deposit checkout already installed';
  END IF;
END; $guard$;

-- Additive columns: subscription rows keep kind='subscription'; deposit rows
-- carry the option snapshot taken when the checkout began, so a later admin
-- rate edit cannot reprice a payment already in progress.
ALTER TABLE hocalist.stripe_test_checkouts
  ALTER COLUMN plan_code DROP NOT NULL,
  ALTER COLUMN price_id DROP NOT NULL,
  ADD COLUMN kind text NOT NULL DEFAULT 'subscription'
    CHECK (kind IN ('subscription','credit_deposit')),
  ADD COLUMN credit_option_id uuid REFERENCES hocalist.credit_deposit_options(id),
  ADD COLUMN credit_initial_minor bigint,
  ADD COLUMN credit_winning_minor bigint,
  ADD COLUMN credit_rate_version text,
  ADD CONSTRAINT stripe_test_checkout_kind_shape CHECK (
    (kind='subscription' AND plan_code IS NOT NULL AND credit_option_id IS NULL)
    OR (kind='credit_deposit' AND plan_code IS NULL AND credit_option_id IS NOT NULL
        AND credit_initial_minor IS NOT NULL AND credit_winning_minor IS NOT NULL
        AND credit_rate_version IS NOT NULL)
  );

-- Payment/batch association persisted on the checkout: an identical finish
-- retry returns its original result, and a conflicting replay (different
-- amount or reference) is refused instead of returning a null or unrelated
-- batch. One provider reference can belong to exactly one checkout.
ALTER TABLE hocalist.stripe_test_checkouts
  ADD COLUMN credit_batch_id uuid REFERENCES hocalist.credit_batches(id),
  ADD COLUMN provider_reference text
    CHECK (provider_reference IS NULL OR length(btrim(provider_reference)) BETWEEN 1 AND 200);
CREATE UNIQUE INDEX stripe_test_checkout_payment_reference
  ON hocalist.stripe_test_checkouts(provider_reference)
  WHERE provider_reference IS NOT NULL;

-- Trusted website/server path only. p_user must come from the verified session,
-- never from request JSON; no client amount is accepted.
--
-- Retry integrity: an existing (membership, key) checkout is recovered with its
-- immutable option snapshot before any current-option validation. An unchanged
-- retry therefore survives an admin fee edit or an option retirement; current
-- options are validated only when creating a new checkout.
CREATE FUNCTION hocalist.stripe_test_deposit_begin(p_user uuid, p_option uuid, p_key uuid)
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

CREATE FUNCTION hocalist.stripe_test_deposit_bind(
  p_checkout uuid, p_customer text, p_session text DEFAULT NULL, p_url text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c hocalist.stripe_test_checkouts%ROWTYPE; current_customer text;
BEGIN
  SELECT * INTO STRICT c FROM hocalist.stripe_test_checkouts WHERE id=p_checkout FOR UPDATE;
  IF c.kind<>'credit_deposit' THEN RAISE EXCEPTION 'not_a_deposit_checkout'; END IF;
  IF c.state NOT IN ('creating','open') THEN RAISE EXCEPTION 'checkout_closed'; END IF;
  IF p_customer IS NULL OR p_customer !~ '^cus_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'invalid_customer'; END IF;
  INSERT INTO hocalist.stripe_test_customers(membership_id,customer_id)
  VALUES(c.membership_id,p_customer) ON CONFLICT(membership_id) DO NOTHING;
  SELECT customer_id INTO current_customer FROM hocalist.stripe_test_customers WHERE membership_id=c.membership_id;
  IF current_customer<>p_customer THEN RAISE EXCEPTION 'customer_conflict'; END IF;
  IF p_session IS NOT NULL THEN
    IF p_session !~ '^cs_test_[A-Za-z0-9]+$' OR p_url IS NULL OR p_url !~ '^https://checkout[.]stripe[.]com/' THEN
      RAISE EXCEPTION 'invalid_session'; END IF;
    IF c.session_id IS NOT NULL AND c.session_id<>p_session THEN RAISE EXCEPTION 'session_conflict'; END IF;
    UPDATE hocalist.stripe_test_checkouts SET session_id=p_session,session_url=p_url,
      state=CASE WHEN state='creating' THEN 'open' ELSE state END WHERE id=c.id;
  END IF;
END $$;

-- Caller must have verified the signed provider event and its paid amount.
-- A redirect never reaches this function. The batch is created once per
-- provider reference and keeps the rates snapshotted at checkout start. The
-- checkout persists its payment reference and batch id, so an identical retry
-- returns the original outcome while a conflicting replay (different amount or
-- reference) fails instead of returning a null or unrelated batch.
CREATE FUNCTION hocalist.stripe_test_deposit_finish(
  p_checkout uuid, p_customer text, p_paid_amount bigint, p_reference text,
  p_error text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  c hocalist.stripe_test_checkouts%ROWTYPE;
  v_user uuid;
  v_batch uuid;
  v_reference text;
BEGIN
  SELECT * INTO STRICT c FROM hocalist.stripe_test_checkouts WHERE id=p_checkout FOR UPDATE;
  IF c.kind<>'credit_deposit' THEN RAISE EXCEPTION 'not_a_deposit_checkout'; END IF;
  IF p_customer IS NULL OR NOT EXISTS(
       SELECT 1 FROM hocalist.stripe_test_customers
       WHERE membership_id=c.membership_id AND customer_id=p_customer) THEN
    RAISE EXCEPTION 'customer_conflict'; END IF;
  IF p_error IS NOT NULL THEN
    IF c.state='complete' THEN RAISE EXCEPTION 'checkout_closed' USING ERRCODE='P0001'; END IF;
    IF p_error='review_required' THEN
      UPDATE hocalist.stripe_test_customers SET requires_review=true WHERE membership_id=c.membership_id;
      UPDATE hocalist.stripe_test_checkouts SET state='expired' WHERE id=c.id;
      RETURN jsonb_build_object('status','review_required','checkout_id',c.id);
    END IF;
    RETURN jsonb_build_object('status','retry','checkout_id',c.id);
  END IF;
  IF c.state='complete' THEN
    -- Identical retry: return the recorded payment/batch association. A
    -- conflicting replay (different reference or amount) must fail and can
    -- never return a null or unrelated batch.
    IF p_reference IS DISTINCT FROM c.provider_reference THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    IF p_paid_amount IS DISTINCT FROM c.amount_minor THEN
      RAISE EXCEPTION 'amount_mismatch' USING ERRCODE='P0001'; END IF;
    IF c.credit_batch_id IS NULL THEN
      RAISE EXCEPTION 'checkout_association_missing' USING ERRCODE='P0001'; END IF;
    RETURN jsonb_build_object('status','complete','checkout_id',c.id,
      'batch_id',c.credit_batch_id,'reference',c.provider_reference);
  END IF;
  IF c.state NOT IN ('creating','open') THEN RAISE EXCEPTION 'checkout_closed'; END IF;
  IF p_reference IS NULL OR length(btrim(p_reference)) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'invalid_reference' USING ERRCODE='22023'; END IF;
  IF p_paid_amount IS DISTINCT FROM c.amount_minor THEN
    RAISE EXCEPTION 'amount_mismatch' USING ERRCODE='P0001'; END IF;
  IF EXISTS(SELECT 1 FROM hocalist.stripe_test_checkouts
            WHERE provider_reference=btrim(p_reference) AND id<>c.id) THEN
    RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
  SELECT user_id INTO v_user FROM hocalist.memberships WHERE id=c.membership_id;
  v_reference := 'stripe_test:'||p_reference;
  v_batch := hocalist.credit_deposit_internal(
    v_user, v_reference, c.amount_minor,
    c.credit_initial_minor, c.credit_winning_minor, c.credit_rate_version);
  UPDATE hocalist.stripe_test_checkouts
    SET state='complete', credit_batch_id=v_batch, provider_reference=btrim(p_reference)
    WHERE id=c.id;
  RETURN jsonb_build_object('status','complete','checkout_id',c.id,'batch_id',v_batch);
END $$;

-- App-facing read: the active purchasable options and the caller's own deposit
-- checkout states. No provider secret, session URL or card data is exposed.
CREATE FUNCTION hocalist.credit_deposit_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();
BEGIN
  IF u IS NULL OR NOT EXISTS(
       SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='seller' AND status='active')
     OR EXISTS(
       SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object(
    'options',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',id,'amount_minor',amount_minor,'initial_fee_minor',initial_fee_minor,
      'winning_total_minor',winning_total_minor,'rate_version',rate_version,'sort_order',sort_order)
      ORDER BY sort_order,amount_minor) FROM hocalist.credit_deposit_options WHERE active),'[]'::jsonb),
    'checkouts',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',c.id,'option_id',c.credit_option_id,'amount_minor',c.amount_minor,
      'state',c.state,'created_at',c.created_at,'expires_at',c.expires_at)
      ORDER BY c.created_at DESC,c.id DESC)
      FROM hocalist.stripe_test_checkouts c
      JOIN hocalist.memberships m ON m.id=c.membership_id
      WHERE m.user_id=u AND c.kind='credit_deposit' LIMIT 20),'[]'::jsonb));
END $$;

REVOKE ALL ON FUNCTION
  hocalist.stripe_test_deposit_begin(uuid,uuid,uuid),
  hocalist.stripe_test_deposit_bind(uuid,text,text,text),
  hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text),
  hocalist.credit_deposit_status()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  hocalist.stripe_test_deposit_begin(uuid,uuid,uuid),
  hocalist.stripe_test_deposit_bind(uuid,text,text,text),
  hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.credit_deposit_status() TO authenticated;
COMMIT;

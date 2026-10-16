-- Additive service-role read used by the reconciliation worker to classify an
-- event from the authoritative stored checkout/session binding before it
-- trusts any provider metadata. It is a superset of the reviewed
-- `stripe_test_customer_context` projection (006) with the checkout `kind` and
-- payment association, and never grants a client role access.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.stripe_test_customers') IS NULL
     OR to_regclass('hocalist.stripe_test_plans') IS NULL
     OR to_regclass('hocalist.stripe_test_checkouts') IS NULL
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
  IF to_regprocedure('hocalist.website_checkout_context(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Website checkout context already installed';
  END IF;
END; $guard$;

CREATE FUNCTION hocalist.website_checkout_context(p_customer text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT jsonb_build_object(
    'membership_id', c.membership_id,
    'requires_review', c.requires_review,
    'plans', (SELECT jsonb_agg(jsonb_build_object(
      'code', code, 'price_id', price_id, 'amount_minor', amount_minor))
      FROM hocalist.stripe_test_plans),
    'checkouts', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', x.id,
        'kind', x.kind,
        'state', x.state,
        'session_id', x.session_id,
        'plan_code', x.plan_code,
        'price_id', x.price_id,
        'amount_minor', x.amount_minor,
        'option_id', x.credit_option_id,
        'credit_batch_id', x.credit_batch_id,
        'provider_reference', x.provider_reference)), '[]'::jsonb)
      FROM hocalist.stripe_test_checkouts x WHERE x.membership_id = c.membership_id))
  FROM hocalist.stripe_test_customers c WHERE c.customer_id = p_customer;
$$;

REVOKE ALL ON FUNCTION hocalist.website_checkout_context(text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.website_checkout_context(text) TO service_role;
COMMIT;

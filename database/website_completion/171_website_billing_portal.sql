-- Additive read contract for the hosted billing portal. The website server
-- authenticates the browser session and then asks this service-role-only
-- function which provider customer belongs to the verified account. The
-- customer id never comes from request JSON, and a seller that is restricted,
-- disabled or pending is refused instead of receiving a portal link.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.stripe_test_customers') IS NULL
     OR to_regclass('hocalist.stripe_test_checkouts') IS NULL THEN
    RAISE EXCEPTION 'Stripe TEST subscription foundation 006 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.stripe_test_portal_access(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Website billing portal contract already installed';
  END IF;
END; $guard$;

CREATE FUNCTION hocalist.stripe_test_portal_access(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  m hocalist.memberships%ROWTYPE;
  v_customer text;
  v_review boolean := false;
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM hocalist.profiles WHERE id = p_user;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO m FROM hocalist.memberships WHERE user_id = p_user AND role = 'seller';
  IF NOT FOUND OR m.status <> 'active'
     OR EXISTS(SELECT 1 FROM hocalist.memberships
               WHERE user_id = p_user AND status IN ('restricted', 'disabled')) THEN
    RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT customer_id, requires_review INTO v_customer, v_review
    FROM hocalist.stripe_test_customers WHERE membership_id = m.id;
  RETURN jsonb_build_object(
    'membership_id', m.id,
    'customer_id', v_customer,
    'requires_review', coalesce(v_review, false));
END $$;

REVOKE ALL ON FUNCTION hocalist.stripe_test_portal_access(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.stripe_test_portal_access(uuid) TO service_role;
COMMIT;

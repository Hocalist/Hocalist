BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $guard$ BEGIN
IF to_regclass('hocalist.profiles') IS NULL THEN RAISE EXCEPTION 'Missing prerequisite relation: hocalist.profiles'; END IF;
IF to_regclass('hocalist.stripe_test_plans') IS NULL THEN RAISE EXCEPTION 'Missing prerequisite relation: hocalist.stripe_test_plans'; END IF;
IF to_regclass('hocalist.stripe_test_customers') IS NULL THEN RAISE EXCEPTION 'Missing prerequisite relation: hocalist.stripe_test_customers'; END IF;
IF to_regclass('hocalist.stripe_test_checkouts') IS NULL THEN RAISE EXCEPTION 'Missing prerequisite relation: hocalist.stripe_test_checkouts'; END IF;
IF to_regclass('hocalist.stripe_test_subscriptions') IS NULL THEN RAISE EXCEPTION 'Missing prerequisite relation: hocalist.stripe_test_subscriptions'; END IF;
IF to_regclass('hocalist.credit_deposit_options') IS NULL THEN RAISE EXCEPTION 'Missing prerequisite relation: hocalist.credit_deposit_options'; END IF;
IF to_regclass('hocalist.credit_batches') IS NULL THEN RAISE EXCEPTION 'Missing prerequisite relation: hocalist.credit_batches'; END IF;
IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='stripe_test_checkouts' AND column_name='kind') THEN RAISE EXCEPTION 'Missing prerequisite column: stripe_test_checkouts.kind'; END IF;
IF to_regclass('hocalist.website_waitlist_signups') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: website_waitlist_signups'; END IF;
IF to_regclass('hocalist.website_waitlist_admissions') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: website_waitlist_admissions'; END IF;
IF to_regclass('hocalist.website_waitlist_config') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: website_waitlist_config'; END IF;
IF to_regprocedure('hocalist.website_waitlist_join(text,text,text,text,text)') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.website_waitlist_join(text,text,text,text,text)'; END IF;
IF to_regprocedure('hocalist.website_purchase_status(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.website_purchase_status(uuid)'; END IF;
IF to_regprocedure('hocalist.stripe_test_portal_access(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.stripe_test_portal_access(uuid)'; END IF;
IF to_regprocedure('hocalist.website_waitlist_configure(text)') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.website_waitlist_configure(text)'; END IF;
IF to_regprocedure('hocalist.website_waitlist_set_caps(integer,integer)') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.website_waitlist_set_caps(integer,integer)'; END IF;
IF to_regprocedure('hocalist.website_checkout_context(text)') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: hocalist.website_checkout_context(text)'; END IF;
END $guard$;
-- Additive public-website launch waitlist. Stores only what is needed to
-- honor an explicit consent: the address, the consent version/time, an
-- optional source label and a salted client fingerprint used for bounded
-- abuse control. No client role can read the list; marketing sends, public
-- launch and retention automation stay gated outside this migration.
--
-- Correction (review 05): the intake function is a server-controlled boundary.
-- Public callers cannot invent fingerprints or enumerate addresses:
--   1. it requires a deployment secret whose md5 is configured by the service
--      role through `website_waitlist_configure`; without it the function
--      reports `waitlist_not_configured`,
--   2. fingerprints must be presented by the trusted website server, and both
--      the per-fingerprint and the global hourly caps are enforced atomically
--      under advisory locks,
--   3. rate-limit admission is counted separately from stored consent rows, so
--      every admitted valid submission consumes the same budget whether the
--      address is new or already registered, and `consented_at` is never
--      exposed. Known and unknown addresses are therefore indistinguishable at,
--      below and above the caps, including across request sequences.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.profiles') IS NULL THEN
    RAISE EXCEPTION 'Hocalist account prerequisite missing';
  END IF;
  IF to_regclass('hocalist.website_waitlist_signups') IS NOT NULL THEN
    RAISE EXCEPTION 'Website waitlist already installed';
  END IF;
END; $guard$;

CREATE TABLE hocalist.website_waitlist_signups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL CHECK (length(email) BETWEEN 3 AND 254),
  email_normalized text NOT NULL UNIQUE
    CHECK (email_normalized = lower(btrim(email_normalized)) AND length(email_normalized) >= 3),
  consent_version text NOT NULL CHECK (consent_version = 'launch-updates-v1'),
  consented_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  source text NOT NULL DEFAULT 'website'
    CHECK (length(btrim(source)) BETWEEN 1 AND 80),
  client_hash text NOT NULL CHECK (client_hash ~ '^[0-9a-f]{64}$')
);
ALTER TABLE hocalist.website_waitlist_signups ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.website_waitlist_signups
  FROM PUBLIC, anon, authenticated, service_role;

-- Admission budget, deliberately separate from consent rows: every admitted
-- valid submission (new or duplicate) consumes one slot in its hour window, so
-- the public response cannot reveal whether an address was already stored.
CREATE TABLE hocalist.website_waitlist_admissions (
  client_hash text NOT NULL CHECK (client_hash ~ '^[0-9a-f]{64}$'),
  window_start timestamptz NOT NULL,
  admitted integer NOT NULL CHECK (admitted > 0),
  PRIMARY KEY (client_hash, window_start)
);
CREATE INDEX website_waitlist_admissions_window
  ON hocalist.website_waitlist_admissions(window_start);
ALTER TABLE hocalist.website_waitlist_admissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.website_waitlist_admissions
  FROM PUBLIC, anon, authenticated, service_role;

-- Service-role configuration: the website server's intake secret (stored as
-- md5) and the atomic abuse caps. No client role may read it.
CREATE TABLE hocalist.website_waitlist_config (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  intake_token_hash text
    CHECK (intake_token_hash IS NULL OR intake_token_hash ~ '^[0-9a-f]{32}$'),
  per_fingerprint_cap integer NOT NULL DEFAULT 5
    CHECK (per_fingerprint_cap BETWEEN 1 AND 50),
  global_hourly_cap integer NOT NULL DEFAULT 240
    CHECK (global_hourly_cap BETWEEN 1 AND 100000),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.website_waitlist_config(singleton) VALUES (true);
ALTER TABLE hocalist.website_waitlist_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.website_waitlist_config
  FROM PUBLIC, anon, authenticated, service_role;

-- Service role only: set or rotate the intake secret. The secret itself is
-- never stored; only its md5. The website holds the same value in its
-- server-only environment (HOCALIST_WAITLIST_INTAKE_SECRET).
CREATE FUNCTION hocalist.website_waitlist_configure(p_token text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF p_token IS NULL OR length(p_token) NOT BETWEEN 32 AND 200 THEN
    RAISE EXCEPTION 'invalid_intake_token' USING ERRCODE='22023';
  END IF;
  UPDATE hocalist.website_waitlist_config
    SET intake_token_hash = md5(p_token), updated_at = now()
    WHERE singleton;
END $$;
REVOKE ALL ON FUNCTION hocalist.website_waitlist_configure(text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.website_waitlist_configure(text) TO service_role;

-- Service role only: adjust the atomic abuse caps without touching the table.
CREATE FUNCTION hocalist.website_waitlist_set_caps(
  p_per_fingerprint integer,
  p_global_hourly integer
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF p_per_fingerprint IS NULL OR p_per_fingerprint NOT BETWEEN 1 AND 50
     OR p_global_hourly IS NULL OR p_global_hourly NOT BETWEEN 1 AND 100000 THEN
    RAISE EXCEPTION 'invalid_caps' USING ERRCODE='22023';
  END IF;
  UPDATE hocalist.website_waitlist_config
    SET per_fingerprint_cap = p_per_fingerprint,
        global_hourly_cap = p_global_hourly,
        updated_at = now()
    WHERE singleton;
END $$;
REVOKE ALL ON FUNCTION hocalist.website_waitlist_set_caps(integer,integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.website_waitlist_set_caps(integer,integer) TO service_role;

-- Public intake, gated by the deployment secret. The email/consent/source and
-- the fingerprint format are validated here; the caps are counted inside the
-- same transaction under advisory locks so concurrent callers cannot exceed
-- them. The returned status is for the website server only: the public HTTP
-- response is a single generic acknowledgement.
CREATE FUNCTION hocalist.website_waitlist_join(
  p_email text,
  p_consent_version text,
  p_source text DEFAULT NULL,
  p_client_hash text DEFAULT NULL,
  p_intake_token text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_config hocalist.website_waitlist_config%ROWTYPE;
  v_email text := btrim(coalesce(p_email, ''));
  v_normalized text;
  v_source text := btrim(coalesce(p_source, 'website'));
  v_window timestamptz := date_trunc('hour', now());
  v_fingerprint integer;
  v_global integer;
BEGIN
  SELECT * INTO v_config FROM hocalist.website_waitlist_config WHERE singleton;
  IF NOT FOUND OR v_config.intake_token_hash IS NULL THEN
    RAISE EXCEPTION 'waitlist_not_configured' USING ERRCODE='P0001';
  END IF;
  IF p_intake_token IS NULL OR length(p_intake_token) NOT BETWEEN 32 AND 200
     OR md5(p_intake_token) IS DISTINCT FROM v_config.intake_token_hash THEN
    RAISE EXCEPTION 'invalid_intake' USING ERRCODE='42501';
  END IF;
  v_normalized := lower(v_email);
  IF length(v_email) NOT BETWEEN 3 AND 254
     OR v_normalized !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' THEN
    RAISE EXCEPTION 'invalid_email' USING ERRCODE='22023';
  END IF;
  IF p_consent_version IS DISTINCT FROM 'launch-updates-v1' THEN
    RAISE EXCEPTION 'consent_required' USING ERRCODE='22023';
  END IF;
  IF length(v_source) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'invalid_source' USING ERRCODE='22023';
  END IF;
  IF p_client_hash IS NULL OR p_client_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_client' USING ERRCODE='22023';
  END IF;
  -- Admission accounting is independent of whether the address already exists:
  -- both caps are checked (and both locks held) before any existence-dependent
  -- response, and every admitted submission consumes budget. Stale hour
  -- windows are pruned opportunistically so the ledger stays bounded.
  DELETE FROM hocalist.website_waitlist_admissions
    WHERE window_start < v_window - interval '2 hours';
  PERFORM pg_advisory_xact_lock(hashtextextended('waitlist:' || p_client_hash, 771));
  SELECT admitted INTO v_fingerprint FROM hocalist.website_waitlist_admissions
    WHERE client_hash = p_client_hash AND window_start = v_window;
  IF coalesce(v_fingerprint, 0) >= v_config.per_fingerprint_cap THEN
    RAISE EXCEPTION 'rate_limited' USING ERRCODE='P0001';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('waitlist:global', 771));
  SELECT coalesce(sum(admitted), 0)::integer INTO v_global
    FROM hocalist.website_waitlist_admissions WHERE window_start = v_window;
  IF v_global >= v_config.global_hourly_cap THEN
    RAISE EXCEPTION 'rate_limited' USING ERRCODE='P0001';
  END IF;
  INSERT INTO hocalist.website_waitlist_admissions(client_hash, window_start, admitted)
  VALUES (p_client_hash, v_window, 1)
  ON CONFLICT (client_hash, window_start)
  DO UPDATE SET admitted = hocalist.website_waitlist_admissions.admitted + 1;
  -- Admitted: persistence stays idempotent. A repeat creates no second row and
  -- keeps its original consent record.
  IF EXISTS(SELECT 1 FROM hocalist.website_waitlist_signups
            WHERE email_normalized = v_normalized) THEN
    RETURN jsonb_build_object('status', 'already_joined');
  END IF;
  INSERT INTO hocalist.website_waitlist_signups(
    email, email_normalized, consent_version, source, client_hash)
  VALUES (v_email, v_normalized, 'launch-updates-v1', v_source, p_client_hash)
  ON CONFLICT(email_normalized) DO NOTHING;
  IF FOUND THEN
    RETURN jsonb_build_object('status', 'joined');
  END IF;
  RETURN jsonb_build_object('status', 'already_joined');
END $$;

REVOKE ALL ON FUNCTION hocalist.website_waitlist_join(text,text,text,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA hocalist TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.website_waitlist_join(text,text,text,text,text)
  TO anon, authenticated;

-- Additive read contract for the hosted billing portal. The website server
-- authenticates the browser session and then asks this service-role-only
-- function which provider customer belongs to the verified account. The
-- customer id never comes from request JSON, and a seller that is restricted,
-- disabled or pending is refused instead of receiving a portal link.

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

-- Additive website purchase read: one authoritative projection of the signed-in
-- seller's plan catalogue, credit-pack catalogue, exact checkout state and
-- subscription state. The browser never receives a price or a completion time
-- from anywhere else; the return page resolves one exact checkout by id and
-- never infers a result from a URL.

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

-- Additive service-role read used by the reconciliation worker to classify an
-- event from the authoritative stored checkout/session binding before it
-- trusts any provider metadata. It is a superset of the reviewed
-- `stripe_test_customer_context` projection (006) with the checkout `kind` and
-- payment association, and never grants a client role access.

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

DO $verify$ DECLARE f oid; r text; priv text; BEGIN
f:=to_regprocedure('hocalist.website_waitlist_join(text,text,text,text,text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'42b19d8253095408eb01b893b826a933' THEN RAISE EXCEPTION 'Function drift: hocalist.website_waitlist_join(text,text,text,text,text)'; END IF;
f:=to_regprocedure('hocalist.website_purchase_status(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'fbac7ee87ba010e830d0ee70f00dba74' THEN RAISE EXCEPTION 'Function drift: hocalist.website_purchase_status(uuid)'; END IF;
f:=to_regprocedure('hocalist.stripe_test_portal_access(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'6b6ee04925ca2b9b3fe11388ec12e3ae' THEN RAISE EXCEPTION 'Function drift: hocalist.stripe_test_portal_access(uuid)'; END IF;
f:=to_regprocedure('hocalist.website_waitlist_configure(text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'d3700e00e90731a88644321ee5ba6dd4' THEN RAISE EXCEPTION 'Function drift: hocalist.website_waitlist_configure(text)'; END IF;
f:=to_regprocedure('hocalist.website_waitlist_set_caps(integer,integer)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'465e4f34eab042717e8bec3948a9e745' THEN RAISE EXCEPTION 'Function drift: hocalist.website_waitlist_set_caps(integer,integer)'; END IF;
f:=to_regprocedure('hocalist.website_checkout_context(text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'9bf62a98114963bb1344ade75d8a0d8a' THEN RAISE EXCEPTION 'Function drift: hocalist.website_checkout_context(text)'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.website_waitlist_signups')),false) THEN RAISE EXCEPTION 'Missing RLS: website_waitlist_signups'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.website_waitlist_signups',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: website_waitlist_signups % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.website_waitlist_admissions')),false) THEN RAISE EXCEPTION 'Missing RLS: website_waitlist_admissions'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.website_waitlist_admissions',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: website_waitlist_admissions % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.website_waitlist_config')),false) THEN RAISE EXCEPTION 'Missing RLS: website_waitlist_config'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.website_waitlist_config',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: website_waitlist_config % %',r,priv; END IF; END LOOP; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.website_waitlist_join(text,text,text,text,text)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['anon','authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.website_waitlist_join(text,text,text,text,text) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.website_purchase_status(uuid)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.website_purchase_status(uuid) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.stripe_test_portal_access(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on server-only helper: hocalist.stripe_test_portal_access(uuid)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.stripe_test_portal_access(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.stripe_test_portal_access(uuid)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.website_waitlist_configure(text)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on server-only helper: hocalist.website_waitlist_configure(text)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.website_waitlist_configure(text)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.website_waitlist_configure(text)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.website_waitlist_set_caps(integer,integer)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on server-only helper: hocalist.website_waitlist_set_caps(integer,integer)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.website_waitlist_set_caps(integer,integer)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.website_waitlist_set_caps(integer,integer)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.website_checkout_context(text)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on server-only helper: hocalist.website_checkout_context(text)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.website_checkout_context(text)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.website_checkout_context(text)'; END IF;
END $verify$;
COMMIT;

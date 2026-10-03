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
BEGIN;
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
COMMIT;

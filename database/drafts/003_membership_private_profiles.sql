-- DRAFT: locally tested only. Not an instruction to apply to a live project.
-- Preserves the existing signup seed and shared Auth trigger.
-- Hardened for the guarded rollout bundle: baseline shape checks, explicit
-- schema/table grants and no service-role table access.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $guard$
DECLARE
  v_missing text;
BEGIN
  IF to_regclass('hocalist.profiles') IS NULL THEN
    RAISE EXCEPTION 'Expected Hocalist signup seed is missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'auth.users'::regclass
      AND tgname = 'on_auth_user_created'
      AND tgfoid = to_regprocedure('hocalist.handle_new_user()')
      AND tgtype = 5 AND tgenabled = 'O'
  ) THEN
    RAISE EXCEPTION 'Signup routing differs from the approved baseline';
  END IF;
  SELECT string_agg(expected.name, ', ') INTO v_missing
  FROM (VALUES ('id'), ('full_name'), ('avatar_url'), ('onboarding_status'),
               ('created_at'), ('updated_at')) AS expected(name)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_attribute a
    WHERE a.attrelid = 'hocalist.profiles'::regclass
      AND a.attname = expected.name AND NOT a.attisdropped
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Hocalist signup seed is missing columns: %', v_missing;
  END IF;
  IF (SELECT count(*) FROM pg_attribute a
      WHERE a.attrelid = 'hocalist.profiles'::regclass
        AND a.attnum > 0 AND NOT a.attisdropped) <> 6 THEN
    RAISE EXCEPTION 'Hocalist signup seed has unexpected extra columns';
  END IF;
END
$guard$;

CREATE TABLE hocalist.memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('buyer', 'seller')),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'active', 'restricted', 'disabled')),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);

-- Domain profile id = membership id; Auth identity remains a separate id.
CREATE TABLE hocalist.role_profiles (
  membership_id uuid PRIMARY KEY REFERENCES hocalist.memberships(id) ON DELETE CASCADE,
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 200),
  area_label text CHECK (length(area_label) <= 200),
  profile_note text CHECK (length(profile_note) <= 2000),
  preferred_meetup_type text CHECK (length(preferred_meetup_type) <= 100),
  service_radius_miles integer CHECK (service_radius_miles >= 0),
  pickup_availability text CHECK (length(pickup_availability) <= 500),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Never join these columns into public profile/search/realtime responses.
-- Email stays in Auth; phone here is unverified user input, not a trust signal.
CREATE TABLE hocalist.profile_contacts (
  user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  phone text CHECK (length(phone) <= 40),
  address_line1 text CHECK (length(address_line1) <= 300),
  address_line2 text CHECK (length(address_line2) <= 300),
  city text CHECK (length(city) <= 150),
  region text CHECK (length(region) <= 150),
  postal_code text CHECK (length(postal_code) <= 40),
  country_code text CHECK (country_code ~ '^[A-Z]{2}$'),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE hocalist.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.role_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.profile_contacts ENABLE ROW LEVEL SECURITY;
-- No client or service-role direct writes. The commands are the only writers.
REVOKE ALL ON hocalist.memberships, hocalist.role_profiles, hocalist.profile_contacts
  FROM PUBLIC, anon, authenticated, service_role;

-- Re-assert the bootstrap intent: clients never create objects in this schema.
REVOKE ALL ON SCHEMA hocalist FROM PUBLIC, anon, authenticated;

-- The owner can read membership status to render restriction/onboarding UI.
CREATE POLICY membership_owner_read ON hocalist.memberships
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY active_owner_profile_read ON hocalist.role_profiles
  FOR SELECT TO authenticated USING (EXISTS (
    SELECT 1 FROM hocalist.memberships m
    WHERE m.id = membership_id AND m.user_id = (SELECT auth.uid()) AND m.status = 'active'
  ));
CREATE POLICY active_owner_contact_read ON hocalist.profile_contacts
  FOR SELECT TO authenticated USING (
    user_id = (SELECT auth.uid()) AND EXISTS (
      SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id = (SELECT auth.uid()) AND m.status = 'active'
    )
  );

GRANT USAGE ON SCHEMA hocalist TO authenticated;
GRANT SELECT ON hocalist.memberships, hocalist.role_profiles, hocalist.profile_contacts
  TO authenticated;
COMMENT ON TABLE hocalist.memberships IS
  'Server-provisioned Hocalist membership. No client writes or automatic activation.';
COMMENT ON TABLE hocalist.role_profiles IS
  'Private owner read model. Not a public profile projection. Writes require future reviewed commands.';
COMMENT ON TABLE hocalist.profile_contacts IS
  'Owner-only contacts. No email copy, verification evidence or public projection.';
COMMIT;

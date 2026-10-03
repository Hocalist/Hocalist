-- Owner-approved: all new shared-project Auth identities provision Hocalist.
-- Existing Postaneur records and public.handle_new_user() remain unchanged.
-- This is a private onboarding seed, not the complete domain profile contract.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'auth.users'::regclass
      AND t.tgname = 'on_auth_user_created'
      AND t.tgfoid = 'public.handle_new_user()'::regprocedure
      AND md5(pg_get_functiondef(t.tgfoid)) = '8a2ad53d7e3f7400241a38d3fea48bd3'
      AND t.tgtype = 5 AND t.tgenabled = 'O'
  ) THEN
    RAISE EXCEPTION 'Signup baseline changed; review before applying';
  END IF;
END
$guard$;

CREATE TABLE hocalist.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text,
  avatar_url text,
  onboarding_status text NOT NULL DEFAULT 'pending'
    CHECK (onboarding_status IN ('pending', 'complete')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE hocalist.profiles FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE hocalist.profiles IS
  'Private signup seed. No client grants/policies yet. Role membership and completed domain profile require reviewed onboarding.';

CREATE FUNCTION hocalist.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  INSERT INTO hocalist.profiles (id, full_name, avatar_url)
  VALUES (
    NEW.id,
    left(coalesce(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name'), 200),
    left(NEW.raw_user_meta_data->>'avatar_url', 2048)
  );
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION hocalist.handle_new_user() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION hocalist.handle_new_user();
COMMIT;

-- Rollback strategy, only after reviewing new signup implications:
-- point on_auth_user_created back to the unchanged public.handle_new_user().
-- Keep new Hocalist records; do not drop schema/table or migrate identities blindly.

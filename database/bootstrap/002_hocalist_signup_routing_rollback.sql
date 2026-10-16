-- Prepared rollback only. Do not run without review of signup routing impact.
-- Preserves all Hocalist profiles; does not backfill Postaneur profiles.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'auth.users'::regclass
      AND tgname = 'on_auth_user_created'
      AND tgfoid = 'hocalist.handle_new_user()'::regprocedure
  ) OR md5(pg_get_functiondef('public.handle_new_user()'::regprocedure))
       <> '8a2ad53d7e3f7400241a38d3fea48bd3' THEN
    RAISE EXCEPTION 'Signup baseline changed; review rollback';
  END IF;
END
$guard$;
CREATE OR REPLACE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
COMMIT;

-- Transaction-only synthetic fixtures; no Auth API or emails are sent.
BEGIN;
SET LOCAL statement_timeout = '30s';
DO $test$
DECLARE
  normal_id uuid := gen_random_uuid();
  hostile_id uuid := gen_random_uuid();
  empty_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
    (normal_id, normal_id::text || '@example.invalid', '{"full_name":"Hocalist routing test"}'::jsonb),
    (hostile_id, hostile_id::text || '@example.invalid', '{"role":"admin","verified":true,"onboarding_status":"complete","name":"Metadata test"}'::jsonb),
    (empty_id, NULL, NULL);
  IF (SELECT count(*) FROM hocalist.profiles WHERE id IN (normal_id, hostile_id, empty_id)) <> 3 THEN
    RAISE EXCEPTION 'Missing Hocalist signup profiles';
  END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id IN (normal_id, hostile_id, empty_id)) THEN
    RAISE EXCEPTION 'Signup still writes Postaneur profiles';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.profiles WHERE id IN (normal_id, hostile_id, empty_id) AND onboarding_status <> 'pending') THEN
    RAISE EXCEPTION 'Untrusted metadata changed onboarding state';
  END IF;
  IF (SELECT full_name FROM hocalist.profiles WHERE id = normal_id) <> 'Hocalist routing test' THEN
    RAISE EXCEPTION 'Name not preserved';
  END IF;
  IF has_table_privilege('anon', 'hocalist.profiles', 'SELECT') OR
     has_table_privilege('authenticated', 'hocalist.profiles', 'SELECT') OR
     has_function_privilege('authenticated', 'hocalist.handle_new_user()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Unexpected client access';
  END IF;
END
$test$;
SELECT 'PASS: 3 signup cases; Hocalist only; metadata cannot grant onboarding; clients denied' AS result;
ROLLBACK;

-- Hocalist-only account messages. No data, grants or deletion rules change.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $$
DECLARE signature text; definition text; repaired text;
BEGIN
  FOREACH signature IN ARRAY ARRAY['hocalist.account_export_build(uuid)','hocalist.account_lifecycle_status()'] LOOP
    IF to_regprocedure(signature) IS NULL THEN RAISE EXCEPTION 'account_lifecycle_prerequisite_missing'; END IF;
    SELECT pg_get_functiondef(to_regprocedure(signature)) INTO definition;
    repaired := replace(definition, 'Shared Supabase Auth ', 'Hocalist sign-in ');
    repaired := replace(repaired, 'credentials and Postaneur records are not included.', 'credentials are not included.');
    repaired := replace(repaired, 'identity, Postaneur records and legal evidence are not deleted here.', 'identity and retained legal evidence are handled separately.');
    IF repaired ILIKE '%postaneur%' THEN RAISE EXCEPTION 'unexpected_legacy_account_wording'; END IF;
    IF repaired <> definition THEN EXECUTE repaired; END IF;
  END LOOP;
END $$;
COMMIT;

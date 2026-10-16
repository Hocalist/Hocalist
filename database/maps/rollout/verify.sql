-- Hocalist Places gateway verification. READ-ONLY: safe any time after
-- apply.sql. The DO block is textually identical to the post-apply block in
-- apply.sql; database/maps/tests/places_rollout.test.mjs asserts that equality.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $hocalist_places_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_service_functions constant text[] := ARRAY[
    'places_gate(uuid,text,uuid,text,text)',
    'places_record_suggestions(uuid,uuid,text[])',
    'places_resolve_session(uuid,uuid)',
    'places_release_session(uuid,uuid)'];
  v_tables constant text[] := ARRAY[
    'places_search_sessions','places_search_suggestions','places_rate_counters'];
  v_fn text;
  v_table text;
  v_columns text[];
  v_expected_sessions constant text[] := ARRAY[
    'token:uuid','user_id:uuid','operation_count:integer',
    'created_at:timestamp with time zone','expires_at:timestamp with time zone',
    'resolved_at:timestamp with time zone','resolving_at:timestamp with time zone'];
  v_expected_suggestions constant text[] := ARRAY[
    'session_token:uuid','place_id:text','created_at:timestamp with time zone'];
  v_expected_counters constant text[] := ARRAY[
    'scope:text','operation:text','window_kind:text',
    'bucket:timestamp with time zone','count:integer'];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing places table: ' || v_table);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.' || v_table)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: ' || v_table);
    ELSIF has_table_privilege('authenticated', 'hocalist.' || v_table, 'SELECT')
       OR has_table_privilege('anon', 'hocalist.' || v_table, 'SELECT') THEN
      v_issues := array_append(v_issues, 'places table is client-readable: ' || v_table);
    END IF;
  END LOOP;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_search_sessions'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_sessions THEN
    v_issues := array_append(v_issues, 'places_search_sessions columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_search_suggestions'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_suggestions THEN
    v_issues := array_append(v_issues, 'places_search_suggestions columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_rate_counters'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_counters THEN
    v_issues := array_append(v_issues, 'places_rate_counters columns differ from the reviewed shape');
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist'
      AND table_name IN ('places_search_sessions','places_search_suggestions','places_rate_counters')
      AND column_name ~* '(query|label|address|input|display|formatted|latitude|longitude)'
  ) THEN
    v_issues := array_append(v_issues, 'places gateway must not store queries, labels or addresses');
  END IF;
  FOREACH v_fn IN ARRAY v_service_functions LOOP
    IF NOT has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'places function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  IF has_function_privilege(
       'authenticated','hocalist.places_rate_bump(text,text,text,timestamptz)','EXECUTE')
     OR has_function_privilege(
       'service_role','hocalist.places_rate_bump(text,text,text,timestamptz)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'internal places helper is executable');
  END IF;
  IF NOT has_function_privilege(
       'authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed account grants changed');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist places post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_places_postapply$;
SELECT 'places verification passed' AS status;
COMMIT;

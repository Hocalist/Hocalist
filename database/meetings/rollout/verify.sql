-- Hocalist meeting rollout verification. READ-ONLY: safe any time after
-- apply.sql. The DO block is textually identical to the post-apply block in
-- apply.sql; database/meetings/tests/meetings_rollout.test.mjs asserts that
-- equality.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $hocalist_meeting_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_client_functions constant text[] := ARRAY[
    'meeting_propose(uuid,jsonb,text)','meeting_respond(uuid,boolean,bigint,text)',
    'meeting_reschedule_propose(uuid,jsonb,bigint,text)','meeting_cancel(uuid,bigint,text)',
    'meeting_detail(uuid)','meeting_list(text,integer,text)'];
  v_internal_functions constant text[] := ARRAY[
    'meeting_normalize_schedule(jsonb)','meeting_assert_participant(uuid,uuid)',
    'meeting_assert_conversation_member(uuid,uuid)',
    'meeting_receipt_begin(uuid,text,text,text)',
    'meeting_receipt_store(uuid,text,text,text,jsonb)',
    'meeting_json(uuid)','meeting_revision_json(hocalist.meeting_schedule_revisions)'];
  v_fn text;
  v_table text;
  v_columns text[];
  v_expected_meetings constant text[] := ARRAY[
    'id:uuid','conversation_id:uuid','request_id:uuid','offer_id:uuid',
    'buyer_user_id:uuid','seller_user_id:uuid','status:text',
    'accepted_revision_id:uuid','meeting_expires_at:timestamp with time zone',
    'revision:bigint','created_at:timestamp with time zone',
    'updated_at:timestamp with time zone'];
  v_expected_receipts constant text[] := ARRAY[
    'user_id:uuid','operation:text','idempotency_key:text',
    'request_hash:text','result:jsonb','created_at:timestamp with time zone'];
BEGIN
  FOREACH v_table IN ARRAY ARRAY['meetings','meeting_schedule_revisions','meeting_receipts'] LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing meeting table: ' || v_table);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.' || v_table)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: ' || v_table);
    END IF;
  END LOOP;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.meetings'::regclass AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_meetings THEN
    v_issues := array_append(v_issues, 'meetings columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.meeting_receipts'::regclass AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_receipts THEN
    v_issues := array_append(v_issues, 'meeting_receipts columns differ from the reviewed shape');
  END IF;
  FOREACH v_fn IN ARRAY v_client_functions LOOP
    IF NOT has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'meeting function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY v_internal_functions LOOP
    IF has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'internal meeting function is executable: ' || v_fn);
    END IF;
  END LOOP;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist' AND table_name='meetings'
      AND column_name IN ('pin','pin_hash','pin_attempts')
  ) THEN
    v_issues := array_append(v_issues, 'PIN columns must not exist in the meeting foundation');
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.marketplace_timezones()','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed account/marketplace grants changed');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist meeting post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_meeting_postapply$;
SELECT 'meeting verification passed' AS status;
COMMIT;

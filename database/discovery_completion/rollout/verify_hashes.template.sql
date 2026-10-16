-- Post-apply drift verification: pinned prerequisite and package definition
-- hashes, authorization signature inventory, and the exact new table/column
-- inventory with RLS and no unexpected policies.
DO $hocalist_discovery_completion_hashes$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_pair text;
  v_signature text;
  v_hash text;
  v_table text;
  v_expected_columns text[];
  v_actual_columns text[];
  v_expected_prerequisites constant text[] := ARRAY[
    __PREREQUISITE_HASHES__
  ];
  v_expected_package constant text[] := ARRAY[
    __PACKAGE_HASHES__
  ];
  v_tables constant text[] := ARRAY[
    'seller_discovery_origins','outcome_reviews','buyer_public_profile_consent'];
BEGIN
  FOREACH v_pair IN ARRAY v_expected_prerequisites LOOP
    v_signature := split_part(v_pair, '=', 1);
    v_hash := split_part(v_pair, '=', 2);
    IF to_regprocedure('hocalist.' || v_signature) IS NULL THEN
      v_issues := array_append(v_issues, 'prerequisite function missing: ' || v_signature);
    ELSIF (SELECT md5(replace(prosrc, chr(13), '')) FROM pg_proc
           WHERE oid = ('hocalist.' || v_signature)::regprocedure) IS DISTINCT FROM v_hash THEN
      v_issues := array_append(v_issues, 'prerequisite definition drift: ' || v_signature);
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'hocalist'
        AND p.proname IN ('marketplace_assert_role','marketplace_is_admin',
                          'marketplace_assert_admin','chat_open_internal',
                          'discovery_assert_active_member')) <> 5 THEN
    v_issues := array_append(v_issues, 'authorization function overload inventory changed');
  END IF;
  FOREACH v_pair IN ARRAY v_expected_package LOOP
    v_signature := split_part(v_pair, '=', 1);
    v_hash := split_part(v_pair, '=', 2);
    IF to_regprocedure('hocalist.' || v_signature) IS NULL THEN
      v_issues := array_append(v_issues, 'package function missing: ' || v_signature);
    ELSIF (SELECT md5(replace(prosrc, chr(13), '')) FROM pg_proc
           WHERE oid = ('hocalist.' || v_signature)::regprocedure) IS DISTINCT FROM v_hash THEN
      v_issues := array_append(v_issues, 'package definition drift: ' || v_signature);
    END IF;
  END LOOP;
  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing package table: ' || v_table);
      CONTINUE;
    END IF;
    v_expected_columns := CASE v_table
      WHEN 'seller_discovery_origins' THEN ARRAY[
        'area_label','created_at','latitude','longitude','radius_miles','revision',
        'seller_profile_id','seller_user_id','updated_at']
      WHEN 'outcome_reviews' THEN ARRAY[
        'body','buyer_user_id','created_at','id','meeting_id','moderated_at','moderated_by',
        'moderation_reason','offer_id','rating','request_id','revision','seller_profile_id',
        'seller_user_id','status','updated_at']
      ELSE ARRAY[
        'created_at','is_public','revision','show_area','show_categories',
        'show_display_name','updated_at','user_id']
    END;
    SELECT array_agg(column_name::text ORDER BY column_name) INTO v_actual_columns
      FROM information_schema.columns
      WHERE table_schema = 'hocalist' AND table_name = v_table;
    IF v_actual_columns IS DISTINCT FROM v_expected_columns THEN
      v_issues := array_append(v_issues, 'package table columns changed: ' || v_table);
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class
            WHERE oid = ('hocalist.' || v_table)::regclass) THEN
      v_issues := array_append(v_issues, 'package table RLS disabled: ' || v_table);
    END IF;
    IF EXISTS (SELECT 1 FROM pg_policies
               WHERE schemaname = 'hocalist' AND tablename = v_table) THEN
      v_issues := array_append(v_issues, 'unexpected package table policy: ' || v_table);
    END IF;
  END LOOP;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist discovery_completion drift verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_discovery_completion_hashes$;

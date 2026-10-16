-- Hocalist marketplace rollout verification. READ-ONLY: safe any time after
-- apply.sql. The DO block is textually identical to the post-apply block in
-- apply.sql and the draft; the rollout test asserts that equality.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $hocalist_marketplace_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_table text;
  v_role text;
  v_priv text;
  v_fn text;
  v_roles constant text[] := ARRAY['anon','authenticated','service_role'];
  v_privileges constant text[] := ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'];
  v_tables constant text[] := ARRAY[
    'marketplace_plan_limits','seller_entitlements','platform_admins',
    'catalogue_categories','catalogue_option_groups','catalogue_options','locations',
    'requests','offers','offer_revisions','store_listings','saved_items','marketplace_receipts'];
  v_client_functions constant text[] := ARRAY[
    'marketplace_catalogue(text,boolean)','marketplace_locations(text,boolean)',
    'marketplace_timezones()',
    'marketplace_request(uuid)','marketplace_my_requests(text,integer,text)',
    'marketplace_seller_leads(text,uuid,text,integer,text)',
    'marketplace_request_offers(uuid,integer,text)','marketplace_my_offers(integer,text)',
    'marketplace_offer(uuid)','marketplace_store_summary()',
    'marketplace_my_store_listings(text,text,text,integer,text)','marketplace_store_listing(uuid)',
    'marketplace_public_store_listings(uuid,text,integer,text)','marketplace_saved_items()',
    'marketplace_command(text,text,jsonb)','marketplace_admin_command(text,text,jsonb)',
    'marketplace_admin_moderation_queue(integer,text)'];
  v_internal_functions constant text[] := ARRAY[
    'marketplace_assert_role(uuid,text)','marketplace_is_admin(uuid)','marketplace_assert_admin(uuid)',
    'marketplace_seller_plan(uuid)','marketplace_store_limit(uuid)','marketplace_uuid_array(jsonb,text)',
    'marketplace_optional_text(jsonb,text,integer)',
    'marketplace_valid_timezone(text)','marketplace_next_local_day_start(date,text)',
    'marketplace_normalize_request(jsonb)',
    'marketplace_normalize_offer(jsonb)','marketplace_normalize_listing(jsonb)',
    'marketplace_request_json(uuid)','marketplace_lead_json(uuid)','marketplace_revision_json(uuid)',
    'marketplace_offer_json(uuid)','marketplace_listing_json(uuid)','marketplace_public_listing_json(uuid)'];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing marketplace table: ' || v_table);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.' || v_table)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: ' || v_table);
    END IF;
    FOREACH v_role IN ARRAY v_roles LOOP
      FOREACH v_priv IN ARRAY v_privileges LOOP
        IF has_table_privilege(v_role, 'hocalist.' || v_table, v_priv) THEN
          v_issues := array_append(v_issues,
            'unexpected ' || v_priv || ' for ' || v_role || ' on ' || v_table);
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
  IF (SELECT count(*) FROM hocalist.marketplace_plan_limits) <> 3 THEN
    v_issues := array_append(v_issues, 'plan limit seed differs from the reviewed values');
  END IF;
  IF (SELECT count(*) FROM pg_policies
      WHERE schemaname='hocalist' AND policyname LIKE 'marketplace_%') <> 5 THEN
    v_issues := array_append(v_issues, 'unexpected marketplace policy set');
  END IF;
  FOREACH v_fn IN ARRAY v_client_functions LOOP
    IF NOT has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'marketplace function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY v_internal_functions LOOP
    IF has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'internal marketplace function is executable: ' || v_fn);
    END IF;
  END LOOP;
  -- The deployed account and chat state must be untouched. The Stripe receipt
  -- table is checked only when it is present: this bundle's guard requires the
  -- account and chat foundations, not the billing rollout.
  IF NOT has_function_privilege('authenticated','hocalist.chat_send(uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE')
     OR NOT has_table_privilege('authenticated','hocalist.memberships','SELECT')
     OR (to_regclass('hocalist.stripe_test_inbox') IS NOT NULL
         AND has_table_privilege('service_role','hocalist.stripe_test_inbox','SELECT')) THEN
    v_issues := array_append(v_issues, 'deployed account/chat grants changed');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist marketplace post-apply verification failed: %', array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_marketplace_postapply$;
ROLLBACK;
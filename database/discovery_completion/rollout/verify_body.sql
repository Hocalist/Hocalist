-- Shared post-apply verification body. Included verbatim in apply.sql and used
-- standalone by verify.sql. Read-only checks.
DO $hocalist_discovery_completion_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_table text;
  v_role text;
  v_priv text;
  v_fn text;
  v_roles constant text[] := ARRAY['anon','authenticated','service_role'];
  v_privileges constant text[] := ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'];
  v_tables constant text[] := ARRAY[
    'seller_discovery_origins','outcome_reviews','buyer_public_profile_consent'];
  v_client_functions constant text[] := ARRAY[
    'discovery_origin_json()','discovery_origin_set(text,jsonb)',
    'marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)',
    'marketplace_recommended_leads(integer)',
    'review_status(uuid)','review_submit(text,jsonb)','review_update(text,jsonb)',
    'seller_public_reputation(uuid)',
    'buyer_public_profile_consent_json()','buyer_public_profile_consent_set(text,jsonb)',
    'buyer_public_profile(uuid)','hocatrends_trends(integer)','hocatrends_winners(integer)',
    'discovery_open_enquiry(text,jsonb)','marketplace_seller_outcomes(integer)',
    'hocatrends_topic_sellers(uuid,integer)'];
  v_internal_functions constant text[] := ARRAY[
    'discovery_distance_miles(double precision,double precision,double precision,double precision)',
    'discovery_declared_category_ids(uuid)',
    'discovery_assert_active_member(uuid)',
    'discovery_lead_json(uuid,double precision,integer,jsonb)',
    'review_reviewer_label(uuid)','review_json(uuid)'];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing discovery_completion table: ' || v_table);
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
  FOREACH v_fn IN ARRAY v_client_functions LOOP
    IF NOT has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'discovery_completion function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  -- review_moderate is admin-only through marketplace_assert_admin but is
  -- granted to authenticated so the reviewed admin RPC path can reach it.
  IF NOT has_function_privilege('authenticated','hocalist.review_moderate(text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','hocalist.review_moderate(text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'review_moderate grant is wrong');
  END IF;
  FOREACH v_fn IN ARRAY v_internal_functions LOOP
    IF has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'internal discovery_completion function is executable: ' || v_fn);
    END IF;
  END LOOP;
  -- Deployed chat and marketplace state must be untouched.
  IF NOT has_function_privilege('authenticated','hocalist.chat_send(uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.marketplace_command(text,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.sale_pin(uuid,text,text)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed chat/marketplace/outcome grants changed');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist discovery_completion post-apply verification failed: %', array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_discovery_completion_postapply$;

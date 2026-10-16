-- Hocalist discovery_completion containment. NON-DESTRUCTIVE.
--
-- Withdraws client execution of the discovery/review/trends RPCs without
-- deleting any rows. Chat, marketplace, meetings, outcomes and account objects
-- and grants are preserved. Safe to run repeatedly. Grants-only containment,
-- not a rollback.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '15s';
REVOKE EXECUTE ON FUNCTION
  hocalist.discovery_origin_json(),
  hocalist.discovery_origin_set(text,jsonb),
  hocalist.marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint),
  hocalist.marketplace_recommended_leads(integer),
  hocalist.review_status(uuid),
  hocalist.review_submit(text,jsonb),
  hocalist.review_update(text,jsonb),
  hocalist.review_moderate(text,jsonb),
  hocalist.seller_public_reputation(uuid),
  hocalist.buyer_public_profile_consent_json(),
  hocalist.buyer_public_profile_consent_set(text,jsonb),
  hocalist.buyer_public_profile(uuid),
  hocalist.hocatrends_trends(integer),
  hocalist.hocatrends_winners(integer),
  hocalist.discovery_open_enquiry(text,jsonb),
  hocalist.marketplace_seller_outcomes(integer),
  hocalist.hocatrends_topic_sellers(uuid,integer)
  FROM PUBLIC, anon, authenticated, service_role;
DO $hocalist_discovery_completion_containment$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_fn text;
  v_functions constant text[] := ARRAY[
    'discovery_origin_json()','discovery_origin_set(text,jsonb)',
    'marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)',
    'marketplace_recommended_leads(integer)',
    'review_status(uuid)','review_submit(text,jsonb)','review_update(text,jsonb)',
    'review_moderate(text,jsonb)','seller_public_reputation(uuid)',
    'buyer_public_profile_consent_json()','buyer_public_profile_consent_set(text,jsonb)',
    'buyer_public_profile(uuid)','hocatrends_trends(integer)','hocatrends_winners(integer)',
    'discovery_open_enquiry(text,jsonb)','marketplace_seller_outcomes(integer)',
    'hocatrends_topic_sellers(uuid,integer)'];
BEGIN
  FOREACH v_fn IN ARRAY v_functions LOOP
    IF has_function_privilege('authenticated','hocalist.' || v_fn,'EXECUTE')
       OR has_function_privilege('anon','hocalist.' || v_fn,'EXECUTE')
       OR has_function_privilege('service_role','hocalist.' || v_fn,'EXECUTE') THEN
      v_issues := array_append(v_issues, 'client can still execute ' || v_fn);
    END IF;
  END LOOP;
  IF NOT has_function_privilege('authenticated','hocalist.chat_send(uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.marketplace_command(text,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.sale_pin(uuid,text,text)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed chat/marketplace/outcome grants were disturbed');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist discovery_completion containment verification failed: %', array_to_string(v_issues,' | ');
  END IF;
END
$hocalist_discovery_completion_containment$;
COMMIT;
SELECT 'PASS: discovery_completion client access contained; rows and deployed objects preserved' AS discovery_completion_containment;

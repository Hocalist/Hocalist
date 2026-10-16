-- Hocalist marketplace containment. NON-DESTRUCTIVE.
--
-- Withdraws client execution of the marketplace RPCs without deleting any
-- rows. Account, chat, billing and push objects and grants are preserved.
-- Safe to run repeatedly. This is grants-only containment, not a rollback.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '15s';
REVOKE EXECUTE ON FUNCTION
  hocalist.marketplace_catalogue(text,boolean),
  hocalist.marketplace_locations(text,boolean),
  hocalist.marketplace_timezones(),
  hocalist.marketplace_request(uuid),
  hocalist.marketplace_my_requests(text,integer,text),
  hocalist.marketplace_seller_leads(text,uuid,text,integer,text),
  hocalist.marketplace_request_offers(uuid,integer,text),
  hocalist.marketplace_my_offers(integer,text),
  hocalist.marketplace_offer(uuid),
  hocalist.marketplace_store_summary(),
  hocalist.marketplace_my_store_listings(text,text,text,integer,text),
  hocalist.marketplace_store_listing(uuid),
  hocalist.marketplace_public_store_listings(uuid,text,integer,text),
  hocalist.marketplace_saved_items(),
  hocalist.marketplace_command(text,text,jsonb),
  hocalist.marketplace_admin_command(text,text,jsonb),
  hocalist.marketplace_admin_moderation_queue(integer,text)
  FROM PUBLIC, anon, authenticated, service_role;
DO $hocalist_marketplace_containment$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_fn text;
  v_functions constant text[] := ARRAY[
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
BEGIN
  FOREACH v_fn IN ARRAY v_functions LOOP
    IF has_function_privilege('authenticated','hocalist.' || v_fn,'EXECUTE')
       OR has_function_privilege('anon','hocalist.' || v_fn,'EXECUTE')
       OR has_function_privilege('service_role','hocalist.' || v_fn,'EXECUTE') THEN
      v_issues := array_append(v_issues, 'client can still execute ' || v_fn);
    END IF;
  END LOOP;
  IF NOT has_function_privilege('authenticated','hocalist.chat_send(uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE')
     OR (SELECT count(*) FROM hocalist.marketplace_plan_limits) <> 3 THEN
    v_issues := array_append(v_issues, 'deployed account/chat state or marketplace rows were disturbed');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist marketplace containment verification failed: %', array_to_string(v_issues,' | ');
  END IF;
END
$hocalist_marketplace_containment$;
COMMIT;
SELECT 'PASS: client marketplace access contained; rows and deployed objects preserved' AS marketplace_containment;
-- Read-only verification for deployed repairs 254 and 255.
-- Candidate 253 was not deployed: live discovery already has its context fields.
SELECT
 EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='seller_business_addresses' AND column_name='latitude') AS business_coordinates_installed,
 EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='sync_business_location' AND NOT tgisinternal) AS business_sync_installed,
 EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='sync_seller_service_radius' AND NOT tgisinternal) AS radius_sync_installed,
 position('coalesce(v_city' IN pg_get_functiondef(coalesce(to_regprocedure('hocalist.marketplace_normalize_request_before_questions(jsonb)'),to_regprocedure('hocalist.marketplace_normalize_request(jsonb)'))))>0 AS home_area_snapshot_supported,
 NOT has_function_privilege('authenticated','hocalist.sync_business_location()','execute') AND NOT has_function_privilege('authenticated','hocalist.sync_seller_service_radius()','execute') AS sync_helpers_private;

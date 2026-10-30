-- Preserve buyer-confirmed timezones; seller projections remain area-only.
BEGIN;
SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_normalize_request(jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('4c03c5d16c8ea6a9f169e921edf6a952', 'bf6547d36878420357cfa004e4b4a7a7') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_normalize_request'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_request_json(uuid)') AND md5(replace(prosrc,chr(13),'')) IN ('87344e90fca44ea903a38569fdbd8692', '10fd3c2b23bbba9178052c664d6c4e1e') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_request_json'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('e45fec459978cff4442c7d7ad84f524c', 'c4d2d6dfc061a8fd588577547a91b9b5') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_command'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_lead_json(uuid)') AND md5(replace(prosrc,chr(13),'')) IN ('49648feb929fee5f0b72a149372a1a34', '1bff944a220727b9cfa4ecf1f800f369', '0171b14f5cad3774b07f94ea12bba15d') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_lead_json'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.discovery_lead_json(uuid,double precision,integer,jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('1d6fc727511724f91e0cdffc647652e4', '5f6e35abb8033228ac01f13bff3abb77', '79bdc43e98f636bb785e03350e469882') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: discovery_lead_json'; END IF;
END $guard$;
ALTER TABLE hocalist.requests ADD COLUMN IF NOT EXISTS location_timezone text
 CHECK(location_timezone IS NULL OR hocalist.marketplace_valid_timezone(location_timezone));
CREATE OR REPLACE FUNCTION hocalist.marketplace_normalize_request(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_allowed constant text[] := ARRAY[
    'request_id','expected_revision',
    'kind','title','description','condition','service_type','quantity',
    'budget_minimum_minor','budget_maximum_minor','currency_code',
    'accepts_higher_offers','category_id','use_home_address',
    'address_line1','address_line2','city','region','postal_code','country_code','latitude','longitude','location_timezone'];
  v_kind text;
  v_title text;
  v_description text;
  v_condition text;
  v_service_type text;
  v_quantity integer;
  v_min bigint;
  v_max bigint;
  v_currency text;
  v_category uuid;
  v_category_scope text;
  v_use_home boolean;
  v_line1 text;
  v_line2 text;
  v_city text;
  v_region text;
  v_postal text;
  v_country text;
  v_field text;
BEGIN
  IF p_input->>'location_timezone' IS NOT NULL AND NOT hocalist.marketplace_valid_timezone(p_input->>'location_timezone') THEN
    RAISE EXCEPTION 'invalid_field: location_timezone' USING ERRCODE='22023';
  END IF;
  IF p_input IS NULL OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023';
  END IF;
  FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
    RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
  END LOOP;

  v_kind := p_input->>'kind';
  IF v_kind IS NULL OR v_kind NOT IN ('product','service') THEN
    RAISE EXCEPTION 'invalid_field: kind' USING ERRCODE='22023';
  END IF;
  v_title := btrim(coalesce(p_input->>'title',''));
  IF length(v_title) NOT BETWEEN 1 AND 160 THEN
    RAISE EXCEPTION 'invalid_field: title' USING ERRCODE='22023';
  END IF;
  v_description := coalesce(p_input->>'description','');
  IF length(v_description) > 500 THEN
    RAISE EXCEPTION 'invalid_field: description' USING ERRCODE='22023';
  END IF;

  v_condition := nullif(p_input->>'condition','');
  v_service_type := nullif(p_input->>'service_type','');
  IF v_kind = 'product' THEN
    IF v_condition IS NULL OR v_condition NOT IN ('new_item','used') OR v_service_type IS NOT NULL THEN
      RAISE EXCEPTION 'invalid_field: condition' USING ERRCODE='22023';
    END IF;
  ELSE
    IF v_service_type IS NULL OR v_service_type NOT IN ('one_time','ongoing') OR v_condition IS NOT NULL THEN
      RAISE EXCEPTION 'invalid_field: service_type' USING ERRCODE='22023';
    END IF;
  END IF;

  IF jsonb_typeof(p_input->'quantity') = 'null' OR NOT (p_input ? 'quantity') THEN
    v_quantity := 1;
  ELSIF jsonb_typeof(p_input->'quantity') = 'number'
        AND (p_input->>'quantity') ~ '^[1-9][0-9]?$' THEN
    v_quantity := (p_input->>'quantity')::integer;
  ELSE
    RAISE EXCEPTION 'invalid_field: quantity' USING ERRCODE='22023';
  END IF;
  IF v_kind = 'service' AND v_quantity <> 1 THEN
    RAISE EXCEPTION 'invalid_field: quantity' USING ERRCODE='22023';
  END IF;

  v_min := NULL;
  v_max := NULL;
  v_currency := nullif(p_input->>'currency_code','');
  IF v_currency IS NOT NULL AND v_currency !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'invalid_field: currency_code' USING ERRCODE='22023';
  END IF;
  IF p_input ? 'budget_minimum_minor' AND jsonb_typeof(p_input->'budget_minimum_minor') <> 'null' THEN
    IF jsonb_typeof(p_input->'budget_minimum_minor') <> 'number'
       OR (p_input->>'budget_minimum_minor') !~ '^[0-9]{1,15}$' THEN
      RAISE EXCEPTION 'invalid_field: budget_minimum_minor' USING ERRCODE='22023';
    END IF;
    v_min := (p_input->>'budget_minimum_minor')::bigint;
  END IF;
  IF p_input ? 'budget_maximum_minor' AND jsonb_typeof(p_input->'budget_maximum_minor') <> 'null' THEN
    IF jsonb_typeof(p_input->'budget_maximum_minor') <> 'number'
       OR (p_input->>'budget_maximum_minor') !~ '^[0-9]{1,15}$' THEN
      RAISE EXCEPTION 'invalid_field: budget_maximum_minor' USING ERRCODE='22023';
    END IF;
    v_max := (p_input->>'budget_maximum_minor')::bigint;
  END IF;
  IF v_min IS NOT NULL OR v_max IS NOT NULL THEN
    IF v_currency IS NULL THEN
      RAISE EXCEPTION 'invalid_field: currency_code' USING ERRCODE='22023';
    END IF;
    IF v_min IS NOT NULL AND v_max IS NOT NULL AND v_max < v_min THEN
      RAISE EXCEPTION 'invalid_field: budget_maximum_minor' USING ERRCODE='22023';
    END IF;
  END IF;

  IF p_input ? 'category_id' AND jsonb_typeof(p_input->'category_id') <> 'null' THEN
    IF jsonb_typeof(p_input->'category_id') <> 'string'
       OR (p_input->>'category_id') !~ '^[0-9a-fA-F-]{36}$' THEN
      RAISE EXCEPTION 'invalid_field: category_id' USING ERRCODE='22023';
    END IF;
    v_category := (p_input->>'category_id')::uuid;
    SELECT scope INTO v_category_scope FROM hocalist.catalogue_categories
      WHERE id = v_category AND status = 'active';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'invalid_category' USING ERRCODE='22023';
    END IF;
    IF v_category_scope <> 'both' AND v_category_scope <> v_kind THEN
      RAISE EXCEPTION 'invalid_category' USING ERRCODE='22023';
    END IF;
  ELSE
    v_category := NULL;
  END IF;

  IF p_input ? 'use_home_address' AND jsonb_typeof(p_input->'use_home_address') <> 'null' THEN
    IF jsonb_typeof(p_input->'use_home_address') <> 'boolean' THEN
      RAISE EXCEPTION 'invalid_field: use_home_address' USING ERRCODE='22023';
    END IF;
    v_use_home := (p_input->>'use_home_address')::boolean;
  ELSE
    v_use_home := true;
  END IF;
  v_line1 := hocalist.marketplace_optional_text(p_input, 'address_line1', 300);
  v_line2 := hocalist.marketplace_optional_text(p_input, 'address_line2', 300);
  v_city := hocalist.marketplace_optional_text(p_input, 'city', 150);
  v_region := hocalist.marketplace_optional_text(p_input, 'region', 150);
  v_postal := hocalist.marketplace_optional_text(p_input, 'postal_code', 40);
  v_country := hocalist.marketplace_optional_text(p_input, 'country_code', 2);
  IF v_country IS NOT NULL AND v_country !~ '^[A-Z]{2}$' THEN
    RAISE EXCEPTION 'invalid_field: country_code' USING ERRCODE='22023';
  END IF;
  IF NOT v_use_home AND v_line1 IS NULL AND v_line2 IS NULL AND v_city IS NULL
     AND v_region IS NULL AND v_postal IS NULL AND v_country IS NULL THEN
    RAISE EXCEPTION 'invalid_field: address_line1' USING ERRCODE='22023';
  END IF;
  IF p_input ? 'accepts_higher_offers'
     AND jsonb_typeof(p_input->'accepts_higher_offers') NOT IN ('boolean','null') THEN
    RAISE EXCEPTION 'invalid_field: accepts_higher_offers' USING ERRCODE='22023';
  END IF;

  IF (p_input->>'latitude' IS NULL) <> (p_input->>'longitude' IS NULL) THEN
    RAISE EXCEPTION 'invalid_field: coordinates' USING ERRCODE='22023';
  END IF;
  IF p_input->>'latitude' IS NOT NULL THEN
    IF v_use_home OR jsonb_typeof(p_input->'latitude') <> 'number'
       OR jsonb_typeof(p_input->'longitude') <> 'number' THEN
      RAISE EXCEPTION 'invalid_field: coordinates' USING ERRCODE='22023';
    END IF;
    IF (p_input->>'latitude')::numeric NOT BETWEEN -90 AND 90
       OR (p_input->>'longitude')::numeric NOT BETWEEN -180 AND 180 THEN
      RAISE EXCEPTION 'invalid_field: coordinates' USING ERRCODE='22023';
    END IF;
  END IF;
  RETURN jsonb_build_object(
    'location_timezone', p_input->>'location_timezone', 'latitude', p_input->'latitude', 'longitude', p_input->'longitude',
    'kind', v_kind,
    'title', v_title,
    'description', v_description,
    'condition', CASE WHEN v_kind = 'product' THEN v_condition ELSE NULL END,
    'service_type', CASE WHEN v_kind = 'service' THEN v_service_type ELSE NULL END,
    'quantity', v_quantity,
    'budget_minimum_minor', v_min,
    'budget_maximum_minor', v_max,
    'currency_code', CASE WHEN v_min IS NOT NULL OR v_max IS NOT NULL THEN v_currency ELSE NULL END,
    'accepts_higher_offers', coalesce((p_input->>'accepts_higher_offers')::boolean, false),
    'category_id', v_category,
    'use_home_address', v_use_home,
    'address_line1', CASE WHEN v_use_home THEN NULL ELSE v_line1 END,
    'address_line2', CASE WHEN v_use_home THEN NULL ELSE v_line2 END,
    'city', CASE WHEN v_use_home THEN NULL ELSE v_city END,
    'region', CASE WHEN v_use_home THEN NULL ELSE v_region END,
    'postal_code', CASE WHEN v_use_home THEN NULL ELSE v_postal END,
    'country_code', CASE WHEN v_use_home THEN NULL ELSE v_country END
  );
END; $$;
CREATE OR REPLACE FUNCTION hocalist.marketplace_request_json(p_request uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', r.id,
    'buyer_user_id', r.buyer_user_id,
    'buyer_profile_id', r.buyer_profile_id,
    'kind', r.kind,
    'title', r.title,
    'description', r.description,
    'condition', r.condition,
    'service_type', r.service_type,
    'quantity', r.quantity,
    'budget', jsonb_build_object(
      'minimum_minor', r.budget_min_minor,
      'maximum_minor', r.budget_max_minor,
      'currency', r.currency_code),
    'accepts_higher_offers', r.accepts_higher_offers,
    'category_id', r.category_id,
    'location', jsonb_build_object(
      'use_home_address', r.use_home_address, 'timezone_id', r.location_timezone,
      'latitude', r.latitude, 'longitude', r.longitude,
      'address_line1', r.address_line1,
      'address_line2', r.address_line2,
      'city', r.city,
      'region', r.region,
      'postal_code', r.postal_code,
      'country_code', r.country_code),
    'first_accepted_at', r.first_accepted_at,
    'acceptance_expires_at', r.acceptance_expires_at,
    'purchase_offer_id', r.purchase_offer_id,
    'purchase_selected_at', r.purchase_selected_at,
    'discovery_open', r.status = 'active'
      AND (r.acceptance_expires_at IS NULL OR now() < r.acceptance_expires_at),
    'status', r.status,
    'revision', r.revision,
    'created_at', r.created_at,
    'updated_at', r.updated_at)
  FROM hocalist.requests r WHERE r.id = p_request;
$$;
CREATE OR REPLACE FUNCTION hocalist.marketplace_command(p_operation text, p_key text, p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_hash text;
  v_receipt hocalist.marketplace_receipts%ROWTYPE;
  v_result jsonb;
  v_id uuid;
  v_expected bigint;
  v_norm jsonb;
  v_request hocalist.requests%ROWTYPE;
  v_offer hocalist.offers%ROWTYPE;
  v_listing hocalist.store_listings%ROWTYPE;
  v_count integer;
  v_limit integer;
  v_sequence integer;
  v_participants jsonb;
  v_conversation uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_operation IS NULL OR p_operation NOT IN (
    'request.create','request.update','request.close','request.reopen',
    'offer.submit','offer.revise','offer.withdraw','offer.select','purchase.select',
    'store.create','store.update','store.publish','store.archive','store.duplicate',
    'saved.toggle','conversation.open_offer') THEN
    RAISE EXCEPTION 'invalid_operation' USING ERRCODE='22023';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
     OR octet_length(p_input::text) > 32768 THEN
    RAISE EXCEPTION 'invalid_command' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = v_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  IF p_operation IN ('offer.revise','offer.withdraw','offer.select','purchase.select')
     AND (jsonb_typeof(p_input->'expected_offer_revision') <> 'number'
          OR (p_input->>'expected_offer_revision') !~ '^[1-9][0-9]{0,17}$') THEN
    RAISE EXCEPTION 'invalid_field: expected_offer_revision' USING ERRCODE='22023';
  END IF;
  IF p_operation IN ('request.update','request.close','request.reopen',
                     'store.update','store.publish','store.archive')
     AND (jsonb_typeof(p_input->'expected_revision') <> 'number'
          OR (p_input->>'expected_revision') !~ '^[1-9][0-9]{0,17}$') THEN
    RAISE EXCEPTION 'invalid_field: expected_revision' USING ERRCODE='22023';
  END IF;
  -- Serialize identical retries for one (user, operation, key) so a concurrent
  -- duplicate submission waits, then replays the committed receipt instead of
  -- racing the receipt insert or duplicating a create.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text || ':' || p_operation || ':' || p_key, 0));

  v_hash := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  SELECT * INTO v_receipt FROM hocalist.marketplace_receipts
    WHERE user_id = v_user AND operation = p_operation AND idempotency_key = p_key;
  IF FOUND THEN
    IF v_receipt.request_hash <> v_hash THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
    END IF;
    RETURN v_receipt.result;
  END IF;

  IF p_operation = 'request.create' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'buyer');
    v_norm := hocalist.marketplace_normalize_request(p_input);
    INSERT INTO hocalist.requests(
      buyer_user_id, buyer_profile_id, kind, title, description, condition, service_type,
      quantity, budget_min_minor, budget_max_minor, currency_code, accepts_higher_offers,
      category_id, use_home_address, address_line1, address_line2, city, region, postal_code, country_code, latitude, longitude, location_timezone)
    VALUES (
      v_user, hocalist.marketplace_assert_role(v_user, 'buyer'),
      v_norm->>'kind', v_norm->>'title', v_norm->>'description',
      v_norm->>'condition', v_norm->>'service_type',
      (v_norm->>'quantity')::integer,
      (v_norm->>'budget_minimum_minor')::bigint,
      (v_norm->>'budget_maximum_minor')::bigint,
      v_norm->>'currency_code',
      (v_norm->>'accepts_higher_offers')::boolean,
      (v_norm->>'category_id')::uuid,
      (v_norm->>'use_home_address')::boolean,
      v_norm->>'address_line1', v_norm->>'address_line2',
      v_norm->>'city', v_norm->>'region', v_norm->>'postal_code', v_norm->>'country_code',
      (v_norm->>'latitude')::double precision, (v_norm->>'longitude')::double precision, v_norm->>'location_timezone')
    RETURNING id INTO v_id;
    v_result := hocalist.marketplace_request_json(v_id);

  ELSIF p_operation = 'request.update' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'buyer');
    IF NOT (p_input ? 'request_id') OR jsonb_typeof(p_input->'request_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: request_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'request_id')::uuid;
    IF jsonb_typeof(p_input->'expected_revision') <> 'number'
       OR (p_input->>'expected_revision') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_field: expected_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_revision')::bigint;
    v_norm := hocalist.marketplace_normalize_request(p_input);
    SELECT * INTO v_request FROM hocalist.requests
      WHERE id = v_id AND buyer_user_id = v_user FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'request_access_denied' USING ERRCODE='42501';
    END IF;
    IF v_request.status NOT IN ('draft','active') THEN
      RAISE EXCEPTION 'request_not_editable' USING ERRCODE='P0001';
    END IF;
    UPDATE hocalist.requests SET
      kind = v_norm->>'kind',
      title = v_norm->>'title',
      description = v_norm->>'description',
      condition = v_norm->>'condition',
      service_type = v_norm->>'service_type',
      quantity = (v_norm->>'quantity')::integer,
      budget_min_minor = (v_norm->>'budget_minimum_minor')::bigint,
      budget_max_minor = (v_norm->>'budget_maximum_minor')::bigint,
      currency_code = v_norm->>'currency_code',
      accepts_higher_offers = (v_norm->>'accepts_higher_offers')::boolean,
      category_id = (v_norm->>'category_id')::uuid,
      use_home_address = (v_norm->>'use_home_address')::boolean,
      address_line1 = v_norm->>'address_line1',
      address_line2 = v_norm->>'address_line2',
      city = v_norm->>'city',
      region = v_norm->>'region',
      postal_code = v_norm->>'postal_code',
      country_code = v_norm->>'country_code',
      location_timezone = v_norm->>'location_timezone',
      latitude = (v_norm->>'latitude')::double precision,
      longitude = (v_norm->>'longitude')::double precision,
      revision = revision + 1, updated_at = now()
    WHERE id = v_id AND buyer_user_id = v_user AND revision = v_expected
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := hocalist.marketplace_request_json(v_id);

  ELSIF p_operation = 'request.close' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'buyer');
    IF NOT (p_input ? 'request_id') OR jsonb_typeof(p_input->'request_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: request_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'request_id')::uuid;
    IF jsonb_typeof(p_input->'expected_revision') <> 'number'
       OR (p_input->>'expected_revision') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_field: expected_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_revision')::bigint;
    SELECT * INTO v_request FROM hocalist.requests
      WHERE id = v_id AND buyer_user_id = v_user FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'request_access_denied' USING ERRCODE='42501';
    END IF;
    IF v_request.status = 'closed' THEN
      v_result := hocalist.marketplace_request_json(v_id);
    ELSE
      IF v_request.status NOT IN ('draft','active') THEN
        RAISE EXCEPTION 'request_not_editable' USING ERRCODE='P0001';
      END IF;
      UPDATE hocalist.requests SET status = 'closed', revision = revision + 1, updated_at = now()
        WHERE id = v_id AND buyer_user_id = v_user AND revision = v_expected
        RETURNING id INTO v_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
      END IF;
      v_result := hocalist.marketplace_request_json(v_id);
    END IF;

  ELSIF p_operation = 'request.reopen' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'buyer');
    IF NOT (p_input ? 'request_id') OR jsonb_typeof(p_input->'request_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: request_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'request_id')::uuid;
    IF jsonb_typeof(p_input->'expected_revision') <> 'number'
       OR (p_input->>'expected_revision') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_field: expected_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_revision')::bigint;
    SELECT * INTO v_request FROM hocalist.requests
      WHERE id = v_id AND buyer_user_id = v_user FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'request_access_denied' USING ERRCODE='42501';
    END IF;
    IF v_request.status NOT IN ('closed','expired','cancelled') THEN
      RAISE EXCEPTION 'request_not_reopenable' USING ERRCODE='P0001';
    END IF;
    -- Reopening never clears the first-acceptance window. An already expired
    -- window stays expired for discovery; accepted meetings keep their own
    -- valid outcome path.
    UPDATE hocalist.requests SET status = 'active', revision = revision + 1, updated_at = now()
      WHERE id = v_id AND buyer_user_id = v_user AND revision = v_expected
      RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := hocalist.marketplace_request_json(v_id);

  ELSIF p_operation = 'offer.submit' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
    IF NOT (p_input ? 'request_id') OR jsonb_typeof(p_input->'request_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: request_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'request_id')::uuid;
    v_norm := hocalist.marketplace_normalize_offer(p_input);
    SELECT * INTO v_request FROM hocalist.requests WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'request_not_found' USING ERRCODE='P0002';
    END IF;
    IF v_request.status <> 'active' THEN
      RAISE EXCEPTION 'request_not_open' USING ERRCODE='P0001';
    END IF;
    IF v_request.acceptance_expires_at IS NOT NULL
       AND now() >= v_request.acceptance_expires_at THEN
      RAISE EXCEPTION 'request_expired' USING ERRCODE='P0001';
    END IF;
    IF v_request.buyer_user_id = v_user THEN
      RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
    END IF;
    BEGIN
      INSERT INTO hocalist.offers(request_id, buyer_user_id, seller_user_id, seller_profile_id)
      VALUES (v_id, v_request.buyer_user_id, v_user, hocalist.marketplace_assert_role(v_user, 'seller'))
      RETURNING id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'offer_exists' USING ERRCODE='P0001';
    END;
    INSERT INTO hocalist.offer_revisions(
      offer_id, sequence, price_minor, currency_code, message, image_media_ids,
      schedule_date, schedule_time, schedule_timezone, schedule_occurrence,
      schedule_offset_minutes, schedule_instant, place_choice,
      place_label, place_address, place_id, place_latitude, place_longitude, proposed_by_user_id)
    VALUES (
      v_id, 1,
      (v_norm->>'price_minor')::bigint, v_norm->>'currency_code', v_norm->>'message',
      v_norm->'image_media_ids',
      (v_norm->>'schedule_date')::date, (v_norm->>'schedule_time')::time,
      v_norm->>'schedule_timezone', v_norm->>'schedule_occurrence',
      (v_norm->>'schedule_offset_minutes')::integer,
      (v_norm->>'schedule_instant')::timestamptz, v_norm->>'place_choice',
      v_norm->>'place_label', v_norm->>'place_address', v_norm->>'place_id',
      (v_norm->>'place_latitude')::double precision,
      (v_norm->>'place_longitude')::double precision, v_user);
    -- Full winning-fee reservation before the targeting interaction is
    -- permitted, from the oldest eligible single batch. Absent commercial
    -- module or absent rate policy leaves the offer usable without a charge.
    IF to_regprocedure('hocalist.credit_authorize_target(uuid,uuid,uuid)') IS NOT NULL THEN
      PERFORM hocalist.credit_authorize_target(v_user, v_request.id, v_id);
    END IF;
    v_result := hocalist.marketplace_offer_json(v_id);

  ELSIF p_operation = 'offer.revise' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
    IF NOT (p_input ? 'offer_id') OR jsonb_typeof(p_input->'offer_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: offer_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'offer_id')::uuid;
    IF jsonb_typeof(p_input->'expected_offer_revision') <> 'number'
       OR (p_input->>'expected_offer_revision') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_field: expected_offer_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_offer_revision')::bigint;
    v_norm := hocalist.marketplace_normalize_offer(p_input);
    SELECT * INTO v_offer FROM hocalist.offers WHERE id = v_id AND seller_user_id = v_user FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
    END IF;
    IF v_offer.status <> 'submitted' THEN
      RAISE EXCEPTION 'offer_not_open' USING ERRCODE='P0001';
    END IF;
    IF v_offer.revision <> v_expected THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    UPDATE hocalist.offer_revisions SET status = 'superseded'
      WHERE offer_id = v_id AND status = 'proposed';
    SELECT coalesce(max(sequence), 0) + 1 INTO v_sequence
      FROM hocalist.offer_revisions WHERE offer_id = v_id;
    INSERT INTO hocalist.offer_revisions(
      offer_id, sequence, price_minor, currency_code, message, image_media_ids,
      schedule_date, schedule_time, schedule_timezone, schedule_occurrence,
      schedule_offset_minutes, schedule_instant, place_choice,
      place_label, place_address, place_id, place_latitude, place_longitude, proposed_by_user_id)
    VALUES (
      v_id, v_sequence,
      (v_norm->>'price_minor')::bigint, v_norm->>'currency_code', v_norm->>'message',
      v_norm->'image_media_ids',
      (v_norm->>'schedule_date')::date, (v_norm->>'schedule_time')::time,
      v_norm->>'schedule_timezone', v_norm->>'schedule_occurrence',
      (v_norm->>'schedule_offset_minutes')::integer,
      (v_norm->>'schedule_instant')::timestamptz, v_norm->>'place_choice',
      v_norm->>'place_label', v_norm->>'place_address', v_norm->>'place_id',
      (v_norm->>'place_latitude')::double precision,
      (v_norm->>'place_longitude')::double precision, v_user);
    UPDATE hocalist.offers SET revision = revision + 1, updated_at = now()
      WHERE id = v_id AND revision = v_expected;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := hocalist.marketplace_offer_json(v_id);

  ELSIF p_operation = 'offer.withdraw' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
    IF NOT (p_input ? 'offer_id') OR jsonb_typeof(p_input->'offer_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: offer_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'offer_id')::uuid;
    IF jsonb_typeof(p_input->'expected_offer_revision') <> 'number'
       OR (p_input->>'expected_offer_revision') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_field: expected_offer_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_offer_revision')::bigint;
    SELECT * INTO v_offer FROM hocalist.offers WHERE id = v_id AND seller_user_id = v_user FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
    END IF;
    IF v_offer.status = 'withdrawn' THEN
      v_result := hocalist.marketplace_offer_json(v_id);
    ELSE
      IF v_offer.status <> 'submitted' THEN
        RAISE EXCEPTION 'offer_not_open' USING ERRCODE='P0001';
      END IF;
      UPDATE hocalist.offer_revisions SET status = 'withdrawn'
        WHERE offer_id = v_id AND status = 'proposed';
      UPDATE hocalist.offers SET status = 'withdrawn', revision = revision + 1, updated_at = now()
        WHERE id = v_id AND seller_user_id = v_user AND revision = v_expected
        RETURNING id INTO v_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
      END IF;
      -- A withdrawn negotiation never charged the initial fee unless both
      -- parties had already sent a qualifying message; settlement preserves
      -- the already-charged initial amount and returns the unused reserve.
      IF to_regprocedure('hocalist.credit_release_offer(uuid)') IS NOT NULL THEN
        PERFORM hocalist.credit_release_offer(v_id);
      END IF;
      v_result := hocalist.marketplace_offer_json(v_id);
    END IF;

  ELSIF p_operation = 'offer.select' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'buyer');
    IF NOT (p_input ? 'offer_id') OR jsonb_typeof(p_input->'offer_id') <> 'string'
       OR NOT (p_input ? 'revision_id') OR jsonb_typeof(p_input->'revision_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: offer_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'offer_id')::uuid;
    IF jsonb_typeof(p_input->'expected_offer_revision') <> 'number'
       OR (p_input->>'expected_offer_revision') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_field: expected_offer_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_offer_revision')::bigint;
    SELECT * INTO v_offer FROM hocalist.offers WHERE id = v_id AND buyer_user_id = v_user;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
    END IF;
    -- Serialize every acceptance decision for one request: the request row is
    -- the lock target so two buyer sessions cannot race the countdown stamp.
    SELECT * INTO v_request FROM hocalist.requests WHERE id = v_offer.request_id FOR UPDATE;
    IF v_request.status <> 'active' THEN
      RAISE EXCEPTION 'request_not_open' USING ERRCODE='P0001';
    END IF;
    IF v_request.acceptance_expires_at IS NOT NULL
       AND now() >= v_request.acceptance_expires_at THEN
      UPDATE hocalist.requests SET status = 'expired', updated_at = now()
        WHERE id = v_request.id AND status = 'active';
      RAISE EXCEPTION 'request_expired' USING ERRCODE='P0001';
    END IF;
    -- Re-read the offer under the request lock so the decision uses the
    -- committed state after any concurrent writer released the lock.
    SELECT * INTO v_offer FROM hocalist.offers WHERE id = v_id FOR UPDATE;
    IF v_offer.status = 'selected' THEN
      IF v_offer.accepted_revision_id = (p_input->>'revision_id')::uuid THEN
        v_result := hocalist.marketplace_offer_json(v_id);
      ELSE
        RAISE EXCEPTION 'offer_revision_conflict' USING ERRCODE='P0001';
      END IF;
    ELSE
      IF v_offer.status <> 'submitted' THEN
        RAISE EXCEPTION 'offer_not_open' USING ERRCODE='P0001';
      END IF;
      IF v_offer.revision <> v_expected THEN
        RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM hocalist.offer_revisions
        WHERE id = (p_input->>'revision_id')::uuid AND offer_id = v_id AND status = 'proposed'
      ) THEN
        RAISE EXCEPTION 'offer_revision_conflict' USING ERRCODE='P0001';
      END IF;
      UPDATE hocalist.offer_revisions SET status = 'superseded'
        WHERE offer_id = v_id AND status = 'proposed';
      UPDATE hocalist.offer_revisions SET status = 'accepted'
        WHERE id = (p_input->>'revision_id')::uuid AND offer_id = v_id;
      UPDATE hocalist.offers
        SET status = 'selected', accepted_revision_id = (p_input->>'revision_id')::uuid,
            revision = revision + 1, updated_at = now()
        WHERE id = v_id AND revision = v_expected
        RETURNING id INTO v_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
      END IF;
      -- First acceptance starts the seven-day window once; later acceptances
      -- never move it.
      UPDATE hocalist.requests
        SET first_accepted_at = coalesce(first_accepted_at, now()),
            acceptance_expires_at = coalesce(acceptance_expires_at, now() + interval '7 days')
        WHERE id = v_request.id;
      v_result := hocalist.marketplace_offer_json(v_id);
    END IF;

  ELSIF p_operation = 'purchase.select' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'buyer');
    IF NOT (p_input ? 'offer_id') OR jsonb_typeof(p_input->'offer_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: offer_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'offer_id')::uuid;
    IF jsonb_typeof(p_input->'expected_offer_revision') <> 'number'
       OR (p_input->>'expected_offer_revision') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_field: expected_offer_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_offer_revision')::bigint;
    SELECT * INTO v_offer FROM hocalist.offers WHERE id = v_id AND buyer_user_id = v_user;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
    END IF;
    SELECT * INTO v_request FROM hocalist.requests WHERE id = v_offer.request_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'request_not_found' USING ERRCODE='P0002';
    END IF;
    IF to_regclass('hocalist.sale_confirmations') IS NOT NULL
       AND EXISTS (SELECT 1 FROM hocalist.sale_confirmations WHERE request_id = v_request.id) THEN
      RAISE EXCEPTION 'sale_already_confirmed' USING ERRCODE='P0001';
    END IF;
    SELECT * INTO v_offer FROM hocalist.offers WHERE id = v_id FOR UPDATE;
    IF v_offer.status <> 'selected' OR v_offer.accepted_revision_id IS NULL THEN
      RAISE EXCEPTION 'offer_not_selected' USING ERRCODE='P0001';
    END IF;
    IF v_offer.revision <> v_expected THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    -- The buyer may change the designated seller until a purchase is
    -- confirmed; only the designated seller can complete the PIN.
    UPDATE hocalist.requests
      SET purchase_offer_id = v_offer.id,
          purchase_selected_at = now(),
          updated_at = now()
      WHERE id = v_request.id;
    v_result := hocalist.marketplace_offer_json(v_offer.id);

  ELSIF p_operation = 'store.create' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
    v_norm := hocalist.marketplace_normalize_listing(p_input);
    -- Serialize this seller's capacity changes so two parallel creates cannot
    -- both pass at the last remaining slot. The settled 3/15/50 allowances are
    -- unchanged; counting/downgrade policy beyond this lock is still open.
    PERFORM 1 FROM hocalist.profiles WHERE id = v_user FOR UPDATE;
    v_limit := hocalist.marketplace_store_limit(v_user);
    SELECT count(*)::integer INTO v_count FROM hocalist.store_listings
      WHERE seller_user_id = v_user AND status <> 'archived';
    IF v_count >= v_limit THEN
      RAISE EXCEPTION 'store_limit_exceeded' USING ERRCODE='P0001';
    END IF;
    INSERT INTO hocalist.store_listings(
      seller_user_id, seller_profile_id, kind, title, description, category_id,
      category_label, price_label, service_area, availability, image_media_ids,
      status, moderation_status, published_at)
    VALUES (
      v_user, hocalist.marketplace_assert_role(v_user, 'seller'),
      v_norm->>'kind', v_norm->>'title', v_norm->>'description',
      (v_norm->>'category_id')::uuid, v_norm->>'category_label',
      v_norm->>'price_label', v_norm->>'service_area', v_norm->>'availability',
      v_norm->'image_media_ids',
      CASE WHEN v_norm->>'publish_intent' = 'publish' THEN 'active' ELSE 'draft' END,
      'pending_review',
      CASE WHEN v_norm->>'publish_intent' = 'publish' THEN now() ELSE NULL END)
    RETURNING id INTO v_id;
    v_result := hocalist.marketplace_listing_json(v_id);

  ELSIF p_operation = 'store.update' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
    IF NOT (p_input ? 'listing_id') OR jsonb_typeof(p_input->'listing_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: listing_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'listing_id')::uuid;
    IF jsonb_typeof(p_input->'expected_revision') <> 'number'
       OR (p_input->>'expected_revision') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_field: expected_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_revision')::bigint;
    v_norm := hocalist.marketplace_normalize_listing(p_input);
    SELECT * INTO v_listing FROM hocalist.store_listings
      WHERE id = v_id AND seller_user_id = v_user;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'listing_access_denied' USING ERRCODE='42501';
    END IF;
    IF v_listing.status = 'archived' THEN
      RAISE EXCEPTION 'listing_not_editable' USING ERRCODE='P0001';
    END IF;
    UPDATE hocalist.store_listings SET
      title = v_norm->>'title',
      description = v_norm->>'description',
      category_id = (v_norm->>'category_id')::uuid,
      category_label = v_norm->>'category_label',
      price_label = v_norm->>'price_label',
      service_area = v_norm->>'service_area',
      availability = v_norm->>'availability',
      image_media_ids = v_norm->'image_media_ids',
      moderation_status = 'pending_review',
      revision = revision + 1, updated_at = now()
    WHERE id = v_id AND seller_user_id = v_user AND revision = v_expected
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := hocalist.marketplace_listing_json(v_id);

  ELSIF p_operation = 'store.publish' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
    IF NOT (p_input ? 'listing_id') OR jsonb_typeof(p_input->'listing_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: listing_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'listing_id')::uuid;
    IF jsonb_typeof(p_input->'expected_revision') <> 'number'
       OR (p_input->>'expected_revision') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_field: expected_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_revision')::bigint;
    IF jsonb_typeof(p_input->'publish') <> 'boolean' THEN
      RAISE EXCEPTION 'invalid_field: publish' USING ERRCODE='22023';
    END IF;
    SELECT * INTO v_listing FROM hocalist.store_listings
      WHERE id = v_id AND seller_user_id = v_user;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'listing_access_denied' USING ERRCODE='42501';
    END IF;
    IF v_listing.status = 'archived' THEN
      RAISE EXCEPTION 'listing_not_editable' USING ERRCODE='P0001';
    END IF;
    IF (p_input->>'publish')::boolean THEN
      PERFORM 1 FROM hocalist.profiles WHERE id = v_user FOR UPDATE;
      v_limit := hocalist.marketplace_store_limit(v_user);
      SELECT count(*)::integer INTO v_count FROM hocalist.store_listings
        WHERE seller_user_id = v_user AND status <> 'archived' AND id <> v_id;
      IF v_count >= v_limit THEN
        RAISE EXCEPTION 'store_limit_exceeded' USING ERRCODE='P0001';
      END IF;
      UPDATE hocalist.store_listings
        SET status = 'active', published_at = coalesce(published_at, now()),
            revision = revision + 1, updated_at = now()
        WHERE id = v_id AND seller_user_id = v_user AND revision = v_expected
        RETURNING id INTO v_id;
    ELSE
      UPDATE hocalist.store_listings
        SET status = 'paused', revision = revision + 1, updated_at = now()
        WHERE id = v_id AND seller_user_id = v_user AND revision = v_expected
        RETURNING id INTO v_id;
    END IF;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := hocalist.marketplace_listing_json(v_id);

  ELSIF p_operation = 'store.archive' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
    IF NOT (p_input ? 'listing_id') OR jsonb_typeof(p_input->'listing_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: listing_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'listing_id')::uuid;
    IF jsonb_typeof(p_input->'expected_revision') <> 'number'
       OR (p_input->>'expected_revision') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_field: expected_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_revision')::bigint;
    SELECT * INTO v_listing FROM hocalist.store_listings
      WHERE id = v_id AND seller_user_id = v_user;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'listing_access_denied' USING ERRCODE='42501';
    END IF;
    IF v_listing.status = 'archived' THEN
      v_result := hocalist.marketplace_listing_json(v_id);
    ELSE
      PERFORM 1 FROM hocalist.profiles WHERE id = v_user FOR UPDATE;
      UPDATE hocalist.store_listings
        SET status = 'archived', revision = revision + 1, updated_at = now()
        WHERE id = v_id AND seller_user_id = v_user AND revision = v_expected
        RETURNING id INTO v_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
      END IF;
      v_result := hocalist.marketplace_listing_json(v_id);
    END IF;

  ELSIF p_operation = 'store.duplicate' THEN
    PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
    IF NOT (p_input ? 'listing_id') OR jsonb_typeof(p_input->'listing_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: listing_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'listing_id')::uuid;
    PERFORM 1 FROM hocalist.profiles WHERE id = v_user FOR UPDATE;
    v_limit := hocalist.marketplace_store_limit(v_user);
    SELECT count(*)::integer INTO v_count FROM hocalist.store_listings
      WHERE seller_user_id = v_user AND status <> 'archived';
    IF v_count >= v_limit THEN
      RAISE EXCEPTION 'store_limit_exceeded' USING ERRCODE='P0001';
    END IF;
    INSERT INTO hocalist.store_listings(
      seller_user_id, seller_profile_id, kind, title, description, category_id,
      category_label, price_label, service_area, availability, image_media_ids,
      status, moderation_status)
    SELECT l.seller_user_id, l.seller_profile_id, l.kind, left(l.title || ' copy', 160),
           l.description, l.category_id, l.category_label, l.price_label,
           l.service_area, l.availability, l.image_media_ids, 'draft', 'pending_review'
    FROM hocalist.store_listings l
    WHERE l.id = v_id AND l.seller_user_id = v_user
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'listing_access_denied' USING ERRCODE='42501';
    END IF;
    v_result := hocalist.marketplace_listing_json(v_id);

  ELSIF p_operation = 'saved.toggle' THEN
    IF NOT (p_input ? 'item_type') OR (p_input->>'item_type') NOT IN ('request','store_listing')
       OR NOT (p_input ? 'item_id') OR jsonb_typeof(p_input->'item_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: item_type' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'item_id')::uuid;
    IF EXISTS (SELECT 1 FROM hocalist.saved_items
               WHERE user_id = v_user AND item_type = p_input->>'item_type' AND item_id = v_id) THEN
      DELETE FROM hocalist.saved_items
        WHERE user_id = v_user AND item_type = p_input->>'item_type' AND item_id = v_id;
      v_result := jsonb_build_object('saved', false, 'item_type', p_input->>'item_type', 'item_id', v_id);
    ELSE
      INSERT INTO hocalist.saved_items(user_id, item_type, item_id)
        VALUES (v_user, p_input->>'item_type', v_id);
      v_result := jsonb_build_object('saved', true, 'item_type', p_input->>'item_type', 'item_id', v_id);
    END IF;

  ELSE -- conversation.open_offer
    IF NOT (p_input ? 'offer_id') OR jsonb_typeof(p_input->'offer_id') <> 'string' THEN
      RAISE EXCEPTION 'invalid_field: offer_id' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'offer_id')::uuid;
    SELECT * INTO v_offer FROM hocalist.offers WHERE id = v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'offer_not_found' USING ERRCODE='P0002';
    END IF;
    IF v_offer.buyer_user_id <> v_user AND v_offer.seller_user_id <> v_user THEN
      RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
    END IF;
    IF v_offer.status <> 'selected' OR v_offer.accepted_revision_id IS NULL THEN
      RAISE EXCEPTION 'conversation_not_eligible' USING ERRCODE='P0001';
    END IF;
    IF v_offer.conversation_id IS NOT NULL THEN
      v_result := jsonb_build_object('conversation_id', v_offer.conversation_id);
    ELSE
      IF to_regprocedure('hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)') IS NULL THEN
        RAISE EXCEPTION 'chat_foundation_missing' USING ERRCODE='P0001';
      END IF;
      PERFORM hocalist.marketplace_assert_role(v_user,
        CASE WHEN v_user = v_offer.buyer_user_id THEN 'buyer' ELSE 'seller' END);
      -- The participant list is derived from the accepted offer and the two
      -- active memberships, never from the caller.
      SELECT hocalist.chat_open_internal(
        'targeted_request', v_offer.request_id, v_offer.id, NULL, NULL,
        jsonb_build_array(
          jsonb_build_object(
            'user_id', v_offer.buyer_user_id,
            'profile_id', (SELECT buyer_profile_id FROM hocalist.requests WHERE id = v_offer.request_id),
            'role', 'buyer'),
          jsonb_build_object(
            'user_id', v_offer.seller_user_id,
            'profile_id', v_offer.seller_profile_id,
            'role', 'seller')))
      INTO v_conversation;
      UPDATE hocalist.offers SET conversation_id = v_conversation, updated_at = now()
        WHERE id = v_offer.id AND conversation_id IS NULL;
      v_result := jsonb_build_object('conversation_id', v_conversation);
    END IF;
  END IF;

  INSERT INTO hocalist.marketplace_receipts(user_id, operation, idempotency_key, request_hash, result)
    VALUES (v_user, p_operation, p_key, v_hash, v_result);
  RETURN v_result;
END; $$;
CREATE OR REPLACE FUNCTION hocalist.marketplace_lead_json(p_request uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'request_id', r.id,
    'kind', r.kind,
    'title', r.title,
    'description', r.description,
    'condition', r.condition,
    'service_type', r.service_type,
    'quantity', r.quantity,
    'budget', jsonb_build_object(
      'minimum_minor', r.budget_min_minor,
      'maximum_minor', r.budget_max_minor,
      'currency', r.currency_code),
    'accepts_higher_offers', r.accepts_higher_offers,
    'category_id', r.category_id,
    'buyer_profile_id', r.buyer_profile_id,
    'buyer_display_name', coalesce(nullif(btrim(rp.display_name), ''), 'Hocalist member'),
    'area_label', CASE WHEN r.use_home_address THEN rp.area_label ELSE coalesce(nullif(btrim(r.city),''),nullif(btrim(r.region),''),rp.area_label) END,
    'location_timezone', r.location_timezone, 'request_revision', r.revision,
    'acceptance_expires_at', r.acceptance_expires_at,
    'discovery_open', r.status = 'active'
      AND (r.acceptance_expires_at IS NULL OR now() < r.acceptance_expires_at),
    'published_at', r.created_at, 'verified_purchase_count', (SELECT count(*) FROM hocalist.sale_confirmations s WHERE s.buyer_user_id=r.buyer_user_id))
  FROM hocalist.requests r
  LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = r.buyer_profile_id
  WHERE r.id = p_request;
$$;
CREATE OR REPLACE FUNCTION hocalist.discovery_lead_json(
  p_request uuid,
  p_distance_miles double precision DEFAULT NULL,
  p_match integer DEFAULT NULL,
  p_match_reasons jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'request_id', r.id,
    'kind', r.kind,
    'title', r.title,
    'description', r.description,
    'condition', r.condition,
    'service_type', r.service_type,
    'quantity', r.quantity,
    'budget', jsonb_build_object(
      'minimum_minor', r.budget_min_minor,
      'maximum_minor', r.budget_max_minor,
      'currency', r.currency_code),
    'accepts_higher_offers', r.accepts_higher_offers,
    'category_id', r.category_id,
    'buyer_profile_id', r.buyer_profile_id,
    'buyer_display_name', coalesce(nullif(btrim(rp.display_name), ''), 'Hocalist member'),
    'area_label', CASE WHEN r.use_home_address THEN rp.area_label ELSE coalesce(nullif(btrim(r.city),''),nullif(btrim(r.region),''),rp.area_label) END,
    'location_timezone', r.location_timezone, 'request_revision', r.revision,
    'acceptance_expires_at', r.acceptance_expires_at,
    'discovery_open', r.status = 'active'
      AND (r.acceptance_expires_at IS NULL OR now() < r.acceptance_expires_at),
    'published_at', r.created_at,
    'distance_miles', p_distance_miles,
    'match_percent', p_match,
    'match_reasons', coalesce(p_match_reasons, '[]'::jsonb),
    'verified_purchase_count', (
      SELECT count(*)::integer FROM hocalist.sale_confirmations s
      WHERE s.buyer_user_id = r.buyer_user_id)
  )
  FROM hocalist.requests r
  LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = r.buyer_profile_id
  WHERE r.id = p_request;
$$;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_normalize_request(jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('4c03c5d16c8ea6a9f169e921edf6a952') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_normalize_request'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_request_json(uuid)') AND md5(replace(prosrc,chr(13),'')) IN ('87344e90fca44ea903a38569fdbd8692') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_request_json'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('e45fec459978cff4442c7d7ad84f524c') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_command'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.marketplace_lead_json(uuid)') AND md5(replace(prosrc,chr(13),'')) IN ('49648feb929fee5f0b72a149372a1a34') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: marketplace_lead_json'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.discovery_lead_json(uuid,double precision,integer,jsonb)') AND md5(replace(prosrc,chr(13),'')) IN ('1d6fc727511724f91e0cdffc647652e4') AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: discovery_lead_json'; END IF;
END $guard$;
NOTIFY pgrst, 'reload schema';
COMMIT;

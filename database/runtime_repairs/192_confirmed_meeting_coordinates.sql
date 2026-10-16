-- Participant-only confirmed pins; no new grants or public coordinate projection.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.marketplace_normalize_offer(jsonb)')) IS DISTINCT FROM '53d709735f09544b91a6ab2b5aefc4b3' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: marketplace_normalize_offer';
  END IF;
  IF has_function_privilege('anon','hocalist.marketplace_normalize_offer(jsonb)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_normalize_offer(jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.marketplace_normalize_offer(jsonb)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.marketplace_normalize_offer(jsonb)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: marketplace_normalize_offer';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.marketplace_revision_json(uuid)')) IS DISTINCT FROM '469fed2ad69e5368e8b39374efa8e0e5' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: marketplace_revision_json';
  END IF;
  IF has_function_privilege('anon','hocalist.marketplace_revision_json(uuid)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_revision_json(uuid)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.marketplace_revision_json(uuid)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.marketplace_revision_json(uuid)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: marketplace_revision_json';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)')) IS DISTINCT FROM '8b97abe37830ec8b67abcf2ffc011286' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: marketplace_command';
  END IF;
  IF has_function_privilege('anon','hocalist.marketplace_command(text,text,jsonb)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_command(text,text,jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.marketplace_command(text,text,jsonb)','EXECUTE')
      IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: marketplace_command';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_normalize_schedule(jsonb)')) IS DISTINCT FROM 'b5a6cf4bce96a4342bd46590bbae1537' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_normalize_schedule';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_normalize_schedule(jsonb)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_normalize_schedule(jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_normalize_schedule(jsonb)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_normalize_schedule(jsonb)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_normalize_schedule';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)')) IS DISTINCT FROM 'd42ff578c099e4080823113610d19929' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_revision_json';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_revision_json';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)')) IS DISTINCT FROM '78ad91f34f48a44342c8845c7c29e063' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_propose';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_propose(uuid,jsonb,text)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_propose(uuid,jsonb,text)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_propose(uuid,jsonb,text)','EXECUTE')
      IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_propose';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)')) IS DISTINCT FROM 'de0e4dce750f951ff4a240411879ebf5' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_reschedule_propose';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)','EXECUTE')
      IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_reschedule_propose';
  END IF;
END $guard$;
ALTER TABLE hocalist.offer_revisions
  ADD COLUMN place_latitude double precision,
  ADD COLUMN place_longitude double precision,
  ADD CONSTRAINT offer_revisions_place_coordinates CHECK (
    (place_latitude IS NULL AND place_longitude IS NULL) OR
    (place_latitude IS NOT NULL AND place_longitude IS NOT NULL
      AND place_latitude BETWEEN -90 AND 90 AND place_longitude BETWEEN -180 AND 180));
ALTER TABLE hocalist.meeting_schedule_revisions
  ADD COLUMN place_latitude double precision,
  ADD COLUMN place_longitude double precision,
  ADD CONSTRAINT meeting_schedule_revisions_place_coordinates CHECK (
    (place_latitude IS NULL AND place_longitude IS NULL) OR
    (place_latitude IS NOT NULL AND place_longitude IS NOT NULL
      AND place_latitude BETWEEN -90 AND 90 AND place_longitude BETWEEN -180 AND 180));
CREATE OR REPLACE FUNCTION hocalist.marketplace_normalize_offer(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_allowed constant text[] := ARRAY[
    'request_id','offer_id','expected_offer_revision',
    'price_minor','currency_code','message','image_media_ids',
    'schedule_date','schedule_time','schedule_timezone','schedule_occurrence',
    'place_choice','place_label','place_address','place_id','place_latitude','place_longitude'];
  v_price bigint;
  v_currency text;
  v_message text;
  v_images jsonb;
  v_date date;
  v_time time;
  v_timezone text;
  v_occurrence text;
  v_local timestamp;
  v_base timestamptz;
  v_candidates timestamptz[];
  v_count integer;
  v_instant timestamptz;
  v_offset integer;
  v_choice text;
  v_label text;
  v_address text;
  v_place_id text;
  v_field text;
BEGIN
  IF p_input IS NULL OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_offer' USING ERRCODE='22023';
  END IF;
  FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
    RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
  END LOOP;

  IF jsonb_typeof(p_input->'price_minor') <> 'number'
     OR (p_input->>'price_minor') !~ '^[1-9][0-9]{0,14}$' THEN
    RAISE EXCEPTION 'invalid_field: price_minor' USING ERRCODE='22023';
  END IF;
  v_price := (p_input->>'price_minor')::bigint;
  v_currency := p_input->>'currency_code';
  IF v_currency IS NULL OR v_currency !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'invalid_field: currency_code' USING ERRCODE='22023';
  END IF;
  v_message := coalesce(p_input->>'message','');
  IF length(v_message) > 1000 THEN
    RAISE EXCEPTION 'invalid_field: message' USING ERRCODE='22023';
  END IF;
  v_images := hocalist.marketplace_uuid_array(coalesce(p_input->'image_media_ids','[]'::jsonb), 'image_media_ids');

  IF jsonb_typeof(p_input->'schedule_date') <> 'string'
     OR (p_input->>'schedule_date') !~ '^\d{4}-\d{2}-\d{2}$' THEN
    RAISE EXCEPTION 'invalid_field: schedule_date' USING ERRCODE='22023';
  END IF;
  BEGIN
    v_date := (p_input->>'schedule_date')::date;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'invalid_field: schedule_date' USING ERRCODE='22023';
  END;
  IF jsonb_typeof(p_input->'schedule_time') <> 'string'
     OR (p_input->>'schedule_time') !~ '^\d{2}:\d{2}(:\d{2})?$' THEN
    RAISE EXCEPTION 'invalid_field: schedule_time' USING ERRCODE='22023';
  END IF;
  BEGIN
    v_time := (p_input->>'schedule_time')::time;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'invalid_field: schedule_time' USING ERRCODE='22023';
  END;
  v_timezone := btrim(coalesce(p_input->>'schedule_timezone',''));
  IF NOT hocalist.marketplace_valid_timezone(v_timezone) THEN
    RAISE EXCEPTION 'invalid_field: schedule_timezone' USING ERRCODE='22023';
  END IF;
  v_occurrence := nullif(btrim(coalesce(p_input->>'schedule_occurrence','')), '');
  IF v_occurrence IS NOT NULL AND v_occurrence NOT IN ('earlier','later') THEN
    RAISE EXCEPTION 'invalid_field: schedule_occurrence' USING ERRCODE='22023';
  END IF;

  -- Resolve the local wall time against the named zone's own rules. A
  -- nonexistent local time (DST spring gap) is rejected; a repeated local time
  -- (DST fall-back) requires an explicit occurrence. The stored offset and UTC
  -- instant are server-resolved so both parties share one schedule revision.
  --
  -- Every candidate instant is enumerated instead of assuming the usual
  -- one-hour fall-back: the zone offset is sampled across the transition
  -- window and each observed offset is tested, so 30-minute (Australia/
  -- Lord_Howe) and two-hour (Antarctica/Troll) transitions resolve to their
  -- real instants.
  v_local := (v_date + v_time)::timestamp;
  v_base := v_local AT TIME ZONE v_timezone;
  SELECT array_agg(DISTINCT candidate ORDER BY candidate)
    INTO v_candidates
  FROM (
    SELECT ((v_local - make_interval(mins => (EXTRACT(EPOCH FROM
               ((v_base + make_interval(mins => g)) AT TIME ZONE v_timezone)
               - ((v_base + make_interval(mins => g)) AT TIME ZONE 'UTC')
             ) / 60)::integer)) AT TIME ZONE 'UTC') AS candidate
    FROM generate_series(-1560, 1560, 5) AS g
  ) AS candidates
  WHERE (candidate AT TIME ZONE v_timezone) = v_local;

  IF v_candidates IS NULL THEN
    RAISE EXCEPTION 'nonexistent_local_time' USING ERRCODE='22023';
  END IF;
  v_count := array_length(v_candidates, 1);
  IF v_count > 1 THEN
    IF v_occurrence IS NULL THEN
      RAISE EXCEPTION 'ambiguous_local_time' USING ERRCODE='22023';
    END IF;
    IF v_occurrence = 'earlier' THEN
      v_instant := v_candidates[1];
    ELSE
      v_instant := v_candidates[v_count];
    END IF;
  ELSE
    IF v_occurrence IS NOT NULL THEN
      RAISE EXCEPTION 'invalid_field: schedule_occurrence' USING ERRCODE='22023';
    END IF;
    v_instant := v_candidates[1];
  END IF;
  v_offset := (EXTRACT(EPOCH FROM (v_local - (v_instant AT TIME ZONE 'UTC'))) / 60)::integer;

  v_choice := p_input->>'place_choice';
  IF v_choice IS NULL OR v_choice NOT IN ('seller_business','buyer_location','specific_place') THEN
    RAISE EXCEPTION 'invalid_field: place_choice' USING ERRCODE='22023';
  END IF;
  v_label := hocalist.marketplace_optional_text(p_input, 'place_label', 200);
  v_address := hocalist.marketplace_optional_text(p_input, 'place_address', 300);
  v_place_id := hocalist.marketplace_optional_text(p_input, 'place_id', 200);
  IF v_choice = 'specific_place' AND v_label IS NULL AND v_place_id IS NULL THEN
    RAISE EXCEPTION 'invalid_field: place_label' USING ERRCODE='22023';
  END IF;

  IF (p_input->>'place_latitude' IS NULL) <> (p_input->>'place_longitude' IS NULL)
    OR (p_input->>'place_latitude' IS NOT NULL AND (
      jsonb_typeof(p_input->'place_latitude') <> 'number'
      OR jsonb_typeof(p_input->'place_longitude') <> 'number')) THEN
    RAISE EXCEPTION 'invalid_place_coordinates' USING ERRCODE='P0001';
  END IF;
  IF p_input->>'place_latitude' IS NOT NULL AND (
    (p_input->>'place_latitude')::numeric NOT BETWEEN -90 AND 90
    OR (p_input->>'place_longitude')::numeric NOT BETWEEN -180 AND 180) THEN
    RAISE EXCEPTION 'invalid_place_coordinates' USING ERRCODE='P0001';
  END IF;
  RETURN jsonb_build_object(
    'price_minor', v_price,
    'currency_code', v_currency,
    'message', v_message,
    'image_media_ids', v_images,
    'schedule_date', v_date,
    'schedule_time', v_time,
    'schedule_timezone', v_timezone,
    'schedule_occurrence', v_occurrence,
    'schedule_offset_minutes', v_offset,
    'schedule_instant', v_instant,
    'place_choice', v_choice,
    'place_label', v_label,
    'place_address', v_address,
    'place_id', v_place_id,
    'place_latitude', p_input->'place_latitude',
    'place_longitude', p_input->'place_longitude'
  );
END; $$;
CREATE OR REPLACE FUNCTION hocalist.marketplace_revision_json(p_revision uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', v.id,
    'offer_id', v.offer_id,
    'sequence', v.sequence,
    'price_minor', v.price_minor,
    'currency_code', v.currency_code,
    'message', v.message,
    'image_media_ids', v.image_media_ids,
    'schedule_date', to_char(v.schedule_date, 'YYYY-MM-DD'),
    'schedule_time', to_char(v.schedule_time, 'HH24:MI'),
    'schedule_timezone', v.schedule_timezone,
    'schedule_occurrence', v.schedule_occurrence,
    'schedule_utc_offset_minutes', v.schedule_offset_minutes,
    'schedule_utc_instant', v.schedule_instant,
    'place_choice', v.place_choice,
    'place_label', v.place_label,
    'place_address', v.place_address,
    'place_id', v.place_id,
    'place_latitude', v.place_latitude,
    'place_longitude', v.place_longitude,
    'status', v.status,
    'proposed_by_user_id', v.proposed_by_user_id,
    'created_at', v.created_at)
  FROM hocalist.offer_revisions v WHERE v.id = p_revision;
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
      category_id, use_home_address, address_line1, address_line2, city, region, postal_code, country_code, latitude, longitude)
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
      (v_norm->>'latitude')::double precision, (v_norm->>'longitude')::double precision)
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
CREATE OR REPLACE FUNCTION hocalist.meeting_normalize_schedule(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_norm jsonb;
BEGIN
  v_norm := hocalist.marketplace_normalize_offer(jsonb_build_object(
    'price_minor', 1,
    'currency_code', 'USD',
    'message', '',
    'image_media_ids', '[]'::jsonb,
    'schedule_date', p_input->>'schedule_date',
    'schedule_time', p_input->>'schedule_time',
    'schedule_timezone', p_input->>'schedule_timezone',
    'schedule_occurrence', p_input->>'schedule_occurrence',
    'place_choice', p_input->>'place_choice',
    'place_label', p_input->>'place_label',
    'place_address', p_input->>'place_address',
    'place_id', p_input->>'place_id',
    'place_latitude', p_input->'place_latitude',
    'place_longitude', p_input->'place_longitude'
  ));
  RETURN v_norm;
END; $$;
CREATE OR REPLACE FUNCTION hocalist.meeting_revision_json(p_revision hocalist.meeting_schedule_revisions)
RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', p_revision.id,
    'meeting_id', p_revision.meeting_id,
    'sequence', p_revision.sequence,
    'schedule_date', p_revision.schedule_date,
    'schedule_time', p_revision.schedule_time,
    'schedule_timezone', p_revision.schedule_timezone,
    'schedule_occurrence', p_revision.schedule_occurrence,
    'schedule_offset_minutes', p_revision.schedule_offset_minutes,
    'schedule_instant', p_revision.schedule_instant,
    'place_choice', p_revision.place_choice,
    'place_label', p_revision.place_label,
    'place_address', p_revision.place_address,
    'place_id', p_revision.place_id,
    'place_latitude', p_revision.place_latitude,
    'place_longitude', p_revision.place_longitude,
    'proposed_by_user_id', p_revision.proposed_by_user_id,
    'status', p_revision.status,
    'created_at', p_revision.created_at,
    'resolved_at', p_revision.resolved_at
  );
$$;
CREATE OR REPLACE FUNCTION hocalist.meeting_propose(
  p_conversation uuid,
  p_input jsonb,
  p_key text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_conv hocalist.conversations%ROWTYPE;
  v_offer hocalist.offers%ROWTYPE;
  v_meeting hocalist.meetings%ROWTYPE;
  v_norm jsonb;
  v_hash text;
  v_replay jsonb;
  v_meeting_id uuid;
  v_seq integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid_field: p_key' USING ERRCODE='22023';
  END IF;
  IF p_conversation IS NULL OR p_input IS NULL
     OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_field: p_input' USING ERRCODE='22023';
  END IF;
  PERFORM hocalist.meeting_assert_conversation_member(p_conversation, v_user);
  SELECT * INTO v_conv FROM hocalist.conversations
    WHERE id = p_conversation AND origin = 'targeted_request' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'meeting_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_offer FROM hocalist.offers
    WHERE id = v_conv.offer_id AND status = 'selected'
      AND conversation_id = p_conversation;
  IF NOT FOUND OR v_offer.accepted_revision_id IS NULL THEN
    RAISE EXCEPTION 'meeting_offer_not_selected' USING ERRCODE='P0001';
  END IF;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'conversation', p_conversation, 'input', p_input)::text,'UTF8')),'hex');
  v_replay := hocalist.meeting_receipt_begin(
    v_user, 'meeting.propose', p_key, v_hash);
  IF v_replay IS NOT NULL THEN
    RETURN v_replay;
  END IF;

  SELECT * INTO v_meeting FROM hocalist.meetings
    WHERE conversation_id = p_conversation AND offer_id = v_offer.id;
  IF FOUND THEN
    IF v_meeting.status = 'cancelled' THEN
      RAISE EXCEPTION 'meeting_cancelled' USING ERRCODE='P0001';
    END IF;
    IF v_meeting.accepted_revision_id IS NOT NULL
       OR v_meeting.status = 'accepted' THEN
      RAISE EXCEPTION 'meeting_already_exists' USING ERRCODE='P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM hocalist.meeting_schedule_revisions
               WHERE meeting_id = v_meeting.id AND status = 'proposed') THEN
      RAISE EXCEPTION 'meeting_reschedule_pending' USING ERRCODE='P0001';
    END IF;
    v_norm := hocalist.meeting_normalize_schedule(p_input);
    SELECT coalesce(max(sequence), 0) + 1 INTO v_seq
      FROM hocalist.meeting_schedule_revisions WHERE meeting_id = v_meeting.id;
    INSERT INTO hocalist.meeting_schedule_revisions(
      meeting_id, sequence, schedule_date, schedule_time, schedule_timezone,
      schedule_occurrence, schedule_offset_minutes, schedule_instant,
      place_choice, place_label, place_address, place_id, place_latitude, place_longitude, proposed_by_user_id)
    VALUES (
      v_meeting.id, v_seq,
      (v_norm->>'schedule_date')::date,
      (v_norm->>'schedule_time')::time,
      v_norm->>'schedule_timezone',
      v_norm->>'schedule_occurrence',
      (v_norm->>'schedule_offset_minutes')::integer,
      (v_norm->>'schedule_instant')::timestamptz,
      v_norm->>'place_choice',
      v_norm->>'place_label',
      v_norm->>'place_address',
      v_norm->>'place_id',
      (v_norm->>'place_latitude')::double precision,
      (v_norm->>'place_longitude')::double precision,
      v_user);
    UPDATE hocalist.meetings
      SET status = 'proposed', revision = revision + 1, updated_at = now()
      WHERE id = v_meeting.id;
    RETURN hocalist.meeting_receipt_store(
      v_user, 'meeting.propose', p_key, v_hash,
      hocalist.meeting_json(v_meeting.id));
  END IF;

  v_norm := hocalist.meeting_normalize_schedule(p_input);
  INSERT INTO hocalist.meetings(
    conversation_id, request_id, offer_id, buyer_user_id, seller_user_id)
  VALUES (
    p_conversation, v_offer.request_id, v_offer.id,
    v_offer.buyer_user_id, v_offer.seller_user_id)
  RETURNING id INTO v_meeting_id;

  INSERT INTO hocalist.meeting_schedule_revisions(
    meeting_id, sequence, schedule_date, schedule_time, schedule_timezone,
    schedule_occurrence, schedule_offset_minutes, schedule_instant,
    place_choice, place_label, place_address, place_id, place_latitude, place_longitude, proposed_by_user_id)
  VALUES (
    v_meeting_id, 1,
    (v_norm->>'schedule_date')::date,
    (v_norm->>'schedule_time')::time,
    v_norm->>'schedule_timezone',
    v_norm->>'schedule_occurrence',
    (v_norm->>'schedule_offset_minutes')::integer,
    (v_norm->>'schedule_instant')::timestamptz,
    v_norm->>'place_choice',
    v_norm->>'place_label',
    v_norm->>'place_address',
    v_norm->>'place_id',
      (v_norm->>'place_latitude')::double precision,
      (v_norm->>'place_longitude')::double precision,
    v_user);

  RETURN hocalist.meeting_receipt_store(
    v_user, 'meeting.propose', p_key, v_hash,
    hocalist.meeting_json(v_meeting_id));
END; $$;
CREATE OR REPLACE FUNCTION hocalist.meeting_reschedule_propose(
  p_meeting uuid,
  p_input jsonb,
  p_expected_revision bigint,
  p_key text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_row hocalist.meetings%ROWTYPE;
  v_norm jsonb;
  v_hash text;
  v_replay jsonb;
  v_seq integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid_field: p_key' USING ERRCODE='22023';
  END IF;
  IF p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
     OR p_expected_revision IS NULL OR p_expected_revision < 1 THEN
    RAISE EXCEPTION 'invalid_field: p_expected_revision' USING ERRCODE='22023';
  END IF;
  PERFORM hocalist.meeting_assert_participant(p_meeting, v_user);

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'meeting', p_meeting, 'input', p_input,
    'expected_revision', p_expected_revision)::text,'UTF8')),'hex');
  v_replay := hocalist.meeting_receipt_begin(
    v_user, 'meeting.reschedule_propose', p_key, v_hash);
  IF v_replay IS NOT NULL THEN
    RETURN v_replay;
  END IF;

  SELECT * INTO v_row FROM hocalist.meetings WHERE id = p_meeting FOR UPDATE;
  IF v_row.revision <> p_expected_revision THEN
    RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
  END IF;
  IF v_row.status NOT IN ('accepted','reschedule_proposed') THEN
    RAISE EXCEPTION 'meeting_not_accepted' USING ERRCODE='P0001';
  END IF;
  IF EXISTS (
    SELECT 1 FROM hocalist.meeting_schedule_revisions
    WHERE meeting_id = p_meeting AND status = 'proposed'
  ) THEN
    RAISE EXCEPTION 'meeting_reschedule_pending' USING ERRCODE='P0001';
  END IF;

  v_norm := hocalist.meeting_normalize_schedule(p_input);
  SELECT coalesce(max(sequence), 0) + 1 INTO v_seq
  FROM hocalist.meeting_schedule_revisions WHERE meeting_id = p_meeting;
  INSERT INTO hocalist.meeting_schedule_revisions(
    meeting_id, sequence, schedule_date, schedule_time, schedule_timezone,
    schedule_occurrence, schedule_offset_minutes, schedule_instant,
    place_choice, place_label, place_address, place_id, place_latitude, place_longitude, proposed_by_user_id)
  VALUES (
    p_meeting, v_seq,
    (v_norm->>'schedule_date')::date,
    (v_norm->>'schedule_time')::time,
    v_norm->>'schedule_timezone',
    v_norm->>'schedule_occurrence',
    (v_norm->>'schedule_offset_minutes')::integer,
    (v_norm->>'schedule_instant')::timestamptz,
    v_norm->>'place_choice',
    v_norm->>'place_label',
    v_norm->>'place_address',
    v_norm->>'place_id',
      (v_norm->>'place_latitude')::double precision,
      (v_norm->>'place_longitude')::double precision,
    v_user);
  UPDATE hocalist.meetings
    SET status = 'reschedule_proposed',
        revision = revision + 1,
        updated_at = now()
    WHERE id = p_meeting;
  RETURN hocalist.meeting_receipt_store(
    v_user, 'meeting.reschedule_propose', p_key, v_hash,
    hocalist.meeting_json(p_meeting));
END; $$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.marketplace_normalize_offer(jsonb)')) IS DISTINCT FROM '8a56e9c38aa1bfdf99ae437e53acdf99' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: marketplace_normalize_offer';
  END IF;
  IF has_function_privilege('anon','hocalist.marketplace_normalize_offer(jsonb)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_normalize_offer(jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.marketplace_normalize_offer(jsonb)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.marketplace_normalize_offer(jsonb)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: marketplace_normalize_offer';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.marketplace_revision_json(uuid)')) IS DISTINCT FROM '4c4389bc5e67e3948a3b91f16171b734' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: marketplace_revision_json';
  END IF;
  IF has_function_privilege('anon','hocalist.marketplace_revision_json(uuid)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_revision_json(uuid)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.marketplace_revision_json(uuid)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.marketplace_revision_json(uuid)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: marketplace_revision_json';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)')) IS DISTINCT FROM 'c4d2d6dfc061a8fd588577547a91b9b5' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: marketplace_command';
  END IF;
  IF has_function_privilege('anon','hocalist.marketplace_command(text,text,jsonb)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_command(text,text,jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.marketplace_command(text,text,jsonb)','EXECUTE')
      IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: marketplace_command';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_normalize_schedule(jsonb)')) IS DISTINCT FROM '6cba775454b1ed71c5e124a0e1a786d9' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_normalize_schedule';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_normalize_schedule(jsonb)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_normalize_schedule(jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_normalize_schedule(jsonb)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_normalize_schedule(jsonb)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_normalize_schedule';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)')) IS DISTINCT FROM 'f83d6494b4da6b69f6b9996043e8d8f9' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_revision_json';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_revision_json';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)')) IS DISTINCT FROM 'dbbc3139676df6e2312b6622de7a17c0' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_propose';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_propose(uuid,jsonb,text)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_propose(uuid,jsonb,text)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_propose(uuid,jsonb,text)','EXECUTE')
      IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_propose';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)')) IS DISTINCT FROM '81f4d38048b005f6c9286eb84e7ed0df' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_reschedule_propose';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)','EXECUTE')
      IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_reschedule_propose';
  END IF;
END $guard$;
COMMIT;

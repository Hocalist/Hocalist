BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
DO $guard$ BEGIN
IF to_regprocedure('hocalist.marketplace_request_json(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_request_json(uuid)')),chr(13),''))<>'d1707451d3854d729b8654fbc9b47985' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_request_json(uuid)'; END IF;
IF to_regprocedure('hocalist.marketplace_lead_json(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_lead_json(uuid)')),chr(13),''))<>'5d0dc0dcc462c59a3c30cb7cbe380a3c' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_lead_json(uuid)'; END IF;
IF to_regprocedure('hocalist.marketplace_offer_json(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_offer_json(uuid)')),chr(13),''))<>'9d5fdec5970731716e843c0b03803731' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_offer_json(uuid)'; END IF;
IF to_regprocedure('hocalist.marketplace_request(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_request(uuid)')),chr(13),''))<>'c6225021a74624672406e0b7d73ccc8b' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_request(uuid)'; END IF;
IF to_regprocedure('hocalist.marketplace_seller_leads(text,uuid,text,integer,text)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_seller_leads(text,uuid,text,integer,text)')),chr(13),''))<>'e05521dc79f56fc16118522190da8908' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_seller_leads(text,uuid,text,integer,text)'; END IF;
IF to_regprocedure('hocalist.marketplace_command(text,text,jsonb)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_command(text,text,jsonb)')),chr(13),''))<>'f75fb4eae067f16f0270eedcce83772a' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_command(text,text,jsonb)'; END IF;
IF to_regprocedure('hocalist.sale_pin(uuid,text,text)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.sale_pin(uuid,text,text)')),chr(13),''))<>'c935b662860d575095ba45ed6daaf5c5' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.sale_pin(uuid,text,text)'; END IF;
IF to_regprocedure('hocalist.meeting_json(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.meeting_json(uuid)')),chr(13),''))<>'0b1f3230ac1a5f1052f99d6239ff210c' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.meeting_json(uuid)'; END IF;
IF to_regprocedure('hocalist.credit_wallet()') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.credit_wallet()')),chr(13),''))<>'ade39ebd47e0ebf915a901e4e587b2e4' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.credit_wallet()'; END IF;
IF to_regprocedure('hocalist.reward_wallet()') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.reward_wallet()')),chr(13),''))<>'bd5248bf235b034fcdeed1d5d5a0113c' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.reward_wallet()'; END IF;
IF to_regclass('hocalist.credit_deposit_options') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: credit_deposit_options'; END IF;
IF to_regclass('hocalist.reward_policy') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: reward_policy'; END IF;
IF to_regclass('hocalist.conversation_credit_hook') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: conversation_credit_hook'; END IF;
IF to_regclass('hocalist.withdrawal_policy') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: withdrawal_policy'; END IF;
IF to_regclass('hocalist.withdrawal_requests') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: withdrawal_requests'; END IF;
IF to_regclass('hocalist.withdrawal_events') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: withdrawal_events'; END IF;
IF to_regclass('hocalist.verification_submissions') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: verification_submissions'; END IF;
IF to_regclass('hocalist.health_review_notes') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: health_review_notes'; END IF;
IF to_regclass('hocalist.account_restrictions') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: account_restrictions'; END IF;
IF to_regclass('hocalist.restriction_appeals') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: restriction_appeals'; END IF;
END $guard$;
-- Additive migration over reviewed 021: multiple accepted negotiations with a
-- single purchase, the first-acceptance seven-day countdown, discovery closure
-- on request expiry and buyer designation of the final purchase seller.
--
-- Prerequisites: 020 foundation + 021 request coordinates already applied.
-- This file never reaches a live database; it is applied by the reviewed
-- upgrade bundle only after the coordinator's separate authorization.
--
-- Local decisions implemented here (DECISIONS.md 2026-09-26):
--   1. acceptance_expires_at is set once at the first acceptance and never
--      reset by later acceptances;
--   2. several offers may be selected for one request, each keeping its own
--      conversation and meeting history;
--   4. request expiry closes discovery and new offers only. Accepted meetings
--      survive to their own next-local-midnight PIN cutoff.
--
-- Credit reservation/settlement is invoked through optional internal hooks so
-- this migration stays applicable without the commercial module (dynamic
-- dispatch only when the reviewed helper exists).

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regprocedure('hocalist.marketplace_command(text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'marketplace 020 prerequisite missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist' AND table_name='requests' AND column_name='latitude'
  ) THEN
    RAISE EXCEPTION 'request coordinates 021 prerequisite missing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist' AND table_name='requests' AND column_name='first_accepted_at'
  ) THEN
    RAISE EXCEPTION 'multi-negotiation already installed';
  END IF;
END; $guard$;

-- ---------------------------------------------------------------------------
-- Countdown and final-purchase designation
-- ---------------------------------------------------------------------------

ALTER TABLE hocalist.requests
  ADD COLUMN first_accepted_at timestamptz,
  ADD COLUMN acceptance_expires_at timestamptz,
  ADD COLUMN purchase_offer_id uuid REFERENCES hocalist.offers(id),
  ADD COLUMN purchase_selected_at timestamptz,
  ADD CONSTRAINT request_acceptance_window CHECK (
    (first_accepted_at IS NULL AND acceptance_expires_at IS NULL)
    OR (first_accepted_at IS NOT NULL AND acceptance_expires_at IS NOT NULL
        AND acceptance_expires_at > first_accepted_at));

-- Settled weekly customer-target capacity. One targeted customer consumes one
-- slot; a winning adjustment never consumes another slot.
ALTER TABLE hocalist.marketplace_plan_limits
  ADD COLUMN weekly_target_limit integer;
UPDATE hocalist.marketplace_plan_limits SET weekly_target_limit = CASE plan_code
  WHEN 'free' THEN 10 WHEN 'pro' THEN 50 WHEN 'elite' THEN 100 END;
ALTER TABLE hocalist.marketplace_plan_limits
  ALTER COLUMN weekly_target_limit SET NOT NULL,
  ADD CONSTRAINT plan_weekly_target_limit_valid CHECK (weekly_target_limit >= 0);

CREATE FUNCTION hocalist.marketplace_weekly_target_limit(p_user uuid)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT l.weekly_target_limit
  FROM hocalist.marketplace_plan_limits l
  WHERE l.plan_code = hocalist.marketplace_seller_plan(p_user);
$$;

-- ---------------------------------------------------------------------------
-- Projections now carry the authoritative countdown and designation
-- ---------------------------------------------------------------------------

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
      'use_home_address', r.use_home_address,
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

-- Seller-visible projection: no address, no contacts, no other offers. The
-- accepted seller sees the same authoritative request window as the buyer.
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
    'area_label', coalesce(rp.area_label, r.city, r.region),
    'request_revision', r.revision,
    'acceptance_expires_at', r.acceptance_expires_at,
    'discovery_open', r.status = 'active'
      AND (r.acceptance_expires_at IS NULL OR now() < r.acceptance_expires_at),
    'published_at', r.created_at)
  FROM hocalist.requests r
  LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = r.buyer_profile_id
  WHERE r.id = p_request;
$$;

CREATE OR REPLACE FUNCTION hocalist.marketplace_offer_json(p_offer uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', o.id,
    'request_id', o.request_id,
    'buyer_user_id', o.buyer_user_id,
    'seller_user_id', o.seller_user_id,
    'seller_profile_id', o.seller_profile_id,
    'seller_display_name', coalesce(nullif(btrim(rp.display_name), ''), 'Hocalist member'),
    'status', o.status,
    'accepted_revision_id', o.accepted_revision_id,
    'conversation_id', o.conversation_id,
    'purchase_selected', o.id = q.purchase_offer_id,
    'request_acceptance_expires_at', q.acceptance_expires_at,
    'request_first_accepted_at', q.first_accepted_at,
    'revision', o.revision,
    'created_at', o.created_at,
    'updated_at', o.updated_at,
    'revisions', coalesce((
      SELECT jsonb_agg(hocalist.marketplace_revision_json(v.id) ORDER BY v.sequence)
      FROM hocalist.offer_revisions v WHERE v.offer_id = o.id
    ), '[]'::jsonb))
  FROM hocalist.offers o
  JOIN hocalist.requests q ON q.id = o.request_id
  LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = o.seller_profile_id
  WHERE o.id = p_offer;
$$;

-- Discovery closes at the request's acceptance window even before a lazy
-- status flip; accepted negotiations and their meetings are unaffected.
CREATE OR REPLACE FUNCTION hocalist.marketplace_request(p_request uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_owner uuid;
  v_status text;
  v_expires timestamptz;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  SELECT buyer_user_id, status, acceptance_expires_at
    INTO v_owner, v_status, v_expires
    FROM hocalist.requests WHERE id = p_request;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found' USING ERRCODE='P0002';
  END IF;
  IF v_owner = v_user THEN
    RETURN hocalist.marketplace_request_json(p_request);
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = v_user AND role = 'seller' AND status = 'active')
     AND v_status = 'active'
     AND (v_expires IS NULL OR now() < v_expires) THEN
    RETURN hocalist.marketplace_lead_json(p_request);
  END IF;
  RAISE EXCEPTION 'request_access_denied' USING ERRCODE='42501';
END; $$;

CREATE OR REPLACE FUNCTION hocalist.marketplace_seller_leads(
  p_kind text DEFAULT NULL,
  p_category uuid DEFAULT NULL,
  p_area text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_cursor text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_size integer;
  v_cursor_micros bigint;
  v_cursor_id uuid;
  v_items jsonb;
  v_next text;
  v_last_micros bigint;
  v_last_id uuid;
BEGIN
  PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
  IF p_kind IS NOT NULL AND p_kind NOT IN ('product','service') THEN
    RAISE EXCEPTION 'invalid_field: kind' USING ERRCODE='22023';
  END IF;
  IF p_area IS NOT NULL AND length(btrim(p_area)) NOT BETWEEN 1 AND 150 THEN
    RAISE EXCEPTION 'invalid_field: area' USING ERRCODE='22023';
  END IF;
  v_size := greatest(1, least(coalesce(p_limit, 50), 100));
  IF p_cursor IS NOT NULL THEN
    BEGIN
      v_cursor_micros := split_part(p_cursor, '|', 1)::bigint;
      v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023';
    END;
  END IF;
  SELECT coalesce(jsonb_agg(row_json ORDER BY row_micros DESC, row_id DESC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT r.id AS row_id,
           (extract(epoch FROM r.created_at) * 1000000)::bigint AS row_micros,
           hocalist.marketplace_lead_json(r.id) AS row_json
    FROM hocalist.requests r
    LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = r.buyer_profile_id
    WHERE r.status = 'active'
      AND (r.acceptance_expires_at IS NULL OR now() < r.acceptance_expires_at)
      AND r.buyer_user_id <> v_user
      AND (p_kind IS NULL OR r.kind = p_kind)
      AND (p_category IS NULL OR r.category_id = p_category)
      AND (p_area IS NULL OR rp.area_label ILIKE '%' || btrim(p_area) || '%'
           OR r.city ILIKE '%' || btrim(p_area) || '%'
           OR r.region ILIKE '%' || btrim(p_area) || '%')
      AND (p_cursor IS NULL OR
           ((extract(epoch FROM r.created_at) * 1000000)::bigint, r.id) < (v_cursor_micros, v_cursor_id))
    ORDER BY r.created_at DESC, r.id DESC
    LIMIT v_size
  ) rows;
  v_next := NULL;
  IF jsonb_array_length(v_items) = v_size THEN
    SELECT (extract(epoch FROM r.created_at) * 1000000)::bigint, r.id
      INTO v_last_micros, v_last_id
      FROM hocalist.requests r WHERE r.id = (v_items->-1->>'request_id')::uuid;
    IF EXISTS (
      SELECT 1 FROM hocalist.requests r
      LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = r.buyer_profile_id
      WHERE r.status = 'active'
        AND (r.acceptance_expires_at IS NULL OR now() < r.acceptance_expires_at)
        AND r.buyer_user_id <> v_user
        AND (p_kind IS NULL OR r.kind = p_kind)
        AND (p_category IS NULL OR r.category_id = p_category)
        AND (p_area IS NULL OR rp.area_label ILIKE '%' || btrim(p_area) || '%'
             OR r.city ILIKE '%' || btrim(p_area) || '%'
             OR r.region ILIKE '%' || btrim(p_area) || '%')
        AND ((extract(epoch FROM r.created_at) * 1000000)::bigint, r.id) < (v_last_micros, v_last_id)
    ) THEN
      v_next := v_last_micros::text || '|' || v_last_id::text;
    END IF;
  END IF;
  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

-- ---------------------------------------------------------------------------
-- Command surface: multiple acceptances, countdown, purchase designation
-- ---------------------------------------------------------------------------

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
      place_label, place_address, place_id, proposed_by_user_id)
    VALUES (
      v_id, 1,
      (v_norm->>'price_minor')::bigint, v_norm->>'currency_code', v_norm->>'message',
      v_norm->'image_media_ids',
      (v_norm->>'schedule_date')::date, (v_norm->>'schedule_time')::time,
      v_norm->>'schedule_timezone', v_norm->>'schedule_occurrence',
      (v_norm->>'schedule_offset_minutes')::integer,
      (v_norm->>'schedule_instant')::timestamptz, v_norm->>'place_choice',
      v_norm->>'place_label', v_norm->>'place_address', v_norm->>'place_id', v_user);
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
      place_label, place_address, place_id, proposed_by_user_id)
    VALUES (
      v_id, v_sequence,
      (v_norm->>'price_minor')::bigint, v_norm->>'currency_code', v_norm->>'message',
      v_norm->'image_media_ids',
      (v_norm->>'schedule_date')::date, (v_norm->>'schedule_time')::time,
      v_norm->>'schedule_timezone', v_norm->>'schedule_occurrence',
      (v_norm->>'schedule_offset_minutes')::integer,
      (v_norm->>'schedule_instant')::timestamptz, v_norm->>'place_choice',
      v_norm->>'place_label', v_norm->>'place_address', v_norm->>'place_id', v_user);
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

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION hocalist.marketplace_weekly_target_limit(uuid),
  hocalist.marketplace_request_json(uuid), hocalist.marketplace_lead_json(uuid),
  hocalist.marketplace_offer_json(uuid), hocalist.marketplace_request(uuid),
  hocalist.marketplace_seller_leads(text,uuid,text,integer,text),
  hocalist.marketplace_command(text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.marketplace_request(uuid),
  hocalist.marketplace_seller_leads(text,uuid,text,integer,text),
  hocalist.marketplace_command(text,text,jsonb) TO authenticated;

-- Additive migration over reviewed 080: the buyer designates one final purchase
-- seller, only that seller can complete the PIN, a confirmed purchase closes
-- every other negotiation for the request, and the winning credit/reward
-- settlement runs through the optional commercial hooks.
--
-- Prerequisites: meetings 040 + outcomes 080 + marketplace 023 already applied.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.sale_confirmations') IS NULL THEN
    RAISE EXCEPTION 'sale confirmation 080 prerequisite missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist' AND table_name='requests' AND column_name='purchase_offer_id'
  ) THEN
    RAISE EXCEPTION 'marketplace multi-negotiation 023 prerequisite missing';
  END IF;
END; $guard$;

CREATE OR REPLACE FUNCTION hocalist.sale_pin(p_meeting uuid,p_action text,p_pin text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); m hocalist.meetings%ROWTYPE;
 s hocalist.request_pin_secrets%ROWTYPE; outcome hocalist.sale_confirmations%ROWTYPE;
 v_purchase uuid;
BEGIN
 m:=hocalist.meeting_assert_participant(p_meeting,u);
 IF p_action NOT IN ('display','verify','status') OR p_action IS NULL THEN
  RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023';
 END IF;
 IF (p_action='display' AND u<>m.buyer_user_id) OR (p_action='verify' AND u<>m.seller_user_id) THEN
  RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501';
 END IF;
 -- Match marketplace lock order; serialize all sellers for the request.
 PERFORM 1 FROM hocalist.requests WHERE id=m.request_id FOR UPDATE;
 PERFORM 1 FROM hocalist.meetings WHERE id=p_meeting FOR UPDATE;
 m:=hocalist.meeting_assert_participant(p_meeting,u);
 SELECT * INTO outcome FROM hocalist.sale_confirmations WHERE request_id=m.request_id;
 IF FOUND THEN
  IF outcome.meeting_id<>p_meeting THEN RETURN jsonb_build_object('status','completed_elsewhere'); END IF;
  RETURN jsonb_build_object('status','confirmed','outcome_id',outcome.id,'confirmed_at',outcome.confirmed_at);
 END IF;
 IF p_action='status' THEN RETURN jsonb_build_object('status','unconfirmed'); END IF;
 IF m.status<>'accepted' OR m.accepted_revision_id IS NULL THEN
  RETURN jsonb_build_object('status','meeting_not_accepted');
 END IF;
 IF m.meeting_expires_at IS NULL OR now()>=m.meeting_expires_at THEN
  RETURN jsonb_build_object('status','expired');
 END IF;
 IF p_action='display' THEN
  INSERT INTO hocalist.request_pin_secrets(request_id,meeting_id,schedule_revision_id)
   VALUES(m.request_id,m.id,m.accepted_revision_id)
   ON CONFLICT(request_id) DO UPDATE SET meeting_id=excluded.meeting_id,
    schedule_revision_id=excluded.schedule_revision_id,secret=gen_random_uuid()
   WHERE request_pin_secrets.meeting_id<>excluded.meeting_id
      OR request_pin_secrets.schedule_revision_id<>excluded.schedule_revision_id;
  SELECT * INTO s FROM hocalist.request_pin_secrets WHERE request_id=m.request_id;
  RETURN jsonb_build_object('status','ready','pin',hocalist.sale_pin_digits(s.secret),'expires_at',m.meeting_expires_at);
 END IF;
 -- Only the seller the buyer designated as the final purchase may complete the
 -- transaction. A different accepted negotiation cannot claim the sale.
 SELECT purchase_offer_id INTO v_purchase FROM hocalist.requests WHERE id=m.request_id;
 IF v_purchase IS NULL OR v_purchase<>m.offer_id THEN
  RETURN jsonb_build_object('status','purchase_seller_required');
 END IF;
 SELECT * INTO s FROM hocalist.request_pin_secrets WHERE request_id=m.request_id FOR UPDATE;
 IF NOT FOUND OR s.meeting_id<>m.id OR s.schedule_revision_id<>m.accepted_revision_id THEN
  RETURN jsonb_build_object('status','buyer_must_open_pin');
 END IF;
 IF s.attempts>=30 THEN RETURN jsonb_build_object('status','support_required'); END IF;
 IF s.locked_until>now() THEN RETURN jsonb_build_object('status','locked','retry_at',s.locked_until); END IF;
 IF p_pin IS NULL OR p_pin!~'^[0-9]{5}$' THEN RETURN jsonb_build_object('status','invalid_format'); END IF;
 IF s.locked_until IS NOT NULL THEN s.window_attempts:=0; END IF;
 IF p_pin<>hocalist.sale_pin_digits(s.secret) THEN
  UPDATE hocalist.request_pin_secrets SET attempts=attempts+1,
   window_attempts=s.window_attempts+1,
   locked_until=CASE WHEN s.window_attempts+1>=5 THEN now()+interval '15 minutes' ELSE NULL END
   WHERE request_id=m.request_id;
  -- A returned failure, not an exception: failed attempts must COMMIT.
  RETURN jsonb_build_object('status',CASE WHEN s.window_attempts+1>=5 THEN 'locked' ELSE 'incorrect' END);
 END IF;
 INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id)
  VALUES(m.request_id,m.id,m.offer_id,m.accepted_revision_id,m.buyer_user_id,m.seller_user_id) RETURNING * INTO outcome;
 -- One purchase per request: the winning negotiation completes, every other
 -- negotiation for this request closes with its conversation history intact.
 UPDATE hocalist.offers SET status='completed',revision=revision+1,updated_at=now()
  WHERE id=m.offer_id;
 UPDATE hocalist.offers SET status='declined',revision=revision+1,updated_at=now()
  WHERE request_id=m.request_id AND id<>m.offer_id AND status IN ('submitted','selected');
 UPDATE hocalist.meetings SET status='cancelled',revision=revision+1,updated_at=now()
  WHERE request_id=m.request_id AND id<>m.id AND status<>'cancelled';
 UPDATE hocalist.requests SET status='closed',revision=revision+1,updated_at=now() WHERE id=m.request_id;
 DELETE FROM hocalist.request_pin_secrets WHERE request_id=m.request_id;
 -- Winning fee difference and unused-reserve release. The helper is optional so
 -- the local foundation remains testable before the commercial module applies.
 IF to_regprocedure('hocalist.credit_settle_purchase(uuid)') IS NOT NULL THEN
  PERFORM hocalist.credit_settle_purchase(m.request_id);
 END IF;
 RETURN jsonb_build_object('status','confirmed','outcome_id',outcome.id,'confirmed_at',outcome.confirmed_at);
END $$;

REVOKE ALL ON FUNCTION hocalist.sale_pin(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.sale_pin(uuid,text,text) TO authenticated;

-- The meeting projection carries the buyer's final-purchase designation so
-- both sides can see who can complete the PIN.
CREATE OR REPLACE FUNCTION hocalist.meeting_json(p_meeting uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', m.id,
    'conversation_id', m.conversation_id,
    'request_id', m.request_id,
    'offer_id', m.offer_id,
    'buyer_user_id', m.buyer_user_id,
    'seller_user_id', m.seller_user_id,
    'status', m.status,
    'accepted_revision_id', m.accepted_revision_id,
    'meeting_expires_at', m.meeting_expires_at,
    'purchase_selected', q.purchase_offer_id = m.offer_id,
    'purchase_selected_at', q.purchase_selected_at,
    'revision', m.revision,
    'created_at', m.created_at,
    'updated_at', m.updated_at,
    -- Authorized summary tied to the offer revision the buyer accepted at
    -- selection time. It never substitutes a newer offer revision and stays
    -- null when the offer has no accepted revision.
    'offer_summary', (
      SELECT jsonb_build_object(
        'title', r.title,
        'price_minor', ar.price_minor,
        'currency_code', ar.currency_code,
        'revision_id', ar.id)
      FROM hocalist.offers o
      JOIN hocalist.offer_revisions ar ON ar.id = o.accepted_revision_id
      JOIN hocalist.requests r ON r.id = o.request_id
      WHERE o.id = m.offer_id
    ),
    'accepted_schedule', (
      SELECT hocalist.meeting_revision_json(r)
      FROM hocalist.meeting_schedule_revisions r
      WHERE r.id = m.accepted_revision_id
    ),
    'pending_schedule', (
      SELECT hocalist.meeting_revision_json(r)
      FROM hocalist.meeting_schedule_revisions r
      WHERE r.meeting_id = m.id AND r.status = 'proposed'
      ORDER BY r.sequence DESC LIMIT 1
    ),
    'revisions', coalesce((
      SELECT jsonb_agg(hocalist.meeting_revision_json(r) ORDER BY r.sequence)
      FROM hocalist.meeting_schedule_revisions r WHERE r.meeting_id = m.id
    ), '[]'::jsonb)
  )
  FROM hocalist.meetings m
  JOIN hocalist.requests q ON q.id = m.request_id
  WHERE m.id = p_meeting;
$$;
REVOKE ALL ON FUNCTION hocalist.meeting_json(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Additive commercial settlement over the reviewed 090/091 foundation.
--
-- Implements the September 26 approved credit rules with batch-owned pricing:
--   * the subscription/plan determines weekly targeting capacity only;
--   * every deposit batch keeps ITS immutable initial/winning rates;
--   * before permitting a targeting interaction, reserve the full possible
--     winning fee from the oldest single batch that can cover its own winning
--     fee, and copy that batch's rates/version into the reservation;
--   * later deposits, plan changes or admin deposit-option edits never reprice
--     an existing batch or an existing reservation;
--   * charge the initial fee once both parties have sent a qualifying message,
--     and only the remaining winning difference on a PIN-confirmed purchase;
--   * release the unused reservation for non-winners, or the entire
--     reservation when no qualifying interaction occurred;
--   * an absent paid configuration is an explicit error: a chargeable action
--     is never acknowledged without its required reservation.
--
-- No fee rate is invented here. New batches are created only by the reviewed
-- provider path (`credit_deposit_internal`), which snapshots the rates of an
-- admin-managed deposit option after a confirmed payment.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.credit_targets') IS NULL THEN
    RAISE EXCEPTION 'credit batches 090 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.marketplace_plan_limits') IS NULL THEN
    RAISE EXCEPTION 'marketplace 020 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.marketplace_weekly_target_limit(uuid)') IS NULL THEN
    RAISE EXCEPTION 'marketplace weekly capacity 023 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.credit_deposit_options') IS NOT NULL THEN
    RAISE EXCEPTION 'credit settlement already installed';
  END IF;
END; $guard$;

-- ---------------------------------------------------------------------------
-- Admin-managed deposit and reward configuration
-- ---------------------------------------------------------------------------

-- A deposit option is the admin-managed 1:1 amount plus the fee rates that a
-- confirmed payment of that amount will freeze into one new batch. No option is
-- seeded: an empty table means credit deposits are not purchasable yet, and a
-- targeting attempt reports that explicitly instead of proceeding free.
CREATE TABLE hocalist.credit_deposit_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  amount_minor bigint NOT NULL UNIQUE CHECK (amount_minor > 0),
  initial_fee_minor bigint NOT NULL CHECK (initial_fee_minor >= 0),
  winning_total_minor bigint NOT NULL
    CHECK (winning_total_minor >= initial_fee_minor AND winning_total_minor <= amount_minor),
  rate_version text NOT NULL CHECK (length(btrim(rate_version)) BETWEEN 1 AND 100),
  active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Buyer reward rates remain a separate ledger from seller credits. The late
-- window is optional; when unconfigured the normal rate applies and no
-- undocumented late-window shortcut is inferred. An absent policy is visible
-- to the app as `reward_policy_configured: false`; it never blocks a sale.
CREATE TABLE hocalist.reward_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  normal_minor bigint NOT NULL CHECK (normal_minor > 0),
  late_minor bigint NOT NULL CHECK (late_minor >= normal_minor),
  late_window_hours integer CHECK (late_window_hours IS NULL OR late_window_hours BETWEEN 1 AND 168),
  rule_version text NOT NULL CHECK (length(btrim(rule_version)) BETWEEN 1 AND 100),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE hocalist.credit_targets
  ADD COLUMN offer_id uuid REFERENCES hocalist.offers(id),
  ADD COLUMN qualified_at timestamptz,
  ADD COLUMN rate_version text
    CHECK (rate_version IS NULL OR length(btrim(rate_version)) BETWEEN 1 AND 100);
-- Append-only history: one live target per seller/request, but a withdrawn and
-- re-submitted negotiation may append a new target after the old one closes.
ALTER TABLE hocalist.credit_targets DROP CONSTRAINT credit_targets_user_id_request_id_key;
CREATE UNIQUE INDEX credit_targets_live
  ON hocalist.credit_targets(user_id, request_id)
  WHERE status IN ('reserved','initial_charged','won');

ALTER TABLE hocalist.credit_deposit_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.reward_policy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.credit_deposit_options, hocalist.reward_policy
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Targeted-fee reservation (batch-owned pricing)
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS hocalist.credit_reserve_internal(uuid,uuid,date,integer);

-- Reserves the full winning fee of ONE selected batch. Only batches whose
-- remaining spendable amount covers their own winning_total_minor are
-- eligible; the oldest eligible batch wins. Its initial fee, winning total and
-- rate version are copied onto the target, so a later deposit, plan change or
-- admin edit cannot reprice this reservation.
CREATE FUNCTION hocalist.credit_reserve_internal(
  p_user uuid, p_request uuid, p_offer uuid, p_week date, p_limit integer
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  b hocalist.credit_batches%ROWTYPE;
  t hocalist.credit_targets%ROWTYPE;
  o hocalist.offers%ROWTYPE;
BEGIN
  IF p_week IS NULL OR p_limit IS NULL OR p_limit < 1 THEN
    RAISE EXCEPTION 'invalid_reservation' USING ERRCODE='22023';
  END IF;
  SELECT * INTO o FROM hocalist.offers WHERE id=p_offer AND request_id=p_request;
  IF NOT FOUND OR o.seller_user_id<>p_user THEN
    RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
  END IF;
  -- Same seller lock across quota check, batch selection and all mutations.
  PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
  SELECT * INTO t FROM hocalist.credit_targets
    WHERE user_id=p_user AND request_id=p_request
      AND status IN ('reserved','initial_charged','won');
  IF FOUND THEN RETURN t.id; END IF;
  IF (SELECT count(*) FROM hocalist.credit_targets WHERE user_id=p_user AND week_start=p_week) >= p_limit THEN
    RAISE EXCEPTION 'weekly_target_limit' USING ERRCODE='P0001';
  END IF;
  SELECT * INTO b FROM hocalist.credit_batches
    WHERE user_id=p_user AND balance_minor-reserved_minor >= winning_total_minor
    ORDER BY created_at,id LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN
    -- Distinguish "buy more credits" from "the platform cannot sell credits":
    -- an absent paid configuration is an explicit error, never free targeting.
    IF EXISTS (SELECT 1 FROM hocalist.credit_deposit_options WHERE active) THEN
      RAISE EXCEPTION 'insufficient_single_batch' USING ERRCODE='P0001';
    END IF;
    RAISE EXCEPTION 'targeting_fee_unconfigured' USING ERRCODE='P0001';
  END IF;
  INSERT INTO hocalist.credit_targets(
    user_id,request_id,batch_id,offer_id,initial_minor,winning_minor,reserved_minor,week_start,rate_version)
  VALUES (p_user,p_request,b.id,p_offer,
    b.initial_fee_minor,b.winning_total_minor,b.winning_total_minor,p_week,b.rate_version)
  RETURNING * INTO t;
  UPDATE hocalist.credit_batches SET reserved_minor=reserved_minor+t.winning_minor WHERE id=b.id;
  INSERT INTO hocalist.credit_entries(batch_id,target_id,kind,amount_minor,reserve_delta_minor)
    VALUES(b.id,t.id,'reserve',0,t.winning_minor);
  RETURN t.id;
END $$;

-- Called by the marketplace command before the offer is acknowledged. Resolves
-- weekly capacity from the plan and pricing from the batch. It raises
-- `targeting_fee_unconfigured` when no deposit option exists and no eligible
-- batch can fund the action, so a chargeable interaction is never silently
-- free.
CREATE FUNCTION hocalist.credit_authorize_target(p_user uuid, p_request uuid, p_offer uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_week date := date_trunc('week', now() AT TIME ZONE 'UTC')::date;
  v_limit integer;
  v_id uuid;
  t hocalist.credit_targets%ROWTYPE;
  b hocalist.credit_batches%ROWTYPE;
BEGIN
  v_limit := coalesce(hocalist.marketplace_weekly_target_limit(p_user), 0);
  IF v_limit < 1 THEN
    RAISE EXCEPTION 'weekly_target_limit' USING ERRCODE='P0001';
  END IF;
  v_id := hocalist.credit_reserve_internal(p_user, p_request, p_offer, v_week, v_limit);
  SELECT * INTO t FROM hocalist.credit_targets WHERE id=v_id;
  SELECT * INTO b FROM hocalist.credit_batches WHERE id=t.batch_id;
  RETURN jsonb_build_object('status','reserved','target_id',t.id,'batch_id',b.id,
    'initial_fee_minor',t.initial_minor,'winning_total_minor',t.winning_minor,
    'rate_version',t.rate_version);
END $$;

-- ---------------------------------------------------------------------------
-- Qualification, release and purchase settlement
-- ---------------------------------------------------------------------------

-- A qualifying interaction is at least one buyer message and one seller
-- message in the negotiation conversation. System notices never qualify.
CREATE FUNCTION hocalist.credit_qualify_conversation(p_conversation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  o hocalist.offers%ROWTYPE;
  t hocalist.credit_targets%ROWTYPE;
BEGIN
  SELECT x.* INTO o FROM hocalist.conversations c
    JOIN hocalist.offers x ON x.id = c.offer_id
    WHERE c.id = p_conversation AND c.origin = 'targeted_request';
  IF NOT FOUND THEN RETURN jsonb_build_object('status','no_target'); END IF;
  PERFORM 1 FROM hocalist.profiles WHERE id=o.seller_user_id FOR UPDATE;
  SELECT * INTO t FROM hocalist.credit_targets
    WHERE offer_id = o.id AND user_id = o.seller_user_id
      AND status IN ('reserved','initial_charged','won') FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','no_target'); END IF;
  IF t.status <> 'reserved' THEN
    RETURN jsonb_build_object('status',t.status,'target_id',t.id);
  END IF;
  IF NOT (EXISTS (
        SELECT 1 FROM hocalist.conversation_messages m
        WHERE m.conversation_id=p_conversation AND m.sender_user_id=o.buyer_user_id
          AND m.kind IN ('text','attachment'))
      AND EXISTS (
        SELECT 1 FROM hocalist.conversation_messages m
        WHERE m.conversation_id=p_conversation AND m.sender_user_id=o.seller_user_id
          AND m.kind IN ('text','attachment'))) THEN
    RETURN jsonb_build_object('status','awaiting_qualification');
  END IF;
  PERFORM hocalist.credit_settle_internal(t.id,'initial');
  UPDATE hocalist.credit_targets SET qualified_at=now() WHERE id=t.id;
  RETURN jsonb_build_object('status','initial_charged','target_id',t.id);
END $$;

-- Releases the live reservation for one withdrawn or closed negotiation.
CREATE FUNCTION hocalist.credit_release_offer(p_offer uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t hocalist.credit_targets%ROWTYPE;
BEGIN
  SELECT * INTO t FROM hocalist.credit_targets
    WHERE offer_id=p_offer AND status IN ('reserved','initial_charged') FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','no_target'); END IF;
  PERFORM 1 FROM hocalist.profiles WHERE id=t.user_id FOR UPDATE;
  PERFORM hocalist.credit_settle_internal(t.id,'release');
  RETURN jsonb_build_object('status','released','target_id',t.id);
END $$;

-- Purchase settlement. The winning seller keeps the full winning fee from its
-- own batch (only the remaining difference is charged when the initial fee was
-- already collected); every other negotiation releases its unused reservation,
-- keeping an already charged initial/losing fee. Buyer reward accrual is a
-- separate ledger and only happens when a configured reward policy exists and
-- the winning fee was actually collected.
CREATE FUNCTION hocalist.credit_settle_purchase(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_outcome hocalist.sale_confirmations%ROWTYPE;
  v_request hocalist.requests%ROWTYPE;
  t hocalist.credit_targets%ROWTYPE;
  v_win hocalist.credit_targets%ROWTYPE;
  rp hocalist.reward_policy%ROWTYPE;
  v_amount bigint;
  v_rule text;
  v_won boolean := false;
  v_released integer := 0;
BEGIN
  IF to_regclass('hocalist.sale_confirmations') IS NULL THEN
    RAISE EXCEPTION 'sale confirmation prerequisite missing';
  END IF;
  SELECT * INTO STRICT v_outcome FROM hocalist.sale_confirmations WHERE request_id=p_request;
  SELECT * INTO v_request FROM hocalist.requests WHERE id=p_request;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found' USING ERRCODE='P0002'; END IF;

  SELECT * INTO v_win FROM hocalist.credit_targets
    WHERE user_id=v_outcome.seller_user_id AND request_id=p_request
      AND status IN ('reserved','initial_charged','won');
  IF FOUND THEN
    PERFORM 1 FROM hocalist.profiles WHERE id=v_win.user_id FOR UPDATE;
    SELECT * INTO v_win FROM hocalist.credit_targets WHERE id=v_win.id FOR UPDATE;
    IF v_win.status IN ('reserved','initial_charged') THEN
      PERFORM hocalist.credit_settle_internal(v_win.id,'win');
      SELECT * INTO v_win FROM hocalist.credit_targets WHERE id=v_win.id;
    END IF;
    v_won := v_win.status='won';
  END IF;

  FOR t IN SELECT * FROM hocalist.credit_targets
           WHERE request_id=p_request AND user_id<>v_outcome.seller_user_id
             AND status IN ('reserved','initial_charged')
           ORDER BY user_id LOOP
    PERFORM 1 FROM hocalist.profiles WHERE id=t.user_id FOR UPDATE;
    PERFORM hocalist.credit_settle_internal(t.id,'release');
    v_released := v_released + 1;
  END LOOP;

  IF v_won AND to_regprocedure('hocalist.reward_accrue_internal(uuid,uuid,bigint,text)') IS NOT NULL THEN
    SELECT * INTO rp FROM hocalist.reward_policy WHERE singleton;
    IF FOUND THEN
      v_amount := rp.normal_minor;
      v_rule := rp.rule_version;
      IF rp.late_window_hours IS NOT NULL
         AND v_request.acceptance_expires_at IS NOT NULL
         AND EXISTS (
           SELECT 1 FROM hocalist.offers o
           WHERE o.id = v_outcome.offer_id
             AND o.created_at >= v_request.acceptance_expires_at - make_interval(hours => rp.late_window_hours)) THEN
        v_amount := rp.late_minor;
        v_rule := rp.rule_version || ':late';
      END IF;
      PERFORM hocalist.reward_accrue_internal(v_outcome.id, v_win.id, v_amount, v_rule);
    END IF;
  END IF;

  RETURN jsonb_build_object('winning_target',v_win.id,'won',v_won,'released',v_released);
END $$;

-- Releases live reservations whose negotiation ended without a winning
-- purchase. A request that merely passed its discovery window keeps its
-- reservation while an accepted meeting is still valid, and while a pending
-- proposal can still be accepted for an already accepted negotiation. Only the
-- caller's own targets are ever touched; this is not a global job.
CREATE FUNCTION hocalist.credit_reconcile_internal(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  t hocalist.credit_targets%ROWTYPE;
  o hocalist.offers%ROWTYPE;
  r hocalist.requests%ROWTYPE;
  v_closed boolean;
  v_expired boolean;
  v_released integer := 0;
BEGIN
  IF p_user IS NULL THEN RAISE EXCEPTION 'invalid_user' USING ERRCODE='22023'; END IF;
  FOR t IN SELECT * FROM hocalist.credit_targets
           WHERE user_id=p_user AND status IN ('reserved','initial_charged')
           ORDER BY created_at,id LOOP
    IF t.offer_id IS NULL THEN CONTINUE; END IF;
    SELECT * INTO o FROM hocalist.offers WHERE id=t.offer_id;
    SELECT * INTO r FROM hocalist.requests WHERE id=t.request_id;
    IF o.id IS NULL OR r.id IS NULL THEN CONTINUE; END IF;
    v_closed := o.status IN ('withdrawn','declined','cancelled','expired','completed')
      OR r.status IN ('closed','cancelled');
    v_expired := r.acceptance_expires_at IS NOT NULL AND now() >= r.acceptance_expires_at;
    IF NOT (v_closed OR v_expired) THEN CONTINUE; END IF;
    IF to_regclass('hocalist.meetings') IS NOT NULL AND EXISTS (
      SELECT 1 FROM hocalist.meetings m
      WHERE m.offer_id=t.offer_id
        AND m.status IN ('accepted','reschedule_proposed')
        AND m.meeting_expires_at IS NOT NULL AND now() < m.meeting_expires_at) THEN
      CONTINUE;
    END IF;
    IF NOT v_closed AND to_regclass('hocalist.meetings') IS NOT NULL AND EXISTS (
      SELECT 1 FROM hocalist.meetings m
      WHERE m.offer_id=t.offer_id AND m.status='proposed') THEN
      -- Discovery closed but the accepted negotiation may still confirm a
      -- meeting; the reservation stays until that proposal resolves.
      CONTINUE;
    END IF;
    PERFORM 1 FROM hocalist.profiles WHERE id=t.user_id FOR UPDATE;
    PERFORM hocalist.credit_settle_internal(t.id,'release');
    v_released := v_released + 1;
  END LOOP;
  RETURN jsonb_build_object('released',v_released);
END $$;

-- ---------------------------------------------------------------------------
-- Wallet projection
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION hocalist.credit_wallet() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid:=auth.uid();
  v_week date := date_trunc('week', now() AT TIME ZONE 'UTC')::date;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='seller' AND status='active')
   OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
   RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE='42501'; END IF;
  -- Reconciliation only releases this caller's own ended negotiations; it is
  -- idempotent and never settles a live accepted meeting.
  PERFORM hocalist.credit_reconcile_internal(u);
  RETURN jsonb_build_object('currency','HC',
   'balance_minor',coalesce((SELECT sum(balance_minor) FROM hocalist.credit_batches WHERE user_id=u),0),
   'reserved_minor',coalesce((SELECT sum(reserved_minor) FROM hocalist.credit_batches WHERE user_id=u),0),
   'weekly',jsonb_build_object(
     'used',(SELECT count(*) FROM hocalist.credit_targets WHERE user_id=u AND week_start=v_week),
     'limit',hocalist.marketplace_weekly_target_limit(u)),
   'deposit_options',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',id,'amount_minor',amount_minor,'initial_fee_minor',initial_fee_minor,
      'winning_total_minor',winning_total_minor,'rate_version',rate_version,
      'active',active,'revision',revision,'sort_order',sort_order)
      ORDER BY sort_order,amount_minor) FROM hocalist.credit_deposit_options WHERE active),'[]'::jsonb),
   'batches',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'original_minor',original_minor,'balance_minor',balance_minor,
    'reserved_minor',reserved_minor,'initial_fee_minor',initial_fee_minor,'winning_total_minor',winning_total_minor,
    'rate_version',rate_version,'created_at',created_at) ORDER BY created_at,id)
    FROM hocalist.credit_batches WHERE user_id=u),'[]'::jsonb));
END $$;

-- Reward configuration is reported explicitly so an absent rate is visible
-- instead of silently accruing nothing.
CREATE OR REPLACE FUNCTION hocalist.reward_wallet() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); p hocalist.reward_policy%ROWTYPE;
BEGIN
 IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='buyer' AND status='active')
  OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO p FROM hocalist.reward_policy WHERE singleton;
 RETURN jsonb_build_object('currency','USD','withdrawals_enabled',false,
  'reward_policy_configured',FOUND,
  'earned_minor',coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r
    JOIN hocalist.credit_targets t ON t.id=r.target_id
    WHERE r.buyer_user_id=u AND t.status='won'),0),
  'items',coalesce((SELECT jsonb_agg(x.data ORDER BY x.created_at DESC,x.id DESC) FROM (
   SELECT r.id,r.created_at,jsonb_build_object('id',r.id,'amount_minor',r.amount_minor,'created_at',r.created_at,
    'status',CASE WHEN t.status='won' THEN 'earned' ELSE 'held' END) AS data
   FROM hocalist.buyer_rewards r JOIN hocalist.credit_targets t ON t.id=r.target_id
   WHERE r.buyer_user_id=u ORDER BY r.created_at DESC,r.id DESC LIMIT 50) x),'[]'::jsonb));
END $$;

-- ---------------------------------------------------------------------------
-- Admin configuration command
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.credit_admin_command(p_operation text, p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid:=auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  result jsonb;
  v_id uuid;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_operation IS NULL OR p_operation NOT IN ('deposit_option.set','deposit_option.retire','reward_policy.set')
   OR p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
   OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':credit_admin:'||p_operation||':'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id=u AND operation='credit_admin.'||p_operation AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  IF p_operation='deposit_option.set' THEN
    IF p_input - ARRAY['id','amount_minor','initial_fee_minor','winning_total_minor','rate_version','active','sort_order','expected_revision'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'active') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION 'invalid_option' USING ERRCODE='22023';
    END IF;
    IF p_input->>'id' IS NULL THEN
      INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version,active,sort_order)
      VALUES((p_input->>'amount_minor')::bigint,(p_input->>'initial_fee_minor')::bigint,
        (p_input->>'winning_total_minor')::bigint,btrim(p_input->>'rate_version'),
        (p_input->>'active')::boolean,coalesce((p_input->>'sort_order')::integer,0))
      RETURNING id INTO v_id;
    ELSE
      UPDATE hocalist.credit_deposit_options SET
        amount_minor=(p_input->>'amount_minor')::bigint,
        initial_fee_minor=(p_input->>'initial_fee_minor')::bigint,
        winning_total_minor=(p_input->>'winning_total_minor')::bigint,
        rate_version=btrim(p_input->>'rate_version'),
        active=(p_input->>'active')::boolean,
        sort_order=coalesce((p_input->>'sort_order')::integer,0),
        revision=revision+1,updated_at=now()
      WHERE id=(p_input->>'id')::uuid
        AND (p_input->'expected_revision' IS NULL OR revision=(p_input->>'expected_revision')::bigint)
      RETURNING id INTO v_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    END IF;
    result:=jsonb_build_object('id',v_id);
  ELSIF p_operation='deposit_option.retire' THEN
    IF p_input - ARRAY['id','expected_revision'] <> '{}'::jsonb THEN
      RAISE EXCEPTION 'invalid_option' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.credit_deposit_options SET active=false,revision=revision+1,updated_at=now()
    WHERE id=(p_input->>'id')::uuid
      AND (p_input->'expected_revision' IS NULL OR revision=(p_input->>'expected_revision')::bigint)
    RETURNING id INTO v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    result:=jsonb_build_object('id',v_id,'active',false);
  ELSE
    IF p_input - ARRAY['normal_minor','late_minor','late_window_hours','rule_version','expected_revision'] <> '{}'::jsonb THEN
      RAISE EXCEPTION 'invalid_policy' USING ERRCODE='22023';
    END IF;
    INSERT INTO hocalist.reward_policy(singleton,normal_minor,late_minor,late_window_hours,rule_version)
    VALUES(true,(p_input->>'normal_minor')::bigint,(p_input->>'late_minor')::bigint,
      nullif(p_input->>'late_window_hours','')::integer,btrim(p_input->>'rule_version'))
    ON CONFLICT(singleton) DO UPDATE SET normal_minor=excluded.normal_minor,late_minor=excluded.late_minor,
      late_window_hours=excluded.late_window_hours,rule_version=excluded.rule_version,
      revision=hocalist.reward_policy.revision+1,updated_at=now()
    WHERE p_input->'expected_revision' IS NULL OR hocalist.reward_policy.revision=(p_input->>'expected_revision')::bigint;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    result:=jsonb_build_object('singleton',true);
  END IF;
  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'credit_admin.'||p_operation,p_key,h,result);
  RETURN result;
END $$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION
  hocalist.credit_reserve_internal(uuid,uuid,uuid,date,integer),
  hocalist.credit_authorize_target(uuid,uuid,uuid),
  hocalist.credit_qualify_conversation(uuid),
  hocalist.credit_release_offer(uuid),
  hocalist.credit_settle_purchase(uuid),
  hocalist.credit_reconcile_internal(uuid),
  hocalist.credit_wallet(),
  hocalist.reward_wallet(),
  hocalist.credit_admin_command(text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.credit_wallet(), hocalist.reward_wallet(),
  hocalist.credit_admin_command(text,text,jsonb) TO authenticated;

-- Provider-neutral buyer withdrawal workflow over the reviewed reward ledger.
--
-- September 26 approved terms: $20 earned-balance minimum, $2.50 deduction,
-- explicit net amount, verified email and phone, reserve while processing and
-- restore only after a confirmed failure with reconciliation that prevents a
-- double payout or refund. No provider call, credential or simulated success
-- is performed here; provider execution stays coordinator-owned.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.buyer_rewards') IS NULL THEN
    RAISE EXCEPTION 'buyer rewards 091 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.withdrawal_requests') IS NOT NULL THEN
    RAISE EXCEPTION 'withdrawals already installed';
  END IF;
END; $guard$;

-- Settled withdrawal terms are admin-managed so a later approved change does
-- not need a new migration, but the defaults are the agreed values.
CREATE TABLE hocalist.withdrawal_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  minimum_minor bigint NOT NULL CHECK (minimum_minor > 0),
  fee_minor bigint NOT NULL CHECK (fee_minor >= 0),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.withdrawal_policy(singleton,minimum_minor,fee_minor)
  VALUES (true,2000,250);

CREATE TABLE hocalist.withdrawal_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  client_key text NOT NULL CHECK (length(btrim(client_key)) BETWEEN 1 AND 128),
  amount_minor bigint NOT NULL,
  fee_minor bigint NOT NULL,
  net_minor bigint NOT NULL,
  status text NOT NULL DEFAULT 'processing'
    CHECK (status IN ('processing','failed','paid')),
  provider text CHECK (provider IS NULL OR length(btrim(provider)) BETWEEN 1 AND 60),
  provider_reference text CHECK (provider_reference IS NULL OR length(btrim(provider_reference)) BETWEEN 1 AND 200),
  failure_reason text CHECK (failure_reason IS NULL OR length(btrim(failure_reason)) BETWEEN 1 AND 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT withdrawal_net_matches CHECK (net_minor = amount_minor - fee_minor AND net_minor > 0),
  CONSTRAINT withdrawal_paid_reference CHECK (status <> 'paid' OR provider_reference IS NOT NULL),
  UNIQUE (user_id, client_key)
);
CREATE INDEX withdrawal_owner_order ON hocalist.withdrawal_requests(user_id, created_at DESC, id DESC);

-- Append-only state history. A late provider success after a recorded failure
-- stays visible for manual reconciliation instead of being silently applied.
CREATE TABLE hocalist.withdrawal_events (
  withdrawal_id uuid NOT NULL REFERENCES hocalist.withdrawal_requests(id) ON DELETE CASCADE,
  revision bigint NOT NULL CHECK (revision > 0),
  event text NOT NULL CHECK (event IN ('requested','paid','failed','reconciliation')),
  actor text NOT NULL CHECK (length(btrim(actor)) BETWEEN 1 AND 60),
  detail text CHECK (detail IS NULL OR length(detail) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (withdrawal_id, revision)
);

ALTER TABLE hocalist.withdrawal_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.withdrawal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.withdrawal_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.withdrawal_policy, hocalist.withdrawal_requests,
  hocalist.withdrawal_events FROM PUBLIC, anon, authenticated, service_role;

-- Email/phone verification is read from Auth, never from editable profile
-- text. "No Auth column" means not verified in this environment.
CREATE FUNCTION hocalist.contact_verified(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_email boolean := false;
  v_phone boolean := false;
BEGIN
  IF p_user IS NULL THEN RAISE EXCEPTION 'invalid_user' USING ERRCODE='22023'; END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='auth' AND table_name='users' AND column_name='email_confirmed_at') THEN
    EXECUTE 'SELECT email_confirmed_at IS NOT NULL FROM auth.users WHERE id=$1'
      INTO v_email USING p_user;
    v_email := coalesce(v_email,false);
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='auth' AND table_name='users' AND column_name='phone_confirmed_at') THEN
    EXECUTE 'SELECT phone_confirmed_at IS NOT NULL FROM auth.users WHERE id=$1'
      INTO v_phone USING p_user;
    v_phone := coalesce(v_phone,false);
  END IF;
  RETURN jsonb_build_object('email_verified',v_email,'phone_verified',v_phone);
END $$;

CREATE FUNCTION hocalist.withdrawal_available_minor(p_user uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT greatest(0,
    coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r
      JOIN hocalist.credit_targets t ON t.id=r.target_id
      WHERE r.buyer_user_id=p_user AND t.status='won'),0)
    - coalesce((SELECT sum(w.amount_minor) FROM hocalist.withdrawal_requests w
      WHERE w.user_id=p_user AND w.status='processing'),0));
$$;

-- Provider-neutral settlement, callable only by the reviewed service path.
-- Idempotent per outcome; a failure can never later become paid through this
-- function, and a replayed success never applies twice.
CREATE FUNCTION hocalist.withdrawal_settle_internal(
  p_withdrawal uuid, p_result text, p_provider text DEFAULT NULL,
  p_reference text DEFAULT NULL, p_reason text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE w hocalist.withdrawal_requests%ROWTYPE; n bigint;
BEGIN
  IF p_result IS NULL OR p_result NOT IN ('paid','failed') THEN
    RAISE EXCEPTION 'invalid_result' USING ERRCODE='22023';
  END IF;
  SELECT * INTO STRICT w FROM hocalist.withdrawal_requests WHERE id=p_withdrawal FOR UPDATE;
  SELECT coalesce(max(revision),0)+1 INTO n
    FROM hocalist.withdrawal_events WHERE withdrawal_id=p_withdrawal;
  IF w.status='paid' THEN
    IF p_result='paid' THEN
      RETURN jsonb_build_object('status','paid','withdrawal_id',w.id);
    END IF;
    RAISE EXCEPTION 'late_failure_after_payout' USING ERRCODE='P0001';
  END IF;
  IF w.status='failed' THEN
    IF p_result='failed' THEN
      RETURN jsonb_build_object('status','failed','withdrawal_id',w.id);
    END IF;
    -- The provider reported success after a recorded failure. Never apply a
    -- second payout silently; record it for manual reconciliation.
    INSERT INTO hocalist.withdrawal_events(withdrawal_id,revision,event,actor,detail)
    VALUES(w.id,n,'reconciliation','provider',
      left(coalesce(p_reason,'late success after failure'),500));
    UPDATE hocalist.withdrawal_requests
      SET provider=coalesce(p_provider,provider),provider_reference=coalesce(p_reference,provider_reference),
          updated_at=now()
      WHERE id=w.id;
    RETURN jsonb_build_object('status','reconciliation_required','withdrawal_id',w.id);
  END IF;
  IF p_result='failed' THEN
    UPDATE hocalist.withdrawal_requests
      SET status='failed',failure_reason=left(coalesce(p_reason,'provider failure'),500),
          provider=coalesce(p_provider,provider),updated_at=now()
      WHERE id=w.id;
    INSERT INTO hocalist.withdrawal_events(withdrawal_id,revision,event,actor,detail)
    VALUES(w.id,n,'failed','provider',left(coalesce(p_reason,'provider failure'),500));
  ELSE
    IF p_provider IS NULL OR length(btrim(p_provider)) NOT BETWEEN 1 AND 60
       OR p_reference IS NULL OR length(btrim(p_reference)) NOT BETWEEN 1 AND 200 THEN
      RAISE EXCEPTION 'invalid_provider_reference' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.withdrawal_requests
      SET status='paid',provider=p_provider,provider_reference=p_reference,failure_reason=NULL,updated_at=now()
      WHERE id=w.id;
    INSERT INTO hocalist.withdrawal_events(withdrawal_id,revision,event,actor,detail)
    VALUES(w.id,n,'paid','provider',left(p_reference,500));
  END IF;
  RETURN jsonb_build_object('status',p_result,'withdrawal_id',w.id);
END $$;

CREATE FUNCTION hocalist.withdrawal_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); p hocalist.withdrawal_policy%ROWTYPE; c jsonb;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='buyer' AND status='active')
   OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'withdrawal_access_denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO p FROM hocalist.withdrawal_policy WHERE singleton;
  c := hocalist.contact_verified(u);
  RETURN jsonb_build_object(
    'currency','USD',
    'minimum_minor',p.minimum_minor,'fee_minor',p.fee_minor,
    'earned_minor',coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r
      JOIN hocalist.credit_targets t ON t.id=r.target_id
      WHERE r.buyer_user_id=u AND t.status='won'),0),
    'processing_minor',coalesce((SELECT sum(w.amount_minor) FROM hocalist.withdrawal_requests w
      WHERE w.user_id=u AND w.status='processing'),0),
    'available_minor',hocalist.withdrawal_available_minor(u),
    'email_verified',(c->>'email_verified')::boolean,
    'phone_verified',(c->>'phone_verified')::boolean,
    'provider_neutral',true,
    'requests',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',w.id,'amount_minor',w.amount_minor,'fee_minor',w.fee_minor,'net_minor',w.net_minor,
      'status',w.status,'failure_reason',w.failure_reason,'created_at',w.created_at,'updated_at',w.updated_at)
      ORDER BY w.created_at DESC,w.id DESC) FROM hocalist.withdrawal_requests w WHERE w.user_id=u),'[]'::jsonb));
END $$;

CREATE FUNCTION hocalist.withdrawal_request(p_key text, p_amount_minor bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid:=auth.uid(); p hocalist.withdrawal_policy%ROWTYPE; c jsonb;
  h text; w hocalist.withdrawal_requests%ROWTYPE;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='buyer' AND status='active')
   OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'withdrawal_access_denied' USING ERRCODE='42501'; END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_amount_minor IS NULL OR p_amount_minor <= 0 THEN
    RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':withdrawal:'||p_key,0));
  SELECT * INTO w FROM hocalist.withdrawal_requests WHERE user_id=u AND client_key=p_key;
  IF FOUND THEN
    RETURN jsonb_build_object('status','processing','withdrawal_id',w.id,
      'amount_minor',w.amount_minor,'fee_minor',w.fee_minor,'net_minor',w.net_minor);
  END IF;
  SELECT * INTO p FROM hocalist.withdrawal_policy WHERE singleton;
  c := hocalist.contact_verified(u);
  IF NOT (c->>'email_verified')::boolean OR NOT (c->>'phone_verified')::boolean THEN
    RAISE EXCEPTION 'contact_verification_required' USING ERRCODE='P0001'; END IF;
  IF p_amount_minor < p.minimum_minor THEN
    RAISE EXCEPTION 'below_minimum' USING ERRCODE='P0001'; END IF;
  IF p_amount_minor > hocalist.withdrawal_available_minor(u) THEN
    RAISE EXCEPTION 'insufficient_earned_balance' USING ERRCODE='P0001'; END IF;
  INSERT INTO hocalist.withdrawal_requests(user_id,client_key,amount_minor,fee_minor,net_minor)
  VALUES(u,btrim(p_key),p_amount_minor,p.fee_minor,p_amount_minor-p.fee_minor)
  RETURNING * INTO w;
  INSERT INTO hocalist.withdrawal_events(withdrawal_id,revision,event,actor,detail)
  VALUES(w.id,1,'requested','user','net '||w.net_minor::text);
  RETURN jsonb_build_object('status','processing','withdrawal_id',w.id,
    'amount_minor',w.amount_minor,'fee_minor',w.fee_minor,'net_minor',w.net_minor);
END $$;

-- Admin read-only queue; settlement stays with the provider-owned service path.
CREATE FUNCTION hocalist.admin_withdrawal_queue(p_limit integer DEFAULT 50, p_cursor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); rows jsonb; next_id uuid;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023'; END IF;
  WITH found AS (
    SELECT w.*,coalesce(rp.display_name,'Hocalist member') AS display_name
    FROM hocalist.withdrawal_requests w
    LEFT JOIN hocalist.memberships m ON m.user_id=w.user_id AND m.role='buyer'
    LEFT JOIN hocalist.role_profiles rp ON rp.membership_id=m.id
    WHERE p_cursor IS NULL OR w.id>p_cursor ORDER BY w.id LIMIT p_limit+1),
  page AS(SELECT * FROM found ORDER BY id LIMIT p_limit)
  SELECT coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'user_id',user_id,'display_name',display_name,
    'amount_minor',amount_minor,'fee_minor',fee_minor,'net_minor',net_minor,'status',status,
    'provider',provider,'provider_reference',provider_reference,'failure_reason',failure_reason,
    'created_at',created_at,'updated_at',updated_at) ORDER BY id) FROM page),'[]'::jsonb),
   CASE WHEN (SELECT count(*) FROM found)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
   INTO rows,next_id;
  RETURN jsonb_build_object('items',rows,'next_cursor',next_id,
    'processing_minor',coalesce((SELECT sum(amount_minor) FROM hocalist.withdrawal_requests WHERE status='processing'),0));
END $$;

REVOKE ALL ON FUNCTION hocalist.contact_verified(uuid),hocalist.withdrawal_available_minor(uuid),
  hocalist.withdrawal_settle_internal(uuid,text,text,text,text),
  hocalist.withdrawal_status(),hocalist.withdrawal_request(text,bigint),
  hocalist.admin_withdrawal_queue(integer,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.withdrawal_status(),hocalist.withdrawal_request(text,bigint),
  hocalist.admin_withdrawal_queue(integer,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.withdrawal_settle_internal(uuid,text,text,text,text) TO service_role;

-- Additive qualification hook: a committed message insert checks whether both
-- parties have now sent a qualifying message in a targeted-request negotiation,
-- which charges the initial HocaCredit fee once. The credit helper is resolved
-- dynamically so the chat foundation keeps working without the commercial
-- module applied.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.conversation_messages') IS NULL THEN
    RAISE EXCEPTION 'chat foundation 010 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.conversation_credit_hook') IS NOT NULL THEN
    RAISE EXCEPTION 'credit qualification hook already installed';
  END IF;
END; $guard$;

CREATE TABLE hocalist.conversation_credit_hook (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  installed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.conversation_credit_hook(singleton) VALUES (true);
ALTER TABLE hocalist.conversation_credit_hook ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION hocalist.chat_message_credit_qualify() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF to_regprocedure('hocalist.credit_qualify_conversation(uuid)') IS NOT NULL THEN
    PERFORM hocalist.credit_qualify_conversation(NEW.conversation_id);
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER chat_message_credit_qualify
  AFTER INSERT ON hocalist.conversation_messages
  FOR EACH ROW EXECUTE FUNCTION hocalist.chat_message_credit_qualify();

REVOKE ALL ON TABLE hocalist.conversation_credit_hook FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.chat_message_credit_qualify() FROM PUBLIC, anon, authenticated, service_role;

-- Manual verification and seller-health review workflow.
--
-- September 26 approved rule: begin with reviewable admin decisions.
-- Verified email/phone (Auth) stays separate from reviewed business/identity
-- evidence. A report is a signal, never an automatic penalty. A restriction
-- requires an authorized reviewer, a recorded reason and an appeal route.
-- No automated score, threshold or retention period is invented here.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.memberships') IS NULL
     OR to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL THEN
    RAISE EXCEPTION 'account/marketplace admin prerequisite missing';
  END IF;
  IF to_regclass('hocalist.verification_submissions') IS NOT NULL THEN
    RAISE EXCEPTION 'review workflow already installed';
  END IF;
END; $guard$;

CREATE TABLE hocalist.verification_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  kind text NOT NULL CHECK (kind IN ('identity','business')),
  note text NOT NULL CHECK (length(btrim(note)) BETWEEN 10 AND 2000),
  -- Media references are optional until the reviewed evidence-upload purpose
  -- ships; an empty list is an honest "no evidence attached yet" state.
  evidence_media_ids jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (
    jsonb_typeof(evidence_media_ids)='array' AND jsonb_array_length(evidence_media_ids)<=8
  ),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reviewer_id uuid REFERENCES hocalist.profiles(id),
  decision_reason text CHECK (decision_reason IS NULL OR length(btrim(decision_reason)) BETWEEN 1 AND 500),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verification_decision_shape CHECK (
    (status='pending' AND reviewer_id IS NULL AND decided_at IS NULL)
    OR (status<>'pending' AND reviewer_id IS NOT NULL AND decision_reason IS NOT NULL)
  )
);

CREATE TABLE hocalist.health_review_notes (
  case_id uuid PRIMARY KEY REFERENCES hocalist.support_cases(id),
  reviewer_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  decision text NOT NULL CHECK (decision IN ('no_action','watch','restriction_recommended')),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 500),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE hocalist.account_restrictions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  scope text NOT NULL CHECK (scope IN ('all','buyer','seller')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 500),
  source text NOT NULL CHECK (source IN ('review','health','admin')),
  source_case_id uuid REFERENCES hocalist.support_cases(id),
  created_by uuid NOT NULL REFERENCES hocalist.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_by uuid REFERENCES hocalist.profiles(id),
  revoked_at timestamptz,
  revoke_reason text CHECK (revoke_reason IS NULL OR length(btrim(revoke_reason)) BETWEEN 1 AND 500),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  CONSTRAINT restriction_revoke_shape CHECK (
    (status='active' AND revoked_by IS NULL AND revoked_at IS NULL)
    OR (status='revoked' AND revoked_by IS NOT NULL AND revoke_reason IS NOT NULL)
  )
);
CREATE INDEX account_restrictions_active ON hocalist.account_restrictions(user_id) WHERE status='active';

CREATE TABLE hocalist.restriction_appeals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restriction_id uuid NOT NULL REFERENCES hocalist.account_restrictions(id),
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  body text NOT NULL CHECK (length(btrim(body)) BETWEEN 10 AND 4000),
  status text NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted','upheld','reversed')),
  reviewer_id uuid REFERENCES hocalist.profiles(id),
  decision_reason text CHECK (decision_reason IS NULL OR length(btrim(decision_reason)) BETWEEN 1 AND 500),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  CONSTRAINT appeal_decision_shape CHECK (
    (status='submitted' AND reviewer_id IS NULL)
    OR (status<>'submitted' AND reviewer_id IS NOT NULL AND decision_reason IS NOT NULL)
  ),
  UNIQUE (restriction_id)
);

ALTER TABLE hocalist.verification_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.health_review_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.account_restrictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.restriction_appeals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.verification_submissions, hocalist.health_review_notes,
  hocalist.account_restrictions, hocalist.restriction_appeals
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- User-facing status
-- ---------------------------------------------------------------------------

-- Auth email/phone verification is owned by the withdrawal contract when it is
-- installed; this wrapper keeps the review module independently applicable.
CREATE FUNCTION hocalist.trust_contact_verified(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF to_regprocedure('hocalist.contact_verified(uuid)') IS NOT NULL THEN
    RETURN hocalist.contact_verified(p_user);
  END IF;
  RETURN jsonb_build_object('email_verified',false,'phone_verified',false);
END $$;

CREATE FUNCTION hocalist.verification_submit(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid:=auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  v hocalist.verification_submissions%ROWTYPE;
  v_ids jsonb := '[]'::jsonb;
  v_item jsonb;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='seller' AND status='active')
   OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'verification_access_denied' USING ERRCODE='42501'; END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object'
     OR p_input - ARRAY['kind','note','evidence_media_ids'] <> '{}'::jsonb
     OR p_input->>'kind' NOT IN ('identity','business')
     OR jsonb_typeof(p_input->'note') IS DISTINCT FROM 'string'
     OR length(btrim(p_input->>'note')) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'invalid_submission' USING ERRCODE='22023'; END IF;
  IF p_input ? 'evidence_media_ids' THEN
    IF jsonb_typeof(p_input->'evidence_media_ids')<>'array'
       OR jsonb_array_length(p_input->'evidence_media_ids')>8 THEN
      RAISE EXCEPTION 'invalid_submission' USING ERRCODE='22023'; END IF;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_input->'evidence_media_ids') LOOP
      IF jsonb_typeof(v_item)<>'string' THEN RAISE EXCEPTION 'invalid_submission' USING ERRCODE='22023'; END IF;
    END LOOP;
    v_ids := p_input->'evidence_media_ids';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':verification:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id=u AND operation='verification.submit' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  IF EXISTS(SELECT 1 FROM hocalist.verification_submissions
            WHERE user_id=u AND kind=p_input->>'kind' AND status='pending') THEN
    RAISE EXCEPTION 'verification_pending' USING ERRCODE='P0001'; END IF;
  INSERT INTO hocalist.verification_submissions(user_id,kind,note,evidence_media_ids)
  VALUES(u,p_input->>'kind',btrim(p_input->>'note'),v_ids)
  RETURNING * INTO v;
  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
  VALUES(u,'verification.submit',p_key,h,
    jsonb_build_object('id',v.id,'kind',v.kind,'status',v.status,'revision',v.revision));
  RETURN jsonb_build_object('id',v.id,'kind',v.kind,'status',v.status,'revision',v.revision);
END $$;

-- Reviewed evidence status is deliberately separate from Auth email/phone
-- verification, which is reported by the withdrawal/account status contracts.
CREATE FUNCTION hocalist.verification_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object(
    'email_phone', hocalist.trust_contact_verified(u),
    'items',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',v.id,'kind',v.kind,'status',v.status,'note',v.note,
      'evidence_count',jsonb_array_length(v.evidence_media_ids),
      'decision_reason',v.decision_reason,'revision',v.revision,
      'created_at',v.created_at,'decided_at',v.decided_at)
      ORDER BY v.created_at DESC,v.id DESC) FROM hocalist.verification_submissions v WHERE v.user_id=u),'[]'::jsonb));
END $$;

CREATE FUNCTION hocalist.account_health_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object(
    'verified_email_phone', hocalist.trust_contact_verified(u),
    'review_status',coalesce((SELECT v.status FROM hocalist.verification_submissions v
      WHERE v.user_id=u ORDER BY v.created_at DESC,v.id DESC LIMIT 1),'not_submitted'),
    'restrictions',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',r.id,'scope',r.scope,'reason',r.reason,'source',r.source,
      'created_at',r.created_at,
      'appeal_status',(SELECT a.status FROM hocalist.restriction_appeals a WHERE a.restriction_id=r.id),
      'appeal_id',(SELECT a.id FROM hocalist.restriction_appeals a WHERE a.restriction_id=r.id))
      ORDER BY r.created_at DESC,r.id DESC) FROM hocalist.account_restrictions r
      WHERE r.user_id=u AND r.status='active'),'[]'::jsonb),
    'reports_are_signals_only',true);
END $$;

CREATE FUNCTION hocalist.restriction_appeal_submit(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid:=auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  r hocalist.account_restrictions%ROWTYPE;
  a hocalist.restriction_appeals%ROWTYPE;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object'
     OR p_input - ARRAY['restriction_id','body'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'body') IS DISTINCT FROM 'string'
     OR length(btrim(p_input->>'body')) NOT BETWEEN 10 AND 4000 THEN
    RAISE EXCEPTION 'invalid_appeal' USING ERRCODE='22023'; END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':appeal:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id=u AND operation='restriction.appeal' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT * INTO r FROM hocalist.account_restrictions
    WHERE id=(p_input->>'restriction_id')::uuid AND user_id=u AND status='active';
  IF NOT FOUND THEN RAISE EXCEPTION 'restriction_not_found' USING ERRCODE='P0002'; END IF;
  IF EXISTS(SELECT 1 FROM hocalist.restriction_appeals WHERE restriction_id=r.id) THEN
    RAISE EXCEPTION 'appeal_exists' USING ERRCODE='P0001'; END IF;
  INSERT INTO hocalist.restriction_appeals(restriction_id,user_id,body)
  VALUES(r.id,u,btrim(p_input->>'body')) RETURNING * INTO a;
  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
  VALUES(u,'restriction.appeal',p_key,h,
    jsonb_build_object('id',a.id,'status',a.status,'revision',a.revision,'restriction_id',r.id));
  RETURN jsonb_build_object('id',a.id,'status',a.status,'revision',a.revision,'restriction_id',r.id);
END $$;

-- ---------------------------------------------------------------------------
-- Admin review queue and decisions
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.admin_trust_queue(p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); n integer;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023'; END IF;
  n := p_limit;
  RETURN jsonb_build_object(
    'verifications',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',v.id,'user_id',v.user_id,'kind',v.kind,'note',v.note,
      'evidence_count',jsonb_array_length(v.evidence_media_ids),
      'status',v.status,'revision',v.revision,'created_at',v.created_at,
      'decision_reason',v.decision_reason) ORDER BY v.created_at,v.id)
      FROM (SELECT * FROM hocalist.verification_submissions ORDER BY created_at,id LIMIT n) v),'[]'::jsonb),
    'health_reviews',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'case_id',q.id,'reason_code',q.reason_code,'status',q.status,'body',q.body,
      'created_at',q.created_at,'decision',h.decision,'decision_reason',h.reason)
      ORDER BY q.created_at,q.id)
      FROM (SELECT c.* FROM hocalist.support_cases c
            WHERE c.reason_code IN ('safety','deal')
            ORDER BY c.created_at,c.id LIMIT n) q
      LEFT JOIN hocalist.health_review_notes h ON h.case_id=q.id),'[]'::jsonb),
    'restrictions',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',r.id,'user_id',r.user_id,'scope',r.scope,'reason',r.reason,'source',r.source,
      'status',r.status,'created_at',r.created_at,
      'appeal_id',(SELECT a.id FROM hocalist.restriction_appeals a WHERE a.restriction_id=r.id),
      'appeal_status',(SELECT a.status FROM hocalist.restriction_appeals a WHERE a.restriction_id=r.id))
      ORDER BY r.created_at DESC,r.id DESC)
      FROM (SELECT * FROM hocalist.account_restrictions ORDER BY created_at DESC,id DESC LIMIT n) r),'[]'::jsonb),
    'single_report_penalty',false);
END $$;

CREATE FUNCTION hocalist.admin_trust_command(p_operation text, p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid:=auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  v hocalist.verification_submissions%ROWTYPE;
  r hocalist.account_restrictions%ROWTYPE;
  a hocalist.restriction_appeals%ROWTYPE;
  result jsonb;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_operation IS NULL OR p_operation NOT IN
       ('verification.decide','health.review','restriction.apply','restriction.revoke','appeal.decide')
     OR p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object' THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023'; END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':trust:'||p_operation||':'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id=u AND operation='trust.'||p_operation AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  IF p_operation='verification.decide' THEN
    IF p_input - ARRAY['submission_id','status','reason','expected_revision'] <> '{}'::jsonb
       OR p_input->>'status' NOT IN ('approved','rejected')
       OR jsonb_typeof(p_input->'reason') IS DISTINCT FROM 'string'
       OR length(btrim(p_input->>'reason')) NOT BETWEEN 1 AND 500 THEN
      RAISE EXCEPTION 'invalid_decision' USING ERRCODE='22023'; END IF;
    UPDATE hocalist.verification_submissions SET status=p_input->>'status',
      reviewer_id=u,decision_reason=btrim(p_input->>'reason'),
      revision=revision+1,decided_at=now(),updated_at=now()
    WHERE id=(p_input->>'submission_id')::uuid AND status='pending'
      AND revision=(p_input->>'expected_revision')::bigint
    RETURNING * INTO v;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    result := jsonb_build_object('id',v.id,'status',v.status,'revision',v.revision);
  ELSIF p_operation='health.review' THEN
    IF p_input - ARRAY['case_id','decision','reason'] <> '{}'::jsonb
       OR p_input->>'decision' NOT IN ('no_action','watch','restriction_recommended')
       OR jsonb_typeof(p_input->'reason') IS DISTINCT FROM 'string'
       OR length(btrim(p_input->>'reason')) NOT BETWEEN 1 AND 500 THEN
      RAISE EXCEPTION 'invalid_review' USING ERRCODE='22023'; END IF;
    INSERT INTO hocalist.health_review_notes(case_id,reviewer_id,decision,reason)
    SELECT (p_input->>'case_id')::uuid,u,p_input->>'decision',btrim(p_input->>'reason')
    WHERE EXISTS(SELECT 1 FROM hocalist.support_cases WHERE id=(p_input->>'case_id')::uuid)
    ON CONFLICT(case_id) DO UPDATE SET reviewer_id=excluded.reviewer_id,
      decision=excluded.decision,reason=excluded.reason,created_at=now();
    IF NOT FOUND THEN RAISE EXCEPTION 'case_not_found' USING ERRCODE='P0002'; END IF;
    -- A health review records a recommendation only. It never restricts.
    result := jsonb_build_object('case_id',p_input->>'case_id','decision',p_input->>'decision');
  ELSIF p_operation='restriction.apply' THEN
    IF p_input - ARRAY['user_id','scope','reason','source','case_id'] <> '{}'::jsonb
       OR p_input->>'scope' NOT IN ('all','buyer','seller')
       OR p_input->>'source' NOT IN ('review','health','admin')
       OR jsonb_typeof(p_input->'reason') IS DISTINCT FROM 'string'
       OR length(btrim(p_input->>'reason')) NOT BETWEEN 1 AND 500 THEN
      RAISE EXCEPTION 'invalid_restriction' USING ERRCODE='22023'; END IF;
    IF p_input->>'source'='health' AND p_input->>'case_id' IS NULL THEN
      RAISE EXCEPTION 'health_restriction_needs_case' USING ERRCODE='22023'; END IF;
    INSERT INTO hocalist.account_restrictions(user_id,scope,reason,source,source_case_id,created_by)
    VALUES((p_input->>'user_id')::uuid,p_input->>'scope',btrim(p_input->>'reason'),
      p_input->>'source',nullif(p_input->>'case_id','')::uuid,u)
    RETURNING * INTO r;
    UPDATE hocalist.memberships SET status='restricted'
    WHERE user_id=r.user_id AND status='active'
      AND (r.scope='all' OR role=r.scope);
    result := jsonb_build_object('id',r.id,'user_id',r.user_id,'scope',r.scope,'status',r.status);
  ELSIF p_operation='restriction.revoke' THEN
    IF p_input - ARRAY['restriction_id','reason','expected_revision'] <> '{}'::jsonb
       OR jsonb_typeof(p_input->'reason') IS DISTINCT FROM 'string'
       OR length(btrim(p_input->>'reason')) NOT BETWEEN 1 AND 500 THEN
      RAISE EXCEPTION 'invalid_revocation' USING ERRCODE='22023'; END IF;
    UPDATE hocalist.account_restrictions SET status='revoked',revoked_by=u,revoked_at=now(),
      revoke_reason=btrim(p_input->>'reason'),revision=revision+1
    WHERE id=(p_input->>'restriction_id')::uuid AND status='active'
      AND revision=(p_input->>'expected_revision')::bigint
    RETURNING * INTO r;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    UPDATE hocalist.memberships m SET status='active'
    WHERE m.user_id=r.user_id AND m.status='restricted'
      AND (r.scope='all' OR m.role=r.scope)
      AND NOT EXISTS(SELECT 1 FROM hocalist.account_restrictions other
        WHERE other.user_id=r.user_id AND other.status='active'
          AND (other.scope='all' OR other.scope=m.role));
    result := jsonb_build_object('id',r.id,'status',r.status,'revision',r.revision);
  ELSE
    IF p_input - ARRAY['appeal_id','status','reason','expected_revision'] <> '{}'::jsonb
       OR p_input->>'status' NOT IN ('upheld','reversed')
       OR jsonb_typeof(p_input->'reason') IS DISTINCT FROM 'string'
       OR length(btrim(p_input->>'reason')) NOT BETWEEN 1 AND 500
       OR jsonb_typeof(p_input->'expected_revision') <> 'number' THEN
      RAISE EXCEPTION 'invalid_decision' USING ERRCODE='22023'; END IF;
    UPDATE hocalist.restriction_appeals SET status=p_input->>'status',reviewer_id=u,
      decision_reason=btrim(p_input->>'reason'),revision=revision+1,decided_at=now()
    WHERE id=(p_input->>'appeal_id')::uuid AND status='submitted'
      AND revision=(p_input->>'expected_revision')::bigint
    RETURNING * INTO a;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    IF a.status='reversed' THEN
      SELECT * INTO r FROM hocalist.account_restrictions WHERE id=a.restriction_id;
      IF r.status='active' THEN
        UPDATE hocalist.account_restrictions SET status='revoked',revoked_by=u,revoked_at=now(),
          revoke_reason='appeal reversed',revision=revision+1 WHERE id=r.id;
        UPDATE hocalist.memberships m SET status='active'
        WHERE m.user_id=r.user_id AND m.status='restricted'
          AND (r.scope='all' OR m.role=r.scope)
          AND NOT EXISTS(SELECT 1 FROM hocalist.account_restrictions other
            WHERE other.user_id=r.user_id AND other.status='active' AND other.id<>r.id
              AND (other.scope='all' OR other.scope=m.role));
      END IF;
    END IF;
    result := jsonb_build_object('id',a.id,'status',a.status,'restriction_id',a.restriction_id);
  END IF;
  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
  VALUES(u,'trust.'||p_operation,p_key,h,result);
  RETURN result;
END $$;

REVOKE ALL ON FUNCTION hocalist.trust_contact_verified(uuid),
  hocalist.verification_submit(text,jsonb),hocalist.verification_status(),
  hocalist.account_health_status(),hocalist.restriction_appeal_submit(text,jsonb),
  hocalist.admin_trust_queue(integer),hocalist.admin_trust_command(text,text,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.verification_submit(text,jsonb),hocalist.verification_status(),
  hocalist.account_health_status(),hocalist.restriction_appeal_submit(text,jsonb),
  hocalist.admin_trust_queue(integer),hocalist.admin_trust_command(text,text,jsonb)
  TO authenticated;

-- Additive website credit checkout over the reviewed Stripe TEST foundation
-- (005 receipt + 006 subscription checkouts). Provider-neutral and local:
-- no Stripe call, no secret and no entitlement is granted here.
--
-- Flow: the website server creates an account-bound checkout with
-- `stripe_test_deposit_begin` (rates are snapshotted from the admin-managed
-- deposit option), binds the provider customer/session with
-- `stripe_test_deposit_bind`, and only a server process that has verified a
-- signed provider event may call `stripe_test_deposit_finish`. A redirect or
-- success URL can never create a batch: `finish` validates the paid amount
-- against the option and is idempotent by provider reference.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.stripe_test_checkouts') IS NULL
     OR to_regclass('hocalist.stripe_test_customers') IS NULL THEN
    RAISE EXCEPTION 'Stripe TEST subscription foundation 006 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.credit_batches') IS NULL
     OR to_regprocedure('hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text)') IS NULL THEN
    RAISE EXCEPTION 'Credit batch foundation 090 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.credit_deposit_options') IS NULL THEN
    RAISE EXCEPTION 'Deposit option configuration 092 prerequisite missing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist' AND table_name='stripe_test_checkouts' AND column_name='kind'
  ) THEN
    RAISE EXCEPTION 'Deposit checkout already installed';
  END IF;
END; $guard$;

-- Additive columns: subscription rows keep kind='subscription'; deposit rows
-- carry the option snapshot taken when the checkout began, so a later admin
-- rate edit cannot reprice a payment already in progress.
ALTER TABLE hocalist.stripe_test_checkouts
  ALTER COLUMN plan_code DROP NOT NULL,
  ALTER COLUMN price_id DROP NOT NULL,
  ADD COLUMN kind text NOT NULL DEFAULT 'subscription'
    CHECK (kind IN ('subscription','credit_deposit')),
  ADD COLUMN credit_option_id uuid REFERENCES hocalist.credit_deposit_options(id),
  ADD COLUMN credit_initial_minor bigint,
  ADD COLUMN credit_winning_minor bigint,
  ADD COLUMN credit_rate_version text,
  ADD CONSTRAINT stripe_test_checkout_kind_shape CHECK (
    (kind='subscription' AND plan_code IS NOT NULL AND credit_option_id IS NULL)
    OR (kind='credit_deposit' AND plan_code IS NULL AND credit_option_id IS NOT NULL
        AND credit_initial_minor IS NOT NULL AND credit_winning_minor IS NOT NULL
        AND credit_rate_version IS NOT NULL)
  );

-- Payment/batch association persisted on the checkout: an identical finish
-- retry returns its original result, and a conflicting replay (different
-- amount or reference) is refused instead of returning a null or unrelated
-- batch. One provider reference can belong to exactly one checkout.
ALTER TABLE hocalist.stripe_test_checkouts
  ADD COLUMN credit_batch_id uuid REFERENCES hocalist.credit_batches(id),
  ADD COLUMN provider_reference text
    CHECK (provider_reference IS NULL OR length(btrim(provider_reference)) BETWEEN 1 AND 200);
CREATE UNIQUE INDEX stripe_test_checkout_payment_reference
  ON hocalist.stripe_test_checkouts(provider_reference)
  WHERE provider_reference IS NOT NULL;

-- Trusted website/server path only. p_user must come from the verified session,
-- never from request JSON; no client amount is accepted.
--
-- Retry integrity: an existing (membership, key) checkout is recovered with its
-- immutable option snapshot before any current-option validation. An unchanged
-- retry therefore survives an admin fee edit or an option retirement; current
-- options are validated only when creating a new checkout.
CREATE FUNCTION hocalist.stripe_test_deposit_begin(p_user uuid, p_option uuid, p_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  m hocalist.memberships%ROWTYPE;
  c hocalist.stripe_test_checkouts%ROWTYPE;
  o hocalist.credit_deposit_options%ROWTYPE;
  v_customer text;
BEGIN
  PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO m FROM hocalist.memberships WHERE user_id=p_user AND role='seller' FOR UPDATE;
  IF NOT FOUND OR m.status<>'active'
     OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
  IF p_key IS NULL THEN RAISE EXCEPTION 'invalid_option_or_key' USING ERRCODE='22023'; END IF;
  -- Recovery first: the saved checkout carries the original intent snapshot.
  SELECT * INTO c FROM hocalist.stripe_test_checkouts
    WHERE membership_id=m.id AND request_key=p_key FOR UPDATE;
  IF FOUND THEN
    IF c.kind<>'credit_deposit' OR c.credit_option_id<>p_option THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    IF c.state IN ('complete','expired') THEN
      RAISE EXCEPTION 'checkout_closed' USING ERRCODE='P0001'; END IF;
  ELSE
    -- New checkout: validate the current catalogue and account state.
    SELECT * INTO o FROM hocalist.credit_deposit_options WHERE id=p_option AND active;
    IF NOT FOUND THEN RAISE EXCEPTION 'invalid_option_or_key' USING ERRCODE='22023'; END IF;
    IF EXISTS(SELECT 1 FROM hocalist.stripe_test_customers WHERE membership_id=m.id AND requires_review) THEN
      RAISE EXCEPTION 'billing_review_required' USING ERRCODE='P0001'; END IF;
    IF EXISTS(SELECT 1 FROM hocalist.stripe_test_checkouts
              WHERE membership_id=m.id AND state IN ('creating','open')) THEN
      RAISE EXCEPTION 'checkout_pending' USING ERRCODE='P0001'; END IF;
    INSERT INTO hocalist.stripe_test_checkouts(
      membership_id, request_key, plan_code, price_id, amount_minor, kind,
      credit_option_id, credit_initial_minor, credit_winning_minor, credit_rate_version)
    VALUES (m.id, p_key, NULL, NULL, o.amount_minor, 'credit_deposit',
      o.id, o.initial_fee_minor, o.winning_total_minor, o.rate_version)
    RETURNING * INTO c;
  END IF;
  IF c.state='creating' AND c.created_at<now()-interval '25 minutes' THEN
    RAISE EXCEPTION 'checkout_reconciliation_required' USING ERRCODE='P0001'; END IF;
  SELECT customer_id INTO v_customer FROM hocalist.stripe_test_customers WHERE membership_id=m.id;
  RETURN jsonb_build_object('checkout_id',c.id,'membership_id',m.id,'customer_id',v_customer,
    'option_id',c.credit_option_id,'amount_minor',c.amount_minor,'currency','usd',
    'initial_fee_minor',c.credit_initial_minor,'winning_total_minor',c.credit_winning_minor,
    'rate_version',c.credit_rate_version,'session_id',c.session_id,'session_url',c.session_url,
    'expires_at',floor(extract(epoch FROM c.expires_at)),'state',c.state);
END $$;

CREATE FUNCTION hocalist.stripe_test_deposit_bind(
  p_checkout uuid, p_customer text, p_session text DEFAULT NULL, p_url text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c hocalist.stripe_test_checkouts%ROWTYPE; current_customer text;
BEGIN
  SELECT * INTO STRICT c FROM hocalist.stripe_test_checkouts WHERE id=p_checkout FOR UPDATE;
  IF c.kind<>'credit_deposit' THEN RAISE EXCEPTION 'not_a_deposit_checkout'; END IF;
  IF c.state NOT IN ('creating','open') THEN RAISE EXCEPTION 'checkout_closed'; END IF;
  IF p_customer IS NULL OR p_customer !~ '^cus_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'invalid_customer'; END IF;
  INSERT INTO hocalist.stripe_test_customers(membership_id,customer_id)
  VALUES(c.membership_id,p_customer) ON CONFLICT(membership_id) DO NOTHING;
  SELECT customer_id INTO current_customer FROM hocalist.stripe_test_customers WHERE membership_id=c.membership_id;
  IF current_customer<>p_customer THEN RAISE EXCEPTION 'customer_conflict'; END IF;
  IF p_session IS NOT NULL THEN
    IF p_session !~ '^cs_test_[A-Za-z0-9]+$' OR p_url IS NULL OR p_url !~ '^https://checkout[.]stripe[.]com/' THEN
      RAISE EXCEPTION 'invalid_session'; END IF;
    IF c.session_id IS NOT NULL AND c.session_id<>p_session THEN RAISE EXCEPTION 'session_conflict'; END IF;
    UPDATE hocalist.stripe_test_checkouts SET session_id=p_session,session_url=p_url,
      state=CASE WHEN state='creating' THEN 'open' ELSE state END WHERE id=c.id;
  END IF;
END $$;

-- Caller must have verified the signed provider event and its paid amount.
-- A redirect never reaches this function. The batch is created once per
-- provider reference and keeps the rates snapshotted at checkout start. The
-- checkout persists its payment reference and batch id, so an identical retry
-- returns the original outcome while a conflicting replay (different amount or
-- reference) fails instead of returning a null or unrelated batch.
CREATE FUNCTION hocalist.stripe_test_deposit_finish(
  p_checkout uuid, p_customer text, p_paid_amount bigint, p_reference text,
  p_error text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  c hocalist.stripe_test_checkouts%ROWTYPE;
  v_user uuid;
  v_batch uuid;
  v_reference text;
BEGIN
  SELECT * INTO STRICT c FROM hocalist.stripe_test_checkouts WHERE id=p_checkout FOR UPDATE;
  IF c.kind<>'credit_deposit' THEN RAISE EXCEPTION 'not_a_deposit_checkout'; END IF;
  IF p_customer IS NULL OR NOT EXISTS(
       SELECT 1 FROM hocalist.stripe_test_customers
       WHERE membership_id=c.membership_id AND customer_id=p_customer) THEN
    RAISE EXCEPTION 'customer_conflict'; END IF;
  IF p_error IS NOT NULL THEN
    IF c.state='complete' THEN RAISE EXCEPTION 'checkout_closed' USING ERRCODE='P0001'; END IF;
    IF p_error='review_required' THEN
      UPDATE hocalist.stripe_test_customers SET requires_review=true WHERE membership_id=c.membership_id;
      UPDATE hocalist.stripe_test_checkouts SET state='expired' WHERE id=c.id;
      RETURN jsonb_build_object('status','review_required','checkout_id',c.id);
    END IF;
    RETURN jsonb_build_object('status','retry','checkout_id',c.id);
  END IF;
  IF c.state='complete' THEN
    -- Identical retry: return the recorded payment/batch association. A
    -- conflicting replay (different reference or amount) must fail and can
    -- never return a null or unrelated batch.
    IF p_reference IS DISTINCT FROM c.provider_reference THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    IF p_paid_amount IS DISTINCT FROM c.amount_minor THEN
      RAISE EXCEPTION 'amount_mismatch' USING ERRCODE='P0001'; END IF;
    IF c.credit_batch_id IS NULL THEN
      RAISE EXCEPTION 'checkout_association_missing' USING ERRCODE='P0001'; END IF;
    RETURN jsonb_build_object('status','complete','checkout_id',c.id,
      'batch_id',c.credit_batch_id,'reference',c.provider_reference);
  END IF;
  IF c.state NOT IN ('creating','open') THEN RAISE EXCEPTION 'checkout_closed'; END IF;
  IF p_reference IS NULL OR length(btrim(p_reference)) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'invalid_reference' USING ERRCODE='22023'; END IF;
  IF p_paid_amount IS DISTINCT FROM c.amount_minor THEN
    RAISE EXCEPTION 'amount_mismatch' USING ERRCODE='P0001'; END IF;
  IF EXISTS(SELECT 1 FROM hocalist.stripe_test_checkouts
            WHERE provider_reference=btrim(p_reference) AND id<>c.id) THEN
    RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
  SELECT user_id INTO v_user FROM hocalist.memberships WHERE id=c.membership_id;
  v_reference := 'stripe_test:'||p_reference;
  v_batch := hocalist.credit_deposit_internal(
    v_user, v_reference, c.amount_minor,
    c.credit_initial_minor, c.credit_winning_minor, c.credit_rate_version);
  UPDATE hocalist.stripe_test_checkouts
    SET state='complete', credit_batch_id=v_batch, provider_reference=btrim(p_reference)
    WHERE id=c.id;
  RETURN jsonb_build_object('status','complete','checkout_id',c.id,'batch_id',v_batch);
END $$;

-- App-facing read: the active purchasable options and the caller's own deposit
-- checkout states. No provider secret, session URL or card data is exposed.
CREATE FUNCTION hocalist.credit_deposit_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();
BEGIN
  IF u IS NULL OR NOT EXISTS(
       SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='seller' AND status='active')
     OR EXISTS(
       SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object(
    'options',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',id,'amount_minor',amount_minor,'initial_fee_minor',initial_fee_minor,
      'winning_total_minor',winning_total_minor,'rate_version',rate_version,'sort_order',sort_order)
      ORDER BY sort_order,amount_minor) FROM hocalist.credit_deposit_options WHERE active),'[]'::jsonb),
    'checkouts',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',c.id,'option_id',c.credit_option_id,'amount_minor',c.amount_minor,
      'state',c.state,'created_at',c.created_at,'expires_at',c.expires_at)
      ORDER BY c.created_at DESC,c.id DESC)
      FROM hocalist.stripe_test_checkouts c
      JOIN hocalist.memberships m ON m.id=c.membership_id
      WHERE m.user_id=u AND c.kind='credit_deposit' LIMIT 20),'[]'::jsonb));
END $$;

REVOKE ALL ON FUNCTION
  hocalist.stripe_test_deposit_begin(uuid,uuid,uuid),
  hocalist.stripe_test_deposit_bind(uuid,text,text,text),
  hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text),
  hocalist.credit_deposit_status()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  hocalist.stripe_test_deposit_begin(uuid,uuid,uuid),
  hocalist.stripe_test_deposit_bind(uuid,text,text,text),
  hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.credit_deposit_status() TO authenticated;

-- Additive notification producers for the approved outcome, review and
-- withdrawal events (over inbox 030 and producers 031).
--
-- Recipients are derived from the committed domain rows, never from client
-- input, and every event carries a deterministic key so a replayed transition
-- cannot duplicate a row. Disabled optional topics are skipped inside
-- `notification_emit`; account/safety updates stay mandatory. Titles, bodies,
-- links and payloads stay generic: no address, contact, PIN or amount detail.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $guard$ BEGIN
  IF to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('hocalist.notification_recipient_allowed(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Notification inbox/producer foundation 030/031 is missing';
  END IF;
  IF to_regclass('hocalist.sale_confirmations') IS NULL
     OR to_regclass('hocalist.verification_submissions') IS NULL
     OR to_regclass('hocalist.account_restrictions') IS NULL
     OR to_regclass('hocalist.withdrawal_requests') IS NULL THEN
    RAISE EXCEPTION 'Outcome/review/withdrawal tables are missing';
  END IF;
  IF to_regprocedure('hocalist.notification_on_sale_confirmed()') IS NOT NULL THEN
    RAISE EXCEPTION 'Outcome/review producers already exist';
  END IF;
END; $guard$;

-- ---------------------------------------------------------------------------
-- Purchase confirmed: both participants, meeting link, no payment detail
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.notification_on_sale_confirmed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF hocalist.notification_recipient_allowed(NEW.buyer_user_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.buyer_user_id,
      md5('sale:confirmed:' || NEW.id::text || ':buyer')::uuid,
      'meeting_update',
      NEW.meeting_id,
      'Purchase confirmed',
      'Your request PIN confirmed the purchase. Item payment stays between you and the seller.',
      'hocalist://meetings/' || NEW.meeting_id::text,
      jsonb_build_object('meeting_id', NEW.meeting_id, 'request_id', NEW.request_id));
  END IF;
  IF hocalist.notification_recipient_allowed(NEW.seller_user_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.seller_user_id,
      md5('sale:confirmed:' || NEW.id::text || ':seller')::uuid,
      'meeting_update',
      NEW.meeting_id,
      'Purchase confirmed',
      'The buyer confirmed the purchase with their request PIN.',
      'hocalist://meetings/' || NEW.meeting_id::text,
      jsonb_build_object('meeting_id', NEW.meeting_id, 'request_id', NEW.request_id));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_sale_confirmed
  AFTER INSERT ON hocalist.sale_confirmations
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_sale_confirmed();

-- ---------------------------------------------------------------------------
-- Manual review: reviewed-evidence decisions, restrictions and appeals
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.notification_on_verification_decision() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF OLD.status = 'pending' AND NEW.status <> 'pending'
     AND hocalist.notification_recipient_allowed(NEW.user_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.user_id,
      md5('verification:decision:' || NEW.id::text || ':' || NEW.revision::text)::uuid,
      'account_update',
      NEW.id,
      'Verification review updated',
      'Your reviewed evidence was ' || NEW.status || '. Open Hocalist for the reviewer reason.',
      'hocalist://account/' || NEW.id::text,
      jsonb_build_object('submission_id', NEW.id, 'status', NEW.status));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_verification_decision
  AFTER UPDATE ON hocalist.verification_submissions
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_verification_decision();

CREATE FUNCTION hocalist.notification_on_restriction() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF hocalist.notification_recipient_allowed(NEW.user_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.user_id,
      md5('restriction:applied:' || NEW.id::text)::uuid,
      'account_update',
      NEW.id,
      'Account restriction recorded',
      'A restriction was recorded after review. Open Hocalist to read the reason and appeal it.',
      'hocalist://account/' || NEW.id::text,
      jsonb_build_object('restriction_id', NEW.id, 'scope', NEW.scope));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_restriction_applied
  AFTER INSERT ON hocalist.account_restrictions
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_restriction();

CREATE FUNCTION hocalist.notification_on_appeal_decision() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF OLD.status = 'submitted' AND NEW.status <> 'submitted'
     AND hocalist.notification_recipient_allowed(NEW.user_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.user_id,
      md5('appeal:decision:' || NEW.id::text || ':' || NEW.revision::text)::uuid,
      'account_update',
      NEW.restriction_id,
      'Appeal decision recorded',
      'Your appeal was ' || NEW.status || '. Open Hocalist for the reviewer reason.',
      'hocalist://account/' || NEW.restriction_id::text,
      jsonb_build_object('appeal_id', NEW.id, 'restriction_id', NEW.restriction_id,
        'status', NEW.status));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_appeal_decision
  AFTER UPDATE ON hocalist.restriction_appeals
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_appeal_decision();

-- ---------------------------------------------------------------------------
-- Withdrawals: processing acknowledgement and terminal states
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.notification_on_withdrawal() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_event text;
  v_revision bigint;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_event := 'submitted';
    v_revision := 1;
  ELSE
    v_event := NEW.status;
    v_revision := coalesce((SELECT max(revision) + 1 FROM hocalist.withdrawal_events
      WHERE withdrawal_id = NEW.id), 2);
  END IF;
  IF NOT hocalist.notification_recipient_allowed(NEW.user_id) THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;
  PERFORM hocalist.notification_emit(
    NEW.user_id,
    md5('withdrawal:' || v_event || ':' || NEW.id::text || ':' || v_revision::text)::uuid,
    'billing_update',
    NEW.id,
    CASE v_event
      WHEN 'paid' THEN 'Withdrawal paid'
      WHEN 'failed' THEN 'Withdrawal failed'
      ELSE 'Withdrawal submitted'
    END,
    CASE v_event
      WHEN 'paid' THEN 'Your withdrawal was paid. Open Hocalist for details.'
      WHEN 'failed' THEN 'Your withdrawal failed and the reserved amount was restored. Open Hocalist for details.'
      ELSE 'Your withdrawal is processing and the amount is reserved.'
    END,
    'hocalist://billing/' || NEW.id::text,
    jsonb_build_object('withdrawal_id', NEW.id, 'status', NEW.status));
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_withdrawal_insert
  AFTER INSERT ON hocalist.withdrawal_requests
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_withdrawal();

CREATE TRIGGER notification_withdrawal_status
  AFTER UPDATE ON hocalist.withdrawal_requests
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_withdrawal();

REVOKE ALL ON FUNCTION
  hocalist.notification_on_sale_confirmed(),
  hocalist.notification_on_verification_decision(),
  hocalist.notification_on_restriction(),
  hocalist.notification_on_appeal_decision(),
  hocalist.notification_on_withdrawal()
  FROM PUBLIC, anon, authenticated, service_role;

DO $verify$ DECLARE f oid; r text; priv text; BEGIN
f:=to_regprocedure('hocalist.credit_wallet()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'f634c8605ee3883270a8bfd1332a3fae' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_wallet()'; END IF;
f:=to_regprocedure('hocalist.reward_wallet()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'52b454501fb9dea714d856ff4e292337' THEN RAISE EXCEPTION 'Function drift: hocalist.reward_wallet()'; END IF;
f:=to_regprocedure('hocalist.credit_admin_command(text,text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'0a33275e2a20239aad8e3d4f3fbcc07c' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_admin_command(text,text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.withdrawal_status()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'624984c61741a3a48d168ed877c625df' THEN RAISE EXCEPTION 'Function drift: hocalist.withdrawal_status()'; END IF;
f:=to_regprocedure('hocalist.withdrawal_request(text,bigint)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'56d70610f58760eda3c7ca76f15706fe' THEN RAISE EXCEPTION 'Function drift: hocalist.withdrawal_request(text,bigint)'; END IF;
f:=to_regprocedure('hocalist.admin_withdrawal_queue(integer,uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'47dfa5448e7545e863f963e10bb8526e' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_withdrawal_queue(integer,uuid)'; END IF;
f:=to_regprocedure('hocalist.credit_deposit_status()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'bef8e3efc2d765ccccbd10c2f4d68cb4' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_deposit_status()'; END IF;
f:=to_regprocedure('hocalist.verification_submit(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'3c3df6857b254549b3526fdba7cb1b5a' THEN RAISE EXCEPTION 'Function drift: hocalist.verification_submit(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.verification_status()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'fc094a9a51d94fbd1c0f05bfde6988cf' THEN RAISE EXCEPTION 'Function drift: hocalist.verification_status()'; END IF;
f:=to_regprocedure('hocalist.account_health_status()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'dce19dbf79aa099dd31db34d3e5a5abb' THEN RAISE EXCEPTION 'Function drift: hocalist.account_health_status()'; END IF;
f:=to_regprocedure('hocalist.restriction_appeal_submit(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'5fa19babe818a35101723b2ba72fbf93' THEN RAISE EXCEPTION 'Function drift: hocalist.restriction_appeal_submit(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.admin_trust_queue(integer)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'be2adfa1086f9b63287887e905b44ae1' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_trust_queue(integer)'; END IF;
f:=to_regprocedure('hocalist.admin_trust_command(text,text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'7ff01a309889845ad833d753d2609241' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_trust_command(text,text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'0ba79504c42be1bbdc226c4ab4087f78' THEN RAISE EXCEPTION 'Function drift: hocalist.marketplace_command(text,text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.credit_authorize_target(uuid,uuid,uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'342f9ae27957a7127071e766fdc7ead8' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_authorize_target(uuid,uuid,uuid)'; END IF;
f:=to_regprocedure('hocalist.credit_qualify_conversation(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'81f3517936daa5f772d8041ebeaf9dc3' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_qualify_conversation(uuid)'; END IF;
f:=to_regprocedure('hocalist.credit_release_offer(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'da05324873c92353d0639b1379e8f3f3' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_release_offer(uuid)'; END IF;
f:=to_regprocedure('hocalist.credit_settle_purchase(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'8a7256dedbcbec61b6552888e7cba5cb' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_settle_purchase(uuid)'; END IF;
f:=to_regprocedure('hocalist.credit_reconcile_internal(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'adfb2f76c0d81c80494ed9b04dad9c82' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_reconcile_internal(uuid)'; END IF;
f:=to_regprocedure('hocalist.contact_verified(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c8447d7e9ec35e2935b2fb934bd8cc65' THEN RAISE EXCEPTION 'Function drift: hocalist.contact_verified(uuid)'; END IF;
f:=to_regprocedure('hocalist.trust_contact_verified(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'11daa5e9fad67e3f58f63bfda2c814b1' THEN RAISE EXCEPTION 'Function drift: hocalist.trust_contact_verified(uuid)'; END IF;
f:=to_regprocedure('hocalist.notification_on_sale_confirmed()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c16e6207a695f7cff749aab48ef71133' THEN RAISE EXCEPTION 'Function drift: hocalist.notification_on_sale_confirmed()'; END IF;
f:=to_regprocedure('hocalist.notification_on_verification_decision()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'6d1895a9bf5a80b5d4c690e6a964c675' THEN RAISE EXCEPTION 'Function drift: hocalist.notification_on_verification_decision()'; END IF;
f:=to_regprocedure('hocalist.notification_on_restriction()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'8d6225c925d1ccf398ac6a7e696a4274' THEN RAISE EXCEPTION 'Function drift: hocalist.notification_on_restriction()'; END IF;
f:=to_regprocedure('hocalist.notification_on_appeal_decision()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'2891a9093009764f14911ed6ba6db01f' THEN RAISE EXCEPTION 'Function drift: hocalist.notification_on_appeal_decision()'; END IF;
f:=to_regprocedure('hocalist.notification_on_withdrawal()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'b179f333b9150958aabe8b57297419b7' THEN RAISE EXCEPTION 'Function drift: hocalist.notification_on_withdrawal()'; END IF;
f:=to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c02f852987f3850355df6fe361b7c040' THEN RAISE EXCEPTION 'Function drift: hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)'; END IF;
f:=to_regprocedure('hocalist.stripe_test_deposit_bind(uuid,text,text,text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'cb39b57fef8c8c29dbf7908b8ce9fd73' THEN RAISE EXCEPTION 'Function drift: hocalist.stripe_test_deposit_bind(uuid,text,text,text)'; END IF;
f:=to_regprocedure('hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c9154ab0b88f2bbf74af0a8029914c63' THEN RAISE EXCEPTION 'Function drift: hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text)'; END IF;
f:=to_regprocedure('hocalist.meeting_json(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'55e83c1744a712990d50e1d92b70eaae' THEN RAISE EXCEPTION 'Function drift: hocalist.meeting_json(uuid)'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.credit_deposit_options')),false) THEN RAISE EXCEPTION 'Missing RLS: credit_deposit_options'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.credit_deposit_options',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: credit_deposit_options % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.reward_policy')),false) THEN RAISE EXCEPTION 'Missing RLS: reward_policy'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.reward_policy',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: reward_policy % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.conversation_credit_hook')),false) THEN RAISE EXCEPTION 'Missing RLS: conversation_credit_hook'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.conversation_credit_hook',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: conversation_credit_hook % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.withdrawal_policy')),false) THEN RAISE EXCEPTION 'Missing RLS: withdrawal_policy'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.withdrawal_policy',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: withdrawal_policy % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.withdrawal_requests')),false) THEN RAISE EXCEPTION 'Missing RLS: withdrawal_requests'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.withdrawal_requests',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: withdrawal_requests % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.withdrawal_events')),false) THEN RAISE EXCEPTION 'Missing RLS: withdrawal_events'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.withdrawal_events',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: withdrawal_events % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.verification_submissions')),false) THEN RAISE EXCEPTION 'Missing RLS: verification_submissions'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.verification_submissions',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: verification_submissions % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.health_review_notes')),false) THEN RAISE EXCEPTION 'Missing RLS: health_review_notes'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.health_review_notes',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: health_review_notes % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.account_restrictions')),false) THEN RAISE EXCEPTION 'Missing RLS: account_restrictions'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.account_restrictions',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: account_restrictions % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.restriction_appeals')),false) THEN RAISE EXCEPTION 'Missing RLS: restriction_appeals'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.restriction_appeals',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: restriction_appeals % %',r,priv; END IF; END LOOP; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.credit_wallet()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.credit_wallet() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.reward_wallet()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.reward_wallet() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.credit_admin_command(text,text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.credit_admin_command(text,text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.withdrawal_status()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.withdrawal_status() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.withdrawal_request(text,bigint)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.withdrawal_request(text,bigint) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_withdrawal_queue(integer,uuid)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_withdrawal_queue(integer,uuid) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.credit_deposit_status()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.credit_deposit_status() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.verification_submit(text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.verification_submit(text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.verification_status()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.verification_status() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.account_health_status()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.account_health_status() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.restriction_appeal_submit(text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.restriction_appeal_submit(text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_trust_queue(integer)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_trust_queue(integer) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_trust_command(text,text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_trust_command(text,text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.marketplace_command(text,text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.marketplace_command(text,text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.credit_authorize_target(uuid,uuid,uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.credit_authorize_target(uuid,uuid,uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.credit_qualify_conversation(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.credit_qualify_conversation(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.credit_release_offer(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.credit_release_offer(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.credit_settle_purchase(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.credit_settle_purchase(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.credit_reconcile_internal(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.credit_reconcile_internal(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.contact_verified(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.contact_verified(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.trust_contact_verified(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.trust_contact_verified(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.notification_on_sale_confirmed()'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.notification_on_sale_confirmed()'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.notification_on_verification_decision()'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.notification_on_verification_decision()'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.notification_on_restriction()'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.notification_on_restriction()'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.notification_on_appeal_decision()'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.notification_on_appeal_decision()'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.notification_on_withdrawal()'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.notification_on_withdrawal()'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on provider helper: hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.stripe_test_deposit_bind(uuid,text,text,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on provider helper: hocalist.stripe_test_deposit_bind(uuid,text,text,text)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.stripe_test_deposit_bind(uuid,text,text,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.stripe_test_deposit_bind(uuid,text,text,text)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on provider helper: hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text)'; END IF;
END $verify$;
COMMIT;

-- DRAFT: marketplace foundation (requests, offers, Store listings, catalogue,
-- locations, saved items, conversation eligibility). Locally tested only.
--
-- Not an instruction to apply to a live project. Apply only through the
-- guarded bundle in database/marketplace/rollout after coordinating review.
--
-- Scope: persistent marketplace records and the server-side eligibility that
-- authorizes opening a deal conversation. Meetings, PIN, credits, rewards,
-- notifications and moderation policy execution are NOT implemented here.
-- Item payment stays offline.
--
-- Deployment order: this bundle expects the account foundation (003/004) and
-- the chat foundation (010). Chat must be applied first because its rollout
-- preflight aborts on unexpected hocalist functions. `conversation.open_offer`
-- re-checks the chat function at runtime and fails safely when chat is absent.
--
-- Authorization model: no table is readable or writable by clients. All access
-- goes through SECURITY DEFINER functions that derive the caller from
-- auth.uid(), assert an active membership for the member's role, and never
-- trust a caller-supplied owner, role or status. Admin configuration requires
-- a row in hocalist.platform_admins.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $marketplace_guard$
BEGIN
  IF to_regclass('hocalist.profiles') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regclass('hocalist.role_profiles') IS NULL
     OR to_regclass('hocalist.profile_contacts') IS NULL
     OR to_regprocedure('hocalist.account_command(text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Account foundation 002/003/004 is missing';
  END IF;
  IF to_regclass('hocalist.requests') IS NOT NULL
     OR to_regclass('hocalist.offers') IS NOT NULL
     OR to_regclass('hocalist.store_listings') IS NOT NULL
     OR to_regprocedure('hocalist.marketplace_command(text,text,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'Marketplace objects already exist; review before applying';
  END IF;
END
$marketplace_guard$;

-- ---------------------------------------------------------------------------
-- Commercial configuration and entitlements
-- ---------------------------------------------------------------------------

-- Settled Store allowances (Free 3 / Pro 15 / Elite 50). Admin-managed so a
-- later approved change does not need a migration. No plan assignment happens
-- here: seller_entitlements is written by the reviewed billing/earned-benefit
-- work and every seller without a row resolves to Free.
CREATE TABLE hocalist.marketplace_plan_limits (
  plan_code text PRIMARY KEY CHECK (plan_code IN ('free','pro','elite')),
  store_listing_limit integer NOT NULL CHECK (store_listing_limit >= 0),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.marketplace_plan_limits(plan_code, store_listing_limit) VALUES
  ('free', 3), ('pro', 15), ('elite', 50);

CREATE TABLE hocalist.seller_entitlements (
  user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  plan_code text NOT NULL REFERENCES hocalist.marketplace_plan_limits(plan_code),
  source text NOT NULL CHECK (source IN ('billing','earned','admin')),
  active boolean NOT NULL DEFAULT true,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Platform administrators. Provisioning the first admin is a reviewed
-- owner/coordinator database action; no client command can add one.
CREATE TABLE hocalist.platform_admins (
  user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  granted_at timestamptz NOT NULL DEFAULT now(),
  granted_by uuid REFERENCES hocalist.profiles(id)
);

-- ---------------------------------------------------------------------------
-- Catalogue and locations (admin-managed configuration)
-- ---------------------------------------------------------------------------

CREATE TABLE hocalist.catalogue_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id uuid REFERENCES hocalist.catalogue_categories(id),
  label text NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 120),
  slug text CHECK (slug IS NULL OR slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  scope text NOT NULL CHECK (scope IN ('product','service','both')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT catalogue_category_not_own_parent CHECK (parent_id IS NULL OR parent_id <> id)
);
CREATE UNIQUE INDEX catalogue_categories_slug_unique
  ON hocalist.catalogue_categories(slug) WHERE slug IS NOT NULL;
CREATE INDEX catalogue_categories_order ON hocalist.catalogue_categories(parent_id, sort_order, label);

CREATE TABLE hocalist.catalogue_option_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES hocalist.catalogue_categories(id),
  label text NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 120),
  selection_mode text NOT NULL CHECK (selection_mode IN ('single','multiple')),
  is_required boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX catalogue_option_groups_order ON hocalist.catalogue_option_groups(category_id, sort_order, label);

CREATE TABLE hocalist.catalogue_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES hocalist.catalogue_option_groups(id),
  label text NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 120),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX catalogue_options_order ON hocalist.catalogue_options(group_id, sort_order, label);

-- Dynamic locations. Values are admin-managed; no production market list is
-- hardcoded here.
CREATE TABLE hocalist.locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  region text CHECK (region IS NULL OR length(btrim(region)) BETWEEN 1 AND 150),
  city text CHECK (city IS NULL OR length(btrim(city)) BETWEEN 1 AND 150),
  label text NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 200),
  -- Named IANA zone for the meeting location, when an admin has resolved it.
  -- A broad area must never be assumed to share one zone; unresolved entries
  -- stay NULL and scheduling for them is unavailable until configured.
  timezone_id text CHECK (timezone_id IS NULL OR length(btrim(timezone_id)) BETWEEN 1 AND 64),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX locations_order ON hocalist.locations(country_code, region, sort_order, label);

-- ---------------------------------------------------------------------------
-- Buyer requests
-- ---------------------------------------------------------------------------

CREATE TABLE hocalist.requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  buyer_profile_id uuid NOT NULL REFERENCES hocalist.memberships(id),
  kind text NOT NULL CHECK (kind IN ('product','service')),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 500),
  condition text CHECK (condition IS NULL OR condition IN ('new_item','used')),
  service_type text CHECK (service_type IS NULL OR service_type IN ('one_time','ongoing')),
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity BETWEEN 1 AND 99),
  budget_min_minor bigint CHECK (budget_min_minor IS NULL OR budget_min_minor >= 0),
  budget_max_minor bigint CHECK (budget_max_minor IS NULL OR budget_max_minor >= 0),
  currency_code text CHECK (currency_code IS NULL OR currency_code ~ '^[A-Z]{3}$'),
  accepts_higher_offers boolean NOT NULL DEFAULT false,
  category_id uuid REFERENCES hocalist.catalogue_categories(id),
  use_home_address boolean NOT NULL DEFAULT true,
  address_line1 text CHECK (address_line1 IS NULL OR length(address_line1) <= 300),
  address_line2 text CHECK (address_line2 IS NULL OR length(address_line2) <= 300),
  city text CHECK (city IS NULL OR length(city) <= 150),
  region text CHECK (region IS NULL OR length(region) <= 150),
  postal_code text CHECK (postal_code IS NULL OR length(postal_code) <= 40),
  country_code text CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$'),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('draft','active','closed','expired','cancelled')),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT request_kind_fields CHECK (
    (kind = 'product' AND condition IS NOT NULL AND service_type IS NULL)
    OR (kind = 'service' AND service_type IS NOT NULL AND condition IS NULL AND quantity = 1)
  ),
  CONSTRAINT request_budget_order CHECK (
    budget_min_minor IS NULL OR budget_max_minor IS NULL OR budget_max_minor >= budget_min_minor
  ),
  CONSTRAINT request_budget_currency CHECK (
    (budget_min_minor IS NULL AND budget_max_minor IS NULL) OR currency_code IS NOT NULL
  ),
  CONSTRAINT request_location_shape CHECK (
    use_home_address OR address_line1 IS NOT NULL OR address_line2 IS NOT NULL
    OR city IS NOT NULL OR region IS NOT NULL OR postal_code IS NOT NULL OR country_code IS NOT NULL
  )
);
CREATE INDEX requests_buyer_order ON hocalist.requests(buyer_user_id, created_at DESC, id DESC);
CREATE INDEX requests_leads_order ON hocalist.requests(status, created_at DESC, id DESC);
CREATE INDEX requests_category ON hocalist.requests(category_id);

-- ---------------------------------------------------------------------------
-- Seller offers and immutable revisions
-- ---------------------------------------------------------------------------

CREATE TABLE hocalist.offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES hocalist.requests(id),
  buyer_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  seller_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  seller_profile_id uuid NOT NULL REFERENCES hocalist.memberships(id),
  status text NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('submitted','selected','withdrawn','declined','completed','cancelled','expired')),
  accepted_revision_id uuid,
  conversation_id uuid,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT offer_participants_differ CHECK (buyer_user_id <> seller_user_id)
);
CREATE UNIQUE INDEX offers_one_active_per_seller
  ON hocalist.offers(request_id, seller_user_id) WHERE status IN ('submitted','selected');
CREATE INDEX offers_request_order ON hocalist.offers(request_id, created_at DESC, id DESC);
CREATE INDEX offers_seller_order ON hocalist.offers(seller_user_id, created_at DESC, id DESC);
CREATE INDEX offers_buyer_order ON hocalist.offers(buyer_user_id, created_at DESC, id DESC);

CREATE TABLE hocalist.offer_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id uuid NOT NULL REFERENCES hocalist.offers(id) ON DELETE CASCADE,
  sequence integer NOT NULL CHECK (sequence >= 1),
  price_minor bigint NOT NULL CHECK (price_minor > 0),
  currency_code text NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  message text NOT NULL DEFAULT '' CHECK (length(message) <= 1000),
  image_media_ids jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (
    jsonb_typeof(image_media_ids) = 'array' AND jsonb_array_length(image_media_ids) <= 10
  ),
  schedule_date date NOT NULL,
  schedule_time time NOT NULL,
  schedule_timezone text NOT NULL CHECK (length(btrim(schedule_timezone)) BETWEEN 1 AND 64),
  -- Explicit occurrence for a repeated local time (DST fall-back). NULL when the
  -- local time is unique. The server resolves and stores the offset and the
  -- UTC instant so both parties accept the same revision.
  schedule_occurrence text CHECK (schedule_occurrence IS NULL OR schedule_occurrence IN ('earlier','later')),
  schedule_offset_minutes integer NOT NULL CHECK (schedule_offset_minutes BETWEEN -900 AND 900),
  schedule_instant timestamptz NOT NULL,
  place_choice text NOT NULL CHECK (place_choice IN ('seller_business','buyer_location','specific_place')),
  place_label text CHECK (place_label IS NULL OR length(place_label) <= 200),
  place_address text CHECK (place_address IS NULL OR length(place_address) <= 300),
  place_id text CHECK (place_id IS NULL OR length(place_id) <= 200),
  status text NOT NULL DEFAULT 'proposed'
    CHECK (status IN ('proposed','accepted','superseded','rejected','withdrawn')),
  proposed_by_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (offer_id, sequence),
  CONSTRAINT offer_revision_place_shape CHECK (
    place_choice <> 'specific_place' OR place_label IS NOT NULL OR place_id IS NOT NULL
  )
);
CREATE INDEX offer_revisions_offer_order ON hocalist.offer_revisions(offer_id, sequence DESC);

-- ---------------------------------------------------------------------------
-- Seller Store listings (discovery catalogue only; item payment stays offline)
-- ---------------------------------------------------------------------------

CREATE TABLE hocalist.store_listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  seller_profile_id uuid NOT NULL REFERENCES hocalist.memberships(id),
  kind text NOT NULL CHECK (kind IN ('product','service')),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 1000),
  category_id uuid REFERENCES hocalist.catalogue_categories(id),
  category_label text NOT NULL DEFAULT '' CHECK (length(category_label) <= 120),
  price_label text NOT NULL CHECK (length(btrim(price_label)) BETWEEN 1 AND 80),
  service_area text NOT NULL DEFAULT '' CHECK (length(service_area) <= 200),
  availability text NOT NULL DEFAULT '' CHECK (length(availability) <= 200),
  image_media_ids jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (
    jsonb_typeof(image_media_ids) = 'array' AND jsonb_array_length(image_media_ids) <= 10
  ),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','paused','archived')),
  moderation_status text NOT NULL DEFAULT 'pending_review'
    CHECK (moderation_status IN ('pending_review','approved','rejected')),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX store_listings_seller_order ON hocalist.store_listings(seller_user_id, created_at DESC, id DESC);
CREATE INDEX store_listings_public_order ON hocalist.store_listings(seller_profile_id, created_at DESC, id DESC)
  WHERE status = 'active' AND moderation_status = 'approved';
CREATE INDEX store_listings_moderation ON hocalist.store_listings(moderation_status, created_at);

-- ---------------------------------------------------------------------------
-- Saved items and idempotency receipts
-- ---------------------------------------------------------------------------

CREATE TABLE hocalist.saved_items (
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  item_type text NOT NULL CHECK (item_type IN ('request','store_listing')),
  item_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, item_type, item_id)
);

CREATE TABLE hocalist.marketplace_receipts (
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  operation text NOT NULL,
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 128),
  request_hash text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation, idempotency_key)
);

ALTER TABLE hocalist.marketplace_plan_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.seller_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.platform_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.catalogue_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.catalogue_option_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.catalogue_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.offer_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.store_listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.saved_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.marketplace_receipts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON hocalist.marketplace_plan_limits, hocalist.seller_entitlements,
  hocalist.platform_admins, hocalist.catalogue_categories,
  hocalist.catalogue_option_groups, hocalist.catalogue_options,
  hocalist.locations, hocalist.requests, hocalist.offers,
  hocalist.offer_revisions, hocalist.store_listings, hocalist.saved_items,
  hocalist.marketplace_receipts
  FROM PUBLIC, anon, authenticated, service_role;

-- Defense in depth: inert while clients hold no table grants, but a future
-- reviewed grant cannot expose another identity's rows.
CREATE POLICY marketplace_request_owner_read ON hocalist.requests
  FOR SELECT TO authenticated USING (buyer_user_id = (SELECT auth.uid()));
CREATE POLICY marketplace_offer_participant_read ON hocalist.offers
  FOR SELECT TO authenticated USING (
    buyer_user_id = (SELECT auth.uid()) OR seller_user_id = (SELECT auth.uid())
  );
CREATE POLICY marketplace_listing_owner_read ON hocalist.store_listings
  FOR SELECT TO authenticated USING (seller_user_id = (SELECT auth.uid()));
CREATE POLICY marketplace_saved_owner_read ON hocalist.saved_items
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY marketplace_entitlement_owner_read ON hocalist.seller_entitlements
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

-- ---------------------------------------------------------------------------
-- Internal helpers (executable by no client or service role)
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.marketplace_assert_role(p_user uuid, p_role text)
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = p_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  SELECT id INTO v_id FROM hocalist.memberships
    WHERE user_id = p_user AND role = p_role AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'role_not_active' USING ERRCODE='42501';
  END IF;
  RETURN v_id;
END; $$;

CREATE FUNCTION hocalist.marketplace_is_admin(p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p_user IS NOT NULL
     AND EXISTS (SELECT 1 FROM hocalist.platform_admins WHERE user_id = p_user)
     AND NOT EXISTS (SELECT 1 FROM hocalist.memberships
                     WHERE user_id = p_user AND status IN ('restricted','disabled'));
$$;

CREATE FUNCTION hocalist.marketplace_assert_admin(p_user uuid)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF NOT hocalist.marketplace_is_admin(p_user) THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE='42501';
  END IF;
END; $$;

CREATE FUNCTION hocalist.marketplace_seller_plan(p_user uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce((
    SELECT e.plan_code FROM hocalist.seller_entitlements e
    WHERE e.user_id = p_user AND e.active
  ), 'free');
$$;

CREATE FUNCTION hocalist.marketplace_store_limit(p_user uuid)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT l.store_listing_limit
  FROM hocalist.marketplace_plan_limits l
  WHERE l.plan_code = hocalist.marketplace_seller_plan(p_user);
$$;

-- Strict list of uuid strings for media references. Storage upload is a
-- separate reviewed contract; these are references only.
CREATE FUNCTION hocalist.marketplace_uuid_array(p_value jsonb, p_field text)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_item jsonb;
  v_out jsonb := '[]'::jsonb;
BEGIN
  IF p_value IS NULL OR jsonb_typeof(p_value) <> 'array' THEN
    RAISE EXCEPTION 'invalid_field: %', p_field USING ERRCODE='22023';
  END IF;
  IF jsonb_array_length(p_value) > 10 THEN
    RAISE EXCEPTION 'invalid_field: %', p_field USING ERRCODE='22023';
  END IF;
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_value) LOOP
    IF jsonb_typeof(v_item) <> 'string'
       OR (v_item #>> '{}') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
      RAISE EXCEPTION 'invalid_field: %', p_field USING ERRCODE='22023';
    END IF;
    v_out := v_out || to_jsonb((v_item #>> '{}')::uuid);
  END LOOP;
  RETURN v_out;
END; $$;

CREATE FUNCTION hocalist.marketplace_optional_text(
  p_input jsonb, p_field text, p_max integer
) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v text;
BEGIN
  IF NOT (p_input ? p_field) OR jsonb_typeof(p_input->p_field) = 'null' THEN
    RETURN NULL;
  END IF;
  IF jsonb_typeof(p_input->p_field) <> 'string' THEN
    RAISE EXCEPTION 'invalid_field: %', p_field USING ERRCODE='22023';
  END IF;
  v := nullif(btrim(p_input->>p_field), '');
  IF v IS NOT NULL AND length(v) > p_max THEN
    RAISE EXCEPTION 'invalid_field: %', p_field USING ERRCODE='22023';
  END IF;
  RETURN v;
END; $$;

-- Validates and normalizes the complete editable request field set. Raises
-- invalid_field for one bad value; the client shows a typed validation issue.
CREATE FUNCTION hocalist.marketplace_normalize_request(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_allowed constant text[] := ARRAY[
    'request_id','expected_revision',
    'kind','title','description','condition','service_type','quantity',
    'budget_minimum_minor','budget_maximum_minor','currency_code',
    'accepts_higher_offers','category_id','use_home_address',
    'address_line1','address_line2','city','region','postal_code','country_code'];
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

  RETURN jsonb_build_object(
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

-- Named IANA zones only. Abbreviations (UTC, EST) and fixed-offset Etc/posix
-- names are rejected so a fixed offset can never masquerade as a real zone.
CREATE FUNCTION hocalist.marketplace_valid_timezone(p_zone text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p_zone IS NOT NULL
     AND p_zone ~ '^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)+$'
     AND p_zone NOT LIKE 'Etc/%'
     AND p_zone NOT LIKE 'posix/%'
     AND p_zone NOT LIKE 'SystemV/%'
     AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names n WHERE n.name = p_zone);
$$;

-- Exclusive next-local-day cutoff in the accepted zone: the start of the
-- calendar day after p_local_date, converted with the zone's own rules. Never a
-- fixed 24 hours and never device arithmetic.
CREATE FUNCTION hocalist.marketplace_next_local_day_start(
  p_local_date date,
  p_zone text
) RETURNS timestamptz
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_local_date IS NULL OR NOT hocalist.marketplace_valid_timezone(p_zone) THEN
    RAISE EXCEPTION 'invalid_field: timezone' USING ERRCODE='22023';
  END IF;
  RETURN ((p_local_date + 1)::timestamp) AT TIME ZONE p_zone;
END; $$;

CREATE FUNCTION hocalist.marketplace_normalize_offer(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_allowed constant text[] := ARRAY[
    'request_id','offer_id','expected_offer_revision',
    'price_minor','currency_code','message','image_media_ids',
    'schedule_date','schedule_time','schedule_timezone','schedule_occurrence',
    'place_choice','place_label','place_address','place_id'];
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
    'place_id', v_place_id
  );
END; $$;

CREATE FUNCTION hocalist.marketplace_normalize_listing(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_allowed constant text[] := ARRAY[
    'listing_id','expected_revision',
    'kind','title','description','category_id','price_label','service_area',
    'availability','image_media_ids','publish_intent'];
  v_kind text;
  v_title text;
  v_description text;
  v_category uuid;
  v_category_label text;
  v_category_scope text;
  v_price_label text;
  v_service_area text;
  v_availability text;
  v_images jsonb;
  v_intent text;
  v_field text;
BEGIN
  IF p_input IS NULL OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_listing' USING ERRCODE='22023';
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
  IF length(v_description) > 1000 THEN
    RAISE EXCEPTION 'invalid_field: description' USING ERRCODE='22023';
  END IF;

  IF jsonb_typeof(p_input->'category_id') <> 'string'
     OR (p_input->>'category_id') !~ '^[0-9a-fA-F-]{36}$' THEN
    RAISE EXCEPTION 'invalid_field: category_id' USING ERRCODE='22023';
  END IF;
  v_category := (p_input->>'category_id')::uuid;
  SELECT label, scope INTO v_category_label, v_category_scope
    FROM hocalist.catalogue_categories WHERE id = v_category AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_category' USING ERRCODE='22023';
  END IF;
  IF v_category_scope <> 'both' AND v_category_scope <> v_kind THEN
    RAISE EXCEPTION 'invalid_category' USING ERRCODE='22023';
  END IF;

  v_price_label := btrim(coalesce(p_input->>'price_label',''));
  IF length(v_price_label) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'invalid_field: price_label' USING ERRCODE='22023';
  END IF;
  v_service_area := hocalist.marketplace_optional_text(p_input, 'service_area', 200);
  v_availability := hocalist.marketplace_optional_text(p_input, 'availability', 200);
  v_images := hocalist.marketplace_uuid_array(coalesce(p_input->'image_media_ids','[]'::jsonb), 'image_media_ids');
  v_intent := coalesce(p_input->>'publish_intent','draft');
  IF v_intent NOT IN ('draft','publish') THEN
    RAISE EXCEPTION 'invalid_field: publish_intent' USING ERRCODE='22023';
  END IF;

  RETURN jsonb_build_object(
    'kind', v_kind,
    'title', v_title,
    'description', v_description,
    'category_id', v_category,
    'category_label', v_category_label,
    'price_label', v_price_label,
    'service_area', coalesce(v_service_area,''),
    'availability', coalesce(v_availability,''),
    'image_media_ids', v_images,
    'publish_intent', v_intent
  );
END; $$;

-- ---------------------------------------------------------------------------
-- JSON builders
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.marketplace_request_json(p_request uuid)
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
      'address_line1', r.address_line1,
      'address_line2', r.address_line2,
      'city', r.city,
      'region', r.region,
      'postal_code', r.postal_code,
      'country_code', r.country_code),
    'status', r.status,
    'revision', r.revision,
    'created_at', r.created_at,
    'updated_at', r.updated_at)
  FROM hocalist.requests r WHERE r.id = p_request;
$$;

-- Seller-visible projection: no address, no contacts, no other offers.
CREATE FUNCTION hocalist.marketplace_lead_json(p_request uuid)
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
    'published_at', r.created_at)
  FROM hocalist.requests r
  LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = r.buyer_profile_id
  WHERE r.id = p_request;
$$;

CREATE FUNCTION hocalist.marketplace_revision_json(p_revision uuid)
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
    'status', v.status,
    'proposed_by_user_id', v.proposed_by_user_id,
    'created_at', v.created_at)
  FROM hocalist.offer_revisions v WHERE v.id = p_revision;
$$;

CREATE FUNCTION hocalist.marketplace_offer_json(p_offer uuid)
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
    'revision', o.revision,
    'created_at', o.created_at,
    'updated_at', o.updated_at,
    'revisions', coalesce((
      SELECT jsonb_agg(hocalist.marketplace_revision_json(v.id) ORDER BY v.sequence)
      FROM hocalist.offer_revisions v WHERE v.offer_id = o.id
    ), '[]'::jsonb))
  FROM hocalist.offers o
  LEFT JOIN hocalist.role_profiles rp ON rp.membership_id = o.seller_profile_id
  WHERE o.id = p_offer;
$$;

CREATE FUNCTION hocalist.marketplace_listing_json(p_listing uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', l.id,
    'seller_profile_id', l.seller_profile_id,
    'seller_user_id', l.seller_user_id,
    'kind', l.kind,
    'title', l.title,
    'description', l.description,
    'category_id', l.category_id,
    'category_label', l.category_label,
    'price_label', l.price_label,
    'service_area', l.service_area,
    'availability', l.availability,
    'image_media_ids', l.image_media_ids,
    'status', l.status,
    'moderation_status', l.moderation_status,
    'revision', l.revision,
    'published_at', l.published_at,
    'created_at', l.created_at,
    'updated_at', l.updated_at)
  FROM hocalist.store_listings l WHERE l.id = p_listing;
$$;

-- Buyer-facing projection: no owner identity, publication or moderation state.
CREATE FUNCTION hocalist.marketplace_public_listing_json(p_listing uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', l.id,
    'seller_profile_id', l.seller_profile_id,
    'kind', l.kind,
    'title', l.title,
    'description', l.description,
    'category_id', l.category_id,
    'category_label', l.category_label,
    'price_label', l.price_label,
    'service_area', l.service_area,
    'availability', l.availability,
    'image_media_ids', l.image_media_ids,
    'published_at', l.published_at)
  FROM hocalist.store_listings l
  WHERE l.id = p_listing AND l.status = 'active' AND l.moderation_status = 'approved';
$$;

-- ---------------------------------------------------------------------------
-- Client read RPCs
-- ---------------------------------------------------------------------------

-- Active catalogue with nested option groups and options. Retired entries are
-- returned only to platform admins so historical records keep their meaning.
CREATE FUNCTION hocalist.marketplace_catalogue(
  p_scope text DEFAULT NULL,
  p_include_retired boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_include boolean;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_scope IS NOT NULL AND p_scope NOT IN ('product','service') THEN
    RAISE EXCEPTION 'invalid_scope' USING ERRCODE='22023';
  END IF;
  v_include := coalesce(p_include_retired, false) AND hocalist.marketplace_is_admin(v_user);
  RETURN jsonb_build_object('categories', coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id', c.id,
      'parent_id', c.parent_id,
      'label', c.label,
      'slug', c.slug,
      'scope', c.scope,
      'status', c.status,
      'sort_order', c.sort_order,
      'revision', c.revision,
      'created_at', c.created_at,
      'updated_at', c.updated_at,
      'groups', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'id', g.id,
          'category_id', g.category_id,
          'label', g.label,
          'selection_mode', g.selection_mode,
          'is_required', g.is_required,
          'status', g.status,
          'sort_order', g.sort_order,
          'revision', g.revision,
          'created_at', g.created_at,
          'updated_at', g.updated_at,
          'options', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
              'id', o.id,
              'group_id', o.group_id,
              'label', o.label,
              'status', o.status,
              'sort_order', o.sort_order,
              'revision', o.revision,
              'created_at', o.created_at,
              'updated_at', o.updated_at
            ) ORDER BY o.sort_order, o.label)
            FROM hocalist.catalogue_options o
            WHERE o.group_id = g.id AND (v_include OR o.status = 'active')
          ), '[]'::jsonb)
        ) ORDER BY g.sort_order, g.label)
        FROM hocalist.catalogue_option_groups g
        WHERE g.category_id = c.id AND (v_include OR g.status = 'active')
      ), '[]'::jsonb)
    ) ORDER BY c.sort_order, c.label)
    FROM hocalist.catalogue_categories c
    WHERE (v_include OR c.status = 'active')
      AND (p_scope IS NULL OR c.scope = 'both' OR c.scope = p_scope)
  ), '[]'::jsonb));
END; $$;

CREATE FUNCTION hocalist.marketplace_locations(
  p_country text DEFAULT NULL,
  p_include_retired boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_include boolean;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_country IS NOT NULL AND p_country !~ '^[A-Z]{2}$' THEN
    RAISE EXCEPTION 'invalid_field: country_code' USING ERRCODE='22023';
  END IF;
  v_include := coalesce(p_include_retired, false) AND hocalist.marketplace_is_admin(v_user);
  RETURN jsonb_build_object('items', coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id', l.id,
      'country_code', l.country_code,
      'region', l.region,
      'city', l.city,
      'label', l.label,
      'timezone_id', l.timezone_id,
      'status', l.status,
      'sort_order', l.sort_order,
      'revision', l.revision)
      ORDER BY l.country_code, l.region NULLS FIRST, l.sort_order, l.label)
    FROM hocalist.locations l
    WHERE (v_include OR l.status = 'active') AND (p_country IS NULL OR l.country_code = p_country)
  ), '[]'::jsonb));
END; $$;

-- Valid named IANA zones for meeting scheduling. Abbreviations and
-- fixed-offset names are excluded so a client cannot substitute an offset for
-- a real zone.
CREATE FUNCTION hocalist.marketplace_timezones()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('items', coalesce((
    SELECT jsonb_agg(n.name ORDER BY n.name)
    FROM pg_catalog.pg_timezone_names n
    WHERE hocalist.marketplace_valid_timezone(n.name)
  ), '[]'::jsonb));
END; $$;

-- One request. The owner gets the full record; a seller with an active
-- membership gets the lead projection; everyone else is denied.
CREATE FUNCTION hocalist.marketplace_request(p_request uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_owner uuid;
  v_status text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  SELECT buyer_user_id, status INTO v_owner, v_status FROM hocalist.requests WHERE id = p_request;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found' USING ERRCODE='P0002';
  END IF;
  IF v_owner = v_user THEN
    RETURN hocalist.marketplace_request_json(p_request);
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = v_user AND role = 'seller' AND status = 'active')
     AND v_status = 'active' THEN
    RETURN hocalist.marketplace_lead_json(p_request);
  END IF;
  RAISE EXCEPTION 'request_access_denied' USING ERRCODE='42501';
END; $$;

CREATE FUNCTION hocalist.marketplace_my_requests(
  p_status text DEFAULT NULL,
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
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('draft','active','closed','expired','cancelled') THEN
    RAISE EXCEPTION 'invalid_field: status' USING ERRCODE='22023';
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
           hocalist.marketplace_request_json(r.id) AS row_json
    FROM hocalist.requests r
    WHERE r.buyer_user_id = v_user
      AND (p_status IS NULL OR r.status = p_status)
      AND (p_cursor IS NULL OR
           ((extract(epoch FROM r.created_at) * 1000000)::bigint, r.id) < (v_cursor_micros, v_cursor_id))
    ORDER BY r.created_at DESC, r.id DESC
    LIMIT v_size
  ) rows;
  v_next := NULL;
  IF jsonb_array_length(v_items) = v_size THEN
    SELECT (extract(epoch FROM r.created_at) * 1000000)::bigint, r.id
      INTO v_last_micros, v_last_id
      FROM hocalist.requests r
      WHERE r.id = (v_items->-1->>'id')::uuid;
    IF EXISTS (
      SELECT 1 FROM hocalist.requests r
      WHERE r.buyer_user_id = v_user
        AND (p_status IS NULL OR r.status = p_status)
        AND ((extract(epoch FROM r.created_at) * 1000000)::bigint, r.id) < (v_last_micros, v_last_id)
    ) THEN
      v_next := v_last_micros::text || '|' || v_last_id::text;
    END IF;
  END IF;
  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

CREATE FUNCTION hocalist.marketplace_seller_leads(
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
      WHERE r.status = 'active' AND r.buyer_user_id <> v_user
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

-- Buyer sees every offer on the request; a seller sees only their own.
CREATE FUNCTION hocalist.marketplace_request_offers(
  p_request uuid,
  p_limit integer DEFAULT 50,
  p_cursor text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_owner uuid;
  v_is_seller boolean;
  v_size integer;
  v_cursor_micros bigint;
  v_cursor_id uuid;
  v_items jsonb;
  v_next text;
  v_last_micros bigint;
  v_last_id uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  SELECT buyer_user_id INTO v_owner FROM hocalist.requests WHERE id = p_request;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found' USING ERRCODE='P0002';
  END IF;
  v_is_seller := EXISTS (
    SELECT 1 FROM hocalist.memberships
    WHERE user_id = v_user AND role = 'seller' AND status = 'active');
  IF v_owner <> v_user AND NOT v_is_seller THEN
    RAISE EXCEPTION 'request_access_denied' USING ERRCODE='42501';
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
    SELECT o.id AS row_id,
           (extract(epoch FROM o.created_at) * 1000000)::bigint AS row_micros,
           hocalist.marketplace_offer_json(o.id) AS row_json
    FROM hocalist.offers o
    WHERE o.request_id = p_request
      AND (v_owner = v_user OR o.seller_user_id = v_user)
      AND (p_cursor IS NULL OR
           ((extract(epoch FROM o.created_at) * 1000000)::bigint, o.id) < (v_cursor_micros, v_cursor_id))
    ORDER BY o.created_at DESC, o.id DESC
    LIMIT v_size
  ) rows;
  v_next := NULL;
  IF jsonb_array_length(v_items) = v_size THEN
    SELECT (extract(epoch FROM o.created_at) * 1000000)::bigint, o.id
      INTO v_last_micros, v_last_id
      FROM hocalist.offers o WHERE o.id = (v_items->-1->>'id')::uuid;
    IF EXISTS (
      SELECT 1 FROM hocalist.offers o
      WHERE o.request_id = p_request
        AND (v_owner = v_user OR o.seller_user_id = v_user)
        AND ((extract(epoch FROM o.created_at) * 1000000)::bigint, o.id) < (v_last_micros, v_last_id)
    ) THEN
      v_next := v_last_micros::text || '|' || v_last_id::text;
    END IF;
  END IF;
  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

CREATE FUNCTION hocalist.marketplace_my_offers(
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
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
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
    SELECT o.id AS row_id,
           (extract(epoch FROM o.created_at) * 1000000)::bigint AS row_micros,
           hocalist.marketplace_offer_json(o.id) AS row_json
    FROM hocalist.offers o
    WHERE (o.seller_user_id = v_user OR o.buyer_user_id = v_user)
      AND (p_cursor IS NULL OR
           ((extract(epoch FROM o.created_at) * 1000000)::bigint, o.id) < (v_cursor_micros, v_cursor_id))
    ORDER BY o.created_at DESC, o.id DESC
    LIMIT v_size
  ) rows;
  v_next := NULL;
  IF jsonb_array_length(v_items) = v_size THEN
    SELECT (extract(epoch FROM o.created_at) * 1000000)::bigint, o.id
      INTO v_last_micros, v_last_id
      FROM hocalist.offers o WHERE o.id = (v_items->-1->>'id')::uuid;
    IF EXISTS (
      SELECT 1 FROM hocalist.offers o
      WHERE (o.seller_user_id = v_user OR o.buyer_user_id = v_user)
        AND ((extract(epoch FROM o.created_at) * 1000000)::bigint, o.id) < (v_last_micros, v_last_id)
    ) THEN
      v_next := v_last_micros::text || '|' || v_last_id::text;
    END IF;
  END IF;
  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

CREATE FUNCTION hocalist.marketplace_offer(p_offer uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_offer hocalist.offers%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_offer FROM hocalist.offers WHERE id = p_offer;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found' USING ERRCODE='P0002';
  END IF;
  IF v_offer.buyer_user_id <> v_user AND v_offer.seller_user_id <> v_user THEN
    RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
  END IF;
  RETURN hocalist.marketplace_offer_json(p_offer);
END; $$;

CREATE FUNCTION hocalist.marketplace_store_summary()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_plan text;
BEGIN
  PERFORM hocalist.marketplace_assert_role(v_user, 'seller');
  v_plan := hocalist.marketplace_seller_plan(v_user);
  RETURN jsonb_build_object(
    'draft_count', (SELECT count(*)::integer FROM hocalist.store_listings
                    WHERE seller_user_id = v_user AND status = 'draft'),
    'active_count', (SELECT count(*)::integer FROM hocalist.store_listings
                     WHERE seller_user_id = v_user AND status = 'active'),
    'paused_count', (SELECT count(*)::integer FROM hocalist.store_listings
                     WHERE seller_user_id = v_user AND status = 'paused'),
    'archived_count', (SELECT count(*)::integer FROM hocalist.store_listings
                       WHERE seller_user_id = v_user AND status = 'archived'),
    'plan_code', v_plan,
    'store_listing_limit', hocalist.marketplace_store_limit(v_user));
END; $$;

CREATE FUNCTION hocalist.marketplace_my_store_listings(
  p_kind text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_query text DEFAULT NULL,
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
  IF p_status IS NOT NULL AND p_status NOT IN ('draft','active','paused','archived') THEN
    RAISE EXCEPTION 'invalid_field: status' USING ERRCODE='22023';
  END IF;
  IF p_query IS NOT NULL AND length(btrim(p_query)) > 160 THEN
    RAISE EXCEPTION 'invalid_field: query' USING ERRCODE='22023';
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
    SELECT l.id AS row_id,
           (extract(epoch FROM l.created_at) * 1000000)::bigint AS row_micros,
           hocalist.marketplace_listing_json(l.id) AS row_json
    FROM hocalist.store_listings l
    WHERE l.seller_user_id = v_user
      AND (p_kind IS NULL OR l.kind = p_kind)
      AND (p_status IS NULL OR l.status = p_status)
      AND (p_query IS NULL OR l.title ILIKE '%' || btrim(p_query) || '%'
           OR l.description ILIKE '%' || btrim(p_query) || '%')
      AND (p_cursor IS NULL OR
           ((extract(epoch FROM l.created_at) * 1000000)::bigint, l.id) < (v_cursor_micros, v_cursor_id))
    ORDER BY l.created_at DESC, l.id DESC
    LIMIT v_size
  ) rows;
  v_next := NULL;
  IF jsonb_array_length(v_items) = v_size THEN
    SELECT (extract(epoch FROM l.created_at) * 1000000)::bigint, l.id
      INTO v_last_micros, v_last_id
      FROM hocalist.store_listings l WHERE l.id = (v_items->-1->>'id')::uuid;
    IF EXISTS (
      SELECT 1 FROM hocalist.store_listings l
      WHERE l.seller_user_id = v_user
        AND (p_kind IS NULL OR l.kind = p_kind)
        AND (p_status IS NULL OR l.status = p_status)
        AND (p_query IS NULL OR l.title ILIKE '%' || btrim(p_query) || '%'
             OR l.description ILIKE '%' || btrim(p_query) || '%')
        AND ((extract(epoch FROM l.created_at) * 1000000)::bigint, l.id) < (v_last_micros, v_last_id)
    ) THEN
      v_next := v_last_micros::text || '|' || v_last_id::text;
    END IF;
  END IF;
  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

-- Owner sees the full listing; anyone else sees only a published projection.
CREATE FUNCTION hocalist.marketplace_store_listing(p_listing uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_owner uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  SELECT seller_user_id INTO v_owner FROM hocalist.store_listings WHERE id = p_listing;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'listing_not_found' USING ERRCODE='P0002';
  END IF;
  IF v_owner = v_user THEN
    RETURN hocalist.marketplace_listing_json(p_listing);
  END IF;
  IF hocalist.marketplace_public_listing_json(p_listing) IS NULL THEN
    RAISE EXCEPTION 'listing_access_denied' USING ERRCODE='42501';
  END IF;
  RETURN hocalist.marketplace_public_listing_json(p_listing);
END; $$;

CREATE FUNCTION hocalist.marketplace_public_store_listings(
  p_seller_profile uuid,
  p_kind text DEFAULT NULL,
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
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_kind IS NOT NULL AND p_kind NOT IN ('product','service') THEN
    RAISE EXCEPTION 'invalid_field: kind' USING ERRCODE='22023';
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
    SELECT l.id AS row_id,
           (extract(epoch FROM l.created_at) * 1000000)::bigint AS row_micros,
           hocalist.marketplace_public_listing_json(l.id) AS row_json
    FROM hocalist.store_listings l
    WHERE l.seller_profile_id = p_seller_profile
      AND l.status = 'active' AND l.moderation_status = 'approved'
      AND (p_kind IS NULL OR l.kind = p_kind)
      AND (p_cursor IS NULL OR
           ((extract(epoch FROM l.created_at) * 1000000)::bigint, l.id) < (v_cursor_micros, v_cursor_id))
    ORDER BY l.created_at DESC, l.id DESC
    LIMIT v_size
  ) rows;
  v_next := NULL;
  IF jsonb_array_length(v_items) = v_size THEN
    SELECT (extract(epoch FROM l.created_at) * 1000000)::bigint, l.id
      INTO v_last_micros, v_last_id
      FROM hocalist.store_listings l WHERE l.id = (v_items->-1->>'id')::uuid;
    IF EXISTS (
      SELECT 1 FROM hocalist.store_listings l
      WHERE l.seller_profile_id = p_seller_profile
        AND l.status = 'active' AND l.moderation_status = 'approved'
        AND (p_kind IS NULL OR l.kind = p_kind)
        AND ((extract(epoch FROM l.created_at) * 1000000)::bigint, l.id) < (v_last_micros, v_last_id)
    ) THEN
      v_next := v_last_micros::text || '|' || v_last_id::text;
    END IF;
  END IF;
  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

CREATE FUNCTION hocalist.marketplace_saved_items()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('items', coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'item_type', s.item_type,
      'item_id', s.item_id,
      'created_at', s.created_at)
      ORDER BY s.created_at DESC, s.item_id)
    FROM hocalist.saved_items s WHERE s.user_id = v_user
  ), '[]'::jsonb));
END; $$;

-- ---------------------------------------------------------------------------
-- Client command RPC
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.marketplace_command(p_operation text, p_key text, p_input jsonb)
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
    'offer.submit','offer.revise','offer.withdraw','offer.select',
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
  IF p_operation IN ('offer.revise','offer.withdraw','offer.select')
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
      category_id, use_home_address, address_line1, address_line2, city, region, postal_code, country_code)
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
      v_norm->>'city', v_norm->>'region', v_norm->>'postal_code', v_norm->>'country_code')
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
    -- the lock target, so two buyer sessions cannot both observe "no selected
    -- offer" and then select different offers. This atomically enforces the
    -- current conservative single-acceptance policy; it does not decide the
    -- unresolved multi-seller business rule.
    SELECT * INTO v_request FROM hocalist.requests WHERE id = v_offer.request_id FOR UPDATE;
    IF v_request.status <> 'active' THEN
      RAISE EXCEPTION 'request_not_open' USING ERRCODE='P0001';
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
      IF EXISTS (
        SELECT 1 FROM hocalist.offers other
        WHERE other.request_id = v_offer.request_id AND other.status = 'selected' AND other.id <> v_id
      ) THEN
        RAISE EXCEPTION 'selection_policy_pending' USING ERRCODE='P0001';
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
      v_result := hocalist.marketplace_offer_json(v_id);
    END IF;

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
-- Admin command RPC (platform admins only; no client can grant the role)
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.marketplace_admin_command(p_operation text, p_key text, p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_hash text;
  v_receipt hocalist.marketplace_receipts%ROWTYPE;
  v_result jsonb;
  v_id uuid;
  v_expected bigint;
  v_label text;
  v_field text;
  v_allowed text[];
BEGIN
  PERFORM hocalist.marketplace_assert_admin(v_user);
  IF p_operation IS NULL OR p_operation NOT IN (
    'category.create','category.update','group.create','group.update',
    'option.create','option.update','entry.set_status',
    'location.create','location.update','location.set_status',
    'plan_limit.update','store.set_moderation') THEN
    RAISE EXCEPTION 'invalid_operation' USING ERRCODE='22023';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
     OR octet_length(p_input::text) > 16384 THEN
    RAISE EXCEPTION 'invalid_command' USING ERRCODE='22023';
  END IF;
  IF p_operation NOT IN ('category.create','group.create','option.create','location.create')
     AND (jsonb_typeof(p_input->'expected_revision') <> 'number'
          OR (p_input->>'expected_revision') !~ '^[1-9][0-9]{0,17}$') THEN
    RAISE EXCEPTION 'invalid_field: expected_revision' USING ERRCODE='22023';
  END IF;
  -- Same retry serialization as the client command path.
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

  IF p_operation = 'category.create' THEN
    v_allowed := ARRAY['parent_id','label','slug','scope','sort_order'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    v_label := btrim(coalesce(p_input->>'label',''));
    IF length(v_label) NOT BETWEEN 1 AND 120 THEN
      RAISE EXCEPTION 'invalid_field: label' USING ERRCODE='22023';
    END IF;
    IF coalesce(p_input->>'scope','') NOT IN ('product','service','both') THEN
      RAISE EXCEPTION 'invalid_field: scope' USING ERRCODE='22023';
    END IF;
    IF p_input ? 'parent_id' AND jsonb_typeof(p_input->'parent_id') <> 'null' THEN
      IF jsonb_typeof(p_input->'parent_id') <> 'string'
         OR NOT EXISTS (SELECT 1 FROM hocalist.catalogue_categories WHERE id = (p_input->>'parent_id')::uuid) THEN
        RAISE EXCEPTION 'invalid_field: parent_id' USING ERRCODE='22023';
      END IF;
    END IF;
    IF p_input ? 'slug' AND jsonb_typeof(p_input->'slug') <> 'null' THEN
      IF jsonb_typeof(p_input->'slug') <> 'string'
         OR (p_input->>'slug') !~ '^[a-z0-9]+(-[a-z0-9]+)*$' THEN
        RAISE EXCEPTION 'invalid_field: slug' USING ERRCODE='22023';
      END IF;
    END IF;
    INSERT INTO hocalist.catalogue_categories(parent_id, label, slug, scope, sort_order)
    VALUES (
      CASE WHEN p_input ? 'parent_id' AND jsonb_typeof(p_input->'parent_id') <> 'null'
           THEN (p_input->>'parent_id')::uuid ELSE NULL END,
      v_label,
      CASE WHEN p_input ? 'slug' AND jsonb_typeof(p_input->'slug') <> 'null'
           THEN p_input->>'slug' ELSE NULL END,
      p_input->>'scope',
      coalesce((p_input->>'sort_order')::integer, 0))
    RETURNING id INTO v_id;
    v_result := jsonb_build_object('id', v_id);

  ELSIF p_operation = 'category.update' THEN
    v_allowed := ARRAY['category_id','expected_revision','parent_id','label','slug','scope','sort_order'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    v_id := (p_input->>'category_id')::uuid;
    v_expected := (p_input->>'expected_revision')::bigint;
    v_label := btrim(coalesce(p_input->>'label',''));
    IF length(v_label) NOT BETWEEN 1 AND 120
       OR coalesce(p_input->>'scope','') NOT IN ('product','service','both') THEN
      RAISE EXCEPTION 'invalid_field: label' USING ERRCODE='22023';
    END IF;
    IF p_input ? 'parent_id' AND jsonb_typeof(p_input->'parent_id') <> 'null' THEN
      IF (p_input->>'parent_id')::uuid = v_id
         OR NOT EXISTS (SELECT 1 FROM hocalist.catalogue_categories WHERE id = (p_input->>'parent_id')::uuid) THEN
        RAISE EXCEPTION 'invalid_field: parent_id' USING ERRCODE='22023';
      END IF;
    END IF;
    UPDATE hocalist.catalogue_categories SET
      parent_id = CASE WHEN p_input ? 'parent_id' AND jsonb_typeof(p_input->'parent_id') <> 'null'
                       THEN (p_input->>'parent_id')::uuid ELSE NULL END,
      label = v_label,
      slug = CASE WHEN p_input ? 'slug' AND jsonb_typeof(p_input->'slug') <> 'null'
                  THEN p_input->>'slug' ELSE NULL END,
      scope = p_input->>'scope',
      sort_order = coalesce((p_input->>'sort_order')::integer, 0),
      revision = revision + 1, updated_at = now()
    WHERE id = v_id AND revision = v_expected
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := jsonb_build_object('id', v_id);

  ELSIF p_operation = 'group.create' THEN
    v_allowed := ARRAY['category_id','label','selection_mode','is_required','sort_order'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    v_label := btrim(coalesce(p_input->>'label',''));
    IF length(v_label) NOT BETWEEN 1 AND 120 THEN
      RAISE EXCEPTION 'invalid_field: label' USING ERRCODE='22023';
    END IF;
    IF coalesce(p_input->>'selection_mode','') NOT IN ('single','multiple') THEN
      RAISE EXCEPTION 'invalid_field: selection_mode' USING ERRCODE='22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM hocalist.catalogue_categories
                   WHERE id = (p_input->>'category_id')::uuid) THEN
      RAISE EXCEPTION 'invalid_field: category_id' USING ERRCODE='22023';
    END IF;
    INSERT INTO hocalist.catalogue_option_groups(category_id, label, selection_mode, is_required, sort_order)
    VALUES ((p_input->>'category_id')::uuid, v_label, p_input->>'selection_mode',
            coalesce((p_input->>'is_required')::boolean, false),
            coalesce((p_input->>'sort_order')::integer, 0))
    RETURNING id INTO v_id;
    v_result := jsonb_build_object('id', v_id);

  ELSIF p_operation = 'group.update' THEN
    v_allowed := ARRAY['group_id','expected_revision','label','selection_mode','is_required','sort_order'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    v_id := (p_input->>'group_id')::uuid;
    v_expected := (p_input->>'expected_revision')::bigint;
    v_label := btrim(coalesce(p_input->>'label',''));
    IF length(v_label) NOT BETWEEN 1 AND 120
       OR coalesce(p_input->>'selection_mode','') NOT IN ('single','multiple') THEN
      RAISE EXCEPTION 'invalid_field: label' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.catalogue_option_groups SET
      label = v_label,
      selection_mode = p_input->>'selection_mode',
      is_required = coalesce((p_input->>'is_required')::boolean, false),
      sort_order = coalesce((p_input->>'sort_order')::integer, 0),
      revision = revision + 1, updated_at = now()
    WHERE id = v_id AND revision = v_expected
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := jsonb_build_object('id', v_id);

  ELSIF p_operation = 'option.create' THEN
    v_allowed := ARRAY['group_id','label','sort_order'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    v_label := btrim(coalesce(p_input->>'label',''));
    IF length(v_label) NOT BETWEEN 1 AND 120 THEN
      RAISE EXCEPTION 'invalid_field: label' USING ERRCODE='22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM hocalist.catalogue_option_groups
                   WHERE id = (p_input->>'group_id')::uuid) THEN
      RAISE EXCEPTION 'invalid_field: group_id' USING ERRCODE='22023';
    END IF;
    INSERT INTO hocalist.catalogue_options(group_id, label, sort_order)
    VALUES ((p_input->>'group_id')::uuid, v_label, coalesce((p_input->>'sort_order')::integer, 0))
    RETURNING id INTO v_id;
    v_result := jsonb_build_object('id', v_id);

  ELSIF p_operation = 'option.update' THEN
    v_allowed := ARRAY['option_id','expected_revision','label','sort_order'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    v_id := (p_input->>'option_id')::uuid;
    v_expected := (p_input->>'expected_revision')::bigint;
    v_label := btrim(coalesce(p_input->>'label',''));
    IF length(v_label) NOT BETWEEN 1 AND 120 THEN
      RAISE EXCEPTION 'invalid_field: label' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.catalogue_options SET
      label = v_label,
      sort_order = coalesce((p_input->>'sort_order')::integer, 0),
      revision = revision + 1, updated_at = now()
    WHERE id = v_id AND revision = v_expected
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := jsonb_build_object('id', v_id);

  ELSIF p_operation = 'entry.set_status' THEN
    v_allowed := ARRAY['entry_type','entry_id','expected_revision','status'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    IF coalesce(p_input->>'entry_type','') NOT IN ('category','option_group','option')
       OR coalesce(p_input->>'status','') NOT IN ('active','retired') THEN
      RAISE EXCEPTION 'invalid_field: entry_type' USING ERRCODE='22023';
    END IF;
    v_id := (p_input->>'entry_id')::uuid;
    v_expected := (p_input->>'expected_revision')::bigint;
    IF p_input->>'entry_type' = 'category' THEN
      UPDATE hocalist.catalogue_categories SET status = p_input->>'status',
        revision = revision + 1, updated_at = now()
        WHERE id = v_id AND revision = v_expected RETURNING id INTO v_id;
    ELSIF p_input->>'entry_type' = 'option_group' THEN
      UPDATE hocalist.catalogue_option_groups SET status = p_input->>'status',
        revision = revision + 1, updated_at = now()
        WHERE id = v_id AND revision = v_expected RETURNING id INTO v_id;
    ELSE
      UPDATE hocalist.catalogue_options SET status = p_input->>'status',
        revision = revision + 1, updated_at = now()
        WHERE id = v_id AND revision = v_expected RETURNING id INTO v_id;
    END IF;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := jsonb_build_object('entry_type', p_input->>'entry_type', 'id', v_id, 'status', p_input->>'status');

  ELSIF p_operation = 'location.create' THEN
    v_allowed := ARRAY['country_code','region','city','label','timezone_id','sort_order'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    IF coalesce(p_input->>'country_code','') !~ '^[A-Z]{2}$'
       OR length(btrim(coalesce(p_input->>'label',''))) NOT BETWEEN 1 AND 200 THEN
      RAISE EXCEPTION 'invalid_field: country_code' USING ERRCODE='22023';
    END IF;
    IF p_input ? 'timezone_id' AND jsonb_typeof(p_input->'timezone_id') <> 'null'
       AND NOT hocalist.marketplace_valid_timezone(btrim(p_input->>'timezone_id')) THEN
      RAISE EXCEPTION 'invalid_field: timezone_id' USING ERRCODE='22023';
    END IF;
    INSERT INTO hocalist.locations(country_code, region, city, label, timezone_id, sort_order)
    VALUES (p_input->>'country_code',
            nullif(btrim(coalesce(p_input->>'region','')),''),
            nullif(btrim(coalesce(p_input->>'city','')),''),
            btrim(p_input->>'label'),
            nullif(btrim(coalesce(p_input->>'timezone_id','')),''),
            coalesce((p_input->>'sort_order')::integer, 0))
    RETURNING id INTO v_id;
    v_result := jsonb_build_object('id', v_id);

  ELSIF p_operation = 'location.update' THEN
    v_allowed := ARRAY['location_id','expected_revision','country_code','region','city','label','timezone_id','sort_order'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    v_id := (p_input->>'location_id')::uuid;
    v_expected := (p_input->>'expected_revision')::bigint;
    IF coalesce(p_input->>'country_code','') !~ '^[A-Z]{2}$'
       OR length(btrim(coalesce(p_input->>'label',''))) NOT BETWEEN 1 AND 200 THEN
      RAISE EXCEPTION 'invalid_field: country_code' USING ERRCODE='22023';
    END IF;
    IF p_input ? 'timezone_id' AND jsonb_typeof(p_input->'timezone_id') <> 'null'
       AND NOT hocalist.marketplace_valid_timezone(btrim(p_input->>'timezone_id')) THEN
      RAISE EXCEPTION 'invalid_field: timezone_id' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.locations SET
      country_code = p_input->>'country_code',
      region = nullif(btrim(coalesce(p_input->>'region','')),''),
      city = nullif(btrim(coalesce(p_input->>'city','')),''),
      label = btrim(p_input->>'label'),
      timezone_id = CASE WHEN p_input ? 'timezone_id'
                         THEN nullif(btrim(coalesce(p_input->>'timezone_id','')),'')
                         ELSE timezone_id END,
      sort_order = coalesce((p_input->>'sort_order')::integer, 0),
      revision = revision + 1, updated_at = now()
    WHERE id = v_id AND revision = v_expected
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := jsonb_build_object('id', v_id);

  ELSIF p_operation = 'location.set_status' THEN
    v_allowed := ARRAY['location_id','expected_revision','status'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    v_id := (p_input->>'location_id')::uuid;
    v_expected := (p_input->>'expected_revision')::bigint;
    IF coalesce(p_input->>'status','') NOT IN ('active','retired') THEN
      RAISE EXCEPTION 'invalid_field: status' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.locations SET status = p_input->>'status',
      revision = revision + 1, updated_at = now()
    WHERE id = v_id AND revision = v_expected
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := jsonb_build_object('id', v_id, 'status', p_input->>'status');

  ELSIF p_operation = 'plan_limit.update' THEN
    v_allowed := ARRAY['plan_code','expected_revision','store_listing_limit'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    IF coalesce(p_input->>'plan_code','') NOT IN ('free','pro','elite')
       OR (p_input->>'store_listing_limit') !~ '^[0-9]{1,6}$' THEN
      RAISE EXCEPTION 'invalid_field: plan_code' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_revision')::bigint;
    UPDATE hocalist.marketplace_plan_limits SET
      store_listing_limit = (p_input->>'store_listing_limit')::integer,
      revision = revision + 1, updated_at = now()
    WHERE plan_code = p_input->>'plan_code' AND revision = v_expected
    RETURNING plan_code INTO v_label;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := jsonb_build_object('plan_code', p_input->>'plan_code');

  ELSE -- store.set_moderation
    v_allowed := ARRAY['listing_id','expected_revision','moderation_status'];
    FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
      RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
    END LOOP;
    v_id := (p_input->>'listing_id')::uuid;
    v_expected := (p_input->>'expected_revision')::bigint;
    IF coalesce(p_input->>'moderation_status','') NOT IN ('pending_review','approved','rejected') THEN
      RAISE EXCEPTION 'invalid_field: moderation_status' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.store_listings SET
      moderation_status = p_input->>'moderation_status',
      revision = revision + 1, updated_at = now()
    WHERE id = v_id AND revision = v_expected
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    v_result := hocalist.marketplace_listing_json(v_id);
  END IF;

  INSERT INTO hocalist.marketplace_receipts(user_id, operation, idempotency_key, request_hash, result)
    VALUES (v_user, p_operation, p_key, v_hash, v_result);
  RETURN v_result;
END; $$;

-- Admin moderation queue: listings waiting for a decision.
CREATE FUNCTION hocalist.marketplace_admin_moderation_queue(
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
  PERFORM hocalist.marketplace_assert_admin(v_user);
  v_size := greatest(1, least(coalesce(p_limit, 50), 100));
  IF p_cursor IS NOT NULL THEN
    BEGIN
      v_cursor_micros := split_part(p_cursor, '|', 1)::bigint;
      v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023';
    END;
  END IF;
  SELECT coalesce(jsonb_agg(row_json ORDER BY row_micros ASC, row_id), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT l.id AS row_id,
           (extract(epoch FROM l.created_at) * 1000000)::bigint AS row_micros,
           hocalist.marketplace_listing_json(l.id) AS row_json
    FROM hocalist.store_listings l
    WHERE l.moderation_status = 'pending_review'
      AND (p_cursor IS NULL OR
           ((extract(epoch FROM l.created_at) * 1000000)::bigint, l.id) > (v_cursor_micros, v_cursor_id))
    ORDER BY l.created_at ASC, l.id
    LIMIT v_size
  ) rows;
  v_next := NULL;
  IF jsonb_array_length(v_items) = v_size THEN
    SELECT (extract(epoch FROM l.created_at) * 1000000)::bigint, l.id
      INTO v_last_micros, v_last_id
      FROM hocalist.store_listings l WHERE l.id = (v_items->-1->>'id')::uuid;
    IF EXISTS (
      SELECT 1 FROM hocalist.store_listings l
      WHERE l.moderation_status = 'pending_review'
        AND ((extract(epoch FROM l.created_at) * 1000000)::bigint, l.id) > (v_last_micros, v_last_id)
    ) THEN
      v_next := v_last_micros::text || '|' || v_last_id::text;
    END IF;
  END IF;
  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION
  hocalist.marketplace_assert_role(uuid,text),
  hocalist.marketplace_is_admin(uuid),
  hocalist.marketplace_assert_admin(uuid),
  hocalist.marketplace_seller_plan(uuid),
  hocalist.marketplace_store_limit(uuid),
  hocalist.marketplace_uuid_array(jsonb,text),
  hocalist.marketplace_optional_text(jsonb,text,integer),
  hocalist.marketplace_valid_timezone(text),
  hocalist.marketplace_next_local_day_start(date,text),
  hocalist.marketplace_normalize_request(jsonb),
  hocalist.marketplace_normalize_offer(jsonb),
  hocalist.marketplace_normalize_listing(jsonb),
  hocalist.marketplace_request_json(uuid),
  hocalist.marketplace_lead_json(uuid),
  hocalist.marketplace_revision_json(uuid),
  hocalist.marketplace_offer_json(uuid),
  hocalist.marketplace_listing_json(uuid),
  hocalist.marketplace_public_listing_json(uuid),
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

GRANT EXECUTE ON FUNCTION
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
  TO authenticated;

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
COMMIT;

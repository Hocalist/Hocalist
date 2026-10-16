-- Seller profile categories backed by real catalogue ids.
--
-- A seller selects active catalogue categories for the seller membership.
-- Retired categories stay readable for existing selections and are only
-- dropped by an explicit replacement; a new selection must be active. The
-- update shares the role_profiles revision, so stale editors receive
-- revision_conflict instead of overwriting.
--
-- Dependencies (explicit): account 003/004 and marketplace 020 catalogue.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.memberships') IS NULL
     OR to_regclass('hocalist.role_profiles') IS NULL
     OR to_regclass('hocalist.command_receipts') IS NULL
     OR to_regclass('hocalist.catalogue_categories') IS NULL THEN
    RAISE EXCEPTION 'profile categories require account 003/004 and marketplace 020';
  END IF;
  IF to_regclass('hocalist.role_profile_categories') IS NOT NULL THEN
    RAISE EXCEPTION 'profile categories already installed';
  END IF;
END $guard$;

CREATE TABLE hocalist.role_profile_categories (
  membership_id uuid NOT NULL REFERENCES hocalist.memberships(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES hocalist.catalogue_categories(id),
  added_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (membership_id, category_id)
);
CREATE INDEX role_profile_categories_category ON hocalist.role_profile_categories(category_id);

ALTER TABLE hocalist.role_profile_categories ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.role_profile_categories
  FROM PUBLIC, anon, authenticated, service_role;
-- Owner and buyer reads go through the signed functions below; no direct
-- client table access is granted.

CREATE FUNCTION hocalist.profile_categories_validate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM hocalist.memberships m
    WHERE m.id = NEW.membership_id AND m.role = 'seller') THEN
    RAISE EXCEPTION 'seller_membership_required' USING ERRCODE='22023';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER profile_categories_validate_membership
  BEFORE INSERT OR UPDATE ON hocalist.role_profile_categories
  FOR EACH ROW EXECUTE FUNCTION hocalist.profile_categories_validate();

-- Seller-only selection read. `available` is the current active catalogue;
-- `selected` keeps retired entries visible with selectable=false.
CREATE FUNCTION hocalist.seller_profile_categories()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  v_membership hocalist.memberships%ROWTYPE;
  v_revision bigint;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_membership FROM hocalist.memberships
    WHERE user_id=u AND role='seller' AND status='active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'seller_membership_required' USING ERRCODE='42501';
  END IF;
  SELECT revision INTO v_revision FROM hocalist.role_profiles
    WHERE membership_id=v_membership.id;
  IF v_revision IS NULL THEN
    RAISE EXCEPTION 'profile_required' USING ERRCODE='P0002';
  END IF;
  RETURN jsonb_build_object(
    'membership_id',v_membership.id,
    'revision',v_revision,
    'selected',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',c.id,'label',c.label,'slug',c.slug,'scope',c.scope,
      'status',c.status,'selectable',c.status='active','sort_order',c.sort_order)
      ORDER BY c.sort_order,c.label)
      FROM hocalist.role_profile_categories rpc
      JOIN hocalist.catalogue_categories c ON c.id=rpc.category_id
      WHERE rpc.membership_id=v_membership.id),'[]'::jsonb),
    'available',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',c.id,'label',c.label,'slug',c.slug,'scope',c.scope,
      'status',c.status,'sort_order',c.sort_order)
      ORDER BY c.sort_order,c.label)
      FROM hocalist.catalogue_categories c WHERE c.status='active'),'[]'::jsonb)
  );
END $$;

-- Buyer-visible projection for one seller membership. Retired categories stay
-- readable; restricted sellers are never projected.
CREATE FUNCTION hocalist.member_seller_categories(p_membership uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  v_target_user uuid;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_membership IS NULL THEN RAISE EXCEPTION 'invalid_field: membership' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status='active')
     OR EXISTS (SELECT 1 FROM hocalist.memberships
                WHERE user_id=u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'membership_required' USING ERRCODE='42501';
  END IF;
  SELECT user_id INTO v_target_user FROM hocalist.memberships
    WHERE id=p_membership AND role='seller' AND status='active';
  IF NOT FOUND THEN RAISE EXCEPTION 'profile_not_found' USING ERRCODE='P0002'; END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id=v_target_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'profile_not_found' USING ERRCODE='P0002';
  END IF;
  RETURN jsonb_build_object(
    'membership_id',p_membership,
    'categories',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',c.id,'label',c.label,'status',c.status,'scope',c.scope)
      ORDER BY c.sort_order,c.label)
      FROM hocalist.role_profile_categories rpc
      JOIN hocalist.catalogue_categories c ON c.id=rpc.category_id
      WHERE rpc.membership_id=p_membership),'[]'::jsonb)
  );
END $$;

CREATE FUNCTION hocalist.profile_categories_update(
  p_key text, p_expected_revision bigint, p_category_ids jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.command_receipts%ROWTYPE;
  v_membership hocalist.memberships%ROWTYPE;
  v_profile hocalist.role_profiles%ROWTYPE;
  v_ids uuid[];
  v_item jsonb;
  v_retired uuid[];
  v_unknown uuid[];
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_expected_revision IS NULL OR p_expected_revision < 1
     OR p_category_ids IS NULL OR jsonb_typeof(p_category_ids)<>'array'
     OR jsonb_array_length(p_category_ids) > 50 THEN
    RAISE EXCEPTION 'invalid_category_selection' USING ERRCODE='22023';
  END IF;
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_category_ids) LOOP
    IF jsonb_typeof(v_item)<>'string' THEN
      RAISE EXCEPTION 'invalid_category_selection' USING ERRCODE='22023';
    END IF;
  END LOOP;
  v_ids := ARRAY(SELECT (jsonb_array_elements_text(p_category_ids))::uuid);
  IF (SELECT count(*) FROM unnest(v_ids)) <> (SELECT count(DISTINCT x) FROM unnest(v_ids) x) THEN
    RAISE EXCEPTION 'duplicate_category' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':categories:'||p_key,0));
  -- A restriction on any role cannot be bypassed through category editing.
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id=u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_membership FROM hocalist.memberships
    WHERE user_id=u AND role='seller' AND status='active';
  IF NOT FOUND THEN RAISE EXCEPTION 'seller_membership_required' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_profile FROM hocalist.role_profiles
    WHERE membership_id=v_membership.id;
  IF NOT FOUND THEN RAISE EXCEPTION 'profile_required' USING ERRCODE='P0002'; END IF;
  h := encode(sha256(convert_to(
    p_expected_revision::text||':'||p_category_ids::text,'UTF8')),'hex');
  SELECT * INTO receipt FROM hocalist.command_receipts
    WHERE user_id=u AND operation='profile.categories' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT coalesce(array_agg(x),ARRAY[]::uuid[]) INTO v_unknown
  FROM (SELECT x FROM unnest(v_ids) x
        WHERE NOT EXISTS (SELECT 1 FROM hocalist.catalogue_categories c WHERE c.id=x)) s(x);
  IF coalesce(array_length(v_unknown,1),0) > 0 THEN
    RAISE EXCEPTION 'unknown_category' USING ERRCODE='P0002';
  END IF;
  -- A newly selected category must be active; an already selected retired
  -- category may stay until the seller explicitly replaces it.
  SELECT coalesce(array_agg(x),ARRAY[]::uuid[]) INTO v_retired
  FROM (SELECT x FROM unnest(v_ids) x
        WHERE NOT EXISTS (SELECT 1 FROM hocalist.role_profile_categories rpc
                          WHERE rpc.membership_id=v_membership.id AND rpc.category_id=x)
          AND NOT EXISTS (SELECT 1 FROM hocalist.catalogue_categories c
                          WHERE c.id=x AND c.status='active')) s(x);
  IF coalesce(array_length(v_retired,1),0) > 0 THEN
    RAISE EXCEPTION 'retired_category_selection' USING ERRCODE='22023';
  END IF;
  IF v_profile.revision <> p_expected_revision THEN
    RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
  END IF;
  DELETE FROM hocalist.role_profile_categories
    WHERE membership_id=v_membership.id
      AND NOT (category_id = ANY(v_ids));
  INSERT INTO hocalist.role_profile_categories(membership_id,category_id)
    SELECT v_membership.id, x FROM unnest(v_ids) x
    ON CONFLICT (membership_id,category_id) DO NOTHING;
  UPDATE hocalist.role_profiles
    SET revision=revision+1,updated_at=now()
    WHERE membership_id=v_membership.id AND revision=p_expected_revision
    RETURNING * INTO v_profile;
  IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'profile.categories',p_key,h,jsonb_build_object(
      'membership_id',v_membership.id,
      'revision',v_profile.revision,
      'category_ids',coalesce((SELECT jsonb_agg(category_id ORDER BY category_id)
        FROM hocalist.role_profile_categories
        WHERE membership_id=v_membership.id),'[]'::jsonb)));
  RETURN jsonb_build_object(
    'membership_id',v_membership.id,
    'revision',v_profile.revision,
    'category_ids',coalesce((SELECT jsonb_agg(category_id ORDER BY category_id)
      FROM hocalist.role_profile_categories
      WHERE membership_id=v_membership.id),'[]'::jsonb));
END $$;

REVOKE ALL ON FUNCTION hocalist.profile_categories_validate(),
  hocalist.seller_profile_categories(),
  hocalist.member_seller_categories(uuid),
  hocalist.profile_categories_update(text,bigint,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.seller_profile_categories(),
  hocalist.member_seller_categories(uuid),
  hocalist.profile_categories_update(text,bigint,jsonb)
  TO authenticated;

DO $hocalist_profile_categories_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT coalesce((SELECT relrowsecurity FROM pg_class
      WHERE oid=to_regclass('hocalist.role_profile_categories')),false) THEN
    v_issues := array_append(v_issues,'missing RLS');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
      WHERE tgrelid='hocalist.role_profile_categories'::regclass
        AND tgname='profile_categories_validate_membership' AND NOT tgisinternal) THEN
    v_issues := array_append(v_issues,'missing membership validation');
  END IF;
  IF NOT has_function_privilege('authenticated',
      'hocalist.profile_categories_update(text,bigint,jsonb)','EXECUTE')
     OR has_function_privilege('anon',
      'hocalist.profile_categories_update(text,bigint,jsonb)','EXECUTE')
     OR has_function_privilege('service_role',
      'hocalist.seller_profile_categories()','EXECUTE') THEN
    v_issues := array_append(v_issues,'category grants are wrong');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist profile categories post-apply failed: %',
      array_to_string(v_issues,' | ');
  END IF;
END
$hocalist_profile_categories_postapply$;
COMMIT;

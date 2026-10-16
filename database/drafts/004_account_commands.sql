-- DRAFT: review and disposable tests required before live application.
-- Hardened for the guarded rollout bundle: explicit timeouts, field bounds,
-- stable safe error codes and explicit missing-contact handling.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
CREATE TABLE hocalist.command_receipts (
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  operation text NOT NULL,
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 128),
  request_hash text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation, idempotency_key)
);
ALTER TABLE hocalist.command_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.command_receipts FROM PUBLIC, anon, authenticated, service_role;

-- Every command locks the caller's seed first. This serializes retries and
-- conflicting changes for that identity, including its shared contacts.
CREATE FUNCTION hocalist.account_command(p_operation text, p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_hash text;
  v_receipt hocalist.command_receipts%ROWTYPE;
  v_member hocalist.memberships%ROWTYPE;
  v_profile hocalist.role_profiles%ROWTYPE;
  v_contact hocalist.profile_contacts%ROWTYPE;
  v_result jsonb;
  v_id uuid;
  v_expected bigint;
  v_allowed text[];
  v_field text;
  v_max integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_operation IS NULL OR p_operation NOT IN ('onboard','profile.update','contact.update') THEN
    RAISE EXCEPTION 'invalid_operation' USING ERRCODE='22023';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
    OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object' OR octet_length(p_input::text) > 16384 THEN
    RAISE EXCEPTION 'invalid_command' USING ERRCODE='22023';
  END IF;
  PERFORM 1 FROM hocalist.profiles WHERE id=v_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'onboarding_seed_required' USING ERRCODE='42501'; END IF;
  -- A restriction cannot be bypassed by enrolling in another role or replaying.
  IF EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id=v_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;

  IF p_operation='onboard' THEN
    v_allowed := ARRAY['role','display_name'];
    IF coalesce(p_input->>'role','') NOT IN ('buyer','seller') THEN
      RAISE EXCEPTION 'invalid_role' USING ERRCODE='22023';
    END IF;
  ELSIF p_operation='profile.update' THEN
    v_allowed := ARRAY['profile_id','expected_revision','display_name','area_label','profile_note',
      'preferred_meetup_type','service_radius_miles','pickup_availability'];
  ELSE
    v_allowed := ARRAY['expected_revision','phone','address_line1','address_line2','city','region','postal_code','country_code'];
  END IF;
  FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k WHERE NOT (k = ANY(v_allowed)) LOOP
    RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
  END LOOP;
  FOR v_field IN SELECT jsonb_object_keys(p_input) LOOP
    IF v_field NOT IN ('expected_revision','service_radius_miles') AND
       jsonb_typeof(p_input->v_field) NOT IN ('string','null') THEN
      RAISE EXCEPTION 'invalid_field_type: %', v_field USING ERRCODE='22023';
    END IF;
  END LOOP;
  -- Explicit bounds keep a stable 22023 field error instead of a nameless 23514.
  FOR v_field, v_max IN
    SELECT t.f, t.n FROM (VALUES
      ('area_label', 200), ('profile_note', 2000), ('preferred_meetup_type', 100),
      ('pickup_availability', 500), ('phone', 40), ('address_line1', 300),
      ('address_line2', 300), ('city', 150), ('region', 150), ('postal_code', 40)
    ) AS t(f, n)
  LOOP
    IF p_input ? v_field AND jsonb_typeof(p_input->v_field) = 'string'
       AND length(p_input->>v_field) > v_max THEN
      RAISE EXCEPTION 'invalid_field_value: %', v_field USING ERRCODE='22023';
    END IF;
  END LOOP;
  IF p_operation IN ('onboard','profile.update') AND
     (NOT (p_input ? 'display_name') OR p_input->>'display_name' IS NULL
      OR length(btrim(p_input->>'display_name')) NOT BETWEEN 1 AND 200) THEN
    RAISE EXCEPTION 'invalid_display_name' USING ERRCODE='22023';
  END IF;
  IF p_operation <> 'onboard' THEN
    IF jsonb_typeof(p_input->'expected_revision') <> 'number'
      OR coalesce(p_input->>'expected_revision','') !~ '^[1-9][0-9]{0,17}$' THEN
      RAISE EXCEPTION 'invalid_revision' USING ERRCODE='22023';
    END IF;
    v_expected := (p_input->>'expected_revision')::bigint;
    IF p_operation='profile.update' THEN
      IF NOT (p_input ? 'profile_id') OR jsonb_typeof(p_input->'profile_id') <> 'string' THEN
        RAISE EXCEPTION 'invalid_profile_id' USING ERRCODE='22023';
      END IF;
      BEGIN v_id := (p_input->>'profile_id')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_profile_id' USING ERRCODE='22023'; END;
      SELECT * INTO v_member FROM hocalist.memberships WHERE id=v_id AND user_id=v_user AND status='active';
      IF NOT FOUND THEN RAISE EXCEPTION 'profile_access_denied' USING ERRCODE='42501'; END IF;
      IF v_member.role='buyer' AND (p_input ? 'service_radius_miles' OR p_input ? 'pickup_availability') THEN
        RAISE EXCEPTION 'seller_fields_on_buyer' USING ERRCODE='22023';
      END IF;
      IF p_input ? 'service_radius_miles' AND jsonb_typeof(p_input->'service_radius_miles') <> 'null' AND
        (jsonb_typeof(p_input->'service_radius_miles') <> 'number' OR (p_input->>'service_radius_miles') !~ '^[0-9]{1,8}$') THEN
        RAISE EXCEPTION 'invalid_radius' USING ERRCODE='22023';
      END IF;
    ELSE
      IF NOT EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id=v_user AND status='active') THEN
        RAISE EXCEPTION 'contact_access_denied' USING ERRCODE='42501';
      END IF;
      IF p_input ? 'country_code' AND jsonb_typeof(p_input->'country_code') = 'string'
         AND p_input->>'country_code' !~ '^[A-Z]{2}$' THEN
        RAISE EXCEPTION 'invalid_country_code' USING ERRCODE='22023';
      END IF;
    END IF;
  END IF;
  v_hash := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  SELECT * INTO v_receipt FROM hocalist.command_receipts
    WHERE user_id=v_user AND operation=p_operation AND idempotency_key=p_key;
  IF FOUND THEN
    IF v_receipt.request_hash <> v_hash THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN v_receipt.result;
  END IF;

  IF p_operation='onboard' THEN
    SELECT * INTO v_member FROM hocalist.memberships WHERE user_id=v_user AND role=p_input->>'role';
    IF FOUND THEN RAISE EXCEPTION 'membership_exists' USING ERRCODE='P0001'; END IF;
    INSERT INTO hocalist.memberships(user_id,role,status) VALUES(v_user,p_input->>'role','active') RETURNING * INTO v_member;
    INSERT INTO hocalist.role_profiles(membership_id,display_name)
      VALUES(v_member.id,btrim(p_input->>'display_name')) RETURNING * INTO v_profile;
    INSERT INTO hocalist.profile_contacts(user_id) VALUES(v_user) ON CONFLICT(user_id) DO NOTHING;
    UPDATE hocalist.profiles SET onboarding_status='complete', updated_at=now() WHERE id=v_user;
    v_result := jsonb_build_object('profile_id',v_member.id,'role',v_member.role,'revision',v_profile.revision);
  ELSIF p_operation='profile.update' THEN
    UPDATE hocalist.role_profiles SET
      display_name=btrim(p_input->>'display_name'),
      area_label=CASE WHEN p_input ? 'area_label' THEN p_input->>'area_label' ELSE area_label END,
      profile_note=CASE WHEN p_input ? 'profile_note' THEN p_input->>'profile_note' ELSE profile_note END,
      preferred_meetup_type=CASE WHEN p_input ? 'preferred_meetup_type' THEN p_input->>'preferred_meetup_type' ELSE preferred_meetup_type END,
      service_radius_miles=CASE WHEN p_input ? 'service_radius_miles' THEN (p_input->>'service_radius_miles')::integer ELSE service_radius_miles END,
      pickup_availability=CASE WHEN p_input ? 'pickup_availability' THEN p_input->>'pickup_availability' ELSE pickup_availability END,
      revision=revision+1,updated_at=now()
    WHERE membership_id=v_id AND revision=v_expected RETURNING * INTO v_profile;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    v_result := jsonb_build_object('profile_id',v_id,'revision',v_profile.revision);
  ELSE
    -- Missing-contact behaviour stays explicit: no upsert and no legacy
    -- identity migration. A missing row (onboard always creates one) is
    -- reported like a stale revision so the adapter keeps its ConflictError.
    IF NOT EXISTS (SELECT 1 FROM hocalist.profile_contacts WHERE user_id=v_user) THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    UPDATE hocalist.profile_contacts SET
      phone=CASE WHEN p_input ? 'phone' THEN p_input->>'phone' ELSE phone END,
      address_line1=CASE WHEN p_input ? 'address_line1' THEN p_input->>'address_line1' ELSE address_line1 END,
      address_line2=CASE WHEN p_input ? 'address_line2' THEN p_input->>'address_line2' ELSE address_line2 END,
      city=CASE WHEN p_input ? 'city' THEN p_input->>'city' ELSE city END,
      region=CASE WHEN p_input ? 'region' THEN p_input->>'region' ELSE region END,
      postal_code=CASE WHEN p_input ? 'postal_code' THEN p_input->>'postal_code' ELSE postal_code END,
      country_code=CASE WHEN p_input ? 'country_code' THEN p_input->>'country_code' ELSE country_code END,
      revision=revision+1,updated_at=now()
    WHERE user_id=v_user AND revision=v_expected RETURNING * INTO v_contact;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    v_result := jsonb_build_object('revision',v_contact.revision);
  END IF;
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(v_user,p_operation,p_key,v_hash,v_result);
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION hocalist.account_command(text,text,jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.account_command(text,text,jsonb) TO authenticated;
COMMIT;

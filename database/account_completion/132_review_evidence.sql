-- Private review and report evidence.
--
-- Upload purposes: `review` (identity/business evidence attached to a
-- verification submission) and `report` (evidence attached to a support/report
-- case). Both are private: only the owner and an authorized reviewer can read
-- the bytes, and only through the authenticated media gateway. A generic
-- profile/chat reader cannot reach them because the read rule requires an
-- explicit evidence link and, for reviewers, an admin identity.
--
-- Holds represent legal/appeal retention. No retention job is installed and
-- nothing here deletes evidence.
--
-- Dependencies (explicit): media 100 (media_images/media_gateway), trust 120
-- (verification_submissions), support 070 (support_cases), marketplace 020
-- (platform_admins/marketplace_is_admin). Apply after media 101 when avatar
-- reads are used; this replacement keeps the 101 dispatch guards.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.media_images') IS NULL
     OR to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)') IS NULL
     OR to_regclass('hocalist.verification_submissions') IS NULL
     OR to_regclass('hocalist.support_cases') IS NULL
     OR to_regclass('hocalist.platform_admins') IS NULL
     OR to_regclass('hocalist.command_receipts') IS NULL THEN
    RAISE EXCEPTION 'review evidence requires media 100, trust 120, support 070 and marketplace 020';
  END IF;
  IF to_regclass('hocalist.review_evidence_links') IS NOT NULL
     OR to_regclass('hocalist.evidence_audit') IS NOT NULL THEN
    RAISE EXCEPTION 'review evidence already installed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid='hocalist.media_images'::regclass
        AND conname='media_images_purpose_check') THEN
    RAISE EXCEPTION 'media purpose constraint differs from media 100';
  END IF;
END $guard$;

-- Extend the accepted purposes. Existing rows are unchanged.
ALTER TABLE hocalist.media_images DROP CONSTRAINT media_images_purpose_check;
ALTER TABLE hocalist.media_images ADD CONSTRAINT media_images_purpose_check
  CHECK (purpose IN ('offer','store','profile','chat','review','report'));

-- Current evidence links. A link is created only by the owner's attach command
-- after the media row is ready and purpose-checked.
CREATE TABLE hocalist.review_evidence_links (
  media_id uuid NOT NULL REFERENCES hocalist.media_images(id),
  submission_id uuid REFERENCES hocalist.verification_submissions(id) ON DELETE CASCADE,
  case_id uuid REFERENCES hocalist.support_cases(id) ON DELETE CASCADE,
  attached_by uuid NOT NULL REFERENCES hocalist.profiles(id),
  attached_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT review_evidence_link_target CHECK (
    (submission_id IS NOT NULL AND case_id IS NULL)
    OR (submission_id IS NULL AND case_id IS NOT NULL)
  ),
  PRIMARY KEY (media_id)
);
CREATE INDEX review_evidence_links_submission ON hocalist.review_evidence_links(submission_id);
CREATE INDEX review_evidence_links_case ON hocalist.review_evidence_links(case_id);

-- Append-only audit of evidence actions. Never exposes bytes.
CREATE TABLE hocalist.evidence_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  media_id uuid NOT NULL,
  submission_id uuid,
  case_id uuid,
  action text NOT NULL CHECK (action IN ('attach','detach')),
  actor_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Legal/appeal retention holds. Evidence with an active hold is never a
-- cleanup candidate; releasing a hold is explicit and audited by the row.
CREATE TABLE hocalist.evidence_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  media_id uuid NOT NULL REFERENCES hocalist.media_images(id),
  kind text NOT NULL CHECK (kind IN ('legal','appeal','retention')),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 500),
  created_by uuid NOT NULL REFERENCES hocalist.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  released_by uuid REFERENCES hocalist.profiles(id),
  released_at timestamptz,
  CONSTRAINT evidence_hold_release_shape CHECK (
    (released_at IS NULL AND released_by IS NULL)
    OR (released_at IS NOT NULL AND released_by IS NOT NULL)
  )
);
CREATE INDEX evidence_holds_active ON hocalist.evidence_holds(media_id)
  WHERE released_at IS NULL;

ALTER TABLE hocalist.review_evidence_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.evidence_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.evidence_holds ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.review_evidence_links, hocalist.evidence_audit,
  hocalist.evidence_holds FROM PUBLIC, anon, authenticated, service_role;

-- Any insert/update of the legacy evidence array must reference the caller's
-- own ready review media. This closes the cross-user reference path without
-- replacing the trust 120 command body.
CREATE FUNCTION hocalist.review_evidence_validate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item text;
BEGIN
  IF NEW.evidence_media_ids = '[]'::jsonb THEN RETURN NEW; END IF;
  FOR item IN SELECT jsonb_array_elements_text(NEW.evidence_media_ids) LOOP
    IF NOT EXISTS (SELECT 1 FROM hocalist.media_images mi
        WHERE mi.id=item::uuid AND mi.owner_user_id=NEW.user_id
          AND mi.state='ready' AND mi.purpose='review') THEN
      RAISE EXCEPTION 'invalid_evidence_reference' USING ERRCODE='22023';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

CREATE TRIGGER review_evidence_validate_references
  BEFORE INSERT OR UPDATE OF evidence_media_ids ON hocalist.verification_submissions
  FOR EACH ROW EXECUTE FUNCTION hocalist.review_evidence_validate();

-- ---------------------------------------------------------------------------
-- Owner commands
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.review_evidence_attach(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.command_receipts%ROWTYPE;
  v hocalist.verification_submissions%ROWTYPE;
  v_ids uuid[];
  v_item jsonb;
  v_total integer;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object'
     OR p_input - ARRAY['submission_id','media_ids'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'submission_id') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_input->'media_ids') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_input->'media_ids') NOT BETWEEN 1 AND 8 THEN
    RAISE EXCEPTION 'invalid_evidence_attach' USING ERRCODE='22023';
  END IF;
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_input->'media_ids') LOOP
    IF jsonb_typeof(v_item)<>'string' THEN
      RAISE EXCEPTION 'invalid_evidence_attach' USING ERRCODE='22023';
    END IF;
  END LOOP;
  v_ids := ARRAY(SELECT (jsonb_array_elements_text(p_input->'media_ids'))::uuid);
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':evidence:'||p_key,0));
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  SELECT * INTO receipt FROM hocalist.command_receipts
    WHERE user_id=u AND operation='review.evidence.attach' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT * INTO v FROM hocalist.verification_submissions
    WHERE id=(p_input->>'submission_id')::uuid AND user_id=u AND status='pending'
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'submission_not_editable' USING ERRCODE='P0002'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_ids) x
             WHERE NOT EXISTS (SELECT 1 FROM hocalist.media_images mi
               WHERE mi.id=x AND mi.owner_user_id=u AND mi.state='ready'
                 AND mi.purpose='review')) THEN
    RAISE EXCEPTION 'invalid_evidence_reference' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_ids) x
             JOIN hocalist.review_evidence_links l ON l.media_id=x
             WHERE l.submission_id<>v.id) THEN
    RAISE EXCEPTION 'evidence_already_linked' USING ERRCODE='P0001';
  END IF;
  SELECT count(*) INTO v_total FROM (
    SELECT media_id FROM hocalist.review_evidence_links WHERE submission_id=v.id
    UNION
    SELECT x FROM unnest(v_ids) x) s;
  IF v_total > 8 THEN
    RAISE EXCEPTION 'evidence_limit' USING ERRCODE='22023';
  END IF;
  INSERT INTO hocalist.review_evidence_links(media_id,submission_id,attached_by)
    SELECT x,v.id,u FROM unnest(v_ids) x
    ON CONFLICT (media_id) DO NOTHING;
  INSERT INTO hocalist.evidence_audit(media_id,submission_id,action,actor_id)
    SELECT x,v.id,'attach',u FROM unnest(v_ids) x;
  UPDATE hocalist.verification_submissions
    SET evidence_media_ids=(SELECT coalesce(jsonb_agg(media_id::text ORDER BY attached_at),
          '[]'::jsonb) FROM hocalist.review_evidence_links WHERE submission_id=v.id),
        revision=revision+1,updated_at=now()
    WHERE id=v.id RETURNING * INTO v;
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'review.evidence.attach',p_key,h,
      jsonb_build_object('submission_id',v.id,'revision',v.revision,
        'evidence_media_ids',v.evidence_media_ids));
  RETURN jsonb_build_object('submission_id',v.id,'revision',v.revision,
    'evidence_media_ids',v.evidence_media_ids);
END $$;

CREATE FUNCTION hocalist.review_evidence_detach(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.command_receipts%ROWTYPE;
  v hocalist.verification_submissions%ROWTYPE;
  v_media uuid;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object'
     OR p_input - ARRAY['submission_id','media_id'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'submission_id') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_input->'media_id') IS DISTINCT FROM 'string' THEN
    RAISE EXCEPTION 'invalid_evidence_detach' USING ERRCODE='22023';
  END IF;
  v_media := (p_input->>'media_id')::uuid;
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':evidence.detach:'||p_key,0));
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  SELECT * INTO receipt FROM hocalist.command_receipts
    WHERE user_id=u AND operation='review.evidence.detach' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT * INTO v FROM hocalist.verification_submissions
    WHERE id=(p_input->>'submission_id')::uuid AND user_id=u AND status='pending'
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'submission_not_editable' USING ERRCODE='P0002'; END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.review_evidence_links
      WHERE media_id=v_media AND submission_id=v.id) THEN
    RAISE EXCEPTION 'evidence_not_found' USING ERRCODE='P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.evidence_holds
      WHERE media_id=v_media AND released_at IS NULL) THEN
    RAISE EXCEPTION 'evidence_hold_active' USING ERRCODE='P0001';
  END IF;
  DELETE FROM hocalist.review_evidence_links
    WHERE media_id=v_media AND submission_id=v.id;
  INSERT INTO hocalist.evidence_audit(media_id,submission_id,action,actor_id)
    VALUES(v_media,v.id,'detach',u);
  UPDATE hocalist.verification_submissions
    SET evidence_media_ids=(SELECT coalesce(jsonb_agg(media_id::text ORDER BY attached_at),
          '[]'::jsonb) FROM hocalist.review_evidence_links WHERE submission_id=v.id),
        revision=revision+1,updated_at=now()
    WHERE id=v.id RETURNING * INTO v;
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'review.evidence.detach',p_key,h,
      jsonb_build_object('submission_id',v.id,'revision',v.revision,
        'evidence_media_ids',v.evidence_media_ids));
  RETURN jsonb_build_object('submission_id',v.id,'revision',v.revision,
    'evidence_media_ids',v.evidence_media_ids);
END $$;

CREATE FUNCTION hocalist.report_evidence_attach(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.command_receipts%ROWTYPE;
  v_case hocalist.support_cases%ROWTYPE;
  v_ids uuid[];
  v_item jsonb;
  v_total integer;
BEGIN
  -- Restricted users keep their support channel, so only a membership row is
  -- required here; the media gateway applies the same rule to report uploads.
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u) THEN
    RAISE EXCEPTION 'support_access_denied' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object'
     OR p_input - ARRAY['case_id','media_ids'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'case_id') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_input->'media_ids') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_input->'media_ids') NOT BETWEEN 1 AND 8 THEN
    RAISE EXCEPTION 'invalid_evidence_attach' USING ERRCODE='22023';
  END IF;
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_input->'media_ids') LOOP
    IF jsonb_typeof(v_item)<>'string' THEN
      RAISE EXCEPTION 'invalid_evidence_attach' USING ERRCODE='22023';
    END IF;
  END LOOP;
  v_ids := ARRAY(SELECT (jsonb_array_elements_text(p_input->'media_ids'))::uuid);
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':report.evidence:'||p_key,0));
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  SELECT * INTO receipt FROM hocalist.command_receipts
    WHERE user_id=u AND operation='report.evidence.attach' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT * INTO v_case FROM hocalist.support_cases
    WHERE id=(p_input->>'case_id')::uuid AND reporter_id=u AND status<>'resolved'
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'case_not_editable' USING ERRCODE='P0002'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_ids) x
             WHERE NOT EXISTS (SELECT 1 FROM hocalist.media_images mi
               WHERE mi.id=x AND mi.owner_user_id=u AND mi.state='ready'
                 AND mi.purpose='report')) THEN
    RAISE EXCEPTION 'invalid_evidence_reference' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_ids) x
             JOIN hocalist.review_evidence_links l ON l.media_id=x
             WHERE l.case_id IS DISTINCT FROM v_case.id) THEN
    RAISE EXCEPTION 'evidence_already_linked' USING ERRCODE='P0001';
  END IF;
  SELECT count(*) INTO v_total FROM (
    SELECT media_id FROM hocalist.review_evidence_links WHERE case_id=v_case.id
    UNION
    SELECT x FROM unnest(v_ids) x) s;
  IF v_total > 8 THEN
    RAISE EXCEPTION 'evidence_limit' USING ERRCODE='22023';
  END IF;
  INSERT INTO hocalist.review_evidence_links(media_id,case_id,attached_by)
    SELECT x,v_case.id,u FROM unnest(v_ids) x
    ON CONFLICT (media_id) DO NOTHING;
  INSERT INTO hocalist.evidence_audit(media_id,case_id,action,actor_id)
    SELECT x,v_case.id,'attach',u FROM unnest(v_ids) x;
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'report.evidence.attach',p_key,h,
      jsonb_build_object('case_id',v_case.id,
        'evidence_media_ids',to_jsonb(v_ids)));
  RETURN jsonb_build_object('case_id',v_case.id,
    'evidence_media_ids',to_jsonb(v_ids));
END $$;

CREATE FUNCTION hocalist.report_evidence_detach(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.command_receipts%ROWTYPE;
  v_case hocalist.support_cases%ROWTYPE;
  v_media uuid;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u) THEN
    RAISE EXCEPTION 'support_access_denied' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object'
     OR p_input - ARRAY['case_id','media_id'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'case_id') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_input->'media_id') IS DISTINCT FROM 'string' THEN
    RAISE EXCEPTION 'invalid_evidence_detach' USING ERRCODE='22023';
  END IF;
  v_media := (p_input->>'media_id')::uuid;
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':report.evidence.detach:'||p_key,0));
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  SELECT * INTO receipt FROM hocalist.command_receipts
    WHERE user_id=u AND operation='report.evidence.detach' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT * INTO v_case FROM hocalist.support_cases
    WHERE id=(p_input->>'case_id')::uuid AND reporter_id=u AND status<>'resolved'
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'case_not_editable' USING ERRCODE='P0002'; END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.review_evidence_links
      WHERE media_id=v_media AND case_id=v_case.id) THEN
    RAISE EXCEPTION 'evidence_not_found' USING ERRCODE='P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.evidence_holds
      WHERE media_id=v_media AND released_at IS NULL) THEN
    RAISE EXCEPTION 'evidence_hold_active' USING ERRCODE='P0001';
  END IF;
  DELETE FROM hocalist.review_evidence_links
    WHERE media_id=v_media AND case_id=v_case.id;
  INSERT INTO hocalist.evidence_audit(media_id,case_id,action,actor_id)
    VALUES(v_media,v_case.id,'detach',u);
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'report.evidence.detach',p_key,h,
      jsonb_build_object('case_id',v_case.id));
  RETURN jsonb_build_object('case_id',v_case.id);
END $$;

-- ---------------------------------------------------------------------------
-- Authorized evidence read contract (admin package consumer)
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.media_read_review_evidence(p_user uuid, p_image uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT EXISTS (
    SELECT 1 FROM hocalist.media_images mi
    WHERE mi.id=p_image AND mi.purpose IN ('review','report') AND (
      mi.owner_user_id=p_user
      OR (hocalist.marketplace_is_admin(p_user)
          AND EXISTS (SELECT 1 FROM hocalist.review_evidence_links l
                      WHERE l.media_id=mi.id))));
$$;

-- Admin-only metadata contract. Bytes are fetched separately through the
-- authenticated hocalist-media function using media_id; there is no storage
-- credential in the response.
CREATE FUNCTION hocalist.admin_review_evidence(p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid := auth.uid(); n integer;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  n := p_limit;
  RETURN jsonb_build_object(
    'read_contract',jsonb_build_object(
      'schema','hocalist',
      'edge_function','hocalist-media',
      'action','read',
      'media_id_parameter','id',
      'authorization','admin_or_permitted_subject',
      'note','Bytes are never returned as storage URLs or signed credentials.'),
    'items',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'media_id',l.media_id,
      'purpose',mi.purpose,
      'state',mi.state,
      'size_bytes',mi.size_bytes,
      'width',mi.width,
      'height',mi.height,
      'created_at',mi.created_at,
      'owner_user_id',mi.owner_user_id,
      'owner_name',rp.display_name,
      'submission_id',l.submission_id,
      'submission_kind',v.kind,
      'submission_status',v.status,
      'case_id',l.case_id,
      'case_reason',c.reason_code,
      'case_status',c.status,
      'held',EXISTS(SELECT 1 FROM hocalist.evidence_holds h
        WHERE h.media_id=l.media_id AND h.released_at IS NULL))
      ORDER BY l.attached_at DESC)
      FROM (SELECT * FROM hocalist.review_evidence_links
            ORDER BY attached_at DESC LIMIT n) l
      JOIN hocalist.media_images mi ON mi.id=l.media_id
      LEFT JOIN hocalist.verification_submissions v ON v.id=l.submission_id
      LEFT JOIN hocalist.role_profiles rp ON rp.membership_id=(
        SELECT m.id FROM hocalist.memberships m
        WHERE m.user_id=mi.owner_user_id AND m.role='seller')
      LEFT JOIN hocalist.support_cases c ON c.id=l.case_id),'[]'::jsonb),
    'retention_jobs_enabled',false
  );
END $$;

CREATE FUNCTION hocalist.admin_evidence_hold(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.command_receipts%ROWTYPE;
  v_hold hocalist.evidence_holds%ROWTYPE;
  v_operation text;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object' THEN
    RAISE EXCEPTION 'invalid_hold_command' USING ERRCODE='22023';
  END IF;
  v_operation := p_input->>'operation';
  IF v_operation NOT IN ('set','release') THEN
    RAISE EXCEPTION 'invalid_hold_command' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':evidence.hold:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.command_receipts
    WHERE user_id=u AND operation='admin.evidence.hold' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  IF v_operation='set' THEN
    IF p_input - ARRAY['operation','media_id','kind','reason'] <> '{}'::jsonb
       OR jsonb_typeof(p_input->'media_id') IS DISTINCT FROM 'string'
       OR p_input->>'kind' NOT IN ('legal','appeal','retention')
       OR jsonb_typeof(p_input->'reason') IS DISTINCT FROM 'string'
       OR length(btrim(p_input->>'reason')) NOT BETWEEN 3 AND 500 THEN
      RAISE EXCEPTION 'invalid_hold_command' USING ERRCODE='22023';
    END IF;
    SELECT * INTO v_hold FROM hocalist.evidence_holds
      WHERE media_id=(p_input->>'media_id')::uuid AND released_at IS NULL;
    IF NOT FOUND THEN
      INSERT INTO hocalist.evidence_holds(media_id,kind,reason,created_by)
        VALUES((p_input->>'media_id')::uuid,p_input->>'kind',
          btrim(p_input->>'reason'),u)
        RETURNING * INTO v_hold;
    END IF;
  ELSE
    IF p_input - ARRAY['operation','hold_id'] <> '{}'::jsonb
       OR jsonb_typeof(p_input->'hold_id') IS DISTINCT FROM 'string' THEN
      RAISE EXCEPTION 'invalid_hold_command' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.evidence_holds SET released_by=u,released_at=now()
      WHERE id=(p_input->>'hold_id')::uuid AND released_at IS NULL
      RETURNING * INTO v_hold;
    IF NOT FOUND THEN RAISE EXCEPTION 'hold_not_found' USING ERRCODE='P0002'; END IF;
  END IF;
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'admin.evidence.hold',p_key,h,
      jsonb_build_object('hold_id',v_hold.id,'media_id',v_hold.media_id,
        'kind',v_hold.kind,'released',v_hold.released_at IS NOT NULL));
  RETURN jsonb_build_object('hold_id',v_hold.id,'media_id',v_hold.media_id,
    'kind',v_hold.kind,'released',v_hold.released_at IS NOT NULL);
END $$;

-- ---------------------------------------------------------------------------
-- Media gateway: add review/report purposes and their private read rule
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION hocalist.media_gateway(p_user uuid, p_action text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  m hocalist.media_images%ROWTYPE;
  image_id uuid;
  purpose text;
  n integer;
  v_allowed boolean;
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501';
  END IF;
  IF p_action='begin' AND p_input->>'purpose'='report' THEN
    -- Restricted users retain the support/report channel.
    IF NOT EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id=p_user) THEN
      RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501';
    END IF;
  ELSIF NOT EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status='active')
     OR EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501';
  END IF;
  INSERT INTO hocalist.media_windows(user_id, started_at, calls)
  VALUES (p_user, now(), 1)
  ON CONFLICT (user_id) DO UPDATE SET
    calls = CASE WHEN media_windows.started_at < now() - interval '1 minute' THEN 1 ELSE media_windows.calls + 1 END,
    started_at = CASE WHEN media_windows.started_at < now() - interval '1 minute' THEN now() ELSE media_windows.started_at END
  RETURNING calls INTO n;
  IF n > 60 THEN RAISE EXCEPTION 'media_rate_limit'; END IF;
  IF p_action = 'begin' THEN
    purpose := p_input->>'purpose';
    IF purpose NOT IN ('offer','store','profile','chat','review','report') THEN
      RAISE EXCEPTION 'invalid_purpose' USING ERRCODE='22023';
    END IF;
    IF purpose IN ('offer','store','review') AND NOT EXISTS (
      SELECT 1 FROM hocalist.memberships WHERE user_id = p_user AND role = 'seller' AND status = 'active') THEN
      RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501';
    END IF;
    PERFORM 1 FROM hocalist.profiles WHERE id = p_user FOR UPDATE;
    SELECT * INTO m FROM hocalist.media_images
      WHERE owner_user_id = p_user AND intent_key = (p_input->>'key')::uuid;
    IF FOUND THEN
      IF m.purpose <> purpose OR m.content_hash <> p_input->>'hash' THEN
        RAISE EXCEPTION 'idempotency_conflict';
      END IF;
    ELSE
      IF (SELECT count(*) FROM hocalist.media_images
          WHERE owner_user_id = p_user AND created_at > now() - interval '1 hour') >= 60 THEN
        RAISE EXCEPTION 'media_rate_limit';
      END IF;
      INSERT INTO hocalist.media_images(owner_user_id, intent_key, purpose, content_hash)
      VALUES (p_user, (p_input->>'key')::uuid, purpose, p_input->>'hash')
      RETURNING * INTO m;
    END IF;
  ELSIF p_action = 'complete' THEN
    UPDATE hocalist.media_images
      SET state = 'ready', size_bytes = (p_input->>'size')::integer,
          width = (p_input->>'width')::integer, height = (p_input->>'height')::integer
      WHERE id = (p_input->>'id')::uuid AND owner_user_id = p_user
        AND state IN ('pending','ready')
      RETURNING * INTO m;
    IF NOT FOUND THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='P0002'; END IF;
  ELSIF p_action = 'read' THEN
    image_id := (p_input->>'id')::uuid;
    SELECT * INTO m FROM hocalist.media_images WHERE id = image_id AND state = 'ready';
    IF NOT FOUND THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='P0002'; END IF;
    IF m.owner_user_id <> p_user THEN
      v_allowed :=
        (m.purpose = 'store' AND EXISTS (
          SELECT 1 FROM hocalist.store_listings l
          JOIN hocalist.memberships s ON s.id = l.seller_profile_id
          WHERE l.image_media_ids ? image_id::text
            AND l.status = 'active' AND l.moderation_status = 'approved' AND s.status = 'active'))
        OR (m.purpose = 'offer' AND EXISTS (
          SELECT 1 FROM hocalist.offer_revisions r
          JOIN hocalist.offers o ON o.id = r.offer_id
          JOIN hocalist.requests q ON q.id = o.request_id
          WHERE r.image_media_ids ? image_id::text AND q.buyer_user_id = p_user));
      IF NOT v_allowed
         AND to_regprocedure('hocalist.media_read_chat(uuid,uuid)') IS NOT NULL THEN
        v_allowed := hocalist.media_read_chat(p_user, image_id);
      END IF;
      IF NOT v_allowed
         AND to_regprocedure('hocalist.media_read_profile(uuid,uuid)') IS NOT NULL THEN
        v_allowed := hocalist.media_read_profile(p_user, image_id);
      END IF;
      IF NOT v_allowed
         AND to_regprocedure('hocalist.media_read_review_evidence(uuid,uuid)') IS NOT NULL THEN
        v_allowed := hocalist.media_read_review_evidence(p_user, image_id);
      END IF;
      IF NOT v_allowed THEN
        RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501';
      END IF;
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023';
  END IF;
  RETURN jsonb_build_object(
    'id', m.id,
    'path', m.owner_user_id::text || '/' || m.id::text || '.jpg',
    'state', m.state);
END $$;

REVOKE ALL ON FUNCTION hocalist.review_evidence_validate(),
  hocalist.review_evidence_attach(text,jsonb),
  hocalist.review_evidence_detach(text,jsonb),
  hocalist.report_evidence_attach(text,jsonb),
  hocalist.report_evidence_detach(text,jsonb),
  hocalist.media_read_review_evidence(uuid,uuid),
  hocalist.admin_review_evidence(integer),
  hocalist.admin_evidence_hold(text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.media_gateway(uuid,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.review_evidence_attach(text,jsonb),
  hocalist.review_evidence_detach(text,jsonb),
  hocalist.report_evidence_attach(text,jsonb),
  hocalist.report_evidence_detach(text,jsonb),
  hocalist.admin_review_evidence(integer),
  hocalist.admin_evidence_hold(text,jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.media_gateway(uuid,text,jsonb) TO service_role;

DO $hocalist_review_evidence_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['review_evidence_links','evidence_audit','evidence_holds'] LOOP
    IF NOT coalesce((SELECT relrowsecurity FROM pg_class
        WHERE oid=to_regclass('hocalist.'||t)),false) THEN
      v_issues := array_append(v_issues,'missing RLS: '||t);
    END IF;
    IF has_table_privilege('authenticated','hocalist.'||t,'SELECT') THEN
      v_issues := array_append(v_issues,'unexpected table grant: '||t);
    END IF;
  END LOOP;
  IF NOT has_function_privilege('authenticated',
      'hocalist.review_evidence_attach(text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated',
      'hocalist.admin_review_evidence(integer)','EXECUTE')
     OR has_function_privilege('anon',
      'hocalist.review_evidence_attach(text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated',
      'hocalist.media_read_review_evidence(uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated',
      'hocalist.media_gateway(uuid,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('service_role',
      'hocalist.media_gateway(uuid,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues,'evidence grants are wrong');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid='hocalist.media_images'::regclass
        AND conname='media_images_purpose_check'
        AND pg_get_constraintdef(oid) LIKE '%review%'
        AND pg_get_constraintdef(oid) LIKE '%report%') THEN
    v_issues := array_append(v_issues,'media purpose constraint missing review/report');
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.evidence_holds) THEN
    v_issues := array_append(v_issues,'evidence holds unexpectedly seeded');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist review evidence post-apply failed: %',
      array_to_string(v_issues,' | ');
  END IF;
END
$hocalist_review_evidence_postapply$;
COMMIT;

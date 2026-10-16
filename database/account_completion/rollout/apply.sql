BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
DO $guard$ BEGIN
IF to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)')),chr(13),''))<>'aaee68ae358c131da1aaeacc355aa6ae' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.media_gateway(uuid,text,jsonb)'; END IF;
IF to_regclass('hocalist.account_consent_documents') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: account_consent_documents'; END IF;
IF to_regclass('hocalist.account_consents') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: account_consents'; END IF;
IF to_regclass('hocalist.account_export_requests') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: account_export_requests'; END IF;
IF to_regclass('hocalist.account_exports') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: account_exports'; END IF;
IF to_regclass('hocalist.account_deletion_requests') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: account_deletion_requests'; END IF;
IF to_regclass('hocalist.role_profile_categories') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: role_profile_categories'; END IF;
IF to_regclass('hocalist.review_evidence_links') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: review_evidence_links'; END IF;
IF to_regclass('hocalist.evidence_audit') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: evidence_audit'; END IF;
IF to_regclass('hocalist.evidence_holds') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: evidence_holds'; END IF;
IF to_regclass('hocalist.media_cleanup_audit') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: media_cleanup_audit'; END IF;
END $guard$;
-- Account lifecycle: consent records, own-data export and a deletion REQUEST.
--
-- Scope is Hocalist only. This migration never deletes a shared Supabase Auth
-- user, Postaneur records or legal evidence, and it installs no scheduled
-- retention job. A deletion request records intent, current financial/safety
-- holds, status and cancellation; execution stays a coordinator/owner step.
-- Consent documents ship empty and are admin-managed configuration.
--
-- Dependencies (explicit): account 003/004 (profiles, memberships, command
-- receipts). Optional modules are detected with to_regclass so this file
-- applies independently of marketplace/trust/commercial rollouts.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.profiles') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regclass('hocalist.command_receipts') IS NULL THEN
    RAISE EXCEPTION 'account lifecycle requires account 003/004';
  END IF;
  IF to_regclass('hocalist.account_consents') IS NOT NULL
     OR to_regclass('hocalist.account_export_requests') IS NOT NULL
     OR to_regclass('hocalist.account_deletion_requests') IS NOT NULL THEN
    RAISE EXCEPTION 'account lifecycle already installed';
  END IF;
END $guard$;

-- Admin-managed consent documents. No legal text or version is seeded here.
CREATE TABLE hocalist.account_consent_documents (
  id text PRIMARY KEY CHECK (id ~ '^[a-z0-9_.-]{1,60}$'),
  version text NOT NULL CHECK (length(btrim(version)) BETWEEN 1 AND 40),
  label text NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 200),
  is_required boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Immutable acceptance records: one row per user, document and exact version.
CREATE TABLE hocalist.account_consents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  document_id text NOT NULL REFERENCES hocalist.account_consent_documents(id),
  version text NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, document_id, version)
);

CREATE TABLE hocalist.account_export_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','processing','ready','failed')),
  error_code text CHECK (error_code IS NULL OR length(error_code) BETWEEN 1 AND 60),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  requested_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  ready_at timestamptz
);
CREATE INDEX account_export_requests_owner ON hocalist.account_export_requests(user_id, requested_at DESC);

-- One latest generated document per user. A new request replaces the payload.
CREATE TABLE hocalist.account_exports (
  user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  request_id uuid NOT NULL REFERENCES hocalist.account_export_requests(id) ON DELETE CASCADE,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- At most one open deletion request per user. No execution path is installed.
CREATE TABLE hocalist.account_deletion_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'requested'
    CHECK (status IN ('requested','blocked','cancelled')),
  holds jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(holds)='array'),
  scope text NOT NULL DEFAULT 'hocalist' CHECK (scope IN ('hocalist')),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  requested_at timestamptz NOT NULL DEFAULT now(),
  cancelled_at timestamptz,
  cancel_reason text CHECK (cancel_reason IS NULL OR length(btrim(cancel_reason)) BETWEEN 1 AND 500),
  CONSTRAINT deletion_cancel_shape CHECK (
    (status = 'cancelled' AND cancelled_at IS NOT NULL)
    OR (status <> 'cancelled' AND cancelled_at IS NULL)
  )
);
CREATE UNIQUE INDEX account_deletion_requests_open
  ON hocalist.account_deletion_requests(user_id)
  WHERE status IN ('requested','blocked');

ALTER TABLE hocalist.account_consent_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.account_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.account_export_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.account_exports ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.account_deletion_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.account_consent_documents, hocalist.account_consents,
  hocalist.account_export_requests, hocalist.account_exports,
  hocalist.account_deletion_requests
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Export assembly (Hocalist scope only)
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.account_lifecycle_holds(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE holds jsonb := '[]'::jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id=p_user AND status IN ('restricted','disabled')) THEN
    holds := holds || jsonb_build_array(jsonb_build_object(
      'kind','active_restriction','detail','membership_status'));
  END IF;
  IF to_regclass('hocalist.account_restrictions') IS NOT NULL THEN
    holds := holds || coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'kind','recorded_restriction','detail',r.scope,'since',r.created_at)
        ORDER BY r.created_at)
      FROM hocalist.account_restrictions r
      WHERE r.user_id=p_user AND r.status='active'),'[]'::jsonb);
  END IF;
  IF to_regclass('hocalist.withdrawal_requests') IS NOT NULL THEN
    holds := holds || coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'kind','withdrawal_processing','detail',w.net_minor::text,'since',w.created_at)
        ORDER BY w.created_at)
      FROM hocalist.withdrawal_requests w
      WHERE w.user_id=p_user AND w.status='processing'),'[]'::jsonb);
  END IF;
  IF to_regclass('hocalist.credit_targets') IS NOT NULL THEN
    holds := holds || coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'kind','credit_reservation','detail',t.status,'since',t.created_at)
        ORDER BY t.created_at)
      FROM hocalist.credit_targets t
      WHERE t.user_id=p_user AND t.status IN ('reserved','initial_charged')),'[]'::jsonb);
  END IF;
  RETURN holds;
END $$;

-- Assembled once per request in the same transaction. Sections from modules
-- that are not installed are omitted instead of failing the whole request.
CREATE FUNCTION hocalist.account_export_build(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE payload jsonb;
BEGIN
  payload := jsonb_build_object(
    'schema_scope','hocalist',
    'shared_identity_note',
      'This export contains Hocalist records only. Shared Supabase Auth '
      'credentials and Postaneur records are not included.',
    'generated_at',now(),
    'profile',(SELECT to_jsonb(p) FROM hocalist.profiles p WHERE p.id=p_user),
    'memberships',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.role)
      FROM hocalist.memberships m WHERE m.user_id=p_user),'[]'::jsonb),
    'role_profiles',coalesce((SELECT jsonb_agg(to_jsonb(rp) ORDER BY rp.membership_id)
      FROM hocalist.role_profiles rp
      JOIN hocalist.memberships m ON m.id=rp.membership_id
      WHERE m.user_id=p_user),'[]'::jsonb),
    'private_contact',(SELECT to_jsonb(c)
      FROM hocalist.profile_contacts c WHERE c.user_id=p_user),
    'consents',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'document_id',document_id,'version',version,'accepted_at',accepted_at)
      ORDER BY accepted_at)
      FROM hocalist.account_consents WHERE user_id=p_user),'[]'::jsonb),
    'deletion_requests',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',id,'status',status,'holds',holds,'scope',scope,
      'requested_at',requested_at,'cancelled_at',cancelled_at)
      ORDER BY requested_at)
      FROM hocalist.account_deletion_requests WHERE user_id=p_user),'[]'::jsonb),
    'export_requests',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',id,'status',status,'requested_at',requested_at,'ready_at',ready_at)
      ORDER BY requested_at)
      FROM hocalist.account_export_requests WHERE user_id=p_user),'[]'::jsonb)
  );
  IF to_regclass('hocalist.role_profile_categories') IS NOT NULL THEN
    payload := payload || jsonb_build_object(
      'seller_categories',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'membership_id',rpc.membership_id,'category_id',rpc.category_id,
        'label',c.label,'status',c.status)
        ORDER BY c.label)
        FROM hocalist.role_profile_categories rpc
        JOIN hocalist.memberships m ON m.id=rpc.membership_id
        LEFT JOIN hocalist.catalogue_categories c ON c.id=rpc.category_id
        WHERE m.user_id=p_user),'[]'::jsonb));
  END IF;
  IF to_regclass('hocalist.verification_submissions') IS NOT NULL THEN
    payload := payload || jsonb_build_object(
      'verification_submissions',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',id,'kind',kind,'note',note,'status',status,
        'evidence_media_ids',evidence_media_ids,'revision',revision,
        'created_at',created_at,'decided_at',decided_at)
        ORDER BY created_at)
        FROM hocalist.verification_submissions WHERE user_id=p_user),'[]'::jsonb));
  END IF;
  IF to_regclass('hocalist.restriction_appeals') IS NOT NULL THEN
    payload := payload || jsonb_build_object(
      'restriction_appeals',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',id,'restriction_id',restriction_id,'body',body,'status',status,
        'created_at',created_at,'decided_at',decided_at)
        ORDER BY created_at)
        FROM hocalist.restriction_appeals WHERE user_id=p_user),'[]'::jsonb));
  END IF;
  IF to_regclass('hocalist.support_cases') IS NOT NULL THEN
    payload := payload || jsonb_build_object(
      'support_cases',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',id,'reason_code',reason_code,'body',body,'status',status,
        'response',response,'created_at',created_at)
        ORDER BY created_at)
        FROM hocalist.support_cases WHERE reporter_id=p_user),'[]'::jsonb));
  END IF;
  IF to_regclass('hocalist.store_listings') IS NOT NULL THEN
    payload := payload || jsonb_build_object(
      'store_listings',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',l.id,'title',l.title,'status',l.status,
        'moderation_status',l.moderation_status,'category_id',l.category_id,
        'created_at',l.created_at)
        ORDER BY l.created_at)
        FROM hocalist.store_listings l
        JOIN hocalist.memberships m ON m.id=l.seller_profile_id
        WHERE m.user_id=p_user),'[]'::jsonb));
  END IF;
  IF to_regclass('hocalist.requests') IS NOT NULL THEN
    payload := payload || jsonb_build_object(
      'requests',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',id,'status',status,'title',title,'category_id',category_id,
        'created_at',created_at)
        ORDER BY created_at)
        FROM hocalist.requests WHERE buyer_user_id=p_user),'[]'::jsonb));
  END IF;
  IF to_regclass('hocalist.credit_batches') IS NOT NULL THEN
    payload := payload || jsonb_build_object(
      'credit_batches',coalesce((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.created_at)
        FROM hocalist.credit_batches b WHERE b.user_id=p_user),'[]'::jsonb),
      'credit_targets',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.created_at)
        FROM hocalist.credit_targets t WHERE t.user_id=p_user),'[]'::jsonb));
  END IF;
  IF to_regclass('hocalist.withdrawal_requests') IS NOT NULL THEN
    payload := payload || jsonb_build_object(
      'withdrawals',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',id,'amount_minor',amount_minor,'fee_minor',fee_minor,
        'net_minor',net_minor,'status',status,'created_at',created_at)
        ORDER BY created_at)
        FROM hocalist.withdrawal_requests WHERE user_id=p_user),'[]'::jsonb));
  END IF;
  RETURN payload;
END $$;

-- ---------------------------------------------------------------------------
-- User-facing lifecycle
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.account_lifecycle_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  export_row hocalist.account_export_requests%ROWTYPE;
  deletion_row hocalist.account_deletion_requests%ROWTYPE;
  has_export boolean := false;
  has_deletion boolean := false;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.profiles WHERE id=u) THEN
    RAISE EXCEPTION 'account_lifecycle_denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO export_row FROM hocalist.account_export_requests
    WHERE user_id=u ORDER BY requested_at DESC, id DESC LIMIT 1;
  has_export := FOUND;
  SELECT * INTO deletion_row FROM hocalist.account_deletion_requests
    WHERE user_id=u AND status IN ('requested','blocked')
    ORDER BY requested_at DESC, id DESC LIMIT 1;
  has_deletion := FOUND;
  RETURN jsonb_build_object(
    'consent_documents',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',id,'version',version,'label',label,
      'is_required',is_required,'sort_order',sort_order,'revision',revision)
      ORDER BY sort_order,id)
      FROM hocalist.account_consent_documents WHERE is_active),'[]'::jsonb),
    'accepted_consents',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'document_id',document_id,'version',version,'accepted_at',accepted_at)
      ORDER BY accepted_at)
      FROM hocalist.account_consents WHERE user_id=u),'[]'::jsonb),
    'export',CASE WHEN has_export THEN jsonb_build_object(
      'request_id',export_row.id,'status',export_row.status,
      'requested_at',export_row.requested_at,'ready_at',export_row.ready_at,
      'revision',export_row.revision) END,
    'deletion',CASE WHEN has_deletion THEN jsonb_build_object(
      'request_id',deletion_row.id,'status',deletion_row.status,
      'scope',deletion_row.scope,'holds',deletion_row.holds,
      'requested_at',deletion_row.requested_at,'revision',deletion_row.revision,
      'cancelable',deletion_row.status IN ('requested','blocked'),
      'execution_owner','coordinator') END,
    'deletion_scope_note',
      'Deletion requests cover Hocalist records only. Shared Supabase Auth '
      'identity, Postaneur records and legal evidence are not deleted here.'
  );
END $$;

CREATE FUNCTION hocalist.account_consent_record(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.command_receipts%ROWTYPE;
  doc hocalist.account_consent_documents%ROWTYPE;
  accepted hocalist.account_consents%ROWTYPE;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.profiles WHERE id=u) THEN
    RAISE EXCEPTION 'account_lifecycle_denied' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object'
     OR p_input - ARRAY['document_id','version'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'document_id') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_input->'version') IS DISTINCT FROM 'string' THEN
    RAISE EXCEPTION 'invalid_consent' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':consent:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.command_receipts
    WHERE user_id=u AND operation='consent.record' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT * INTO doc FROM hocalist.account_consent_documents
    WHERE id=p_input->>'document_id' AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'consent_document_unavailable' USING ERRCODE='P0002';
  END IF;
  IF doc.version <> btrim(p_input->>'version') THEN
    RAISE EXCEPTION 'consent_version_mismatch' USING ERRCODE='P0001';
  END IF;
  INSERT INTO hocalist.account_consents(user_id,document_id,version)
    VALUES(u,doc.id,doc.version)
    ON CONFLICT (user_id,document_id,version) DO NOTHING
    RETURNING * INTO accepted;
  IF NOT FOUND THEN
    SELECT * INTO accepted FROM hocalist.account_consents
      WHERE user_id=u AND document_id=doc.id AND version=doc.version;
  END IF;
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'consent.record',p_key,h,
      jsonb_build_object('document_id',accepted.document_id,
        'version',accepted.version,'accepted_at',accepted.accepted_at));
  RETURN jsonb_build_object('document_id',accepted.document_id,
    'version',accepted.version,'accepted_at',accepted.accepted_at);
END $$;

CREATE FUNCTION hocalist.account_export_request(p_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  receipt hocalist.command_receipts%ROWTYPE;
  req hocalist.account_export_requests%ROWTYPE;
  payload jsonb;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.profiles WHERE id=u) THEN
    RAISE EXCEPTION 'account_lifecycle_denied' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid_export_request' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':export:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.command_receipts
    WHERE user_id=u AND operation='export.request' AND idempotency_key=p_key;
  IF FOUND THEN RETURN receipt.result; END IF;
  INSERT INTO hocalist.account_export_requests(user_id,status,started_at)
    VALUES(u,'processing',now()) RETURNING * INTO req;
  BEGIN
    payload := hocalist.account_export_build(u);
  EXCEPTION WHEN OTHERS THEN
    UPDATE hocalist.account_export_requests
      SET status='failed',error_code='export_build_failed',revision=revision+1
      WHERE id=req.id;
    RAISE;
  END;
  UPDATE hocalist.account_export_requests
    SET status='ready',ready_at=now(),revision=revision+1
    WHERE id=req.id RETURNING * INTO req;
  INSERT INTO hocalist.account_exports(user_id,request_id,payload)
    VALUES(u,req.id,payload)
    ON CONFLICT (user_id) DO UPDATE
      SET request_id=excluded.request_id,payload=excluded.payload,created_at=now();
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'export.request',p_key,
      encode(sha256(convert_to(u::text,'UTF8')),'hex'),
      jsonb_build_object('request_id',req.id,'status',req.status,
        'requested_at',req.requested_at,'ready_at',req.ready_at,'revision',req.revision));
  RETURN jsonb_build_object('request_id',req.id,'status',req.status,
    'requested_at',req.requested_at,'ready_at',req.ready_at,'revision',req.revision);
END $$;

CREATE FUNCTION hocalist.account_export_read(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  req hocalist.account_export_requests%ROWTYPE;
  doc hocalist.account_exports%ROWTYPE;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'account_lifecycle_denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO req FROM hocalist.account_export_requests
    WHERE id=p_request AND user_id=u;
  IF NOT FOUND THEN RAISE EXCEPTION 'export_not_found' USING ERRCODE='P0002'; END IF;
  IF req.status <> 'ready' THEN
    RAISE EXCEPTION 'export_not_ready' USING ERRCODE='P0001';
  END IF;
  SELECT * INTO doc FROM hocalist.account_exports
    WHERE request_id=req.id AND user_id=u;
  IF NOT FOUND THEN RAISE EXCEPTION 'export_not_found' USING ERRCODE='P0002'; END IF;
  RETURN jsonb_build_object('request_id',req.id,'generated_at',doc.created_at,
    'payload',doc.payload);
END $$;

CREATE FUNCTION hocalist.account_deletion_request(p_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  receipt hocalist.command_receipts%ROWTYPE;
  existing hocalist.account_deletion_requests%ROWTYPE;
  created hocalist.account_deletion_requests%ROWTYPE;
  holds jsonb;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.profiles WHERE id=u) THEN
    RAISE EXCEPTION 'account_lifecycle_denied' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid_deletion_request' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':deletion:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.command_receipts
    WHERE user_id=u AND operation='deletion.request' AND idempotency_key=p_key;
  IF FOUND THEN RETURN receipt.result; END IF;
  SELECT * INTO existing FROM hocalist.account_deletion_requests
    WHERE user_id=u AND status IN ('requested','blocked') LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('request_id',existing.id,'status',existing.status,
      'scope',existing.scope,'holds',existing.holds,
      'requested_at',existing.requested_at,'revision',existing.revision,
      'cancelable',true,'reused',true,
      'execution_owner','coordinator');
  END IF;
  holds := hocalist.account_lifecycle_holds(u);
  INSERT INTO hocalist.account_deletion_requests(user_id,status,holds)
    VALUES(u,CASE WHEN holds='[]'::jsonb THEN 'requested' ELSE 'blocked' END,holds)
    RETURNING * INTO created;
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'deletion.request',p_key,
      encode(sha256(convert_to(u::text,'UTF8')),'hex'),
      jsonb_build_object('request_id',created.id,'status',created.status,
        'scope',created.scope,'holds',created.holds,
        'requested_at',created.requested_at,'revision',created.revision,
        'cancelable',true,'execution_owner','coordinator'));
  RETURN jsonb_build_object('request_id',created.id,'status',created.status,
    'scope',created.scope,'holds',created.holds,
    'requested_at',created.requested_at,'revision',created.revision,
    'cancelable',true,'execution_owner','coordinator');
END $$;

CREATE FUNCTION hocalist.account_deletion_cancel(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.command_receipts%ROWTYPE;
  updated hocalist.account_deletion_requests%ROWTYPE;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'account_lifecycle_denied' USING ERRCODE='42501'; END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object'
     OR p_input - ARRAY['request_id','expected_revision','reason'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'request_id') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_input->'expected_revision') <> 'number'
     OR (p_input ? 'reason' AND jsonb_typeof(p_input->'reason') NOT IN ('string','null')) THEN
    RAISE EXCEPTION 'invalid_deletion_cancel' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':deletion.cancel:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.command_receipts
    WHERE user_id=u AND operation='deletion.cancel' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  UPDATE hocalist.account_deletion_requests
    SET status='cancelled',cancelled_at=now(),
        cancel_reason=nullif(btrim(coalesce(p_input->>'reason','')),''),
        revision=revision+1
    WHERE id=(p_input->>'request_id')::uuid AND user_id=u
      AND status IN ('requested','blocked')
      AND revision=(p_input->>'expected_revision')::bigint
    RETURNING * INTO updated;
  IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'deletion.cancel',p_key,h,
      jsonb_build_object('request_id',updated.id,'status',updated.status,
        'cancelled_at',updated.cancelled_at,'revision',updated.revision));
  RETURN jsonb_build_object('request_id',updated.id,'status',updated.status,
    'cancelled_at',updated.cancelled_at,'revision',updated.revision);
END $$;

-- Admin-managed consent documents. No admin UI is added by this package; the
-- admin package consumes this command after integration review.
CREATE FUNCTION hocalist.admin_account_lifecycle_command(
  p_operation text, p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.command_receipts%ROWTYPE;
  doc hocalist.account_consent_documents%ROWTYPE;
BEGIN
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE='42501';
  END IF;
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_operation IS NULL OR p_operation <> 'consent.save'
     OR p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object'
     OR p_input - ARRAY['id','version','label','is_required','is_active','sort_order','expected_revision'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'id') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_input->'version') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_input->'label') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_input->'is_required') IS DISTINCT FROM 'boolean'
     OR jsonb_typeof(p_input->'is_active') IS DISTINCT FROM 'boolean'
     OR jsonb_typeof(p_input->'sort_order') <> 'number' THEN
    RAISE EXCEPTION 'invalid_lifecycle_command' USING ERRCODE='22023';
  END IF;
  IF btrim(p_input->>'id') !~ '^[a-z0-9_.-]{1,60}$'
     OR length(btrim(p_input->>'version')) NOT BETWEEN 1 AND 40
     OR length(btrim(p_input->>'label')) NOT BETWEEN 1 AND 200
     OR (p_input->>'sort_order')::integer NOT BETWEEN 0 AND 100000 THEN
    RAISE EXCEPTION 'invalid_lifecycle_values' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':lifecycle.admin:'||p_key,0));
  SELECT * INTO receipt FROM hocalist.command_receipts
    WHERE user_id=u AND operation='admin.consent.save' AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  INSERT INTO hocalist.account_consent_documents(
    id,version,label,is_required,is_active,sort_order)
  VALUES (btrim(p_input->>'id'),btrim(p_input->>'version'),
    btrim(p_input->>'label'),(p_input->>'is_required')::boolean,
    (p_input->>'is_active')::boolean,(p_input->>'sort_order')::integer)
  ON CONFLICT (id) DO UPDATE SET
    version=excluded.version,label=excluded.label,is_required=excluded.is_required,
    is_active=excluded.is_active,sort_order=excluded.sort_order,
    revision=hocalist.account_consent_documents.revision+1,updated_at=now()
  WHERE NOT (p_input ? 'expected_revision')
    OR hocalist.account_consent_documents.revision=(p_input->>'expected_revision')::bigint
  RETURNING * INTO doc;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
  END IF;
  INSERT INTO hocalist.command_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'admin.consent.save',p_key,h,
      jsonb_build_object('id',doc.id,'version',doc.version,'revision',doc.revision));
  RETURN jsonb_build_object('id',doc.id,'version',doc.version,'revision',doc.revision);
END $$;

REVOKE ALL ON FUNCTION hocalist.account_lifecycle_holds(uuid),
  hocalist.account_export_build(uuid),
  hocalist.account_lifecycle_status(),
  hocalist.account_consent_record(text,jsonb),
  hocalist.account_export_request(text),
  hocalist.account_export_read(uuid),
  hocalist.account_deletion_request(text),
  hocalist.account_deletion_cancel(text,jsonb),
  hocalist.admin_account_lifecycle_command(text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.account_lifecycle_status(),
  hocalist.account_consent_record(text,jsonb),
  hocalist.account_export_request(text),
  hocalist.account_export_read(uuid),
  hocalist.account_deletion_request(text),
  hocalist.account_deletion_cancel(text,jsonb),
  hocalist.admin_account_lifecycle_command(text,text,jsonb)
  TO authenticated;

-- Post-apply assertions inside the same transaction.
DO $hocalist_account_lifecycle_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['account_consent_documents','account_consents',
    'account_export_requests','account_exports','account_deletion_requests'] LOOP
    IF NOT coalesce((SELECT relrowsecurity FROM pg_class
        WHERE oid=to_regclass('hocalist.'||t)),false) THEN
      v_issues := array_append(v_issues,'missing RLS: '||t);
    END IF;
    IF has_table_privilege('authenticated','hocalist.'||t,'SELECT')
       OR has_table_privilege('service_role','hocalist.'||t,'SELECT') THEN
      v_issues := array_append(v_issues,'unexpected table grant: '||t);
    END IF;
  END LOOP;
  IF NOT has_function_privilege('authenticated',
      'hocalist.account_lifecycle_status()','EXECUTE')
     OR NOT has_function_privilege('authenticated',
      'hocalist.account_deletion_request(text)','EXECUTE')
     OR has_function_privilege('anon',
      'hocalist.account_lifecycle_status()','EXECUTE')
     OR has_function_privilege('authenticated',
      'hocalist.account_export_build(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated',
      'hocalist.admin_account_lifecycle_command(text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues,'lifecycle grants are wrong');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist account lifecycle post-apply failed: %',
      array_to_string(v_issues,' | ');
  END IF;
END
$hocalist_account_lifecycle_postapply$;

-- Seller profile categories backed by real catalogue ids.
--
-- A seller selects active catalogue categories for the seller membership.
-- Retired categories stay readable for existing selections and are only
-- dropped by an explicit replacement; a new selection must be active. The
-- update shares the role_profiles revision, so stale editors receive
-- revision_conflict instead of overwriting.
--
-- Dependencies (explicit): account 003/004 and marketplace 020 catalogue.

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

-- Media orphan/draft cleanup planning with dry-run default.
--
-- Planning is read-only. Evidence (`review`/`report`), linked evidence, held
-- media, avatars and any referenced store/offer/chat media are never
-- candidates. The service-only apply defaults to a dry run and refuses to run
-- without an explicit confirm hash; it marks abandoned drafts rejected and
-- records an audit row. It never deletes evidence or referenced media, and no
-- scheduled job is installed.
--
-- Dependencies (explicit): media 100. Evidence/avatar references are guarded
-- so this file also applies before 101/132.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.media_images') IS NULL THEN
    RAISE EXCEPTION 'media cleanup requires media 100';
  END IF;
  IF to_regclass('hocalist.media_cleanup_audit') IS NOT NULL THEN
    RAISE EXCEPTION 'media cleanup already installed';
  END IF;
END $guard$;

CREATE TABLE hocalist.media_cleanup_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  plan_hash text NOT NULL,
  plan_limit integer NOT NULL CHECK (plan_limit BETWEEN 1 AND 500),
  dry_run boolean NOT NULL,
  candidate_count integer NOT NULL CHECK (candidate_count >= 0),
  rejected_count integer NOT NULL CHECK (rejected_count >= 0),
  -- A service-role worker has no user subject, so `ran_by` stays null and the
  -- actor is recorded explicitly instead of forging a user id.
  actor_kind text NOT NULL CHECK (actor_kind IN ('service_role','user')),
  ran_by uuid REFERENCES hocalist.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT media_cleanup_audit_actor_shape CHECK (
    (actor_kind='user' AND ran_by IS NOT NULL)
    OR (actor_kind='service_role' AND ran_by IS NULL))
);
ALTER TABLE hocalist.media_cleanup_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.media_cleanup_audit
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION hocalist.media_referenced(p_image uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF to_regclass('hocalist.store_listings') IS NOT NULL AND EXISTS (
      SELECT 1 FROM hocalist.store_listings l
      WHERE l.image_media_ids ? p_image::text) THEN RETURN true; END IF;
  IF to_regclass('hocalist.offer_revisions') IS NOT NULL AND EXISTS (
      SELECT 1 FROM hocalist.offer_revisions r
      WHERE r.image_media_ids ? p_image::text) THEN RETURN true; END IF;
  IF to_regclass('hocalist.conversation_messages') IS NOT NULL
     AND EXISTS (SELECT 1 FROM pg_attribute
       WHERE attrelid='hocalist.conversation_messages'::regclass
         AND attname='attachment_media_ids' AND NOT attisdropped)
     AND EXISTS (SELECT 1 FROM hocalist.conversation_messages msg
       WHERE msg.attachment_media_ids ? p_image::text) THEN RETURN true; END IF;
  IF to_regclass('hocalist.role_profiles') IS NOT NULL AND EXISTS (
      SELECT 1 FROM pg_attribute
      WHERE attrelid='hocalist.role_profiles'::regclass
        AND attname='image_media_id' AND NOT attisdropped)
     AND EXISTS (SELECT 1 FROM hocalist.role_profiles rp
      WHERE rp.image_media_id=p_image) THEN RETURN true; END IF;
  IF to_regclass('hocalist.review_evidence_links') IS NOT NULL AND EXISTS (
      SELECT 1 FROM hocalist.review_evidence_links l WHERE l.media_id=p_image) THEN
    RETURN true; END IF;
  RETURN false;
END $$;

-- Canonical, versioned plan-hash payload. The limit is part of the hashed
-- payload, so two different limits with identical candidate lists never share
-- a hash. The planner and apply compute the same payload.
CREATE FUNCTION hocalist.media_cleanup_hash(
  p_limit integer, p_drafts jsonb, p_orphans jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT encode(sha256(convert_to(jsonb_build_object(
    'version',1,
    'plan_limit',p_limit,
    'drafts',p_drafts,
    'orphans',p_orphans)::text,'UTF8')),'hex');
$$;

-- Read-only plan. `drafts` are unfinished uploads; `orphans` are ready images
-- with no durable reference. Evidence purposes are excluded entirely. The
-- returned `plan_hash` covers exactly the limit and candidate ids, so an
-- unchanged plan re-hashes to the same value and a changed candidate set or
-- limit does not.
CREATE FUNCTION hocalist.media_cleanup_plan(p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  n integer;
  drafts jsonb;
  orphans jsonb;
  v_hash text;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  n := p_limit;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',mi.id,'purpose',mi.purpose,'created_at',mi.created_at)
    ORDER BY mi.created_at,mi.id),'[]'::jsonb) INTO drafts
  FROM (SELECT * FROM hocalist.media_images
        WHERE state='pending' AND purpose NOT IN ('review','report')
          AND created_at < now() - interval '24 hours'
        ORDER BY created_at,id LIMIT n) mi;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',mi.id,'purpose',mi.purpose,'created_at',mi.created_at)
    ORDER BY mi.created_at,mi.id),'[]'::jsonb) INTO orphans
  FROM (SELECT * FROM hocalist.media_images
        WHERE state='ready' AND purpose NOT IN ('review','report')
          AND created_at < now() - interval '7 days'
        ORDER BY created_at,id LIMIT n) mi
  WHERE NOT hocalist.media_referenced(mi.id)
    AND NOT EXISTS (SELECT 1 FROM hocalist.evidence_holds h
      WHERE h.media_id=mi.id AND h.released_at IS NULL);
  v_hash := hocalist.media_cleanup_hash(n,drafts,orphans);
  RETURN jsonb_build_object(
    'planned_at',now(),
    'plan_limit',n,
    'plan_hash',v_hash,
    'dry_run_only',true,
    'excluded_purposes',jsonb_build_array('review','report'),
    'drafts',drafts,
    'orphans',orphans);
END $$;

-- Service-only apply. Defaults to a dry run; a real run needs dry_run=false
-- and the plan_hash returned by `media_cleanup_plan` for the same plan_limit.
CREATE FUNCTION hocalist.media_cleanup_apply(p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  plan jsonb;
  v_hash text;
  v_limit integer;
  v_dry boolean := true;
  v_actor text;
  v_ran_by uuid;
  draft_ids uuid[];
  orphan_ids uuid[];
  rejected integer := 0;
BEGIN
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input)<>'object'
     OR p_input - ARRAY['plan_hash','plan_limit','dry_run'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'plan_hash') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_input->'plan_limit') IS DISTINCT FROM 'number' THEN
    RAISE EXCEPTION 'invalid_cleanup_command' USING ERRCODE='22023';
  END IF;
  v_limit := (p_input->>'plan_limit')::integer;
  IF v_limit NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'invalid_cleanup_command' USING ERRCODE='22023';
  END IF;
  IF p_input ? 'dry_run' THEN
    IF jsonb_typeof(p_input->'dry_run')<>'boolean' THEN
      RAISE EXCEPTION 'invalid_cleanup_command' USING ERRCODE='22023';
    END IF;
    v_dry := (p_input->>'dry_run')::boolean;
  END IF;
  plan := hocalist.media_cleanup_plan(v_limit);
  -- Recompute the canonical payload hash from the recomputed plan; both the
  -- planner output and the caller's confirmation must match it.
  v_hash := hocalist.media_cleanup_hash(
    v_limit, plan->'drafts', plan->'orphans');
  IF v_hash IS DISTINCT FROM plan->>'plan_hash'
     OR (p_input->>'plan_hash') <> v_hash THEN
    RAISE EXCEPTION 'plan_changed' USING ERRCODE='P0001';
  END IF;
  SELECT coalesce(array_agg((e->>'id')::uuid),ARRAY[]::uuid[]) INTO draft_ids
    FROM jsonb_array_elements(plan->'drafts') e;
  SELECT coalesce(array_agg((e->>'id')::uuid),ARRAY[]::uuid[]) INTO orphan_ids
    FROM jsonb_array_elements(plan->'orphans') e;
  -- Actor semantics: a real user subject is attributed; a service-role worker
  -- without a subject is recorded as such and never given a forged user id.
  IF u IS NOT NULL AND EXISTS (SELECT 1 FROM hocalist.profiles WHERE id=u) THEN
    v_actor := 'user';
    v_ran_by := u;
  ELSE
    v_actor := 'service_role';
    v_ran_by := NULL;
  END IF;
  IF NOT v_dry THEN
    -- Re-assert every exclusion in the executing transaction. Nothing linked,
    -- held, referenced or evidence-purpose can be marked rejected.
    UPDATE hocalist.media_images mi SET state='rejected'
      WHERE mi.id = ANY(draft_ids)
        AND mi.state='pending' AND mi.purpose NOT IN ('review','report')
        AND NOT hocalist.media_referenced(mi.id)
        AND NOT EXISTS (SELECT 1 FROM hocalist.evidence_holds h
          WHERE h.media_id=mi.id AND h.released_at IS NULL);
    GET DIAGNOSTICS rejected = ROW_COUNT;
  END IF;
  INSERT INTO hocalist.media_cleanup_audit(
    plan_hash,plan_limit,dry_run,candidate_count,rejected_count,actor_kind,ran_by)
  VALUES (v_hash,v_limit,v_dry,
    coalesce(array_length(draft_ids,1),0)+coalesce(array_length(orphan_ids,1),0),
    rejected,v_actor,v_ran_by);
  RETURN jsonb_build_object(
    'dry_run',v_dry,
    'plan_hash',v_hash,
    'plan_limit',v_limit,
    'actor_kind',v_actor,
    'draft_candidates',coalesce(array_length(draft_ids,1),0),
    'orphan_candidates',coalesce(array_length(orphan_ids,1),0),
    'rejected_count',rejected,
    'orphans_untouched',true,
    'note',
      'Orphan storage bytes are never removed by SQL. Evidence, linked, held '
      'and referenced media are excluded from every cleanup path.');
END $$;

REVOKE ALL ON FUNCTION hocalist.media_referenced(uuid),
  hocalist.media_cleanup_hash(integer,jsonb,jsonb),
  hocalist.media_cleanup_plan(integer),
  hocalist.media_cleanup_apply(text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.media_cleanup_plan(integer),
  hocalist.media_cleanup_apply(text,jsonb)
  TO service_role;

DO $hocalist_media_cleanup_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT coalesce((SELECT relrowsecurity FROM pg_class
      WHERE oid=to_regclass('hocalist.media_cleanup_audit')),false) THEN
    v_issues := array_append(v_issues,'missing RLS');
  END IF;
  IF has_function_privilege('authenticated',
      'hocalist.media_cleanup_plan(integer)','EXECUTE')
     OR has_function_privilege('anon',
      'hocalist.media_cleanup_apply(text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated',
      'hocalist.media_cleanup_hash(integer,jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('service_role',
      'hocalist.media_cleanup_hash(integer,jsonb,jsonb)','EXECUTE')
     OR NOT has_function_privilege('service_role',
      'hocalist.media_cleanup_apply(text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues,'cleanup grants are wrong');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist media cleanup post-apply failed: %',
      array_to_string(v_issues,' | ');
  END IF;
END
$hocalist_media_cleanup_postapply$;

DO $verify$ DECLARE f oid; r text; priv text; BEGIN
f:=to_regprocedure('hocalist.account_lifecycle_status()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'84c4982b08338404c12ec7d5f24ef624' THEN RAISE EXCEPTION 'Function drift: hocalist.account_lifecycle_status()'; END IF;
f:=to_regprocedure('hocalist.account_consent_record(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'9272209040ec59c962ef985d28b2c87b' THEN RAISE EXCEPTION 'Function drift: hocalist.account_consent_record(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.account_export_request(text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'1d54c9ae2d2a0bbf77132016cafb931d' THEN RAISE EXCEPTION 'Function drift: hocalist.account_export_request(text)'; END IF;
f:=to_regprocedure('hocalist.account_export_read(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'8c503ea6351de2175248a7982ebb98b7' THEN RAISE EXCEPTION 'Function drift: hocalist.account_export_read(uuid)'; END IF;
f:=to_regprocedure('hocalist.account_deletion_request(text)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'36849bec7e52b13e6c8f90f6bf488051' THEN RAISE EXCEPTION 'Function drift: hocalist.account_deletion_request(text)'; END IF;
f:=to_regprocedure('hocalist.account_deletion_cancel(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'0a241d30bf88500a840e701ecc1b25ee' THEN RAISE EXCEPTION 'Function drift: hocalist.account_deletion_cancel(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.admin_account_lifecycle_command(text,text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'295d832a6f7bdffcc5ba2e7334a9650e' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_account_lifecycle_command(text,text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.seller_profile_categories()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'75a922092117f2685fc51cf05f1e2030' THEN RAISE EXCEPTION 'Function drift: hocalist.seller_profile_categories()'; END IF;
f:=to_regprocedure('hocalist.member_seller_categories(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c9f860652a33f36bdef40dd0fa193435' THEN RAISE EXCEPTION 'Function drift: hocalist.member_seller_categories(uuid)'; END IF;
f:=to_regprocedure('hocalist.profile_categories_update(text,bigint,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'433f5a25f9ceb95be170c97b4a98574f' THEN RAISE EXCEPTION 'Function drift: hocalist.profile_categories_update(text,bigint,jsonb)'; END IF;
f:=to_regprocedure('hocalist.review_evidence_attach(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c8829dc765ab7d7cfa4ce23b76479aea' THEN RAISE EXCEPTION 'Function drift: hocalist.review_evidence_attach(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.review_evidence_detach(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'9b1e126f1a419f81a8c38759cb5b979a' THEN RAISE EXCEPTION 'Function drift: hocalist.review_evidence_detach(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.report_evidence_attach(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'0c8bcc58301847d736966622d75e3a77' THEN RAISE EXCEPTION 'Function drift: hocalist.report_evidence_attach(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.report_evidence_detach(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'86ce58dd9e35bf2120b904b177bc4800' THEN RAISE EXCEPTION 'Function drift: hocalist.report_evidence_detach(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.admin_review_evidence(integer)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c05503ecbd1c9c74fdaa52f4165da12a' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_review_evidence(integer)'; END IF;
f:=to_regprocedure('hocalist.admin_evidence_hold(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'2c6a409e8cbb64308c283896b3a00c47' THEN RAISE EXCEPTION 'Function drift: hocalist.admin_evidence_hold(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.account_lifecycle_holds(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'9e71a63ac9b8612ddefaa3481b54464f' THEN RAISE EXCEPTION 'Function drift: hocalist.account_lifecycle_holds(uuid)'; END IF;
f:=to_regprocedure('hocalist.account_export_build(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'9d4c42a6044e0e6941541e1b9a697d04' THEN RAISE EXCEPTION 'Function drift: hocalist.account_export_build(uuid)'; END IF;
f:=to_regprocedure('hocalist.review_evidence_validate()');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'6de8fae15e022babfd20a0f629217ef0' THEN RAISE EXCEPTION 'Function drift: hocalist.review_evidence_validate()'; END IF;
f:=to_regprocedure('hocalist.media_read_review_evidence(uuid,uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'ef4f9d5784b9547204b2a17e805757cf' THEN RAISE EXCEPTION 'Function drift: hocalist.media_read_review_evidence(uuid,uuid)'; END IF;
f:=to_regprocedure('hocalist.media_referenced(uuid)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'72e74e82b96d7e6211fdea59140d3ea9' THEN RAISE EXCEPTION 'Function drift: hocalist.media_referenced(uuid)'; END IF;
f:=to_regprocedure('hocalist.media_cleanup_hash(integer,jsonb,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'537c3fe44907fb6ecc93bf0954662dde' THEN RAISE EXCEPTION 'Function drift: hocalist.media_cleanup_hash(integer,jsonb,jsonb)'; END IF;
f:=to_regprocedure('hocalist.media_cleanup_plan(integer)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'03b033dce1b941ecbba896b985b97592' THEN RAISE EXCEPTION 'Function drift: hocalist.media_cleanup_plan(integer)'; END IF;
f:=to_regprocedure('hocalist.media_cleanup_apply(text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'93822f6943f3b00db2e6b73f93734616' THEN RAISE EXCEPTION 'Function drift: hocalist.media_cleanup_apply(text,jsonb)'; END IF;
f:=to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)');
IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'f61ca2fd97d64c7cccaef279424d3c64' THEN RAISE EXCEPTION 'Function drift: hocalist.media_gateway(uuid,text,jsonb)'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.account_consent_documents')),false) THEN RAISE EXCEPTION 'Missing RLS: account_consent_documents'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.account_consent_documents',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: account_consent_documents % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.account_consents')),false) THEN RAISE EXCEPTION 'Missing RLS: account_consents'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.account_consents',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: account_consents % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.account_export_requests')),false) THEN RAISE EXCEPTION 'Missing RLS: account_export_requests'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.account_export_requests',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: account_export_requests % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.account_exports')),false) THEN RAISE EXCEPTION 'Missing RLS: account_exports'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.account_exports',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: account_exports % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.account_deletion_requests')),false) THEN RAISE EXCEPTION 'Missing RLS: account_deletion_requests'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.account_deletion_requests',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: account_deletion_requests % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.role_profile_categories')),false) THEN RAISE EXCEPTION 'Missing RLS: role_profile_categories'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.role_profile_categories',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: role_profile_categories % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.review_evidence_links')),false) THEN RAISE EXCEPTION 'Missing RLS: review_evidence_links'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.review_evidence_links',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: review_evidence_links % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.evidence_audit')),false) THEN RAISE EXCEPTION 'Missing RLS: evidence_audit'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.evidence_audit',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: evidence_audit % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.evidence_holds')),false) THEN RAISE EXCEPTION 'Missing RLS: evidence_holds'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.evidence_holds',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: evidence_holds % %',r,priv; END IF; END LOOP; END LOOP;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.media_cleanup_audit')),false) THEN RAISE EXCEPTION 'Missing RLS: media_cleanup_audit'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.media_cleanup_audit',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: media_cleanup_audit % %',r,priv; END IF; END LOOP; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.account_lifecycle_status()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.account_lifecycle_status() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.account_consent_record(text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.account_consent_record(text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.account_export_request(text)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.account_export_request(text) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.account_export_read(uuid)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.account_export_read(uuid) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.account_deletion_request(text)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.account_deletion_request(text) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.account_deletion_cancel(text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.account_deletion_cancel(text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_account_lifecycle_command(text,text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_account_lifecycle_command(text,text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.seller_profile_categories()'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.seller_profile_categories() %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.member_seller_categories(uuid)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.member_seller_categories(uuid) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.profile_categories_update(text,bigint,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.profile_categories_update(text,bigint,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.review_evidence_attach(text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.review_evidence_attach(text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.review_evidence_detach(text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.review_evidence_detach(text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.report_evidence_attach(text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.report_evidence_attach(text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.report_evidence_detach(text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.report_evidence_detach(text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_review_evidence(integer)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_review_evidence(integer) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.admin_evidence_hold(text,jsonb)'),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.admin_evidence_hold(text,jsonb) %',r; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.account_lifecycle_holds(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.account_lifecycle_holds(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.account_export_build(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.account_export_build(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.review_evidence_validate()'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.review_evidence_validate()'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.media_read_review_evidence(uuid,uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.media_read_review_evidence(uuid,uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.media_referenced(uuid)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.media_referenced(uuid)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.media_cleanup_hash(integer,jsonb,jsonb)'),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: hocalist.media_cleanup_hash(integer,jsonb,jsonb)'; END IF; END LOOP;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.media_cleanup_plan(integer)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: hocalist.media_cleanup_plan(integer)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.media_cleanup_plan(integer)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.media_cleanup_plan(integer)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.media_cleanup_apply(text,jsonb)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: hocalist.media_cleanup_apply(text,jsonb)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.media_cleanup_apply(text,jsonb)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.media_cleanup_apply(text,jsonb)'; END IF;
FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)'),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: hocalist.media_gateway(uuid,text,jsonb)'; END IF; END LOOP;
IF NOT has_function_privilege('service_role',to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)'),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: hocalist.media_gateway(uuid,text,jsonb)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='hocalist.media_images'::regclass AND conname='media_images_purpose_check' AND pg_get_constraintdef(oid) LIKE '%review%' AND pg_get_constraintdef(oid) LIKE '%report%') THEN RAISE EXCEPTION 'media purpose constraint missing review/report'; END IF;

END $verify$;
COMMIT;

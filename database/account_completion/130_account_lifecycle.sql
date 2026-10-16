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
BEGIN;
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
COMMIT;

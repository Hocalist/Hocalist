-- Manual verification and seller-health review workflow.
--
-- September 26 approved rule: begin with reviewable admin decisions.
-- Verified email/phone (Auth) stays separate from reviewed business/identity
-- evidence. A report is a signal, never an automatic penalty. A restriction
-- requires an authorized reviewer, a recorded reason and an appeal route.
-- No automated score, threshold or retention period is invented here.
BEGIN;
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
COMMIT;

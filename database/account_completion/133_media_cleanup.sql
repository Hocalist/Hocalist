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
BEGIN;
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
COMMIT;

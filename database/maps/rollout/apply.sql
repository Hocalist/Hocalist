-- Hocalist Places gateway rollout: guarded single-transaction apply of the
-- secured Places gateway (draft 050). This file is the reviewed draft with
-- this header; database/maps/tests/places_rollout.test.mjs asserts the draft
-- text is present verbatim.
--
-- Prerequisites already deployed and preserved (never re-run here): account
-- 003/004 (profiles, memberships, account_command). The hocalist-places Edge
-- Function is deployed separately and holds the Google Places server
-- credential; this bundle creates no client-callable surface and no
-- credential.
--
-- On any drift or pre-existing places gateway object the guard aborts the
-- whole transaction; nothing is dropped, cascaded or overwritten.
-- DRAFT: secured Places gateway for the hocalist-places Edge Function.
--
-- The Edge Function holds the Google server credential; this module holds the
-- server-authoritative authorization state the function must pass before any
-- provider request: verified caller identity (checked by the function), active
-- Hocalist membership, identity-bound search sessions, selected-suggestion
-- validation for details resolution and shared request ceilings below the
-- Google Places project quotas.
--
-- Privacy: only Google place IDs are persisted (allowed indefinitely by the
-- provider policy). No query text, suggestion label, address, coordinate or
-- provider body is stored or returned to another user.
--
-- All four RPCs are service_role-only: only the deployed Edge Function may
-- call them. A member cannot reach them through PostgREST directly.
--
-- Not an instruction to apply to a live project. Apply only through the
-- guarded bundle in database/maps/rollout after coordinating review.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $places_guard$
BEGIN
  IF to_regclass('hocalist.profiles') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regprocedure('hocalist.account_command(text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Account foundation is missing';
  END IF;
  IF to_regclass('hocalist.places_search_sessions') IS NOT NULL
     OR to_regprocedure('hocalist.places_gate(uuid,text,uuid,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Places gateway objects already exist; review before applying';
  END IF;
END
$places_guard$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- One search session per client token, bound to the authenticated member.
-- operation_count bounds how many autocomplete calls a session may make so a
-- single client cannot drive unbounded provider cost inside one session.
CREATE TABLE hocalist.places_search_sessions (
  token uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  operation_count integer NOT NULL DEFAULT 0 CHECK (operation_count >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  resolved_at timestamptz,
  -- Short single-flight reservation taken before a billed details call.
  resolving_at timestamptz
);

-- Place IDs returned to one session. Details resolution is refused for any
-- place ID this session never received.
CREATE TABLE hocalist.places_search_suggestions (
  session_token uuid NOT NULL
    REFERENCES hocalist.places_search_sessions(token) ON DELETE CASCADE,
  place_id text NOT NULL
    CHECK (length(place_id) <= 256 AND place_id ~ '^[A-Za-z0-9_-]+$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_token, place_id)
);

-- Shared request ceilings. Scopes are 'g' (all members) and 'u:<user id>'.
-- Kept in the database because multiple Edge Function instances share them.
CREATE TABLE hocalist.places_rate_counters (
  scope text NOT NULL,
  operation text NOT NULL CHECK (operation IN ('autocomplete','details')),
  window_kind text NOT NULL CHECK (window_kind IN ('minute','day')),
  bucket timestamptz NOT NULL,
  count integer NOT NULL CHECK (count > 0),
  PRIMARY KEY (scope, operation, window_kind, bucket)
);

CREATE INDEX places_sessions_expiry_idx
  ON hocalist.places_search_sessions (expires_at);
CREATE INDEX places_rate_bucket_idx
  ON hocalist.places_rate_counters (bucket);

ALTER TABLE hocalist.places_search_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.places_search_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.places_rate_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.places_search_sessions,
  hocalist.places_search_suggestions, hocalist.places_rate_counters
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- Atomically increments one counter bucket and returns the new count.
CREATE FUNCTION hocalist.places_rate_bump(
  p_scope text,
  p_operation text,
  p_window text,
  p_bucket timestamptz
) RETURNS integer
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  INSERT INTO hocalist.places_rate_counters(
    scope, operation, window_kind, bucket, count)
  VALUES (p_scope, p_operation, p_window, p_bucket, 1)
  ON CONFLICT (scope, operation, window_kind, bucket)
  DO UPDATE SET count = hocalist.places_rate_counters.count + 1
  RETURNING count;
$$;

-- ---------------------------------------------------------------------------
-- Service RPCs (Edge Function only)
-- ---------------------------------------------------------------------------

-- Decides one provider-bound operation. Returns a decision object; it never
-- raises for a denied caller so the Edge Function can map codes deterministically.
CREATE FUNCTION hocalist.places_gate(
  p_user uuid,
  p_operation text,
  p_session_token uuid,
  p_input text,
  p_place_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  -- Request ceilings, deliberately below the Hocalist Google Places project
  -- quotas (autocomplete 1000/day and 60/minute; details 200/day and
  -- 20/minute). These are request limits, not a monetary cap. Raising them is
  -- a reviewed migration, never a client input.
  c_autocomplete_user_minute constant integer := 20;
  c_autocomplete_user_day constant integer := 200;
  c_autocomplete_global_minute constant integer := 50;
  c_autocomplete_global_day constant integer := 900;
  c_details_user_minute constant integer := 10;
  c_details_user_day constant integer := 60;
  c_details_global_minute constant integer := 15;
  c_details_global_day constant integer := 180;
  c_session_minutes constant integer := 15;
  c_session_operations constant integer := 10;
  c_session_suggestions constant integer := 50;
  c_reservation_seconds integer := 30;
  v_session hocalist.places_search_sessions%ROWTYPE;
  v_minute timestamptz := date_trunc('minute', now());
  v_day timestamptz := date_trunc('day', now());
  v_user_scope text;
BEGIN
  IF p_user IS NULL OR p_session_token IS NULL
     OR p_operation NOT IN ('autocomplete','details') THEN
    RETURN jsonb_build_object('decision','invalid_input');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM hocalist.memberships m
    WHERE m.user_id = p_user AND m.status = 'active'
  ) OR EXISTS (
    SELECT 1 FROM hocalist.memberships m
    WHERE m.user_id = p_user AND m.status IN ('restricted','disabled')
  ) THEN
    RETURN jsonb_build_object('decision','membership_required');
  END IF;

  -- Opportunistic bounded cleanup keeps the gateway tables small without a
  -- scheduled job; both deletes are index-backed.
  DELETE FROM hocalist.places_rate_counters WHERE bucket < v_day - interval '2 days';
  DELETE FROM hocalist.places_search_sessions WHERE expires_at < now() - interval '1 day';

  v_user_scope := 'u:' || p_user::text;

  IF p_operation = 'autocomplete' THEN
    IF p_input IS NULL OR length(btrim(p_input)) < 1 OR length(p_input) > 200 THEN
      RETURN jsonb_build_object('decision','invalid_input');
    END IF;

    SELECT * INTO v_session FROM hocalist.places_search_sessions
      WHERE token = p_session_token FOR UPDATE;
    IF FOUND THEN
      IF v_session.user_id <> p_user THEN
        RETURN jsonb_build_object('decision','session_invalid');
      END IF;
      IF v_session.resolved_at IS NOT NULL OR v_session.expires_at <= now() THEN
        RETURN jsonb_build_object('decision','session_expired');
      END IF;
      IF v_session.operation_count >= c_session_operations THEN
        RETURN jsonb_build_object('decision','session_exhausted');
      END IF;
    END IF;

    IF hocalist.places_rate_bump(
         v_user_scope, 'autocomplete', 'minute', v_minute)
       > c_autocomplete_user_minute
       OR hocalist.places_rate_bump(
         v_user_scope, 'autocomplete', 'day', v_day)
       > c_autocomplete_user_day
       OR hocalist.places_rate_bump('g', 'autocomplete', 'minute', v_minute)
       > c_autocomplete_global_minute
       OR hocalist.places_rate_bump('g', 'autocomplete', 'day', v_day)
       > c_autocomplete_global_day THEN
      RETURN jsonb_build_object('decision','rate_limited');
    END IF;

    IF v_session.token IS NULL THEN
      INSERT INTO hocalist.places_search_sessions(
        token, user_id, operation_count, expires_at)
      VALUES (
        p_session_token, p_user, 1,
        now() + make_interval(mins => c_session_minutes));
    ELSE
      UPDATE hocalist.places_search_sessions
        SET operation_count = operation_count + 1
        WHERE token = p_session_token;
    END IF;
    RETURN jsonb_build_object(
      'decision','allowed','user_id',p_user,'session',p_session_token);
  END IF;

  -- Details resolution: the place must come from this session's own
  -- suggestions, so a member cannot use the endpoint as a generic place
  -- lookup for arbitrary IDs.
  IF p_place_id IS NULL OR length(p_place_id) > 256
     OR p_place_id !~ '^[A-Za-z0-9_-]+$' THEN
    RETURN jsonb_build_object('decision','invalid_input');
  END IF;

  SELECT * INTO v_session FROM hocalist.places_search_sessions
    WHERE token = p_session_token FOR UPDATE;
  IF NOT FOUND OR v_session.user_id <> p_user THEN
    RETURN jsonb_build_object('decision','session_invalid');
  END IF;
  IF v_session.resolved_at IS NOT NULL OR v_session.expires_at <= now() THEN
    RETURN jsonb_build_object('decision','session_expired');
  END IF;
  IF v_session.resolving_at IS NOT NULL
     AND v_session.resolving_at
       > now() - make_interval(secs => c_reservation_seconds) THEN
    RETURN jsonb_build_object('decision','session_busy');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM hocalist.places_search_suggestions s
    WHERE s.session_token = p_session_token AND s.place_id = p_place_id
  ) THEN
    RETURN jsonb_build_object('decision','suggestion_required');
  END IF;

  IF hocalist.places_rate_bump(v_user_scope, 'details', 'minute', v_minute)
       > c_details_user_minute
     OR hocalist.places_rate_bump(v_user_scope, 'details', 'day', v_day)
       > c_details_user_day
     OR hocalist.places_rate_bump('g', 'details', 'minute', v_minute)
       > c_details_global_minute
     OR hocalist.places_rate_bump('g', 'details', 'day', v_day)
       > c_details_global_day THEN
    RETURN jsonb_build_object('decision','rate_limited');
  END IF;

  UPDATE hocalist.places_search_sessions
    SET resolving_at = now()
    WHERE token = p_session_token;
  RETURN jsonb_build_object(
    'decision','allowed','user_id',p_user,'session',p_session_token);
END; $$;

-- Records the place IDs the provider returned for one session. Called by the
-- Edge Function only after a successful autocomplete response.
CREATE FUNCTION hocalist.places_record_suggestions(
  p_session uuid,
  p_user uuid,
  p_place_ids text[]
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_new integer := coalesce(array_length(p_place_ids, 1), 0);
  v_existing integer;
  v_id text;
BEGIN
  IF p_session IS NULL OR p_user IS NULL OR p_place_ids IS NULL
     OR v_new < 1 OR v_new > 5 THEN
    RETURN jsonb_build_object('recorded', false, 'reason', 'invalid_input');
  END IF;
  PERFORM 1 FROM hocalist.places_search_sessions
    WHERE token = p_session AND user_id = p_user
      AND resolved_at IS NULL AND expires_at > now()
    FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('recorded', false, 'reason', 'session_invalid');
  END IF;
  SELECT count(*) INTO v_existing FROM hocalist.places_search_suggestions
    WHERE session_token = p_session;
  IF v_existing + v_new > 50 THEN
    RETURN jsonb_build_object('recorded', false, 'reason', 'session_full');
  END IF;
  FOREACH v_id IN ARRAY p_place_ids LOOP
    IF v_id IS NULL OR length(v_id) > 256
       OR v_id !~ '^[A-Za-z0-9_-]+$' THEN
      RETURN jsonb_build_object('recorded', false, 'reason', 'invalid_input');
    END IF;
  END LOOP;
  INSERT INTO hocalist.places_search_suggestions(session_token, place_id)
  SELECT p_session, u.place_id FROM unnest(p_place_ids) AS u(place_id)
  ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('recorded', true);
END; $$;

-- Closes a session after its details call succeeded. Idempotent.
CREATE FUNCTION hocalist.places_resolve_session(
  p_session uuid,
  p_user uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_token uuid;
BEGIN
  IF p_session IS NULL OR p_user IS NULL THEN
    RETURN jsonb_build_object('resolved', false, 'reason', 'invalid_input');
  END IF;
  UPDATE hocalist.places_search_sessions
    SET resolved_at = now(), resolving_at = NULL
    WHERE token = p_session AND user_id = p_user AND resolved_at IS NULL
    RETURNING token INTO v_token;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('resolved', false, 'reason', 'session_invalid');
  END IF;
  RETURN jsonb_build_object('resolved', true);
END; $$;

-- Releases the details reservation after a provider failure so the member can
-- retry the same session without waiting out the reservation window.
CREATE FUNCTION hocalist.places_release_session(
  p_session uuid,
  p_user uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_session IS NULL OR p_user IS NULL THEN
    RETURN jsonb_build_object('released', false);
  END IF;
  UPDATE hocalist.places_search_sessions
    SET resolving_at = NULL
    WHERE token = p_session AND user_id = p_user AND resolved_at IS NULL;
  RETURN jsonb_build_object('released', FOUND);
END; $$;

-- ---------------------------------------------------------------------------
-- Grants and post-apply verification
-- ---------------------------------------------------------------------------

-- The Edge Function calls these RPCs with the service role; the grant is
-- additive and keeps this bundle independent of the Stripe inbox bundle.
GRANT USAGE ON SCHEMA hocalist TO service_role;

REVOKE ALL ON FUNCTION hocalist.places_rate_bump(text,text,text,timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.places_gate(uuid,text,uuid,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.places_record_suggestions(uuid,uuid,text[])
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.places_resolve_session(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.places_release_session(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION hocalist.places_gate(uuid,text,uuid,text,text)
  TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.places_record_suggestions(uuid,uuid,text[])
  TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.places_resolve_session(uuid,uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.places_release_session(uuid,uuid)
  TO service_role;

DO $hocalist_places_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_service_functions constant text[] := ARRAY[
    'places_gate(uuid,text,uuid,text,text)',
    'places_record_suggestions(uuid,uuid,text[])',
    'places_resolve_session(uuid,uuid)',
    'places_release_session(uuid,uuid)'];
  v_tables constant text[] := ARRAY[
    'places_search_sessions','places_search_suggestions','places_rate_counters'];
  v_fn text;
  v_table text;
  v_columns text[];
  v_expected_sessions constant text[] := ARRAY[
    'token:uuid','user_id:uuid','operation_count:integer',
    'created_at:timestamp with time zone','expires_at:timestamp with time zone',
    'resolved_at:timestamp with time zone','resolving_at:timestamp with time zone'];
  v_expected_suggestions constant text[] := ARRAY[
    'session_token:uuid','place_id:text','created_at:timestamp with time zone'];
  v_expected_counters constant text[] := ARRAY[
    'scope:text','operation:text','window_kind:text',
    'bucket:timestamp with time zone','count:integer'];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing places table: ' || v_table);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.' || v_table)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: ' || v_table);
    ELSIF has_table_privilege('authenticated', 'hocalist.' || v_table, 'SELECT')
       OR has_table_privilege('anon', 'hocalist.' || v_table, 'SELECT') THEN
      v_issues := array_append(v_issues, 'places table is client-readable: ' || v_table);
    END IF;
  END LOOP;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_search_sessions'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_sessions THEN
    v_issues := array_append(v_issues, 'places_search_sessions columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_search_suggestions'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_suggestions THEN
    v_issues := array_append(v_issues, 'places_search_suggestions columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_rate_counters'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_counters THEN
    v_issues := array_append(v_issues, 'places_rate_counters columns differ from the reviewed shape');
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist'
      AND table_name IN ('places_search_sessions','places_search_suggestions','places_rate_counters')
      AND column_name ~* '(query|label|address|input|display|formatted|latitude|longitude)'
  ) THEN
    v_issues := array_append(v_issues, 'places gateway must not store queries, labels or addresses');
  END IF;
  FOREACH v_fn IN ARRAY v_service_functions LOOP
    IF NOT has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'places function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  IF has_function_privilege(
       'authenticated','hocalist.places_rate_bump(text,text,text,timestamptz)','EXECUTE')
     OR has_function_privilege(
       'service_role','hocalist.places_rate_bump(text,text,text,timestamptz)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'internal places helper is executable');
  END IF;
  IF NOT has_function_privilege(
       'authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed account grants changed');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist places post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_places_postapply$;
COMMIT;

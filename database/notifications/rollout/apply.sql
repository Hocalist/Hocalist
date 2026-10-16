-- Hocalist notification inbox rollout: guarded single-transaction apply of
-- the notification inbox foundation (draft 030). This file is the reviewed
-- draft with this header; database/notifications/tests/
-- notifications_rollout.test.mjs asserts the draft text is present verbatim.
--
-- Prerequisites already deployed and preserved (never re-run here): account
-- 003/004 and push 007. The deployed push queue and enqueue function are
-- extended additively, not replaced.
--
-- On any drift or pre-existing notification inbox object the guard aborts the
-- whole transaction; nothing is dropped, cascaded or overwritten.
-- DRAFT: notification inbox foundation (additive to deployed push 007).
--
-- Extends hocalist.notifications with user-facing content, adds per-user
-- preferences and the participant-authorized inbox/read/preference RPCs plus
-- one internal producer for other SECURITY DEFINER functions. It does not
-- change the deployed push delivery queue, and it does not enable sending.
--
-- Not an instruction to apply to a live project. Apply only through the
-- guarded bundle in database/notifications/rollout after coordinating review.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $notification_guard$
BEGIN
  IF to_regclass('hocalist.profiles') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regclass('hocalist.notifications') IS NULL
     OR to_regclass('hocalist.push_devices') IS NULL
     OR to_regclass('hocalist.push_deliveries') IS NULL
     OR to_regprocedure('hocalist.notification_enqueue(uuid,uuid,text,uuid)') IS NULL
     OR to_regprocedure('hocalist.account_command(text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Account/push foundation 003/004/007 is missing';
  END IF;
  IF to_regclass('hocalist.notification_preferences') IS NOT NULL
     OR to_regprocedure('hocalist.notification_inbox(integer,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Notification inbox objects already exist; review before applying';
  END IF;
END
$notification_guard$;

-- ---------------------------------------------------------------------------
-- Inbox content on the deployed notification rows (additive, nullable)
-- ---------------------------------------------------------------------------

ALTER TABLE hocalist.notifications
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS body text,
  ADD COLUMN IF NOT EXISTS deep_link text,
  ADD COLUMN IF NOT EXISTS payload jsonb;

-- Content bounds apply only when a producer supplies content; the deployed
-- enqueue path keeps working with nulls.
ALTER TABLE hocalist.notifications
  ADD CONSTRAINT notifications_title_bounds CHECK (
    title IS NULL OR length(btrim(title)) BETWEEN 1 AND 160
  ),
  ADD CONSTRAINT notifications_body_bounds CHECK (
    body IS NULL OR length(body) <= 500
  ),
  ADD CONSTRAINT notifications_deep_link_scheme CHECK (
    deep_link IS NULL OR deep_link ~ '^hocalist://[A-Za-z0-9/_-]{1,200}$'
  ),
  ADD CONSTRAINT notifications_payload_bounds CHECK (
    payload IS NULL OR octet_length(payload::text) <= 8192
  );

-- ---------------------------------------------------------------------------
-- Preferences
-- ---------------------------------------------------------------------------

-- Safety alerts are mandatory: the row stores the flag but the constraint
-- keeps it true so no client or producer can silence safety content.
CREATE TABLE hocalist.notification_preferences (
  user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  offers boolean NOT NULL DEFAULT true,
  messages boolean NOT NULL DEFAULT true,
  deals boolean NOT NULL DEFAULT true,
  safety boolean NOT NULL DEFAULT true,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT notification_preferences_safety_mandatory CHECK (safety)
);

ALTER TABLE hocalist.notification_preferences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.notification_preferences FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Internal producer (client-denied)
-- ---------------------------------------------------------------------------

-- Emits one inbox row for one committed event. Deduplicated on
-- (user, event_key); disabled optional topics are skipped without an error.
-- Safety content is always emitted. Returns the notification id, or null when
-- the topic is disabled.
CREATE FUNCTION hocalist.notification_emit(
  p_user uuid,
  p_event uuid,
  p_kind text,
  p_source uuid,
  p_title text,
  p_body text,
  p_deep_link text,
  p_payload jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_prefs hocalist.notification_preferences%ROWTYPE;
  v_id uuid;
  v_topic text;
BEGIN
  IF p_user IS NULL OR p_event IS NULL OR p_source IS NULL THEN
    RAISE EXCEPTION 'invalid_field: notification' USING ERRCODE='22023';
  END IF;
  IF p_kind NOT IN ('new_offer','new_message','meeting_update','billing_update','account_update') THEN
    RAISE EXCEPTION 'invalid_field: kind' USING ERRCODE='22023';
  END IF;
  v_topic := CASE p_kind
    WHEN 'new_offer' THEN 'offers'
    WHEN 'new_message' THEN 'messages'
    WHEN 'meeting_update' THEN 'deals'
    WHEN 'billing_update' THEN 'deals'
    ELSE 'safety'
  END;
  IF v_topic <> 'safety' THEN
    SELECT * INTO v_prefs FROM hocalist.notification_preferences WHERE user_id = p_user;
    IF FOUND THEN
      IF v_topic = 'offers' AND NOT v_prefs.offers THEN RETURN NULL; END IF;
      IF v_topic = 'messages' AND NOT v_prefs.messages THEN RETURN NULL; END IF;
      IF v_topic = 'deals' AND NOT v_prefs.deals THEN RETURN NULL; END IF;
    END IF;
  END IF;
  INSERT INTO hocalist.notifications(
    user_id, event_key, kind, source_id, title, body, deep_link, payload)
  VALUES (p_user, p_event, p_kind, p_source, p_title, p_body, p_deep_link, p_payload)
  ON CONFLICT (user_id, event_key) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM hocalist.notifications
      WHERE user_id = p_user AND event_key = p_event;
  END IF;
  RETURN v_id;
END; $$;

-- ---------------------------------------------------------------------------
-- Client RPCs
-- ---------------------------------------------------------------------------

-- One page of the caller's inbox, newest first. The cursor is
-- "<created_at iso>|<id>", validated server-side; no client can read another
-- user's rows.
CREATE FUNCTION hocalist.notification_inbox(
  p_limit integer,
  p_cursor text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_limit integer;
  v_created timestamptz;
  v_id uuid;
  v_items jsonb;
  v_next text;
  v_unread integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM hocalist.memberships m
    WHERE m.user_id = v_user AND m.status = 'active'
  ) THEN
    RAISE EXCEPTION 'membership_required' USING ERRCODE='42501';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'invalid_field: p_limit' USING ERRCODE='22023';
  END IF;
  v_limit := p_limit;
  IF p_cursor IS NOT NULL AND btrim(p_cursor) <> '' THEN
    IF p_cursor !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]{8,}\|[0-9a-f-]{36}$' THEN
      RAISE EXCEPTION 'invalid_field: p_cursor' USING ERRCODE='22023';
    END IF;
    BEGIN
      v_created := split_part(p_cursor, '|', 1)::timestamptz;
      v_id := split_part(p_cursor, '|', 2)::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid_field: p_cursor' USING ERRCODE='22023';
    END;
  END IF;

  SELECT coalesce(jsonb_agg(row_json ORDER BY created_at DESC, id DESC), '[]'::jsonb)
    INTO v_items
  FROM (
    SELECT
      n.created_at,
      n.id,
      jsonb_build_object(
        'id', n.id,
        'kind', n.kind,
        'title', coalesce(n.title, 'Hocalist update'),
        'body', coalesce(n.body, ''),
        'deep_link', n.deep_link,
        'source_id', n.source_id,
        'payload', n.payload,
        'read_at', n.read_at,
        'created_at', n.created_at
      ) AS row_json
    FROM hocalist.notifications n
    WHERE n.user_id = v_user
      AND (v_created IS NULL OR (n.created_at, n.id) < (v_created, v_id))
    ORDER BY n.created_at DESC, n.id DESC
    LIMIT v_limit + 1
  ) page;

  IF jsonb_array_length(v_items) > v_limit THEN
    v_next := (v_items->(v_limit - 1)->>'created_at') || '|' ||
              (v_items->(v_limit - 1)->>'id');
    v_items := (SELECT coalesce(jsonb_agg(value), '[]'::jsonb)
                FROM jsonb_array_elements(v_items) WITH ORDINALITY AS t(value, ord)
                WHERE ord <= v_limit);
  END IF;

  SELECT count(*)::integer INTO v_unread
  FROM hocalist.notifications
  WHERE user_id = v_user AND read_at IS NULL;

  RETURN jsonb_build_object(
    'items', v_items,
    'next_cursor', v_next,
    'unread_count', v_unread
  );
END; $$;

-- Marks one notification read. Idempotent; returns the authoritative row for
-- the caller only.
CREATE FUNCTION hocalist.notification_mark_read(p_notification uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_row hocalist.notifications%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF p_notification IS NULL THEN
    RAISE EXCEPTION 'invalid_field: p_notification' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_row FROM hocalist.notifications
    WHERE id = p_notification AND user_id = v_user FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'notification_access_denied' USING ERRCODE='42501';
  END IF;
  IF v_row.read_at IS NULL THEN
    UPDATE hocalist.notifications SET read_at = now()
      WHERE id = p_notification AND user_id = v_user
      RETURNING * INTO v_row;
  END IF;
  RETURN jsonb_build_object(
    'id', v_row.id,
    'read_at', v_row.read_at
  );
END; $$;

-- Marks every unread notification read. Returns the number of rows changed.
CREATE FUNCTION hocalist.notification_mark_all_read()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_count integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  UPDATE hocalist.notifications SET read_at = now()
    WHERE user_id = v_user AND read_at IS NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('marked', v_count);
END; $$;

-- Current preferences for the caller. Defaults are returned without writing a
-- row; the first update creates it.
CREATE FUNCTION hocalist.notification_preferences()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'offers', coalesce(p.offers, true),
    'messages', coalesce(p.messages, true),
    'deals', coalesce(p.deals, true),
    'safety', true,
    'revision', coalesce(p.revision, 0),
    'updated_at', p.updated_at
  )
  FROM (SELECT 1) AS anchor
  LEFT JOIN hocalist.notification_preferences p ON p.user_id = auth.uid()
  WHERE auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id = auth.uid() AND m.status = 'active'
    );
$$;

-- Replaces the editable preference values at an expected revision. Safety is
-- mandatory and a false value is rejected instead of silently ignored.
CREATE FUNCTION hocalist.notification_preferences_update(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_expected bigint;
  v_offers boolean;
  v_messages boolean;
  v_deals boolean;
  v_safety boolean;
  v_field text;
  v_row hocalist.notification_preferences%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF p_input IS NULL OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_field: p_input' USING ERRCODE='22023';
  END IF;
  FOR v_field IN SELECT k FROM jsonb_object_keys(p_input) k
    WHERE NOT (k = ANY(ARRAY['offers','messages','deals','safety','expected_revision']))
  LOOP
    RAISE EXCEPTION 'unknown_field: %', v_field USING ERRCODE='22023';
  END LOOP;
  IF jsonb_typeof(p_input->'expected_revision') <> 'number'
     OR (p_input->>'expected_revision') !~ '^[0-9]{1,18}$' THEN
    RAISE EXCEPTION 'invalid_field: expected_revision' USING ERRCODE='22023';
  END IF;
  v_expected := (p_input->>'expected_revision')::bigint;
  IF jsonb_typeof(p_input->'offers') <> 'boolean'
     OR jsonb_typeof(p_input->'messages') <> 'boolean'
     OR jsonb_typeof(p_input->'deals') <> 'boolean' THEN
    RAISE EXCEPTION 'invalid_field: preferences' USING ERRCODE='22023';
  END IF;
  v_offers := (p_input->>'offers')::boolean;
  v_messages := (p_input->>'messages')::boolean;
  v_deals := (p_input->>'deals')::boolean;
  IF p_input ? 'safety' THEN
    IF jsonb_typeof(p_input->'safety') <> 'boolean' THEN
      RAISE EXCEPTION 'invalid_field: safety' USING ERRCODE='22023';
    END IF;
    v_safety := (p_input->>'safety')::boolean;
    IF NOT v_safety THEN
      RAISE EXCEPTION 'safety_alerts_required' USING ERRCODE='22023';
    END IF;
  END IF;

  SELECT * INTO v_row FROM hocalist.notification_preferences
    WHERE user_id = v_user FOR UPDATE;
  IF NOT FOUND THEN
    IF v_expected <> 0 THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    INSERT INTO hocalist.notification_preferences(
      user_id, offers, messages, deals, safety)
    VALUES (v_user, v_offers, v_messages, v_deals, true)
    RETURNING * INTO v_row;
  ELSE
    IF v_row.revision <> v_expected THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    UPDATE hocalist.notification_preferences
      SET offers = v_offers,
          messages = v_messages,
          deals = v_deals,
          safety = true,
          revision = revision + 1,
          updated_at = now()
      WHERE user_id = v_user
      RETURNING * INTO v_row;
  END IF;

  RETURN jsonb_build_object(
    'offers', v_row.offers,
    'messages', v_row.messages,
    'deals', v_row.deals,
    'safety', v_row.safety,
    'revision', v_row.revision,
    'updated_at', v_row.updated_at
  );
END; $$;

-- ---------------------------------------------------------------------------
-- Grants and post-apply verification
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.notification_inbox(integer,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.notification_mark_read(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.notification_mark_all_read()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.notification_preferences()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.notification_preferences_update(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION hocalist.notification_inbox(integer,text) TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.notification_mark_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.notification_mark_all_read() TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.notification_preferences() TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.notification_preferences_update(jsonb) TO authenticated;

DO $hocalist_notification_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_client_functions constant text[] := ARRAY[
    'notification_inbox(integer,text)','notification_mark_read(uuid)',
    'notification_mark_all_read()','notification_preferences()',
    'notification_preferences_update(jsonb)'];
  v_internal_functions constant text[] := ARRAY[
    'notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)',
    'notification_enqueue(uuid,uuid,text,uuid)'];
  v_fn text;
  v_columns text[];
  v_expected text[] := ARRAY[
    'id:uuid','user_id:uuid','event_key:uuid','kind:text','source_id:uuid',
    'created_at:timestamp with time zone','read_at:timestamp with time zone',
    'title:text','body:text','deep_link:text','payload:jsonb'];
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'hocalist.notification_preferences'::regclass
      AND conname = 'notification_preferences_safety_mandatory'
  ) THEN
    v_issues := array_append(v_issues, 'safety preference is not mandatory');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid = 'hocalist.notifications'::regclass AND attnum > 0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected THEN
    v_issues := array_append(v_issues, 'notifications columns differ from the reviewed shape');
  END IF;
  FOREACH v_fn IN ARRAY v_client_functions LOOP
    IF NOT has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'notification function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY v_internal_functions LOOP
    IF has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'internal notification function is executable: ' || v_fn);
    END IF;
  END LOOP;
  -- The deployed push queue and account state must be untouched.
  IF NOT has_function_privilege('authenticated','hocalist.push_device_register(uuid,text,text,boolean)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE')
     OR NOT has_table_privilege('authenticated','hocalist.memberships','SELECT') THEN
    v_issues := array_append(v_issues, 'deployed account/push grants changed');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist notification post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_notification_postapply$;
COMMIT;

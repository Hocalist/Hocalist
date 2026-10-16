-- DRAFT: request-update lead notifications (additive to inbox 030 + producers 031).
--
-- When an active buyer request changes (title, description, condition, service
-- type, quantity, budget, higher-offer choice or category), every seller with a
-- live offer on that request receives one `request_update` inbox row. The
-- recipient set is derived from committed `hocalist.offers` rows and the event
-- key includes the request revision, so replaying the same revision cannot
-- duplicate the row. No address, contact, PIN or payment detail is copied.
--
-- This draft also adds the `leads` notification topic so a seller can silence
-- lead and lead-update alerts. The preference is optional on update for
-- backward compatibility with already-installed clients; the emitter defaults
-- it to enabled. Safety content is unaffected.
--
-- Not an instruction to apply to a live project. Apply only through the
-- guarded bundle in database/notifications/request-update-rollout after
-- coordinating review.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $request_update_producer_guard$
BEGIN
  IF to_regclass('hocalist.notifications') IS NULL
     OR to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('hocalist.notification_recipient_allowed(uuid)') IS NULL
     OR to_regclass('hocalist.notification_preferences') IS NULL
     OR to_regclass('hocalist.requests') IS NULL
     OR to_regclass('hocalist.offers') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL THEN
    RAISE EXCEPTION 'Notification/producer/request foundation is missing';
  END IF;
  IF to_regprocedure('hocalist.notification_on_request_update()') IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM pg_attribute
       WHERE attrelid = 'hocalist.notification_preferences'::regclass
         AND attname = 'leads' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'Request-update producer already exists; review before applying';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM pg_constraint
       WHERE conrelid = 'hocalist.notifications'::regclass
         AND conname = 'notifications_kind_check'
         AND pg_get_constraintdef(oid) NOT LIKE '%request_update%')
     OR to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Notification kind constraint is missing or already extended';
  END IF;
END
$request_update_producer_guard$;

-- ---------------------------------------------------------------------------
-- Lead preference topic and request_update event kind
-- ---------------------------------------------------------------------------

ALTER TABLE hocalist.notification_preferences
  ADD COLUMN leads boolean NOT NULL DEFAULT true;

-- The deployed push table keeps its own kind constraint; extend it in the same
-- transaction so the emitter and the stored row agree.
ALTER TABLE hocalist.notifications
  DROP CONSTRAINT notifications_kind_check;
ALTER TABLE hocalist.notifications
  ADD CONSTRAINT notifications_kind_check CHECK (
    kind IN ('new_offer','new_message','meeting_update','request_update','billing_update','account_update')
  );

-- ---------------------------------------------------------------------------
-- Emitter: add the request_update kind and the leads topic
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION hocalist.notification_emit(
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
  IF p_kind NOT IN ('new_offer','new_message','meeting_update','request_update','billing_update','account_update') THEN
    RAISE EXCEPTION 'invalid_field: kind' USING ERRCODE='22023';
  END IF;
  v_topic := CASE p_kind
    WHEN 'new_offer' THEN 'offers'
    WHEN 'new_message' THEN 'messages'
    WHEN 'meeting_update' THEN 'deals'
    WHEN 'request_update' THEN 'leads'
    WHEN 'billing_update' THEN 'deals'
    ELSE 'safety'
  END;
  IF v_topic <> 'safety' THEN
    SELECT * INTO v_prefs FROM hocalist.notification_preferences WHERE user_id = p_user;
    IF FOUND THEN
      IF v_topic = 'offers' AND NOT v_prefs.offers THEN RETURN NULL; END IF;
      IF v_topic = 'messages' AND NOT v_prefs.messages THEN RETURN NULL; END IF;
      IF v_topic = 'deals' AND NOT v_prefs.deals THEN RETURN NULL; END IF;
      IF v_topic = 'leads' AND NOT v_prefs.leads THEN RETURN NULL; END IF;
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
-- Preferences: expose the optional leads topic
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION hocalist.notification_preferences()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'offers', coalesce(p.offers, true),
    'messages', coalesce(p.messages, true),
    'deals', coalesce(p.deals, true),
    'leads', coalesce(p.leads, true),
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

CREATE OR REPLACE FUNCTION hocalist.notification_preferences_update(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_expected bigint;
  v_offers boolean;
  v_messages boolean;
  v_deals boolean;
  v_leads boolean;
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
    WHERE NOT (k = ANY(ARRAY['offers','messages','deals','leads','safety','expected_revision']))
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
  IF p_input ? 'leads' AND jsonb_typeof(p_input->'leads') <> 'boolean' THEN
    RAISE EXCEPTION 'invalid_field: leads' USING ERRCODE='22023';
  END IF;
  v_offers := (p_input->>'offers')::boolean;
  v_messages := (p_input->>'messages')::boolean;
  v_deals := (p_input->>'deals')::boolean;
  IF p_input ? 'leads' THEN
    v_leads := (p_input->>'leads')::boolean;
  END IF;
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
      user_id, offers, messages, deals, leads, safety)
    VALUES (v_user, v_offers, v_messages, v_deals, coalesce(v_leads, true), true)
    RETURNING * INTO v_row;
  ELSE
    IF v_row.revision <> v_expected THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    UPDATE hocalist.notification_preferences
      SET offers = v_offers,
          messages = v_messages,
          deals = v_deals,
          leads = coalesce(v_leads, v_row.leads),
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
    'leads', v_row.leads,
    'safety', v_row.safety,
    'revision', v_row.revision,
    'updated_at', v_row.updated_at
  );
END; $$;

-- ---------------------------------------------------------------------------
-- Producer trigger
-- ---------------------------------------------------------------------------

-- One request-update event per eligible seller. "Eligible" means a committed
-- offer still in play on the changed request; the revision is part of the key.
CREATE FUNCTION hocalist.notification_on_request_update() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_offer record;
BEGIN
  IF NEW.status <> 'active' OR OLD.status <> 'active' THEN
    RETURN NEW;
  END IF;
  IF NEW.revision <= OLD.revision THEN
    RETURN NEW;
  END IF;
  IF NEW.title IS NOT DISTINCT FROM OLD.title
     AND NEW.description IS NOT DISTINCT FROM OLD.description
     AND NEW.condition IS NOT DISTINCT FROM OLD.condition
     AND NEW.service_type IS NOT DISTINCT FROM OLD.service_type
     AND NEW.quantity IS NOT DISTINCT FROM OLD.quantity
     AND NEW.budget_min_minor IS NOT DISTINCT FROM OLD.budget_min_minor
     AND NEW.budget_max_minor IS NOT DISTINCT FROM OLD.budget_max_minor
     AND NEW.accepts_higher_offers IS NOT DISTINCT FROM OLD.accepts_higher_offers
     AND NEW.category_id IS NOT DISTINCT FROM OLD.category_id THEN
    RETURN NEW;
  END IF;
  FOR v_offer IN
    SELECT o.id, o.seller_user_id
    FROM hocalist.offers o
    WHERE o.request_id = NEW.id
      AND o.status IN ('submitted','selected')
      AND o.seller_user_id <> NEW.buyer_user_id
  LOOP
    IF hocalist.notification_recipient_allowed(v_offer.seller_user_id) THEN
      PERFORM hocalist.notification_emit(
        v_offer.seller_user_id,
        md5(
          'request:update:' || NEW.id::text || ':' || NEW.revision::text || ':' ||
          v_offer.seller_user_id::text
        )::uuid,
        'request_update',
        NEW.id,
        'Request updated',
        'A request you offered on was updated. Open Hocalist to review the new details.',
        'hocalist://offers/' || v_offer.id::text,
        jsonb_build_object(
          'request_id', NEW.id,
          'offer_id', v_offer.id,
          'revision', NEW.revision));
    END IF;
  END LOOP;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_request_update
  AFTER UPDATE ON hocalist.requests
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_request_update();

-- ---------------------------------------------------------------------------
-- Grants and post-apply verification
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION hocalist.notification_on_request_update()
  FROM PUBLIC, anon, authenticated, service_role;

DO $hocalist_request_update_producer_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF to_regprocedure('hocalist.notification_on_request_update()') IS NULL THEN
    v_issues := array_append(v_issues, 'missing request-update producer function');
  ELSIF has_function_privilege(
          'authenticated','hocalist.notification_on_request_update()','EXECUTE')
     OR has_function_privilege('anon','hocalist.notification_on_request_update()','EXECUTE')
     OR has_function_privilege('service_role','hocalist.notification_on_request_update()','EXECUTE') THEN
    v_issues := array_append(v_issues, 'request-update producer function is executable');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'hocalist.requests'::regclass
      AND tgname = 'notification_request_update' AND NOT tgisinternal
  ) THEN
    v_issues := array_append(v_issues, 'missing request-update producer trigger');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'hocalist.notification_preferences'::regclass
      AND attname = 'leads' AND attnotnull AND NOT attisdropped
  ) THEN
    v_issues := array_append(v_issues, 'missing mandatory leads preference column');
  END IF;
  IF NOT has_function_privilege(
       'authenticated','hocalist.notification_preferences()','EXECUTE')
     OR NOT has_function_privilege(
       'authenticated','hocalist.notification_preferences_update(jsonb)','EXECUTE')
     OR has_function_privilege(
       'authenticated','hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'notification preference grants changed');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist request-update producer post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_request_update_producer_postapply$;
COMMIT;

-- Additive administrator-only failed-event operations read (162, draft).
--
-- Bounded, read-only view of the deployed Stripe TEST receipt inbox
-- (`stripe_test_inbox`): events the reconciliation worker has not finished,
-- their attempt count, next attempt time and the sanitized error class written
-- by the review worker. No provider object id, customer id, checkout session,
-- payload, payment amount, credential or token is projected.
--
-- Email bounce/suppression status is deliberately absent: no ingestion exists,
-- so `email_events_available` is always false. Provider event ingestion is
-- coordinator work; this file does not invent a status to fill the gap.
--
-- There is no retry, replay, delete or quarantine command here. A broad retry
-- action would require a separately reviewed idempotent worker command.
--
-- Not an instruction to apply to a live project. Generate a guarded rollout
-- bundle and obtain coordinating review before applying.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $admin_event_operations_guard$
BEGIN
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL
     OR to_regclass('hocalist.stripe_test_inbox') IS NULL THEN
    RAISE EXCEPTION 'Admin failed-event operations require the deployed Stripe TEST receipt inbox';
  END IF;
  IF to_regprocedure('hocalist.admin_failed_events(integer,text,text,text)') IS NOT NULL
     OR to_regprocedure('hocalist.admin_failed_event_detail(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Admin failed-event read objects already exist; review before replacement';
  END IF;
END
$admin_event_operations_guard$;

CREATE FUNCTION hocalist.admin_failed_events(
  p_limit integer DEFAULT 50,
  p_cursor text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_type text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rows jsonb;
  v_more boolean;
  v_cursor text;
  v_cursor_micros bigint;
  v_cursor_event text;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
     OR (p_status IS NOT NULL AND p_status NOT IN ('pending','processed','quarantined'))
     OR (p_type IS NOT NULL AND p_type NOT IN (
       'checkout.session.completed','checkout.session.async_payment_succeeded',
       'checkout.session.async_payment_failed','customer.subscription.created',
       'customer.subscription.updated','customer.subscription.deleted',
       'invoice.paid','invoice.payment_failed','charge.refunded',
       'charge.dispute.created','charge.dispute.closed'))
     OR (p_cursor IS NOT NULL AND p_cursor !~ '^[0-9]{1,20}\|[A-Za-z0-9_]{5,255}$') THEN
    RAISE EXCEPTION 'invalid_admin_query' USING ERRCODE='22023';
  END IF;
  IF p_cursor IS NOT NULL THEN
    v_cursor_micros := (split_part(p_cursor, '|', 1))::bigint;
    v_cursor_event := split_part(p_cursor, '|', 2);
  END IF;

  WITH rows AS (
    SELECT i.event_id,
      i.event_type,
      i.status,
      i.attempts,
      i.available_at,
      i.received_at,
      left(coalesce(i.last_error, ''), 80) AS error_class,
      (extract(epoch FROM i.received_at) * 1000000)::bigint AS micros
    FROM hocalist.stripe_test_inbox i
    WHERE (p_status IS NULL OR i.status = p_status)
      AND (p_type IS NULL OR i.event_type = p_type)
  ), windowed AS (
    SELECT * FROM rows
    WHERE p_cursor IS NULL OR (micros, event_id) < (v_cursor_micros, v_cursor_event)
    ORDER BY micros DESC, event_id DESC
    LIMIT p_limit + 1
  ), visible AS (
    SELECT * FROM windowed ORDER BY micros DESC, event_id DESC LIMIT p_limit
  )
  SELECT
    coalesce((SELECT jsonb_agg(jsonb_build_object(
      'event_id', event_id,
      'event_type', event_type,
      'status', status,
      'attempts', attempts,
      'available_at', available_at,
      'received_at', received_at,
      'error_class', error_class
    ) ORDER BY micros DESC, event_id DESC) FROM visible), '[]'::jsonb),
    (SELECT count(*) > p_limit FROM windowed),
    (SELECT micros::text || '|' || event_id FROM visible
      ORDER BY micros ASC, event_id ASC LIMIT 1)
    INTO v_rows, v_more, v_cursor;

  RETURN jsonb_build_object(
    'items', v_rows,
    'next_cursor', CASE WHEN v_more THEN v_cursor ELSE NULL END,
    'email_events_available', false,
    'retry_available', false);
END; $$;

-- One event's sanitized operational metadata. The provider object id is
-- reduced to its class; the raw id, payload and any provider secret stay out.
CREATE FUNCTION hocalist.admin_failed_event_detail(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  e hocalist.stripe_test_inbox%ROWTYPE;
  v_kind text;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF p_event_id IS NULL OR p_event_id !~ '^evt_[A-Za-z0-9]{1,251}$'
     OR length(p_event_id) > 255 THEN
    RAISE EXCEPTION 'invalid_admin_query' USING ERRCODE='22023';
  END IF;
  SELECT * INTO e FROM hocalist.stripe_test_inbox WHERE event_id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event_not_found' USING ERRCODE='P0002';
  END IF;
  v_kind := CASE split_part(e.object_id, '_', 1)
    WHEN 'cus' THEN 'customer'
    WHEN 'sub' THEN 'subscription'
    WHEN 'cs' THEN 'checkout_session'
    WHEN 'in' THEN 'invoice'
    WHEN 'ch' THEN 'charge'
    WHEN 'dp' THEN 'dispute'
    WHEN 'pi' THEN 'payment_intent'
    WHEN 'evt' THEN 'event'
    ELSE 'other'
  END;
  RETURN jsonb_build_object(
    'event_id', e.event_id,
    'event_type', e.event_type,
    'status', e.status,
    'attempts', e.attempts,
    'available_at', e.available_at,
    'received_at', e.received_at,
    'event_created', e.event_created,
    'object_kind', v_kind,
    'error_class', left(coalesce(e.last_error, ''), 80),
    'livemode', e.livemode);
END; $$;

REVOKE ALL ON FUNCTION hocalist.admin_failed_events(integer,text,text,text),
  hocalist.admin_failed_event_detail(text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_failed_events(integer,text,text,text),
  hocalist.admin_failed_event_detail(text) TO authenticated;

DO $hocalist_admin_event_operations_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT has_function_privilege('authenticated','hocalist.admin_failed_events(integer,text,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.admin_failed_event_detail(text)','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_failed_events(integer,text,text,text)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_failed_events(integer,text,text,text)','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_failed_event_detail(text)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_failed_event_detail(text)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'admin failed-event grants are wrong');
  END IF;
  IF has_table_privilege('authenticated','hocalist.stripe_test_inbox','SELECT')
     OR has_table_privilege('anon','hocalist.stripe_test_inbox','SELECT')
     OR has_table_privilege('service_role','hocalist.stripe_test_inbox','SELECT') THEN
    v_issues := array_append(v_issues, 'Stripe receipt inbox became directly readable');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist admin failed-event post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_admin_event_operations_postapply$;
COMMIT;

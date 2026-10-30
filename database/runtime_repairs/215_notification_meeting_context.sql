-- Context is added only to the authenticated inbox read. Stored events and
-- lock-screen push content stay unchanged. No address, contact or PIN is copied.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
CREATE OR REPLACE FUNCTION hocalist.notification_with_context(
  p_notification hocalist.notifications, p_row jsonb
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_title text;
  v_name text;
  v_schedule text;
BEGIN
  IF auth.uid() IS NULL OR p_notification.user_id <> auth.uid()
     OR p_notification.kind <> 'meeting_update' THEN RETURN p_row; END IF;
  SELECT left(regexp_replace(r.title, '\s+', ' ', 'g'), 70),
         left(regexp_replace(coalesce(nullif(btrim(p.display_name), ''), 'Hocalist member'), '\s+', ' ', 'g'), 40),
         CASE WHEN sr.id IS NULL THEN NULL ELSE
           to_char(sr.schedule_date, 'Mon DD, YYYY') || ' · ' ||
           to_char(sr.schedule_time, 'HH12:MI AM') || ' ' || sr.schedule_timezone END
    INTO v_title, v_name, v_schedule
  FROM hocalist.meetings m
  JOIN hocalist.requests r ON r.id = m.request_id
  LEFT JOIN hocalist.memberships pm ON pm.user_id = CASE WHEN m.buyer_user_id = auth.uid()
      THEN m.seller_user_id ELSE m.buyer_user_id END
    AND pm.role = CASE WHEN m.buyer_user_id = auth.uid() THEN 'seller' ELSE 'buyer' END
  LEFT JOIN hocalist.role_profiles p ON p.membership_id = pm.id
  LEFT JOIN LATERAL (
    SELECT x.* FROM hocalist.meeting_schedule_revisions x
    WHERE x.meeting_id = m.id
      AND (x.id::text = p_notification.payload->>'revision_id'
        OR (p_notification.payload->>'revision_id' IS NULL
          AND x.created_at <= p_notification.created_at
          AND ((p_notification.payload->>'status' = 'reschedule_proposed')
            OR (x.status = 'accepted' AND x.resolved_at <= p_notification.created_at))))
    ORDER BY x.sequence DESC LIMIT 1
  ) sr ON true
  WHERE p_notification.deep_link = 'hocalist://meetings/' || m.id::text
    AND auth.uid() IN (m.buyer_user_id, m.seller_user_id);
  IF v_title IS NULL THEN RETURN p_row; END IF;
  RETURN p_row || jsonb_build_object(
    'title', left(coalesce(p_notification.title, 'Meeting update'), 80) || ' — ' || v_title,
    'body', concat_ws(' · ', v_name, v_schedule) || '. View meeting details.',
    'activity_summary', coalesce(v_schedule, 'View meeting details'));
END; $$;
REVOKE ALL ON FUNCTION hocalist.notification_with_context(hocalist.notifications,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION hocalist.notification_inbox(
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
      hocalist.notification_with_context(n, jsonb_build_object(
        'id', n.id,
        'kind', n.kind,
        'title', coalesce(n.title, 'Hocalist update'),
        'body', coalesce(n.body, ''),
        'deep_link', n.deep_link,
        'source_id', n.source_id,
        'payload', n.payload,
        'read_at', n.read_at,
        'created_at', n.created_at
      )) AS row_json
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
NOTIFY pgrst, 'reload schema';
COMMIT;

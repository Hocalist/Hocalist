BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE TABLE hocalist.seller_conduct_reports (
  case_id uuid PRIMARY KEY REFERENCES hocalist.support_cases(id),
  reporter_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  seller_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  request_id uuid NOT NULL REFERENCES hocalist.requests(id),
  offer_id uuid NOT NULL REFERENCES hocalist.offers(id),
  category text NOT NULL CHECK (category IN ('price_disagreement','changed_terms','missed_meetup',
    'other_conduct','illegal_listing','off_platform_evasion','fraud','threats_or_harassment','pin_abuse')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (reporter_id, seller_id, request_id, category)
);
CREATE INDEX seller_conduct_reports_recent ON hocalist.seller_conduct_reports(created_at, seller_id)
  WHERE category <> 'price_disagreement';
ALTER TABLE hocalist.seller_conduct_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE hocalist.seller_conduct_reports FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION hocalist.seller_conduct_is_serious(category text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT category IN ('illegal_listing','off_platform_evasion','fraud','threats_or_harassment','pin_abuse');
$$;

CREATE FUNCTION hocalist.seller_conduct_report(p_offer uuid, p_category text, p_body text, p_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE u uuid := hocalist.support_assert_user(); o hocalist.offers%ROWTYPE; existing jsonb; result jsonb;
BEGIN
  IF p_category IS NULL OR p_category NOT IN ('price_disagreement','changed_terms','missed_meetup',
    'other_conduct','illegal_listing','off_platform_evasion','fraud','threats_or_harassment','pin_abuse')
    OR p_body IS NULL OR length(btrim(p_body)) NOT BETWEEN 10 AND 4000
    OR p_key IS NULL OR length(p_key) NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_report' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO o FROM hocalist.offers WHERE id = p_offer AND buyer_user_id = u;
  IF NOT FOUND THEN RAISE EXCEPTION 'offer_access_denied' USING ERRCODE = '42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    concat('seller-conduct:', u, ':', o.seller_user_id, ':', o.request_id, ':', p_category), 0));
  SELECT jsonb_build_object('id', c.id, 'revision', c.revision, 'status', c.status) INTO existing
  FROM hocalist.seller_conduct_reports r JOIN hocalist.support_cases c ON c.id = r.case_id
  WHERE r.reporter_id = u AND r.seller_id = o.seller_user_id AND r.request_id = o.request_id AND r.category = p_category;
  IF FOUND THEN RETURN existing; END IF;
  result := hocalist.support_command('create', concat('seller-conduct:', o.id, ':', p_category, ':', p_key),
    jsonb_build_object('reason_code', CASE WHEN hocalist.seller_conduct_is_serious(p_category) THEN 'safety' ELSE 'deal' END,
      'body', btrim(p_body)));
  INSERT INTO hocalist.seller_conduct_reports(case_id, reporter_id, seller_id, request_id, offer_id, category)
  VALUES((result->>'id')::uuid, u, o.seller_user_id, o.request_id, o.id, p_category);
  RETURN result;
END $$;

ALTER TABLE hocalist.health_review_notes DROP CONSTRAINT health_review_notes_decision_check;
ALTER TABLE hocalist.health_review_notes ADD CONSTRAINT health_review_notes_decision_check
  CHECK (decision IN ('no_action','watch','restriction_recommended','violation_confirmed'));

CREATE FUNCTION hocalist.seller_conduct_health_internal(p_seller uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = '' AS $$
  WITH confirmed_deals AS (
    SELECT r.request_id, max(CASE WHEN hocalist.seller_conduct_is_serious(r.category) THEN 25 ELSE 10 END) AS points
    FROM hocalist.seller_conduct_reports r
    JOIN hocalist.health_review_notes n ON n.case_id = r.case_id
    WHERE r.seller_id = p_seller AND r.category <> 'price_disagreement'
      AND r.created_at >= now() - interval '6 months' AND n.decision = 'violation_confirmed'
    GROUP BY r.request_id
  )
  SELECT jsonb_build_object('score', greatest(0, 100 - coalesce(sum(points), 0)),
    'confirmed_incidents', count(*)) FROM confirmed_deals;
$$;

REVOKE ALL ON FUNCTION hocalist.seller_conduct_is_serious(text),
  hocalist.seller_conduct_health_internal(uuid), hocalist.seller_conduct_report(uuid,text,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.seller_conduct_report(uuid,text,text,text) TO authenticated;

DO $patch$
DECLARE d text; start_health integer; end_health integer;
BEGIN
  d := pg_get_functiondef('hocalist.account_health_status()'::regprocedure);
  IF position('''reports_are_signals_only'',true' IN d) = 0 THEN RAISE EXCEPTION 'Account health definition drift'; END IF;
  EXECUTE replace(d, '''reports_are_signals_only'',true',
    '''reports_are_signals_only'',true,''conduct'',hocalist.seller_conduct_health_internal(u)');

  d := pg_get_functiondef('hocalist.admin_trust_command(text,text,jsonb)'::regprocedure);
  IF position('INSERT INTO hocalist.health_review_notes' IN d) = 0 OR position('''restriction_recommended'')' IN d) = 0 THEN
    RAISE EXCEPTION 'Health decision definition drift';
  END IF;
  d := replace(d, '''restriction_recommended'')', '''restriction_recommended'',''violation_confirmed'')');
  EXECUTE replace(d, 'INSERT INTO hocalist.health_review_notes', $decision$
    IF p_input->>'decision' = 'violation_confirmed' AND NOT EXISTS (
      SELECT 1 FROM hocalist.seller_conduct_reports linked_report
      WHERE linked_report.case_id = (p_input->>'case_id')::uuid AND linked_report.category <> 'price_disagreement'
    ) THEN RAISE EXCEPTION 'conduct_case_required' USING ERRCODE = '22023'; END IF;
    INSERT INTO hocalist.health_review_notes$decision$);

  d := pg_get_functiondef('hocalist.admin_review_queue(integer,text,text,text,text,text,text)'::regprocedure);
  start_health := position('  -- Health cases' IN d);
  end_health := position('  -- Current restriction revision' IN d);
  IF start_health = 0 OR end_health <= start_health OR position('''needs_review'',''reviewed''' IN d) = 0 THEN
    RAISE EXCEPTION 'Health queue definition drift';
  END IF;
  d := overlay(d placing $queue$
  WITH patterns AS (
    SELECT r.seller_id, count(DISTINCT r.reporter_id)::integer AS buyers
    FROM hocalist.seller_conduct_reports r
    JOIN hocalist.support_cases c ON c.id = r.case_id
    LEFT JOIN hocalist.health_review_notes h ON h.case_id = r.case_id
    WHERE r.category <> 'price_disagreement' AND r.created_at >= now() - interval '6 months'
      AND h.decision IS DISTINCT FROM 'no_action'
      AND (c.status <> 'resolved' OR h.decision = 'violation_confirmed')
    GROUP BY r.seller_id
  ), candidates AS (
    SELECT q.id, q.reason_code, q.status, q.body, q.created_at,
      h.decision, h.reason, r.category, r.seller_id, r.request_id, coalesce(p.buyers, 0) AS buyers,
      CASE WHEN h.case_id IS NULL AND q.status <> 'resolved' THEN CASE
        WHEN hocalist.seller_conduct_is_serious(r.category) OR (r.case_id IS NULL AND q.reason_code = 'safety') THEN 2
        WHEN p.buyers >= 3 AND r.category <> 'price_disagreement' AND r.created_at >= now() - interval '6 months' THEN 1
        ELSE 0 END ELSE 0 END AS priority
    FROM hocalist.support_cases q
    LEFT JOIN hocalist.health_review_notes h ON h.case_id = q.id
    LEFT JOIN hocalist.seller_conduct_reports r ON r.case_id = q.id
    LEFT JOIN patterns p ON p.seller_id = r.seller_id
    WHERE q.reason_code IN ('safety','deal')
      AND (p_health_state IS NULL OR (p_health_state IN ('priority','needs_review') AND h.case_id IS NULL)
        OR (p_health_state = 'reviewed' AND h.case_id IS NOT NULL))
  ), ranked AS (
    SELECT *, row_number() OVER (PARTITION BY seller_id, priority ORDER BY created_at DESC,id DESC) AS group_position
    FROM candidates
  ), source AS (
    SELECT *, (extract(epoch FROM created_at) * 1000000)::bigint
      + CASE WHEN p_health_state = 'priority' THEN priority * 1000000000000000000::bigint ELSE 0 END AS micros
    FROM ranked
    WHERE p_health_state IS DISTINCT FROM 'priority' OR priority = 2 OR (priority = 1 AND group_position = 1)
  ), windowed AS (
    SELECT * FROM source
    WHERE p_health_cursor IS NULL OR (micros,id) < (hc_micros,hc_id)
    ORDER BY micros DESC,id DESC LIMIT n + 1
  ), visible AS (
    SELECT * FROM windowed ORDER BY micros DESC,id DESC LIMIT n
  )
  SELECT coalesce((SELECT jsonb_agg(jsonb_build_object('case_id', q.id,
      'reason_code',q.reason_code,'status',q.status,'body',q.body,'created_at',q.created_at,
      'decision',q.decision,'decision_reason',q.reason,'category',q.category,'seller_id',q.seller_id,
      'request_id',q.request_id,'reporting_buyers',q.buyers,'priority',q.priority)
      ORDER BY q.micros DESC,q.id DESC) FROM visible q),'[]'::jsonb),
    (SELECT count(*) > n FROM windowed),
    (SELECT v.micros::text || '|' || v.id FROM visible v ORDER BY v.micros,v.id LIMIT 1)
  INTO h_items, h_more, h_next;

$queue$ from start_health for end_health - start_health);
  EXECUTE replace(d, '''needs_review'',''reviewed''', '''priority'',''needs_review'',''reviewed''');
END $patch$;

NOTIFY pgrst, 'reload schema';
COMMIT;

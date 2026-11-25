BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE FUNCTION hocalist.normalize_safety_phrase(value text)
RETURNS text LANGUAGE sql IMMUTABLE STRICT SET search_path = '' AS $$
  SELECT btrim(regexp_replace(lower(value), '[^[:alnum:]]+', ' ', 'g'));
$$;

CREATE TABLE hocalist.safety_phrase_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phrase text NOT NULL CHECK (length(phrase) BETWEEN 8 AND 120),
  normalized text GENERATED ALWAYS AS (hocalist.normalize_safety_phrase(phrase)) STORED
    UNIQUE CHECK (normalized LIKE '% %' AND length(normalized) >= 8),
  enabled boolean NOT NULL DEFAULT true,
  revision integer NOT NULL DEFAULT 1,
  updated_by uuid
);
CREATE TABLE hocalist.safety_phrase_matches (
  case_id uuid NOT NULL REFERENCES hocalist.support_cases(id),
  rule_id uuid NOT NULL REFERENCES hocalist.safety_phrase_rules(id),
  phrase text NOT NULL,
  matched_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (case_id, rule_id)
);
ALTER TABLE hocalist.safety_phrase_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.safety_phrase_matches ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.safety_phrase_rules, hocalist.safety_phrase_matches
  FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO hocalist.safety_phrase_rules(phrase) VALUES
  ('threatened to kill me'), ('threatened to hurt my family'),
  ('threatened me with a weapon'), ('threatened to shoot me'),
  ('offered me stolen goods'), ('asked me to sell stolen goods'),
  ('trying to sell illegal drugs'), ('offered a fake prescription'),
  ('threatened to leak my private photos'), ('blackmailed me for money'),
  ('me amenazó con matarme'), ('me amenazó con un arma'),
  ('amenazó con publicar mis fotos privadas');

CREATE FUNCTION hocalist.capture_safety_phrase_matches()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE report_text text := ' ' || hocalist.normalize_safety_phrase(NEW.body) || ' ';
BEGIN
  INSERT INTO hocalist.safety_phrase_matches(case_id, rule_id, phrase)
  SELECT NEW.id, r.id, r.phrase FROM hocalist.safety_phrase_rules r
  WHERE r.enabled AND strpos(report_text, ' ' || r.normalized || ' ') > 0;
  RETURN NEW;
END;
$$;

CREATE TRIGGER capture_safety_phrase_matches
AFTER INSERT ON hocalist.support_cases
FOR EACH ROW EXECUTE FUNCTION hocalist.capture_safety_phrase_matches();

CREATE FUNCTION hocalist.admin_safety_alarm_count()
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  RETURN (
    SELECT count(DISTINCT m.case_id)::integer
    FROM hocalist.safety_phrase_matches m
    JOIN hocalist.support_cases q ON q.id = m.case_id
    WHERE q.status <> 'resolved'
      AND NOT EXISTS (SELECT 1 FROM hocalist.health_review_notes h WHERE h.case_id = m.case_id)
  );
END;
$$;

CREATE FUNCTION hocalist.admin_safety_phrase_rules()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', id, 'phrase', phrase, 'enabled', enabled,
      'revision', revision) ORDER BY phrase, id) FROM hocalist.safety_phrase_rules
  ), '[]'::jsonb);
END;
$$;

CREATE FUNCTION hocalist.admin_save_safety_phrase(p_phrase text, p_enabled boolean,
  p_id uuid DEFAULT NULL, p_revision integer DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE saved uuid; normalized text := hocalist.normalize_safety_phrase(p_phrase);
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF p_phrase IS NULL OR length(btrim(p_phrase)) NOT BETWEEN 8 AND 120
      OR normalized NOT LIKE '% %' OR length(normalized) < 8 OR p_enabled IS NULL
      OR ((p_id IS NULL) <> (p_revision IS NULL)) THEN
    RAISE EXCEPTION 'invalid_safety_phrase' USING ERRCODE = '22023';
  END IF;
  IF p_id IS NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('hocalist.safety_phrase_rules', 0));
    IF (SELECT count(*) FROM hocalist.safety_phrase_rules) >= 100 THEN
      RAISE EXCEPTION 'safety_phrase_limit' USING ERRCODE = '22023';
    END IF;
    INSERT INTO hocalist.safety_phrase_rules(phrase, enabled, updated_by)
    VALUES (btrim(p_phrase), p_enabled, auth.uid()) RETURNING id INTO saved;
  ELSE
    UPDATE hocalist.safety_phrase_rules
    SET phrase = btrim(p_phrase), enabled = p_enabled, updated_by = auth.uid(), revision = revision + 1
    WHERE id = p_id AND revision = p_revision RETURNING id INTO saved;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE = 'P0001'; END IF;
  END IF;
  RETURN saved;
END;
$$;

REVOKE ALL ON FUNCTION hocalist.normalize_safety_phrase(text), hocalist.capture_safety_phrase_matches(),
  hocalist.admin_safety_alarm_count(), hocalist.admin_safety_phrase_rules(),
  hocalist.admin_save_safety_phrase(text,boolean,uuid,integer) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_safety_alarm_count(), hocalist.admin_safety_phrase_rules(),
  hocalist.admin_save_safety_phrase(text,boolean,uuid,integer) TO authenticated;

DO $patch$
DECLARE d text := pg_get_functiondef('hocalist.admin_review_queue(integer,text,text,text,text,text,text)'::regprocedure);
  old_fragments text[] := ARRAY[
    'coalesce(p.buyers, 0) AS buyers,',
    'WHEN hocalist.seller_conduct_is_serious(r.category)',
    'WHERE q.reason_code IN (''safety'',''deal'')',
    'OR priority = 2 OR',
    '''priority'',q.priority)'
  ];
  new_fragments text[] := ARRAY[
    'coalesce(p.buyers, 0) AS buyers, alarm.phrases AS matched_phrases,',
    'WHEN alarm.phrases IS NOT NULL THEN 3 WHEN hocalist.seller_conduct_is_serious(r.category)',
    'LEFT JOIN LATERAL (
      SELECT jsonb_agg(m.phrase ORDER BY m.phrase) AS phrases
      FROM hocalist.safety_phrase_matches m WHERE m.case_id = q.id
    ) alarm ON true
    WHERE (q.reason_code IN (''safety'',''deal'') OR alarm.phrases IS NOT NULL)',
    'OR priority >= 2 OR',
    '''priority'',q.priority,''matched_phrases'',q.matched_phrases)'
  ];
BEGIN
  FOR i IN 1..array_length(old_fragments, 1) LOOP
    IF strpos(d, old_fragments[i]) = 0 THEN RAISE EXCEPTION 'Health queue definition drift'; END IF;
    d := replace(d, old_fragments[i], new_fragments[i]);
  END LOOP;
  EXECUTE d;
END $patch$;

NOTIFY pgrst, 'reload schema';
COMMIT;

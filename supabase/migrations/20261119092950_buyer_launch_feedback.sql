BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE hocalist.website_waitlist_signups
  ADD COLUMN name text CHECK (length(name)<=100),
  ADD COLUMN city text CHECK (length(city)<=100),
  ADD COLUMN interest text CHECK (interest IN ('buyer','seller','both'));

-- Reuse the existing admission, consent and deduplication boundary. Existing
-- addresses cannot have their details overwritten by an anonymous resubmission.
ALTER FUNCTION hocalist.website_waitlist_join(text,text,text,text,text)
  RENAME TO website_waitlist_join_guarded;
REVOKE ALL ON FUNCTION hocalist.website_waitlist_join_guarded(text,text,text,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hocalist.website_waitlist_join(p_email text,p_consent_version text,
  p_source text DEFAULT NULL,p_client_hash text DEFAULT NULL,p_intake_token text DEFAULT NULL,
  p_lead jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
  IF p_lead IS NULL OR jsonb_typeof(p_lead)<>'object' OR
    p_lead - ARRAY['name','city','interest'] <> '{}'::jsonb OR
    (p_lead ? 'name' AND jsonb_typeof(p_lead->'name') IS DISTINCT FROM 'string') OR
    (p_lead ? 'city' AND jsonb_typeof(p_lead->'city') IS DISTINCT FROM 'string') OR
    (p_lead ? 'interest' AND jsonb_typeof(p_lead->'interest') IS DISTINCT FROM 'string') OR
    length(coalesce(p_lead->>'name',''))>100 OR length(coalesce(p_lead->>'city',''))>100 OR
    (p_lead ? 'interest' AND p_lead->>'interest' NOT IN ('buyer','seller','both')) THEN
    RAISE EXCEPTION 'invalid_lead' USING ERRCODE='22023';
  END IF;
  result := hocalist.website_waitlist_join_guarded(p_email,p_consent_version,p_source,p_client_hash,p_intake_token);
  IF result->>'status'='joined' THEN
    UPDATE hocalist.website_waitlist_signups SET name=nullif(btrim(p_lead->>'name'),''),
      city=nullif(btrim(p_lead->>'city'),''),interest=p_lead->>'interest'
    WHERE email_normalized=lower(btrim(p_email));
  END IF;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION hocalist.website_waitlist_join(text,text,text,text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.website_waitlist_join(text,text,text,text,text,jsonb) TO anon;

CREATE TABLE hocalist.website_launch_events(
  id uuid PRIMARY KEY,
  kind text NOT NULL CHECK(kind IN ('download_click','first_app_open')),
  platform text NOT NULL CHECK(platform IN ('android','ios')),
  source text NOT NULL CHECK(length(source) BETWEEN 1 AND 80),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX launch_first_open_user_platform ON hocalist.website_launch_events(user_id,platform)
  WHERE kind='first_app_open';
CREATE INDEX launch_events_date ON hocalist.website_launch_events(created_at);
ALTER TABLE hocalist.website_launch_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.website_launch_events FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION hocalist.website_download_record(p_event_id uuid,p_platform text,p_source text,
  p_client_hash text,p_intake_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE cfg hocalist.website_waitlist_config%ROWTYPE;
  hour_start timestamptz:=date_trunc('hour',now()); used integer;
BEGIN
  SELECT * INTO cfg FROM hocalist.website_waitlist_config WHERE singleton;
  IF cfg.intake_token_hash IS NULL OR md5(coalesce(p_intake_token,'')) IS DISTINCT FROM cfg.intake_token_hash THEN
    RAISE EXCEPTION 'invalid_intake' USING ERRCODE='42501';
  END IF;
  IF p_event_id IS NULL OR p_platform NOT IN ('android','ios') OR p_platform IS NULL OR
    p_source IS NULL OR length(p_source) NOT BETWEEN 1 AND 80 OR
    p_client_hash IS NULL OR p_client_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_event' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('waitlist:'||p_client_hash,771));
  SELECT admitted INTO used FROM hocalist.website_waitlist_admissions WHERE client_hash=p_client_hash AND window_start=hour_start;
  IF coalesce(used,0)>=cfg.per_fingerprint_cap THEN RAISE EXCEPTION 'rate_limited'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('waitlist:global',771));
  DELETE FROM hocalist.website_waitlist_admissions WHERE window_start < hour_start - interval '2 days';
  SELECT coalesce(sum(admitted),0)::integer INTO used FROM hocalist.website_waitlist_admissions WHERE window_start=hour_start;
  IF used>=cfg.global_hourly_cap THEN RAISE EXCEPTION 'rate_limited'; END IF;
  INSERT INTO hocalist.website_waitlist_admissions VALUES(p_client_hash,hour_start,1)
    ON CONFLICT(client_hash,window_start) DO UPDATE SET admitted=hocalist.website_waitlist_admissions.admitted+1;
  INSERT INTO hocalist.website_launch_events(id,kind,platform,source) VALUES(p_event_id,'download_click',p_platform,p_source)
    ON CONFLICT(id) DO NOTHING;
  RETURN jsonb_build_object('recorded',true);
END $$;
REVOKE ALL ON FUNCTION hocalist.website_download_record(uuid,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.website_download_record(uuid,text,text,text,text) TO anon;

CREATE FUNCTION hocalist.launch_record_app_open(p_platform text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();
BEGIN
  PERFORM hocalist.support_assert_user();
  IF p_platform IS NULL OR p_platform NOT IN ('android','ios') THEN RAISE EXCEPTION 'invalid_platform' USING ERRCODE='22023'; END IF;
  INSERT INTO hocalist.website_launch_events(id,kind,platform,source,user_id)
    VALUES(gen_random_uuid(),'first_app_open',p_platform,'signed-in-app',u)
    ON CONFLICT(user_id,platform) WHERE kind='first_app_open' DO NOTHING;
  RETURN jsonb_build_object('recorded',true);
END $$;
REVOKE ALL ON FUNCTION hocalist.launch_record_app_open(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.launch_record_app_open(text) TO authenticated;

CREATE FUNCTION hocalist.admin_launch_overview(p_before uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  RETURN jsonb_build_object(
    'leads_total',(SELECT count(*) FROM hocalist.website_waitlist_signups),
    'registrations',(SELECT count(DISTINCT user_id) FROM hocalist.memberships),
    'download_clicks',(SELECT count(*) FROM hocalist.website_launch_events WHERE kind='download_click'),
    'first_app_opens',(SELECT count(*) FROM hocalist.website_launch_events WHERE kind='first_app_open'),
    'platforms',(SELECT coalesce(jsonb_agg(s),'[]') FROM (
      SELECT kind,platform,count(*) AS total FROM hocalist.website_launch_events GROUP BY kind,platform) s),
    'leads',(SELECT coalesce(jsonb_agg(s),'[]') FROM (
      SELECT id,email,name,city,interest,source,created_at FROM hocalist.website_waitlist_signups
      WHERE p_before IS NULL OR (created_at,id)<(SELECT created_at,id FROM hocalist.website_waitlist_signups WHERE id=p_before)
      ORDER BY created_at DESC,id DESC LIMIT 50) s));
END $$;
REVOKE ALL ON FUNCTION hocalist.admin_launch_overview(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_launch_overview(uuid) TO authenticated;
CREATE FUNCTION hocalist.admin_support_evidence(p_case_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  RETURN jsonb_build_object('items',coalesce((SELECT jsonb_agg(media_id)
    FROM hocalist.review_evidence_links WHERE case_id=p_case_id),'[]'::jsonb));
END $$;
CREATE FUNCTION hocalist.admin_report_evidence_reference(p_submission uuid,p_media uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  RETURN jsonb_build_object('reference_ok',EXISTS(SELECT 1 FROM hocalist.review_evidence_links
    WHERE case_id=p_submission AND media_id=p_media));
END $$;
REVOKE ALL ON FUNCTION hocalist.admin_support_evidence(uuid),hocalist.admin_report_evidence_reference(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_support_evidence(uuid),hocalist.admin_report_evidence_reference(uuid,uuid)
  TO authenticated;
COMMIT;

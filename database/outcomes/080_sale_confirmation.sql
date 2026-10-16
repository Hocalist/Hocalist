-- Local migration: request-owned sale confirmation. No money movement.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $$ BEGIN
 IF to_regprocedure('hocalist.meeting_assert_participant(uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'meeting foundation missing';
 END IF;
 IF to_regclass('hocalist.sale_confirmations') IS NOT NULL THEN
  RAISE EXCEPTION 'sale confirmation already installed';
 END IF;
END $$;
CREATE TABLE hocalist.request_pin_secrets (
 request_id uuid PRIMARY KEY REFERENCES hocalist.requests(id),
 meeting_id uuid NOT NULL REFERENCES hocalist.meetings(id),
 schedule_revision_id uuid NOT NULL,
 secret uuid NOT NULL DEFAULT gen_random_uuid(),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
 window_attempts integer NOT NULL DEFAULT 0 CHECK(window_attempts>=0),
 locked_until timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE hocalist.sale_confirmations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 request_id uuid NOT NULL UNIQUE REFERENCES hocalist.requests(id),
 meeting_id uuid NOT NULL REFERENCES hocalist.meetings(id),
 offer_id uuid NOT NULL REFERENCES hocalist.offers(id),
 schedule_revision_id uuid NOT NULL,
 buyer_user_id uuid NOT NULL,
 seller_user_id uuid NOT NULL,
 confirmed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.request_pin_secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.sale_confirmations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.request_pin_secrets,hocalist.sale_confirmations FROM PUBLIC,anon,authenticated,service_role;

-- Derive display digits from a private random secret; neither plaintext PIN
-- nor attempted PIN is persisted or included in receipts/log messages.
CREATE FUNCTION hocalist.sale_pin_digits(p_secret uuid) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT lpad(((('x'||substr(encode(sha256(convert_to(p_secret::text,'UTF8')),'hex'),1,12))::bit(48)::bigint)%100000)::text,5,'0')
$$;

CREATE FUNCTION hocalist.sale_pin(p_meeting uuid,p_action text,p_pin text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); m hocalist.meetings%ROWTYPE;
 s hocalist.request_pin_secrets%ROWTYPE; outcome hocalist.sale_confirmations%ROWTYPE;
BEGIN
 m:=hocalist.meeting_assert_participant(p_meeting,u);
 IF p_action NOT IN ('display','verify','status') OR p_action IS NULL THEN
  RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023';
 END IF;
 IF (p_action='display' AND u<>m.buyer_user_id) OR (p_action='verify' AND u<>m.seller_user_id) THEN
  RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501';
 END IF;
 -- Match marketplace lock order; serialize all sellers for the request.
 PERFORM 1 FROM hocalist.requests WHERE id=m.request_id FOR UPDATE;
 PERFORM 1 FROM hocalist.meetings WHERE id=p_meeting FOR UPDATE;
 m:=hocalist.meeting_assert_participant(p_meeting,u);
 SELECT * INTO outcome FROM hocalist.sale_confirmations WHERE request_id=m.request_id;
 IF FOUND THEN
  IF outcome.meeting_id<>p_meeting THEN RETURN jsonb_build_object('status','completed_elsewhere'); END IF;
  RETURN jsonb_build_object('status','confirmed','outcome_id',outcome.id,'confirmed_at',outcome.confirmed_at);
 END IF;
 IF p_action='status' THEN RETURN jsonb_build_object('status','unconfirmed'); END IF;
 IF m.status<>'accepted' OR m.accepted_revision_id IS NULL THEN
  RETURN jsonb_build_object('status','meeting_not_accepted');
 END IF;
 IF m.meeting_expires_at IS NULL OR now()>=m.meeting_expires_at THEN
  RETURN jsonb_build_object('status','expired');
 END IF;
 IF p_action='display' THEN
  INSERT INTO hocalist.request_pin_secrets(request_id,meeting_id,schedule_revision_id)
   VALUES(m.request_id,m.id,m.accepted_revision_id)
   ON CONFLICT(request_id) DO UPDATE SET meeting_id=excluded.meeting_id,
    schedule_revision_id=excluded.schedule_revision_id,secret=gen_random_uuid()
   WHERE request_pin_secrets.meeting_id<>excluded.meeting_id
      OR request_pin_secrets.schedule_revision_id<>excluded.schedule_revision_id;
  SELECT * INTO s FROM hocalist.request_pin_secrets WHERE request_id=m.request_id;
  RETURN jsonb_build_object('status','ready','pin',hocalist.sale_pin_digits(s.secret),'expires_at',m.meeting_expires_at);
 END IF;
 SELECT * INTO s FROM hocalist.request_pin_secrets WHERE request_id=m.request_id FOR UPDATE;
 IF NOT FOUND OR s.meeting_id<>m.id OR s.schedule_revision_id<>m.accepted_revision_id THEN
  RETURN jsonb_build_object('status','buyer_must_open_pin');
 END IF;
 IF s.attempts>=30 THEN RETURN jsonb_build_object('status','support_required'); END IF;
 IF s.locked_until>now() THEN RETURN jsonb_build_object('status','locked','retry_at',s.locked_until); END IF;
 IF p_pin IS NULL OR p_pin!~'^[0-9]{5}$' THEN RETURN jsonb_build_object('status','invalid_format'); END IF;
 IF s.locked_until IS NOT NULL THEN s.window_attempts:=0; END IF;
 IF p_pin<>hocalist.sale_pin_digits(s.secret) THEN
  UPDATE hocalist.request_pin_secrets SET attempts=attempts+1,
   window_attempts=s.window_attempts+1,
   locked_until=CASE WHEN s.window_attempts+1>=5 THEN now()+interval '15 minutes' ELSE NULL END
   WHERE request_id=m.request_id;
  -- A returned failure, not an exception: failed attempts must COMMIT.
  RETURN jsonb_build_object('status',CASE WHEN s.window_attempts+1>=5 THEN 'locked' ELSE 'incorrect' END);
 END IF;
 INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id)
  VALUES(m.request_id,m.id,m.offer_id,m.accepted_revision_id,m.buyer_user_id,m.seller_user_id) RETURNING * INTO outcome;
 UPDATE hocalist.requests SET status='closed',revision=revision+1,updated_at=now() WHERE id=m.request_id;
 DELETE FROM hocalist.request_pin_secrets WHERE request_id=m.request_id;
 RETURN jsonb_build_object('status','confirmed','outcome_id',outcome.id,'confirmed_at',outcome.confirmed_at);
END $$;

CREATE FUNCTION hocalist.sale_keep_final() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_TABLE_NAME='meetings' THEN
  IF EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE meeting_id=OLD.id) THEN
   RAISE EXCEPTION 'sale_already_confirmed' USING ERRCODE='P0001';
  END IF;
 ELSIF NEW.status<>'closed' AND EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE request_id=OLD.id) THEN
  RAISE EXCEPTION 'sale_already_confirmed' USING ERRCODE='P0001';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER sale_final_meeting BEFORE UPDATE ON hocalist.meetings FOR EACH ROW EXECUTE FUNCTION hocalist.sale_keep_final();
CREATE TRIGGER sale_final_request BEFORE UPDATE ON hocalist.requests FOR EACH ROW EXECUTE FUNCTION hocalist.sale_keep_final();
REVOKE ALL ON FUNCTION hocalist.sale_pin_digits(uuid),hocalist.sale_keep_final(),hocalist.sale_pin(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.sale_pin(uuid,text,text) TO authenticated;
CREATE FUNCTION hocalist.sale_history(p_before_time timestamptz DEFAULT NULL,p_before_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();items jsonb;
BEGIN
 IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='buyer' AND status='active')
  OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501'; END IF;
 IF (p_before_time IS NULL)<>(p_before_id IS NULL) THEN RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023'; END IF;
 SELECT coalesce(jsonb_agg(x.data ORDER BY x.confirmed_at DESC,x.id DESC),'[]'::jsonb) INTO items FROM (
  SELECT s.id,s.confirmed_at,jsonb_build_object('id',s.id,'meeting_id',s.meeting_id,'confirmed_at',s.confirmed_at,
   'title',q.title,'price_minor',r.price_minor,'currency',r.currency_code) AS data
  FROM hocalist.sale_confirmations s JOIN hocalist.requests q ON q.id=s.request_id
  JOIN hocalist.offers o ON o.id=s.offer_id
  JOIN hocalist.offer_revisions r ON r.id=o.accepted_revision_id
  WHERE s.buyer_user_id=u AND (p_before_time IS NULL OR (s.confirmed_at,s.id)<(p_before_time,p_before_id))
  ORDER BY s.confirmed_at DESC,s.id DESC LIMIT 25
 ) x;
 RETURN jsonb_build_object('items',items);
END $$;
REVOKE ALL ON FUNCTION hocalist.sale_history(timestamptz,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.sale_history(timestamptz,uuid) TO authenticated;
COMMIT;

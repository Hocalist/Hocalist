-- DRAFT, not deployed. Requires reviewed membership foundation 003.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE hocalist.push_devices (
 id uuid PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 installation_secret_hash text NOT NULL,
 token text UNIQUE NOT NULL CHECK(length(token) BETWEEN 20 AND 4096),
 platform text NOT NULL CHECK(platform='android'),
 enabled boolean NOT NULL,
 revision bigint NOT NULL DEFAULT 1,
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE hocalist.notifications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 event_key uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('new_offer','new_message','meeting_update','billing_update','account_update')),
 source_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 read_at timestamptz,
 UNIQUE(user_id,event_key)
);
CREATE TABLE hocalist.push_deliveries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 notification_id uuid NOT NULL REFERENCES hocalist.notifications(id),
 device_id uuid NOT NULL REFERENCES hocalist.push_devices(id),
 device_revision bigint NOT NULL,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','sending','accepted','skipped','failed')),
 attempts integer NOT NULL DEFAULT 0,
 available_at timestamptz NOT NULL DEFAULT now(),
 lease_token uuid, lease_until timestamptz,
 last_error text,
 UNIQUE(notification_id,device_id,device_revision)
);
ALTER TABLE hocalist.push_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.push_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.push_devices,hocalist.notifications,hocalist.push_deliveries FROM PUBLIC,anon,authenticated,service_role;
CREATE POLICY own_notification_read ON hocalist.notifications FOR SELECT TO authenticated USING(
 user_id=(SELECT auth.uid())
 AND EXISTS(SELECT 1 FROM hocalist.memberships m WHERE m.user_id=notifications.user_id AND m.status='active')
 AND NOT EXISTS(SELECT 1 FROM hocalist.memberships m WHERE m.user_id=notifications.user_id AND m.status IN ('restricted','disabled'))
);
GRANT SELECT ON hocalist.notifications TO authenticated;

-- Caller creates a random 256-bit installation secret, retained in device secure storage.
-- Knowing an FCM token or another installation UUID is insufficient to reassign that device.
CREATE FUNCTION hocalist.push_device_register(p_id uuid,p_secret text,p_token text,p_enabled boolean)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); d hocalist.push_devices%ROWTYPE; h text; r bigint;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM hocalist.profiles WHERE id=u FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status='active')
 OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
 RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501'; END IF;
 IF p_id IS NULL OR coalesce(p_secret,'') !~ '^[a-f0-9]{64}$' OR p_token IS NULL
 OR length(p_token) NOT BETWEEN 20 AND 4096 OR p_enabled IS NULL THEN RAISE EXCEPTION 'invalid_device' USING ERRCODE='22023'; END IF;
 h:=encode(sha256(convert_to(p_secret,'UTF8')),'hex');
 SELECT * INTO d FROM hocalist.push_devices WHERE id=p_id FOR UPDATE;
 IF FOUND THEN
  IF d.installation_secret_hash<>h THEN RAISE EXCEPTION 'device_access_denied' USING ERRCODE='42501'; END IF;
  IF d.user_id=u AND d.token=p_token AND d.enabled=p_enabled THEN
   UPDATE hocalist.push_devices SET updated_at=now() WHERE id=p_id; RETURN d.revision;
  END IF;
 END IF;
 IF (d.id IS NULL OR d.user_id<>u) AND (SELECT count(*) FROM hocalist.push_devices WHERE user_id=u)>=10 THEN
  RAISE EXCEPTION 'device_limit' USING ERRCODE='22023'; END IF;
 IF d.id IS NULL THEN
  INSERT INTO hocalist.push_devices(id,user_id,installation_secret_hash,token,platform,enabled)
  VALUES(p_id,u,h,p_token,'android',p_enabled) RETURNING revision INTO r;
 ELSE
  UPDATE hocalist.push_devices SET user_id=u,token=p_token,enabled=p_enabled,revision=revision+1,updated_at=now()
  WHERE id=p_id RETURNING revision INTO r;
  UPDATE hocalist.push_deliveries SET status='skipped',lease_token=NULL,lease_until=NULL
  WHERE device_id=p_id AND status IN ('pending','sending');
 END IF;
 RETURN r;
END; $$;

CREATE FUNCTION hocalist.push_device_disable(p_id uuid,p_secret text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
 UPDATE hocalist.push_devices SET enabled=false,revision=revision+1,updated_at=now()
 WHERE id=p_id AND user_id=auth.uid() AND installation_secret_hash=encode(sha256(convert_to(p_secret,'UTF8')),'hex');
 IF NOT FOUND THEN RAISE EXCEPTION 'device_access_denied' USING ERRCODE='42501'; END IF;
 UPDATE hocalist.push_deliveries SET status='skipped',lease_token=NULL,lease_until=NULL
 WHERE device_id=p_id AND status IN ('pending','sending');
END; $$;

-- Trusted business-event producers only. Must authorize recipient/source before calling.
-- There is no client-facing enqueue endpoint. No production producer is wired yet.
CREATE FUNCTION hocalist.notification_enqueue(p_user uuid,p_event uuid,p_kind text,p_source uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n hocalist.notifications%ROWTYPE;
BEGIN
 INSERT INTO hocalist.notifications(user_id,event_key,kind,source_id) VALUES(p_user,p_event,p_kind,p_source)
 ON CONFLICT(user_id,event_key) DO NOTHING;
 SELECT * INTO STRICT n FROM hocalist.notifications WHERE user_id=p_user AND event_key=p_event;
 IF n.kind<>p_kind OR n.source_id<>p_source THEN RAISE EXCEPTION 'notification_event_conflict'; END IF;
 INSERT INTO hocalist.push_deliveries(notification_id,device_id,device_revision)
 SELECT n.id,d.id,d.revision FROM hocalist.push_devices d WHERE d.user_id=p_user AND d.enabled
 AND d.updated_at>now()-interval '30 days' ON CONFLICT DO NOTHING;
 RETURN n.id;
END; $$;

CREATE FUNCTION hocalist.push_claim()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE q hocalist.push_deliveries%ROWTYPE; t uuid:=gen_random_uuid();
BEGIN
 UPDATE hocalist.push_deliveries SET status='failed',last_error='attempt_limit' WHERE attempts>=8
 AND (status='pending' OR (status='sending' AND lease_until<clock_timestamp()));
 SELECT * INTO q FROM hocalist.push_deliveries WHERE attempts<8 AND available_at<=now()
 AND (status='pending' OR (status='sending' AND lease_until<clock_timestamp()))
 ORDER BY available_at,id LIMIT 1 FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN RETURN NULL; END IF;
 UPDATE hocalist.push_deliveries SET status='sending',attempts=attempts+1,lease_token=t,lease_until=clock_timestamp()+interval '90 seconds' WHERE id=q.id;
 RETURN jsonb_build_object('id',q.id,'lease',t);
END; $$;

CREATE FUNCTION hocalist.push_delivery_target(p_id uuid,p_lease uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('token',d.token,'notification_id',n.id)
 FROM hocalist.push_deliveries q JOIN hocalist.push_devices d ON d.id=q.device_id
 JOIN hocalist.notifications n ON n.id=q.notification_id
 WHERE q.id=p_id AND q.lease_token=p_lease AND q.status='sending' AND q.lease_until>clock_timestamp()
 AND d.user_id=n.user_id AND d.revision=q.device_revision AND d.enabled AND d.updated_at>now()-interval '30 days'
 AND EXISTS(SELECT 1 FROM hocalist.memberships m WHERE m.user_id=n.user_id AND m.status='active')
 AND NOT EXISTS(SELECT 1 FROM hocalist.memberships m WHERE m.user_id=n.user_id AND m.status IN ('restricted','disabled'));
$$;

CREATE FUNCTION hocalist.push_finish(p_id uuid,p_lease uuid,p_outcome text,p_retry_seconds integer DEFAULT 60)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE q hocalist.push_deliveries%ROWTYPE; d uuid;
BEGIN
 -- Same device -> delivery lock order as registration/logout, avoiding a deadlock cycle.
 SELECT device_id INTO STRICT d FROM hocalist.push_deliveries WHERE id=p_id;
 PERFORM 1 FROM hocalist.push_devices WHERE id=d FOR UPDATE;
 SELECT * INTO STRICT q FROM hocalist.push_deliveries WHERE id=p_id FOR UPDATE;
 IF p_lease IS NULL OR q.lease_token IS DISTINCT FROM p_lease OR q.status<>'sending' OR q.lease_until<=clock_timestamp() THEN RAISE EXCEPTION 'push_lease_lost'; END IF;
 IF p_outcome IS NULL OR p_outcome NOT IN ('accepted','skipped','unregistered','retry','configuration_error') THEN RAISE EXCEPTION 'invalid_push_outcome'; END IF;
 UPDATE hocalist.push_deliveries SET status=CASE WHEN p_outcome='accepted' THEN 'accepted' WHEN p_outcome='skipped' THEN 'skipped'
 WHEN p_outcome='retry' AND attempts<8 THEN 'pending' ELSE 'failed' END,
 available_at=now()+make_interval(secs=>greatest(60,least(86400,coalesce(p_retry_seconds,60)))),
 lease_token=NULL,lease_until=NULL,last_error=CASE WHEN p_outcome IN ('accepted','skipped') THEN NULL ELSE p_outcome END WHERE id=p_id;
 IF p_outcome='unregistered' THEN
  UPDATE hocalist.push_devices SET enabled=false,revision=revision+1 WHERE id=q.device_id AND revision=q.device_revision;
 END IF;
END; $$;
REVOKE ALL ON FUNCTION hocalist.push_device_register(uuid,text,text,boolean),hocalist.push_device_disable(uuid,text),
 hocalist.notification_enqueue(uuid,uuid,text,uuid),hocalist.push_claim(),hocalist.push_delivery_target(uuid,uuid),
 hocalist.push_finish(uuid,uuid,text,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.push_device_register(uuid,text,text,boolean),hocalist.push_device_disable(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.notification_enqueue(uuid,uuid,text,uuid),hocalist.push_claim(),
 hocalist.push_delivery_target(uuid,uuid),hocalist.push_finish(uuid,uuid,text,integer) TO service_role;
COMMIT;

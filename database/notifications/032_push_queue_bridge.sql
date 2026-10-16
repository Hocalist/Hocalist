-- Queue future inbox events for currently opted-in devices. No backfill,
-- scheduler activation or provider calls. Requires 007 and 030.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL
     OR to_regclass('hocalist.push_deliveries') IS NULL THEN
    RAISE EXCEPTION 'notification_foundation_required';
  END IF;
  IF to_regprocedure('hocalist.notification_queue_insert()') IS NOT NULL THEN
    RAISE EXCEPTION 'push_bridge_already_present';
  END IF;
END $$;
CREATE FUNCTION hocalist.notification_queue_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=NEW.user_id AND status='active')
     AND NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=NEW.user_id AND status IN ('restricted','disabled')) THEN
    INSERT INTO hocalist.push_deliveries(notification_id,device_id,device_revision)
    SELECT NEW.id,d.id,d.revision FROM hocalist.push_devices d
    WHERE d.user_id=NEW.user_id AND d.enabled AND d.updated_at>now()-interval '30 days'
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION hocalist.notification_queue_insert() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER hocalist_notification_queue_insert AFTER INSERT ON hocalist.notifications
FOR EACH ROW EXECUTE FUNCTION hocalist.notification_queue_insert();
COMMIT;

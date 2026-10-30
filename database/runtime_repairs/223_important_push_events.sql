-- Limit future phone alerts to owner-approved conversation and deal events.
-- No historical queue rows, preferences, schedules or inbox records change.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
 IF to_regprocedure('hocalist.notification_queue_insert()') IS NULL
    OR to_regclass('hocalist.push_deliveries') IS NULL THEN
   RAISE EXCEPTION 'notification_push_bridge_required';
 END IF;
END $$;
CREATE OR REPLACE FUNCTION hocalist.notification_queue_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  -- Routine account/billing/request changes remain in the inbox only.
  IF NEW.kind NOT IN ('new_offer','new_message','meeting_update') THEN
    RETURN NEW;
  END IF;
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
COMMIT;

-- Selection alerts reuse the offer topic, inbox route and important push queue.
-- Applies to future status transitions only; no historical backfill.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $$ BEGIN
 IF to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL
 OR to_regprocedure('hocalist.notification_recipient_allowed(uuid)') IS NULL THEN
   RAISE EXCEPTION 'notification_producers_required';
 END IF;
END $$;
CREATE OR REPLACE FUNCTION hocalist.notification_on_offer_selected()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NEW.status = 'selected' AND OLD.status IS DISTINCT FROM NEW.status
    AND NEW.accepted_revision_id IS NOT NULL
    AND hocalist.notification_recipient_allowed(NEW.seller_user_id) THEN
   PERFORM hocalist.notification_emit(
     NEW.seller_user_id,
     md5('offer:selected:' || NEW.id::text || ':' || NEW.accepted_revision_id::text)::uuid,
     'new_offer', NEW.id,
     'Your offer was selected',
     'A buyer selected your offer. Open the deal to view the details and chat with the buyer.',
     'hocalist://offers/' || NEW.id::text,
     jsonb_build_object('event', 'offer_selected', 'offer_id', NEW.id,
       'request_id', NEW.request_id, 'accepted_revision_id', NEW.accepted_revision_id));
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION hocalist.notification_on_offer_selected() FROM PUBLIC,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS notification_offer_selected ON hocalist.offers;
CREATE TRIGGER notification_offer_selected AFTER UPDATE OF status ON hocalist.offers
 FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_offer_selected();
COMMIT;

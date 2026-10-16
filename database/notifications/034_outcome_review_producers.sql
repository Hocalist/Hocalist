-- Additive notification producers for the approved outcome, review and
-- withdrawal events (over inbox 030 and producers 031).
--
-- Recipients are derived from the committed domain rows, never from client
-- input, and every event carries a deterministic key so a replayed transition
-- cannot duplicate a row. Disabled optional topics are skipped inside
-- `notification_emit`; account/safety updates stay mandatory. Titles, bodies,
-- links and payloads stay generic: no address, contact, PIN or amount detail.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $guard$ BEGIN
  IF to_regprocedure('hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('hocalist.notification_recipient_allowed(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Notification inbox/producer foundation 030/031 is missing';
  END IF;
  IF to_regclass('hocalist.sale_confirmations') IS NULL
     OR to_regclass('hocalist.verification_submissions') IS NULL
     OR to_regclass('hocalist.account_restrictions') IS NULL
     OR to_regclass('hocalist.withdrawal_requests') IS NULL THEN
    RAISE EXCEPTION 'Outcome/review/withdrawal tables are missing';
  END IF;
  IF to_regprocedure('hocalist.notification_on_sale_confirmed()') IS NOT NULL THEN
    RAISE EXCEPTION 'Outcome/review producers already exist';
  END IF;
END; $guard$;

-- ---------------------------------------------------------------------------
-- Purchase confirmed: both participants, meeting link, no payment detail
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.notification_on_sale_confirmed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF hocalist.notification_recipient_allowed(NEW.buyer_user_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.buyer_user_id,
      md5('sale:confirmed:' || NEW.id::text || ':buyer')::uuid,
      'meeting_update',
      NEW.meeting_id,
      'Purchase confirmed',
      'Your request PIN confirmed the purchase. Item payment stays between you and the seller.',
      'hocalist://meetings/' || NEW.meeting_id::text,
      jsonb_build_object('meeting_id', NEW.meeting_id, 'request_id', NEW.request_id));
  END IF;
  IF hocalist.notification_recipient_allowed(NEW.seller_user_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.seller_user_id,
      md5('sale:confirmed:' || NEW.id::text || ':seller')::uuid,
      'meeting_update',
      NEW.meeting_id,
      'Purchase confirmed',
      'The buyer confirmed the purchase with their request PIN.',
      'hocalist://meetings/' || NEW.meeting_id::text,
      jsonb_build_object('meeting_id', NEW.meeting_id, 'request_id', NEW.request_id));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_sale_confirmed
  AFTER INSERT ON hocalist.sale_confirmations
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_sale_confirmed();

-- ---------------------------------------------------------------------------
-- Manual review: reviewed-evidence decisions, restrictions and appeals
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.notification_on_verification_decision() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF OLD.status = 'pending' AND NEW.status <> 'pending'
     AND hocalist.notification_recipient_allowed(NEW.user_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.user_id,
      md5('verification:decision:' || NEW.id::text || ':' || NEW.revision::text)::uuid,
      'account_update',
      NEW.id,
      'Verification review updated',
      'Your reviewed evidence was ' || NEW.status || '. Open Hocalist for the reviewer reason.',
      'hocalist://account/' || NEW.id::text,
      jsonb_build_object('submission_id', NEW.id, 'status', NEW.status));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_verification_decision
  AFTER UPDATE ON hocalist.verification_submissions
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_verification_decision();

CREATE FUNCTION hocalist.notification_on_restriction() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF hocalist.notification_recipient_allowed(NEW.user_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.user_id,
      md5('restriction:applied:' || NEW.id::text)::uuid,
      'account_update',
      NEW.id,
      'Account restriction recorded',
      'A restriction was recorded after review. Open Hocalist to read the reason and appeal it.',
      'hocalist://account/' || NEW.id::text,
      jsonb_build_object('restriction_id', NEW.id, 'scope', NEW.scope));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_restriction_applied
  AFTER INSERT ON hocalist.account_restrictions
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_restriction();

CREATE FUNCTION hocalist.notification_on_appeal_decision() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF OLD.status = 'submitted' AND NEW.status <> 'submitted'
     AND hocalist.notification_recipient_allowed(NEW.user_id) THEN
    PERFORM hocalist.notification_emit(
      NEW.user_id,
      md5('appeal:decision:' || NEW.id::text || ':' || NEW.revision::text)::uuid,
      'account_update',
      NEW.restriction_id,
      'Appeal decision recorded',
      'Your appeal was ' || NEW.status || '. Open Hocalist for the reviewer reason.',
      'hocalist://account/' || NEW.restriction_id::text,
      jsonb_build_object('appeal_id', NEW.id, 'restriction_id', NEW.restriction_id,
        'status', NEW.status));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_appeal_decision
  AFTER UPDATE ON hocalist.restriction_appeals
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_appeal_decision();

-- ---------------------------------------------------------------------------
-- Withdrawals: processing acknowledgement and terminal states
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.notification_on_withdrawal() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_event text;
  v_revision bigint;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_event := 'submitted';
    v_revision := 1;
  ELSE
    v_event := NEW.status;
    v_revision := coalesce((SELECT max(revision) + 1 FROM hocalist.withdrawal_events
      WHERE withdrawal_id = NEW.id), 2);
  END IF;
  IF NOT hocalist.notification_recipient_allowed(NEW.user_id) THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;
  PERFORM hocalist.notification_emit(
    NEW.user_id,
    md5('withdrawal:' || v_event || ':' || NEW.id::text || ':' || v_revision::text)::uuid,
    'billing_update',
    NEW.id,
    CASE v_event
      WHEN 'paid' THEN 'Withdrawal paid'
      WHEN 'failed' THEN 'Withdrawal failed'
      ELSE 'Withdrawal submitted'
    END,
    CASE v_event
      WHEN 'paid' THEN 'Your withdrawal was paid. Open Hocalist for details.'
      WHEN 'failed' THEN 'Your withdrawal failed and the reserved amount was restored. Open Hocalist for details.'
      ELSE 'Your withdrawal is processing and the amount is reserved.'
    END,
    'hocalist://billing/' || NEW.id::text,
    jsonb_build_object('withdrawal_id', NEW.id, 'status', NEW.status));
  RETURN NEW;
END; $$;

CREATE TRIGGER notification_withdrawal_insert
  AFTER INSERT ON hocalist.withdrawal_requests
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_withdrawal();

CREATE TRIGGER notification_withdrawal_status
  AFTER UPDATE ON hocalist.withdrawal_requests
  FOR EACH ROW EXECUTE FUNCTION hocalist.notification_on_withdrawal();

REVOKE ALL ON FUNCTION
  hocalist.notification_on_sale_confirmed(),
  hocalist.notification_on_verification_decision(),
  hocalist.notification_on_restriction(),
  hocalist.notification_on_appeal_decision(),
  hocalist.notification_on_withdrawal()
  FROM PUBLIC, anon, authenticated, service_role;
COMMIT;

-- DRAFT: durable receipt only; never grants entitlements or wallet credits.
BEGIN;
CREATE TABLE hocalist.stripe_test_inbox (
  account_id text NOT NULL CHECK (account_id='acct_1Le6hqDmHEV44E5Y'),
  event_id text NOT NULL CHECK (length(event_id) BETWEEN 5 AND 255),
  event_type text NOT NULL,
  object_id text NOT NULL,
  event_created bigint NOT NULL CHECK (event_created > 0),
  livemode boolean NOT NULL CHECK (livemode=false),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processed','quarantined')),
  received_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(account_id,event_id)
);
ALTER TABLE hocalist.stripe_test_inbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.stripe_test_inbox FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hocalist.receive_stripe_test_event(
  p_account text,p_event_id text,p_type text,p_object_id text,p_created bigint,p_livemode boolean
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_existing hocalist.stripe_test_inbox%ROWTYPE;
BEGIN
  IF p_account IS DISTINCT FROM 'acct_1Le6hqDmHEV44E5Y' OR p_livemode IS DISTINCT FROM false
    OR p_event_id IS NULL OR p_event_id !~ '^evt_[A-Za-z0-9]+$'
    OR p_object_id IS NULL OR length(p_object_id) NOT BETWEEN 3 AND 255
    OR p_type IS NULL OR p_type NOT IN (
      'checkout.session.completed','checkout.session.async_payment_succeeded',
      'checkout.session.async_payment_failed','customer.subscription.created',
      'customer.subscription.updated','customer.subscription.deleted',
      'invoice.paid','invoice.payment_failed','charge.refunded',
      'charge.dispute.created','charge.dispute.closed') THEN
    RAISE EXCEPTION 'invalid_test_event' USING ERRCODE='22023';
  END IF;
  INSERT INTO hocalist.stripe_test_inbox(account_id,event_id,event_type,object_id,event_created,livemode)
    VALUES(p_account,p_event_id,p_type,p_object_id,p_created,p_livemode)
    ON CONFLICT(account_id,event_id) DO NOTHING;
  IF FOUND THEN RETURN true; END IF;
  SELECT * INTO STRICT v_existing FROM hocalist.stripe_test_inbox WHERE account_id=p_account AND event_id=p_event_id;
  IF v_existing.event_type<>p_type OR v_existing.object_id<>p_object_id OR v_existing.event_created<>p_created THEN
    RAISE EXCEPTION 'event_identity_conflict' USING ERRCODE='P0001';
  END IF;
  RETURN false;
END;
$$;
REVOKE ALL ON FUNCTION hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA hocalist TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean) TO service_role;
COMMIT;

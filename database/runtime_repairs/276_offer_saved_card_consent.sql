-- A saved Stripe card still requires the seller's explicit targeting-fee consent.
-- Only the service that checked the card against the seller's Stripe customer can call this.
BEGIN;
CREATE OR REPLACE FUNCTION hocalist.paygo_authorize_saved_card(
  p_user uuid, p_key uuid, p_customer text, p_method text, p_consent text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c jsonb; setup uuid;
BEGIN
  c := hocalist.paygo_customer(p_user);
  IF p_customer IS NULL OR c->>'customer_id' IS DISTINCT FROM p_customer OR
     p_method IS NULL OR p_method !~ '^pm_[a-zA-Z0-9]+$' OR p_key IS NULL OR
     p_consent IS DISTINCT FROM 'paygo-v1' THEN RAISE EXCEPTION 'invalid_authorization'; END IF;
  SELECT id INTO setup FROM hocalist.paygo_payment_setups WHERE user_id=p_user AND request_key=p_key;
  IF FOUND THEN
    IF EXISTS (SELECT 1 FROM hocalist.paygo_payment_methods WHERE user_id=p_user AND
      setup_id=setup AND revoked_at IS NULL AND payment_method_id=p_method AND customer_id=p_customer) THEN RETURN; END IF;
    RAISE EXCEPTION 'authorization_changed';
  END IF;
  UPDATE hocalist.paygo_payment_setups SET state='expired'
    WHERE user_id=p_user AND state IN ('creating','open');
  INSERT INTO hocalist.paygo_payment_setups(user_id,membership_id,request_key,customer_id,consent_version,state)
    VALUES(p_user,(c->>'membership_id')::uuid,p_key,p_customer,p_consent,'complete') RETURNING id INTO setup;
  INSERT INTO hocalist.paygo_payment_methods(user_id,setup_id,customer_id,payment_method_id,consent_version)
    VALUES(p_user,setup,p_customer,p_method,p_consent)
    ON CONFLICT(user_id) DO UPDATE SET setup_id=excluded.setup_id, customer_id=excluded.customer_id,
    payment_method_id=excluded.payment_method_id, consent_version=excluded.consent_version,
    authorised_at=now(),revoked_at=NULL;
END $$;
REVOKE ALL ON FUNCTION hocalist.paygo_authorize_saved_card(uuid,uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION hocalist.paygo_authorize_saved_card(uuid,uuid,text,text,text) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

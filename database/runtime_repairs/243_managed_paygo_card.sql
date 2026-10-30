-- Refresh a previously consented pay-as-you-go card from the verified
-- provider customer default. No new consent, charge or retry is granted.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE FUNCTION hocalist.paygo_card_context(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.marketplace_assert_role(p_user,'seller');
 RETURN (SELECT jsonb_build_object('customer_id',customer_id,'payment_method_id',payment_method_id)
 FROM hocalist.paygo_payment_methods WHERE user_id=p_user AND revoked_at IS NULL);
END $$;
CREATE FUNCTION hocalist.paygo_card_refresh(p_user uuid,p_customer text,p_previous text,p_method text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.marketplace_assert_role(p_user,'seller');
 PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
 IF p_method IS NULL OR p_method !~ '^pm_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
 UPDATE hocalist.paygo_payment_methods SET payment_method_id=p_method
 WHERE user_id=p_user AND customer_id=p_customer AND payment_method_id=p_previous AND revoked_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'payment_method_changed'; END IF;
END $$;
REVOKE ALL ON FUNCTION hocalist.paygo_card_context(uuid),hocalist.paygo_card_refresh(uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.paygo_card_context(uuid),hocalist.paygo_card_refresh(uuid,text,text,text) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

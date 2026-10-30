-- One-use native billing admission receipts. No access tokens are stored here.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE hocalist.native_billing_receipts (
  digest text PRIMARY KEY CHECK(digest ~ '^[a-f0-9]{64}$'),
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  expires_at timestamptz NOT NULL
);
ALTER TABLE hocalist.native_billing_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.native_billing_receipts FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hocalist.native_billing_receipt(p_action text,p_digest text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); consumed integer;
BEGIN
 IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='seller' AND status='active')
 OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'billing_access_denied' USING ERRCODE='42501';
 END IF;
 IF p_digest IS NULL OR p_digest !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'invalid_receipt' USING ERRCODE='22023'; END IF;
 IF p_action='register' THEN
  -- Serialize issuance per account and bound retained rows to one per account.
  PERFORM 1 FROM hocalist.profiles WHERE id=u FOR UPDATE;
  DELETE FROM hocalist.native_billing_receipts WHERE user_id=u OR expires_at<=now();
  INSERT INTO hocalist.native_billing_receipts VALUES(p_digest,u,now()+interval '90 seconds');
  RETURN true;
 ELSIF p_action='consume' THEN
  DELETE FROM hocalist.native_billing_receipts WHERE digest=p_digest AND user_id=u AND expires_at>now();
  GET DIAGNOSTICS consumed=ROW_COUNT;
  RETURN consumed=1;
 END IF;
 RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023';
END $$;
REVOKE ALL ON FUNCTION hocalist.native_billing_receipt(text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION hocalist.native_billing_receipt(text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

-- Restore an owner's archived Store listing as a private draft.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE OR REPLACE FUNCTION hocalist.marketplace_restore_store_listing(p_listing uuid,p_revision bigint,p_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
 v_user uuid := auth.uid(); v_row hocalist.store_listings%ROWTYPE;
 v_receipt hocalist.marketplace_receipts%ROWTYPE; v_hash text; v_result jsonb;
BEGIN
 PERFORM hocalist.marketplace_assert_role(v_user,'seller');
 IF EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=v_user AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501'; END IF;
 IF p_listing IS NULL OR p_revision IS NULL OR p_revision<1 OR p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
  RAISE EXCEPTION 'invalid_command' USING ERRCODE='22023'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text||':store.restore:'||p_key,0));
 v_hash := encode(sha256(convert_to(jsonb_build_object('listing',p_listing,'revision',p_revision)::text,'UTF8')),'hex');
 SELECT * INTO v_receipt FROM hocalist.marketplace_receipts WHERE user_id=v_user AND operation='store.restore' AND idempotency_key=p_key;
 IF FOUND THEN
  IF v_receipt.request_hash<>v_hash THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
  RETURN v_receipt.result;
 END IF;
 -- Same seller lock as Store create/publish protects capacity under concurrent restores.
 PERFORM 1 FROM hocalist.profiles WHERE id=v_user FOR UPDATE;
 SELECT * INTO v_row FROM hocalist.store_listings WHERE id=p_listing AND seller_user_id=v_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'listing_not_found' USING ERRCODE='P0002'; END IF;
 IF v_row.revision<>p_revision THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='40001'; END IF;
 IF v_row.status<>'archived' THEN RAISE EXCEPTION 'invalid_transition' USING ERRCODE='P0001'; END IF;
 IF (SELECT count(*) FROM hocalist.store_listings WHERE seller_user_id=v_user AND status<>'archived') >= hocalist.marketplace_store_limit(v_user) THEN
  RAISE EXCEPTION 'store_limit_exceeded' USING ERRCODE='P0001'; END IF;
 UPDATE hocalist.store_listings SET status='draft', published_at=NULL, revision=revision+1, updated_at=now() WHERE id=p_listing;
 -- Keep the previous moderation decision and all content/photos/history; editing still requires review.
 v_result := hocalist.marketplace_listing_json(p_listing);
 INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
 VALUES(v_user,'store.restore',p_key,v_hash,v_result);
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION hocalist.marketplace_restore_store_listing(uuid,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.marketplace_restore_store_listing(uuid,bigint,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

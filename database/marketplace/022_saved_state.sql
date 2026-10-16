-- Additive desired-state saved operation. Does not replace marketplace commands.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $$ BEGIN
  IF to_regprocedure('hocalist.marketplace_saved_set(text,uuid,boolean,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'saved_state_already_present';
  END IF;
  IF to_regclass('hocalist.saved_items') IS NULL OR
     to_regclass('hocalist.marketplace_receipts') IS NULL THEN
    RAISE EXCEPTION 'marketplace_foundation_required';
  END IF;
END $$;

CREATE FUNCTION hocalist.marketplace_saved_set(
  p_type text, p_item uuid, p_saved boolean, p_key text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_hash text;
  v_receipt hocalist.marketplace_receipts%ROWTYPE;
  v_result jsonb;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_type IS NULL OR p_type NOT IN ('request','store_listing') OR p_item IS NULL
     OR p_saved IS NULL OR p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid_saved_input' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id=v_user AND status='active')
     OR EXISTS (SELECT 1 FROM hocalist.memberships WHERE user_id=v_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text || ':saved.set:' || p_key, 0));
  v_hash := encode(sha256(convert_to(jsonb_build_object('type',p_type,'item',p_item,'saved',p_saved)::text,'UTF8')),'hex');
  SELECT * INTO v_receipt FROM hocalist.marketplace_receipts
    WHERE user_id=v_user AND operation='saved.set' AND idempotency_key=p_key;
  IF FOUND THEN
    IF v_receipt.request_hash <> v_hash THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
    END IF;
    RETURN v_receipt.result;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text || ':saved.item:' || p_type || ':' || p_item::text, 0));
  IF p_saved THEN
    -- Authorization is re-evaluated before storing a new bookmark. Removing a
    -- hidden/deleted item only touches this user's reference and stays allowed.
    IF p_type='request' THEN
      PERFORM hocalist.marketplace_request(p_item);
    ELSE
      PERFORM hocalist.marketplace_store_listing(p_item);
    END IF;
    INSERT INTO hocalist.saved_items(user_id,item_type,item_id)
      VALUES(v_user,p_type,p_item) ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM hocalist.saved_items WHERE user_id=v_user AND item_type=p_type AND item_id=p_item;
  END IF;
  v_result := jsonb_build_object('item_type',p_type,'item_id',p_item,'saved',p_saved);
  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(v_user,'saved.set',p_key,v_hash,v_result);
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION hocalist.marketplace_saved_set(text,uuid,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.marketplace_saved_set(text,uuid,boolean,text) TO authenticated;
COMMIT;

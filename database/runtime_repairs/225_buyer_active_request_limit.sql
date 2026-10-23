-- Owner-managed buyer posting capacity. Existing requests are not closed.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE hocalist.request_posting_settings (
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  maximum_active_requests integer NOT NULL DEFAULT 4 CHECK(maximum_active_requests BETWEEN 1 AND 100),
  revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.request_posting_settings(singleton) VALUES(true);
CREATE TABLE hocalist.request_posting_settings_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid NOT NULL,
  operation_key text NOT NULL,
  expected_revision bigint NOT NULL,
  previous_limit integer NOT NULL,
  requested_limit integer NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(actor_id,operation_key)
);
ALTER TABLE hocalist.request_posting_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.request_posting_settings_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.request_posting_settings,hocalist.request_posting_settings_audit FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION hocalist.admin_request_posting_settings(
  p_limit integer DEFAULT NULL, p_revision bigint DEFAULT NULL, p_key text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  actor uuid:=auth.uid();
  setting hocalist.request_posting_settings%ROWTYPE;
  receipt hocalist.request_posting_settings_audit%ROWTYPE;
  response jsonb;
  previous integer;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(actor);
  IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN
    RAISE EXCEPTION 'admin_mfa_required' USING ERRCODE='42501';
  END IF;
  IF p_limit IS NULL AND p_revision IS NULL AND p_key IS NULL THEN
    SELECT * INTO STRICT setting FROM hocalist.request_posting_settings WHERE singleton;
  ELSE
    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_revision IS NULL OR p_revision<1
       OR p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
      RAISE EXCEPTION 'invalid_posting_limit' USING ERRCODE='22023';
    END IF;
    SELECT * INTO STRICT setting FROM hocalist.request_posting_settings WHERE singleton FOR UPDATE;
    SELECT * INTO receipt FROM hocalist.request_posting_settings_audit WHERE actor_id=actor AND operation_key=p_key;
    IF FOUND THEN
      IF receipt.requested_limit<>p_limit OR receipt.expected_revision<>p_revision THEN
        RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
      END IF;
      RETURN receipt.result;
    END IF;
    IF setting.revision<>p_revision THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;
    previous:=setting.maximum_active_requests;
    UPDATE hocalist.request_posting_settings SET maximum_active_requests=p_limit,
      revision=revision+1,updated_at=now() WHERE singleton RETURNING * INTO setting;
  END IF;
  response:=jsonb_build_object('maximum_active_requests',setting.maximum_active_requests,
    'revision',setting.revision,'updated_at',setting.updated_at);
  IF p_limit IS NOT NULL THEN
    INSERT INTO hocalist.request_posting_settings_audit(actor_id,operation_key,expected_revision,previous_limit,requested_limit,result)
      VALUES(actor,p_key,p_revision,previous,p_limit,response);
  END IF;
  RETURN response;
END $$;
REVOKE ALL ON FUNCTION hocalist.admin_request_posting_settings(integer,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_request_posting_settings(integer,bigint,text) TO authenticated;

CREATE FUNCTION hocalist.enforce_buyer_active_request_limit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE maximum integer; active_count integer;
BEGIN
  -- Only requests still open to offers occupy a slot.
  IF NEW.status<>'active' OR (NEW.acceptance_expires_at IS NOT NULL AND NEW.acceptance_expires_at<=now()) THEN
    RETURN NEW;
  END IF;
  IF TG_OP='UPDATE' THEN
    IF OLD.buyer_user_id=NEW.buyer_user_id AND OLD.status='active'
       AND (OLD.acceptance_expires_at IS NULL OR OLD.acceptance_expires_at>now()) THEN
      RETURN NEW;
    END IF;
  END IF;
  SELECT maximum_active_requests INTO STRICT maximum FROM hocalist.request_posting_settings WHERE singleton FOR SHARE;
  -- Serialize different posting/reopening keys for the same buyer.
  PERFORM pg_advisory_xact_lock(hashtextextended('hocalist.active_requests:'||NEW.buyer_user_id::text,0));
  SELECT count(*)::integer INTO active_count FROM hocalist.requests r
    WHERE r.buyer_user_id=NEW.buyer_user_id AND r.id<>NEW.id AND r.status='active'
      AND (r.acceptance_expires_at IS NULL OR r.acceptance_expires_at>now());
  IF active_count>=maximum THEN
    RAISE EXCEPTION 'active_request_limit_reached:%',maximum USING ERRCODE='P0001';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION hocalist.enforce_buyer_active_request_limit() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER buyer_active_request_limit
  BEFORE INSERT OR UPDATE OF status,acceptance_expires_at,buyer_user_id ON hocalist.requests
  FOR EACH ROW EXECUTE FUNCTION hocalist.enforce_buyer_active_request_limit();
NOTIFY pgrst,'reload schema';
COMMIT;

BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE hocalist.admin_listing_decisions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),listing_id uuid NOT NULL REFERENCES hocalist.store_listings(id),
 actor_id uuid NOT NULL REFERENCES auth.users(id),request_key text NOT NULL,input jsonb NOT NULL,result jsonb NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 1 AND 1000),created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(actor_id,request_key));
ALTER TABLE hocalist.admin_listing_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.admin_listing_decisions FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hocalist.admin_moderation_decide(p_listing uuid,p_revision bigint,p_decision text,p_reason text,p_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=auth.uid(); payload jsonb; prior hocalist.admin_listing_decisions; result jsonb;
BEGIN
 PERFORM hocalist.marketplace_assert_admin(actor);
 IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN RAISE EXCEPTION 'admin_mfa_required' USING ERRCODE='42501';END IF;
 IF p_listing IS NULL OR p_revision IS NULL OR p_revision<1 OR p_decision IS NULL OR p_decision NOT IN ('approved','rejected') OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 1 AND 1000 OR p_key IS NULL OR length(p_key) NOT BETWEEN 1 AND 128 THEN RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';END IF;
 payload:=jsonb_build_object('listing_id',p_listing,'expected_revision',p_revision,'moderation_status',p_decision,'reason',btrim(p_reason));
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||'|moderation|'||p_key,0));
 SELECT * INTO prior FROM hocalist.admin_listing_decisions WHERE actor_id=actor AND request_key=p_key;
 IF FOUND THEN IF prior.input<>payload THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='22023';END IF;RETURN prior.result;END IF;
 result:=hocalist.marketplace_admin_command('store.set_moderation',p_key,payload-'reason');
 INSERT INTO hocalist.admin_listing_decisions(listing_id,actor_id,request_key,input,result,reason) VALUES(p_listing,actor,p_key,payload,result,btrim(p_reason));
 RETURN result;
END $$;
CREATE FUNCTION hocalist.admin_moderation_history(p_listing uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.marketplace_assert_admin(auth.uid());
 IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN RAISE EXCEPTION 'admin_mfa_required' USING ERRCODE='42501';END IF;
 RETURN (SELECT coalesce(jsonb_agg(item ORDER BY created_at DESC,id DESC),'[]'::jsonb) FROM (
 SELECT id,created_at,jsonb_build_object('id',id,'decision',input->>'moderation_status','reason',reason,'created_at',created_at) AS item
 FROM hocalist.admin_listing_decisions WHERE listing_id=p_listing ORDER BY created_at DESC,id DESC LIMIT 50) x);
END $$;
REVOKE ALL ON FUNCTION hocalist.admin_moderation_decide(uuid,bigint,text,text,text),hocalist.admin_moderation_history(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_moderation_decide(uuid,bigint,text,text,text),hocalist.admin_moderation_history(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

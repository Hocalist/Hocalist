-- Applies only to targets created after installation. No historical refunds.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE hocalist.target_fee_policy (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 late_window_hours integer NOT NULL DEFAULT 12 CHECK(late_window_hours BETWEEN 1 AND 168),
 late_total_minor bigint NOT NULL DEFAULT 200 CHECK(late_total_minor>0),
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0)
);
INSERT INTO hocalist.target_fee_policy(singleton) VALUES(true);
ALTER TABLE hocalist.target_fee_policy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.target_fee_policy FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE hocalist.credit_targets ADD COLUMN policy_plan text
 CHECK(policy_plan IN ('free','pro','elite'));
ALTER TABLE hocalist.credit_targets ADD COLUMN competitors_viewed_at timestamptz;
CREATE FUNCTION hocalist.credit_target_policy_snapshot()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 NEW.policy_plan:=hocalist.marketplace_seller_plan(NEW.user_id);
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION hocalist.credit_target_policy_snapshot() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER credit_target_policy_snapshot BEFORE INSERT ON hocalist.credit_targets
 FOR EACH ROW EXECUTE FUNCTION hocalist.credit_target_policy_snapshot();

-- The accepted request expiry, not time since posting, defines this window.
DO $late$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_reserve_internal(uuid,uuid,uuid,date,integer)')) INTO d;
 IF strpos(d,'b.initial_fee_minor,b.winning_total_minor,b.winning_total_minor,p_week,b.rate_version')=0
 OR strpos(d,'balance_minor-reserved_minor >= winning_total_minor')=0 THEN
   RAISE EXCEPTION 'Target reservation definition drift';
 END IF;
 d:=replace(d,'o hocalist.offers%ROWTYPE;','o hocalist.offers%ROWTYPE; v_late boolean;');
 d:=replace(d,'-- Same seller lock',
 'SELECT acceptance_expires_at>now() AND acceptance_expires_at<=now()+make_interval(hours=>(SELECT late_window_hours FROM hocalist.target_fee_policy WHERE singleton)) INTO v_late FROM hocalist.requests WHERE id=p_request; -- Same seller lock');
 d:=replace(d,'balance_minor-reserved_minor >= winning_total_minor',
 'balance_minor-reserved_minor >= CASE WHEN v_late THEN (SELECT late_total_minor FROM hocalist.target_fee_policy WHERE singleton) ELSE winning_total_minor END');
 d:=replace(d,'b.initial_fee_minor,b.winning_total_minor,b.winning_total_minor,p_week,b.rate_version',
 'CASE WHEN v_late THEN (SELECT late_total_minor FROM hocalist.target_fee_policy WHERE singleton) ELSE b.initial_fee_minor END,CASE WHEN v_late THEN (SELECT late_total_minor FROM hocalist.target_fee_policy WHERE singleton) ELSE b.winning_total_minor END,CASE WHEN v_late THEN (SELECT late_total_minor FROM hocalist.target_fee_policy WHERE singleton) ELSE b.winning_total_minor END,p_week,CASE WHEN v_late THEN ''late-fee-v''||(SELECT revision FROM hocalist.target_fee_policy WHERE singleton)::text ELSE b.rate_version END');
 EXECUTE d;
END $late$;

CREATE FUNCTION hocalist.credit_policy_release(p_target uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t hocalist.credit_targets%ROWTYPE; o hocalist.offers%ROWTYPE; v_refund boolean:=false;
BEGIN
 PERFORM 1 FROM hocalist.profiles WHERE id=(SELECT user_id FROM hocalist.credit_targets WHERE id=p_target) FOR UPDATE;
 SELECT * INTO t FROM hocalist.credit_targets WHERE id=p_target FOR UPDATE;
 IF NOT FOUND OR t.status NOT IN ('reserved','initial_charged','released') THEN RETURN; END IF;
 SELECT * INTO o FROM hocalist.offers WHERE id=t.offer_id;
 IF t.policy_plan IN ('pro','elite') AND o.status='withdrawn'
   AND o.accepted_revision_id IS NULL
   AND NOT EXISTS(SELECT 1 FROM hocalist.offer_revisions r WHERE r.offer_id=o.id AND r.proposed_by_user_id=o.buyer_user_id)
   AND NOT EXISTS(SELECT 1 FROM hocalist.conversation_messages m WHERE m.conversation_id=o.conversation_id
     AND m.sender_user_id=o.buyer_user_id AND m.kind='text' AND m.sent_at>=o.created_at) THEN
   v_refund:=true;
 END IF;
 IF t.policy_plan='elite' AND t.competitors_viewed_at IS NULL
   AND NOT EXISTS(SELECT 1 FROM hocalist.sale_confirmations s WHERE s.request_id=t.request_id)
   AND EXISTS(SELECT 1 FROM hocalist.requests r WHERE r.id=t.request_id
     AND (r.status IN ('closed','cancelled') OR r.acceptance_expires_at<=now()))
   AND NOT EXISTS(SELECT 1 FROM hocalist.meetings m WHERE m.request_id=t.request_id
     AND (m.status='proposed' OR (m.status IN ('accepted','reschedule_proposed') AND m.meeting_expires_at>now())))
   AND o.status<>'withdrawn' THEN v_refund:=true; END IF;
 IF t.status='released' AND NOT v_refund THEN RETURN; END IF;
 PERFORM hocalist.credit_settle_internal(t.id,CASE WHEN v_refund THEN 'refund' ELSE 'release' END);
END $$;
REVOKE ALL ON FUNCTION hocalist.credit_policy_release(uuid) FROM PUBLIC,anon,authenticated,service_role;
DO $release$
DECLARE d text; f text;
BEGIN
 FOREACH f IN ARRAY ARRAY['hocalist.credit_release_offer(uuid)','hocalist.credit_reconcile_internal(uuid)'] LOOP
  SELECT pg_get_functiondef(to_regprocedure(f)) INTO d;
  IF strpos(d,'PERFORM hocalist.credit_settle_internal(t.id,''release'');')=0 THEN
    RAISE EXCEPTION 'Target release definition drift: %',f;
  END IF;
  EXECUTE replace(d,'PERFORM hocalist.credit_settle_internal(t.id,''release'');','PERFORM hocalist.credit_policy_release(t.id);');
 END LOOP;
 SELECT pg_get_functiondef(to_regprocedure('hocalist.credit_reconcile_internal(uuid)')) INTO d;
 EXECUTE replace(d,'WHERE user_id=p_user AND status IN (''reserved'',''initial_charged'')',
 'WHERE user_id=p_user AND (status IN (''reserved'',''initial_charged'') OR (status=''released'' AND policy_plan=''elite'' AND competitors_viewed_at IS NULL))');
END $release$;

-- Viewing is a mutation: recording forfeiture and disclosing prices are atomic.
-- Never disclose competitors' names, messages, addresses or contact details.
CREATE FUNCTION hocalist.credit_view_competing_offers(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); t hocalist.credit_targets%ROWTYPE;
BEGIN
 IF u IS NULL OR hocalist.marketplace_seller_plan(u)<>'elite'
 OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='seller' AND status='active')
 OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
 END IF;
 PERFORM 1 FROM hocalist.profiles WHERE id=u FOR UPDATE;
 SELECT x.* INTO t FROM hocalist.credit_targets x JOIN hocalist.offers o ON o.id=x.offer_id
 WHERE x.user_id=u AND x.request_id=p_request AND x.policy_plan='elite'
 AND x.status='initial_charged' AND o.status='selected' AND o.accepted_revision_id IS NOT NULL FOR UPDATE OF x;
 IF NOT FOUND THEN RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501'; END IF;
 UPDATE hocalist.credit_targets SET competitors_viewed_at=coalesce(competitors_viewed_at,now()) WHERE id=t.id;
 RETURN jsonb_build_object('refund_eligible',false,'offers',coalesce((SELECT jsonb_agg(jsonb_build_object(
  'price_minor',r.price_minor,'currency_code',r.currency_code) ORDER BY o.created_at,o.id)
  FROM hocalist.offers o JOIN LATERAL (SELECT price_minor,currency_code FROM hocalist.offer_revisions
    WHERE offer_id=o.id ORDER BY sequence DESC LIMIT 1) r ON true
  WHERE o.request_id=p_request AND o.seller_user_id<>u AND o.status IN ('submitted','selected')),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION hocalist.credit_view_competing_offers(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.credit_view_competing_offers(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

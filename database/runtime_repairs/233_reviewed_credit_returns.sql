-- Reviewed targeting-fee returns only; never creates arbitrary wallet credits.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE hocalist.reviewed_credit_returns (
 target_id uuid PRIMARY KEY REFERENCES hocalist.credit_targets(id),
 case_id uuid NOT NULL REFERENCES hocalist.support_cases(id),
 reviewer_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 amount_minor bigint NOT NULL CHECK(amount_minor>0),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.reviewed_credit_returns ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.reviewed_credit_returns FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hocalist.admin_report_credit_targets(p_case uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE c hocalist.support_cases%ROWTYPE;
BEGIN
 PERFORM hocalist.marketplace_assert_admin(auth.uid());
 SELECT * INTO c FROM hocalist.support_cases WHERE id=p_case AND reason_code IN ('deal','safety');
 IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;
 RETURN coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (
  SELECT t.id,r.title,coalesce((SELECT rr.amount_minor FROM hocalist.reviewed_credit_returns rr WHERE rr.target_id=t.id),t.charged_minor) AS fee_minor,t.status,t.created_at,
    EXISTS(SELECT 1 FROM hocalist.reviewed_credit_returns rr WHERE rr.target_id=t.id) AS returned
  FROM hocalist.credit_targets t JOIN hocalist.offers o ON o.id=t.offer_id JOIN hocalist.requests r ON r.id=t.request_id
  WHERE c.reporter_id IN (o.buyer_user_id,o.seller_user_id)
    AND ((t.status IN ('initial_charged','released') AND t.charged_minor>0) OR EXISTS(SELECT 1 FROM hocalist.reviewed_credit_returns rr WHERE rr.target_id=t.id))
  ORDER BY t.created_at DESC LIMIT 100) x),'[]'::jsonb);
END $$;
CREATE FUNCTION hocalist.admin_report_credit_return(p_case uuid,p_target uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c hocalist.support_cases%ROWTYPE; t hocalist.credit_targets%ROWTYPE; previous hocalist.reviewed_credit_returns%ROWTYPE;
BEGIN
 PERFORM hocalist.marketplace_assert_admin(auth.uid());
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500 THEN RAISE EXCEPTION 'record_review_reason' USING ERRCODE='22023'; END IF;
 SELECT * INTO c FROM hocalist.support_cases WHERE id=p_case AND reason_code IN ('deal','safety') FOR UPDATE;
 IF NOT FOUND OR c.status<>'resolved' OR NOT EXISTS(SELECT 1 FROM hocalist.health_review_notes WHERE case_id=c.id AND decision IN ('watch','restriction_recommended')) THEN
   RAISE EXCEPTION 'complete_misconduct_review_first' USING ERRCODE='P0001';
 END IF;
 PERFORM 1 FROM hocalist.profiles WHERE id=(SELECT user_id FROM hocalist.credit_targets WHERE id=p_target) FOR UPDATE;
 SELECT * INTO t FROM hocalist.credit_targets WHERE id=p_target FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM hocalist.offers o WHERE o.id=t.offer_id AND c.reporter_id IN (o.buyer_user_id,o.seller_user_id)) THEN
   RAISE EXCEPTION 'unrelated_report' USING ERRCODE='42501';
 END IF;
 SELECT * INTO previous FROM hocalist.reviewed_credit_returns WHERE target_id=t.id;
 IF FOUND THEN
   IF previous.case_id<>p_case OR previous.reason<>btrim(p_reason) THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
   RETURN jsonb_build_object('returned_minor',previous.amount_minor,'already_returned',true);
 END IF;
 IF t.status NOT IN ('initial_charged','released') OR t.charged_minor<=0
 OR EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE request_id=t.request_id)
 OR EXISTS(SELECT 1 FROM hocalist.buyer_rewards WHERE target_id=t.id) THEN
   RAISE EXCEPTION 'fee_not_eligible_for_return' USING ERRCODE='P0001';
 END IF;
 INSERT INTO hocalist.reviewed_credit_returns(target_id,case_id,reviewer_id,amount_minor,reason)
 VALUES(t.id,c.id,auth.uid(),t.charged_minor,btrim(p_reason));
 PERFORM hocalist.credit_settle_internal(t.id,'refund');
 RETURN jsonb_build_object('returned_minor',t.charged_minor,'already_returned',false);
END $$;
REVOKE ALL ON FUNCTION hocalist.admin_report_credit_targets(uuid),hocalist.admin_report_credit_return(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_report_credit_targets(uuid),hocalist.admin_report_credit_return(uuid,uuid,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

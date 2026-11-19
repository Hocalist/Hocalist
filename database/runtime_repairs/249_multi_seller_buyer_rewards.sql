-- Prospective multi-seller buyer rewards. LIVE APPLICATION REQUIRES OWNER APPROVAL.
-- Does not backfill historical purchases, charge sellers, change rates,
-- enable payouts, or rewrite existing reward/financial records.
-- Reward estimates are read-only and are never withdrawal funds.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF to_regprocedure('hocalist.paygo_charge_finish(uuid,text,text,bigint,text)') IS NULL
 OR to_regprocedure('hocalist.reversal_admin_command(text,text,jsonb)') IS NULL
 OR to_regprocedure('hocalist.commercial_reward_wallet()') IS NULL THEN
   RAISE EXCEPTION 'Reward aggregation prerequisite missing';
 END IF;
END $guard$;
DO $source_guard$
DECLARE f record; fingerprint text;
BEGIN
 FOR f IN SELECT * FROM (VALUES ('hocalist.reversal_admin_command(text,text,jsonb)','6db799582378d001161177249ecaee9a','5fdbed9e2fea8243a55dc723004abcf2'),('hocalist.commercial_sale_history(timestamptz,uuid)','cb7c70055ba2214859e829cd743b19ae','25bd272b7dfc9d60beba0609860c5e98'),('hocalist.commercial_sale_detail(uuid)','1ad534c01046b7af8719b31e40feb166','5dbf1ab284862dd91b781b556736aa25')) AS reviewed(signature,baseline,repaired) LOOP
   SELECT md5(replace(prosrc,chr(13),'')) INTO fingerprint FROM pg_proc WHERE oid=to_regprocedure(f.signature);
   IF fingerprint IS NULL OR fingerprint NOT IN (f.baseline,f.repaired) THEN
     RAISE EXCEPTION 'Unreviewed live function change: %',f.signature;
   END IF;
 END LOOP;
END $source_guard$;

-- Shared contribution eligibility and preserved historical cutover.
CREATE TABLE IF NOT EXISTS hocalist.reward_aggregation_policy (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 effective_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.reward_aggregation_policy(singleton) VALUES(true) ON CONFLICT(singleton) DO NOTHING;
ALTER TABLE hocalist.reward_aggregation_policy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.reward_aggregation_policy FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION hocalist.reward_target_collected(p_target uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(
   SELECT 1 FROM hocalist.credit_targets t
   JOIN hocalist.sale_confirmations s ON s.request_id=t.request_id
   WHERE t.id=p_target AND t.status<>'refunded' AND t.charged_minor>0
     AND ((t.user_id=s.seller_user_id AND NOT t.reply_qualification_enabled) OR
       (t.qualified_at IS NOT NULL AND t.qualified_at<=s.confirmed_at))
     AND CASE WHEN t.user_id=s.seller_user_id
       THEN t.offer_id=s.offer_id AND t.status='won' AND t.charged_minor=t.winning_minor
       ELSE t.status IN ('initial_charged','released') AND t.charged_minor>=t.initial_minor
         AND t.initial_minor>0 END
 );
$$;

CREATE OR REPLACE FUNCTION hocalist.reward_target_estimate(p_target uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce((SELECT CASE WHEN t.rate_version LIKE 'late-fee-%' THEN p.late_minor
   ELSE p.normal_minor END FROM hocalist.credit_targets t
   CROSS JOIN hocalist.reward_policy p WHERE t.id=p_target AND p.singleton),0);
$$;

CREATE OR REPLACE FUNCTION hocalist.reward_pending_estimate_minor(p_buyer uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce(sum(hocalist.reward_target_estimate(t.id)),0)
 FROM hocalist.credit_targets t JOIN hocalist.requests r ON r.id=t.request_id
 LEFT JOIN hocalist.sale_confirmations s ON s.request_id=r.id
 WHERE r.buyer_user_id=p_buyer AND t.qualified_at IS NOT NULL
   AND t.status IN ('reserved','initial_charged','released')
   AND ((s.id IS NULL AND ((r.status='active' AND (r.acceptance_expires_at IS NULL OR r.acceptance_expires_at>now()))
     OR EXISTS(SELECT 1 FROM hocalist.meetings m WHERE m.request_id=r.id
       AND m.status IN ('accepted','reschedule_proposed') AND m.meeting_expires_at>now())))
     OR (s.id IS NOT NULL AND s.confirmed_at>=(SELECT effective_at FROM hocalist.reward_aggregation_policy WHERE singleton)
       AND t.qualified_at<=s.confirmed_at AND NOT hocalist.reward_target_collected(t.id)
       AND NOT EXISTS(SELECT 1 FROM hocalist.buyer_rewards w WHERE w.target_id=t.id)
       AND EXISTS(SELECT 1 FROM hocalist.paygo_charges j WHERE j.target_id=t.id
         AND j.state IN ('queued','pending','processing','requires_action','requires_payment_method','review'))));
$$;
REVOKE ALL ON FUNCTION hocalist.reward_target_collected(uuid),
 hocalist.reward_target_estimate(uuid),hocalist.reward_pending_estimate_minor(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE hocalist.buyer_rewards DROP CONSTRAINT IF EXISTS buyer_rewards_outcome_id_key;
CREATE INDEX IF NOT EXISTS buyer_rewards_outcome_lookup ON hocalist.buyer_rewards(outcome_id);
CREATE OR REPLACE FUNCTION hocalist.reward_accrue_internal(p_outcome uuid,p_target uuid,p_amount bigint,p_rule text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE outcome hocalist.sale_confirmations%ROWTYPE; target hocalist.credit_targets%ROWTYPE;
 reward hocalist.buyer_rewards%ROWTYPE;
BEGIN
 IF p_amount IS NULL OR p_amount<=0 OR p_rule IS NULL OR length(btrim(p_rule)) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_reward'; END IF;
 SELECT * INTO STRICT outcome FROM hocalist.sale_confirmations WHERE id=p_outcome;
 SELECT * INTO target FROM hocalist.credit_targets WHERE id=p_target;
 IF NOT FOUND OR target.request_id<>outcome.request_id THEN RAISE EXCEPTION 'collected_sale_fee_required'; END IF;
 IF target.user_id<>outcome.seller_user_id AND outcome.confirmed_at<
   (SELECT effective_at FROM hocalist.reward_aggregation_policy WHERE singleton) THEN
   RAISE EXCEPTION 'historical_reward_review_required';
 END IF;
 PERFORM 1 FROM hocalist.profiles WHERE id=target.user_id FOR UPDATE;
 PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||outcome.buyer_user_id::text,902));
 IF NOT hocalist.reward_target_collected(p_target) THEN RAISE EXCEPTION 'collected_sale_fee_required'; END IF;
 SELECT * INTO reward FROM hocalist.buyer_rewards WHERE target_id=p_target;
 IF FOUND THEN
   IF reward.outcome_id<>p_outcome OR reward.amount_minor<>p_amount OR reward.rule_version<>p_rule THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
   RETURN reward.id;
 END IF;
 INSERT INTO hocalist.buyer_rewards(outcome_id,target_id,buyer_user_id,amount_minor,rule_version)
 VALUES(p_outcome,p_target,outcome.buyer_user_id,p_amount,p_rule) RETURNING id INTO reward.id;
 RETURN reward.id;
END $$;

CREATE OR REPLACE FUNCTION hocalist.reward_accrue_request_internal(p_request uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE outcome hocalist.sale_confirmations%ROWTYPE; target hocalist.credit_targets%ROWTYPE; policy hocalist.reward_policy%ROWTYPE;
BEGIN
 SELECT * INTO outcome FROM hocalist.sale_confirmations WHERE request_id=p_request;
 IF NOT FOUND THEN RETURN; END IF;
 SELECT * INTO policy FROM hocalist.reward_policy WHERE singleton;
 IF NOT FOUND THEN RETURN; END IF;
 FOR target IN SELECT * FROM hocalist.credit_targets t WHERE t.request_id=p_request
   AND (t.user_id=outcome.seller_user_id OR outcome.confirmed_at>=
     (SELECT effective_at FROM hocalist.reward_aggregation_policy WHERE singleton))
   AND NOT EXISTS(SELECT 1 FROM hocalist.buyer_rewards r WHERE r.target_id=t.id)
   ORDER BY t.user_id,t.id LOOP
   IF hocalist.reward_target_collected(target.id) THEN
     PERFORM hocalist.reward_accrue_internal(outcome.id,target.id,
       hocalist.reward_target_estimate(target.id),policy.rule_version||CASE WHEN target.rate_version LIKE 'late-fee-%' THEN ':late' ELSE '' END);
   END IF;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION hocalist.reward_accrue_internal(uuid,uuid,bigint,text),
 hocalist.reward_accrue_request_internal(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Only reward readers use this condition. Do not replace seller fee state
-- checks: non-winning sellers remain released, never relabelled as winners.
DO $readers$
DECLARE f text; d text;
BEGIN
 FOREACH f IN ARRAY ARRAY['hocalist.reward_wallet()', 'hocalist.withdrawal_available_minor(uuid)',
   'hocalist.withdrawal_status()', 'hocalist.commercial_reward_wallet()',
   'hocalist.reward_identity_free_internal(uuid)', 'hocalist.reward_causal_unspent_internal(uuid)',
   'hocalist.reward_disputed_pool_free_internal(uuid)'] LOOP
   SELECT pg_get_functiondef(to_regprocedure(f)) INTO d;
   IF d IS NULL THEN RAISE EXCEPTION 'Missing reward reader %',f; END IF;
   d:=replace(d,'tg.status=''won''','hocalist.reward_target_collected(tg.id)');
   d:=replace(d,'t.status=''won''','hocalist.reward_target_collected(t.id)');
   d:=replace(d,'t.status<>''won''','NOT hocalist.reward_target_collected(t.id)');
   EXECUTE d;
 END LOOP;
END $readers$;


-- Reviewed reversal allocation keeps existing authorization and receipts.
CREATE OR REPLACE FUNCTION hocalist.reversal_admin_command(p_operation text, p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  result jsonb;
  r hocalist.payment_reversals%ROWTYPE;
  pol hocalist.reversal_policy%ROWTYPE;
  t hocalist.credit_targets%ROWTYPE;
  w hocalist.buyer_rewards%ROWTYPE;
  wd hocalist.withdrawal_requests%ROWTYPE;
  v_available bigint;
  v_hold bigint;
  v_release bigint;
  v_prior bigint;
  v_recoverable bigint;
  v_shortfall bigint;
  v_face bigint;
  v_total_face bigint;
  v_piece bigint;
  v_face_used bigint;
  v_reversed_amount bigint;
  v_row hocalist.ledger_corrections%ROWTYPE;
  v_event text;
  v_n bigint;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_operation IS NULL OR p_operation NOT IN ('policy.set','reversal.hold','reversal.dismiss','reversal.compensate')
     OR p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':reversal_admin:'||p_operation||':'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id=u AND operation='reversal_admin.'||p_operation AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  SELECT * INTO pol FROM hocalist.reversal_policy WHERE singleton;

  IF p_operation='policy.set' THEN
    IF p_input - ARRAY['clawback_mode','reward_hold_enabled','reward_hold_days','expected_revision'] <> '{}'::jsonb THEN
      RAISE EXCEPTION 'invalid_policy' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.reversal_policy SET
      clawback_mode=CASE WHEN p_input ? 'clawback_mode'
        THEN nullif(p_input->>'clawback_mode','') ELSE clawback_mode END,
      reward_hold_enabled=CASE WHEN p_input ? 'reward_hold_enabled'
        THEN (p_input->>'reward_hold_enabled')::boolean ELSE reward_hold_enabled END,
      reward_hold_days=CASE WHEN p_input ? 'reward_hold_days'
        THEN nullif(p_input->>'reward_hold_days','')::integer ELSE reward_hold_days END,
      revision=revision+1, updated_at=now()
    WHERE singleton
      AND (p_input->'expected_revision' IS NULL
        OR revision=(p_input->>'expected_revision')::bigint);
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    result := jsonb_build_object('singleton',true);
  ELSE
    IF (p_input->>'reversal_id') IS NULL THEN
      RAISE EXCEPTION 'invalid_target' USING ERRCODE='22023';
    END IF;
    SELECT * INTO r FROM hocalist.payment_reversals
      WHERE id=(p_input->>'reversal_id')::uuid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'reversal_not_found' USING ERRCODE='P0002'; END IF;
    IF p_input ? 'expected_revision'
       AND r.revision<>(p_input->>'expected_revision')::bigint THEN
      RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
    END IF;

    IF p_operation='reversal.hold' THEN
      IF p_input - ARRAY['reversal_id','expected_revision','note'] <> '{}'::jsonb THEN
        RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
      END IF;
      IF r.state<>'open' THEN RAISE EXCEPTION 'reversal_final' USING ERRCODE='P0001'; END IF;
      v_hold := 0;
      IF r.scope='credit_batch' THEN
        IF pol.clawback_mode IS NULL THEN
          RAISE EXCEPTION 'reversal_policy_unconfigured' USING ERRCODE='P0001';
        END IF;
        SELECT ct.* INTO t FROM hocalist.credit_targets ct
          WHERE ct.request_id=(SELECT s.request_id FROM hocalist.sale_confirmations s WHERE s.id=r.causal_outcome_id)
            AND ct.offer_id=(SELECT s.offer_id FROM hocalist.sale_confirmations s WHERE s.id=r.causal_outcome_id)
            AND ct.status='won'
          ORDER BY ct.created_at DESC, ct.id DESC LIMIT 1;
        IF NOT FOUND THEN RAISE EXCEPTION 'causal_batch_not_found' USING ERRCODE='P0001'; END IF;
        PERFORM 1 FROM hocalist.credit_batches WHERE id=t.batch_id FOR UPDATE;
        SELECT greatest(0, balance_minor-reserved_minor) INTO v_available
          FROM hocalist.credit_batches WHERE id=t.batch_id;
        v_hold := least(r.amount_minor, v_available);
        IF v_hold > 0 THEN
          UPDATE hocalist.credit_batches SET reserved_minor=reserved_minor+v_hold WHERE id=t.batch_id;
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'credit_batch',t.batch_id,'hold',v_hold,v_hold,
            left(p_input->>'note',500),'admin');
        END IF;
      ELSIF r.scope='buyer_reward' THEN
        IF NOT pol.reward_hold_enabled THEN
          RAISE EXCEPTION 'reward_hold_policy_unconfigured' USING ERRCODE='P0001';
        END IF;
        SELECT * INTO w FROM hocalist.buyer_rewards WHERE outcome_id=r.causal_outcome_id ORDER BY created_at,id LIMIT 1;
        IF NOT FOUND THEN RAISE EXCEPTION 'causal_reward_not_found' USING ERRCODE='P0001'; END IF;
        -- Serialize every reward-ledger transition for this buyer with the
        -- withdrawal admission path so a hold and a withdrawal cannot spend
        -- the same funds.
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||w.buyer_user_id::text,902));
        SELECT coalesce(sum(amount_minor),0) INTO v_total_face
          FROM hocalist.buyer_rewards WHERE outcome_id=r.causal_outcome_id;
        -- Bound the hold by the face value not already covered by other
        -- reversal decisions for this reward. Unrecovered shortfalls count
        -- toward the face bound but are never deducted from spendable funds.
        SELECT coalesce(sum(rv2.reversed_face_minor + rv2.hold_minor),0) INTO v_face_used
          FROM hocalist.payment_reversals rv2
          WHERE rv2.scope='buyer_reward' AND rv2.causal_outcome_id=r.causal_outcome_id
            AND rv2.id<>r.id AND rv2.state IN ('held','resolved');
        -- Allocate only within this purchase's contributions. Recompute
        -- conservation after each insertion so no minor unit is held twice.
        v_face := least(r.amount_minor,greatest(0,v_total_face-v_face_used));
        FOR w IN SELECT * FROM hocalist.buyer_rewards
          WHERE outcome_id=r.causal_outcome_id ORDER BY created_at,id LOOP
          EXIT WHEN v_hold>=v_face;
          IF NOT hocalist.reward_target_collected(w.target_id) THEN CONTINUE; END IF;
          v_piece := least(v_face-v_hold,
            hocalist.reward_causal_unspent_internal(w.id),
            hocalist.reward_identity_free_internal(w.buyer_user_id),
            hocalist.reward_disputed_pool_free_internal(w.id));
          IF v_piece>0 THEN
            INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
              amount_minor,reserve_delta_minor,note,actor)
            VALUES(r.id,'buyer_reward',w.id,'reward_hold',v_piece,0,
              left(p_input->>'note',500),'admin');
            v_hold := v_hold+v_piece;
          END IF;
        END LOOP;
      ELSIF r.scope='withdrawal' THEN
        IF pol.clawback_mode IS NULL THEN
          RAISE EXCEPTION 'reversal_policy_unconfigured' USING ERRCODE='P0001';
        END IF;
        SELECT * INTO wd FROM hocalist.withdrawal_requests WHERE id=r.causal_withdrawal_id;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'causal_withdrawal_not_found' USING ERRCODE='P0001'; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||wd.user_id::text,902));
        v_hold := r.amount_minor;
        INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
          amount_minor,reserve_delta_minor,note,actor)
        VALUES(r.id,'withdrawal',r.causal_withdrawal_id,'hold',v_hold,0,
          left(p_input->>'note',500),'admin');
      ELSE
        v_hold := 0;
      END IF;
      UPDATE hocalist.payment_reversals SET state='held', hold_minor=v_hold,
        shortfall_minor=greatest(0,r.amount_minor-v_hold), note=coalesce(left(p_input->>'note',500),note),
        revision=revision+1, updated_at=now() WHERE id=r.id RETURNING * INTO r;
      SELECT coalesce(max(revision),0)+1 INTO v_n FROM hocalist.reversal_events WHERE reversal_id=r.id;
      INSERT INTO hocalist.reversal_events(reversal_id,revision,event,actor,detail)
        VALUES(r.id,v_n,'held','admin',left(coalesce(p_input->>'note',format('hold %s',v_hold)),500));
      result := jsonb_build_object('reversal_id',r.id,'state',r.state,
        'hold_minor',r.hold_minor,'shortfall_minor',r.shortfall_minor);
    ELSIF p_operation='reversal.dismiss' THEN
      IF p_input - ARRAY['reversal_id','expected_revision','note'] <> '{}'::jsonb THEN
        RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
      END IF;
      IF r.state NOT IN ('open','held') THEN RAISE EXCEPTION 'reversal_final' USING ERRCODE='P0001'; END IF;
      -- Serialize with the buyer's reward-ledger admission path before any
      -- reservation is released.
      PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||x.user_id::text,902))
        FROM (
          SELECT rw.buyer_user_id AS user_id FROM hocalist.ledger_corrections c
            JOIN hocalist.buyer_rewards rw ON rw.id=c.target_id
            WHERE c.reversal_id=r.id AND c.target_kind='buyer_reward'
          UNION
          SELECT wx.user_id FROM hocalist.ledger_corrections c
            JOIN hocalist.withdrawal_requests wx ON wx.id=c.target_id
            WHERE c.reversal_id=r.id AND c.target_kind='withdrawal'
        ) x ORDER BY x.user_id;
      v_release := 0;
      FOR v_row IN SELECT * FROM hocalist.ledger_corrections
          WHERE reversal_id=r.id AND entry_kind='hold' LOOP
        UPDATE hocalist.credit_batches SET reserved_minor=greatest(0,reserved_minor-v_row.reserve_delta_minor)
          WHERE id=v_row.target_id;
        v_release := v_release + v_row.amount_minor;
      END LOOP;
      INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
        amount_minor,reserve_delta_minor,note,actor)
      SELECT r.id, c.target_kind, c.target_id,
        CASE WHEN c.target_kind='buyer_reward' THEN 'reward_release' ELSE 'release_hold' END,
        -c.amount_minor, -c.reserve_delta_minor, 'dismissed', 'admin'
      FROM hocalist.ledger_corrections c
      WHERE c.reversal_id=r.id AND c.entry_kind IN ('hold','reward_hold');
      UPDATE hocalist.payment_reversals SET state='dismissed', hold_minor=0,
        revision=revision+1, updated_at=now()
        WHERE id=r.id RETURNING * INTO r;
      SELECT coalesce(max(revision),0)+1 INTO v_n FROM hocalist.reversal_events WHERE reversal_id=r.id;
      INSERT INTO hocalist.reversal_events(reversal_id,revision,event,actor,detail)
        VALUES(r.id,v_n,'dismissed','admin',left(p_input->>'note',500));
      result := jsonb_build_object('reversal_id',r.id,'state',r.state,'released_minor',v_release);
    ELSE
      -- Compensation is only allowed after an explicit hold decision and only
      -- against the causally-linked ledger row.
      IF p_input - ARRAY['reversal_id','expected_revision','note'] <> '{}'::jsonb THEN
        RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
      END IF;
      IF r.state<>'held' THEN RAISE EXCEPTION 'hold_required_before_compensation' USING ERRCODE='P0001'; END IF;
      IF pol.clawback_mode IS NULL OR pol.clawback_mode<>'same_batch_only' THEN
        RAISE EXCEPTION 'reversal_policy_unconfigured' USING ERRCODE='P0001';
      END IF;
      v_recoverable := 0;
      IF r.scope='credit_batch' THEN
        SELECT ct.* INTO t FROM hocalist.credit_targets ct
          WHERE ct.request_id=(SELECT s.request_id FROM hocalist.sale_confirmations s WHERE s.id=r.causal_outcome_id)
            AND ct.offer_id=(SELECT s.offer_id FROM hocalist.sale_confirmations s WHERE s.id=r.causal_outcome_id)
            AND ct.status='won'
          ORDER BY ct.created_at DESC, ct.id DESC LIMIT 1;
        IF NOT FOUND THEN RAISE EXCEPTION 'causal_batch_not_found' USING ERRCODE='P0001'; END IF;
        PERFORM 1 FROM hocalist.credit_batches WHERE id=t.batch_id FOR UPDATE;
        -- Release this review's hold first so the batch invariant
        -- (balance >= reserved) holds through the compensating debit.
        SELECT coalesce(sum(reserve_delta_minor),0) INTO v_release
          FROM hocalist.ledger_corrections
          WHERE reversal_id=r.id AND entry_kind='hold';
        FOR v_row IN SELECT * FROM hocalist.ledger_corrections
            WHERE reversal_id=r.id AND entry_kind='hold' LOOP
          UPDATE hocalist.credit_batches SET reserved_minor=greatest(0,reserved_minor-v_row.reserve_delta_minor)
            WHERE id=v_row.target_id;
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'credit_batch',v_row.target_id,'release_hold',-v_row.amount_minor,
            -v_row.reserve_delta_minor,'compensation settled','admin')
          ON CONFLICT (reversal_id,entry_kind,target_id) DO NOTHING;
        END LOOP;
        SELECT greatest(0, balance_minor-reserved_minor) INTO v_available
          FROM hocalist.credit_batches WHERE id=t.batch_id;
        v_hold := least(r.amount_minor, v_available);
        IF v_hold > 0 THEN
          UPDATE hocalist.credit_batches SET balance_minor=balance_minor-v_hold WHERE id=t.batch_id;
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'credit_batch',t.batch_id,'compensate',-v_hold,0,
            left(p_input->>'note',500),'admin');
        END IF;
      ELSIF r.scope='buyer_reward' THEN
        SELECT * INTO w FROM hocalist.buyer_rewards WHERE outcome_id=r.causal_outcome_id ORDER BY created_at,id LIMIT 1;
        IF NOT FOUND THEN RAISE EXCEPTION 'causal_reward_not_found' USING ERRCODE='P0001'; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||w.buyer_user_id::text,902));
        SELECT coalesce(sum(amount_minor),0) INTO v_total_face
          FROM hocalist.buyer_rewards WHERE outcome_id=r.causal_outcome_id;
        -- Face value already applied or reserved by other reversals of this
        -- reward. An unrecovered shortfall counts toward the face bound but is
        -- never deducted from spendable funds.
        SELECT coalesce(sum(rv2.reversed_face_minor + rv2.hold_minor),0) INTO v_face_used
          FROM hocalist.payment_reversals rv2
          WHERE rv2.scope='buyer_reward' AND rv2.causal_outcome_id=r.causal_outcome_id
            AND rv2.id<>r.id AND rv2.state IN ('held','resolved');
        v_face := least(r.amount_minor, greatest(0, v_total_face - v_face_used));
        -- The temporary hold is the causal, conservatively proved recoverable
        -- amount. Compensation settles exactly that reservation and never
        -- recomputes an account-wide balance, so an unrelated reward arriving
        -- after the hold cannot be debited. Anything above it stays an
        -- explicit unrecovered shortfall for manual policy.
        SELECT coalesce(sum(cor.amount_minor),0) INTO v_reversed_amount
          FROM hocalist.ledger_corrections cor
         WHERE cor.reversal_id=r.id AND cor.entry_kind='reward_hold';
        v_reversed_amount := least(v_face, v_reversed_amount);
        -- Settle the exact held contributions, never an arbitrary first row.
        v_hold := 0;
        FOR v_row IN SELECT * FROM hocalist.ledger_corrections
            WHERE reversal_id=r.id AND entry_kind='reward_hold' ORDER BY created_at,id LOOP
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'buyer_reward',v_row.target_id,'reward_release',
            -v_row.amount_minor,0,'compensation settled','admin')
          ON CONFLICT (reversal_id,entry_kind,target_id) DO NOTHING;
          v_piece := least(v_row.amount_minor,greatest(0,v_reversed_amount-v_hold));
          IF v_piece>0 THEN
            INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
              amount_minor,reserve_delta_minor,note,actor)
            VALUES(r.id,'buyer_reward',v_row.target_id,'reward_reversed',v_piece,0,
              left(p_input->>'note',500),'admin')
            ON CONFLICT (reversal_id,entry_kind,target_id) DO NOTHING;
            v_hold := v_hold+v_piece;
          END IF;
        END LOOP;
        v_hold := v_reversed_amount;
      ELSE
        -- Withdrawal/subscription corrections stay review records; no reward
        -- or credit balance is silently debited from them. Any logical hold is
        -- released because the review closed.
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||x.user_id::text,902))
          FROM (
            SELECT wx.user_id FROM hocalist.ledger_corrections c
              JOIN hocalist.withdrawal_requests wx ON wx.id=c.target_id
              WHERE c.reversal_id=r.id AND c.target_kind='withdrawal'
          ) x ORDER BY x.user_id;
        v_hold := 0;
        FOR v_row IN SELECT * FROM hocalist.ledger_corrections
            WHERE reversal_id=r.id AND entry_kind='hold' LOOP
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,v_row.target_kind,v_row.target_id,'release_hold',
            -v_row.amount_minor,-v_row.reserve_delta_minor,'review closed','admin')
          ON CONFLICT (reversal_id,entry_kind,target_id) DO NOTHING;
        END LOOP;
      END IF;
      UPDATE hocalist.payment_reversals SET state='resolved', hold_minor=0,
        reversed_face_minor=CASE WHEN r.scope='buyer_reward'
          THEN greatest(0, coalesce(v_face,0)) ELSE 0 END,
        shortfall_minor=CASE WHEN r.scope='buyer_reward'
          THEN greatest(0, coalesce(v_face,0) - coalesce(v_reversed_amount,0))
          ELSE greatest(0, r.amount_minor - coalesce(v_hold,0)) END,
        revision=revision+1, updated_at=now() WHERE id=r.id RETURNING * INTO r;
      SELECT coalesce(max(revision),0)+1 INTO v_n FROM hocalist.reversal_events WHERE reversal_id=r.id;
      INSERT INTO hocalist.reversal_events(reversal_id,revision,event,actor,detail)
        VALUES(r.id,v_n,'resolved','admin',left(coalesce(p_input->>'note',format('compensated %s',v_hold)),500));
      result := jsonb_build_object('reversal_id',r.id,'state',r.state,
        'compensated_minor',greatest(0,coalesce(v_hold,0)),
        'reversed_face_minor',coalesce(r.reversed_face_minor,0),
        'shortfall_minor',r.shortfall_minor);
    END IF;
  END IF;

  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'reversal_admin.'||p_operation,p_key,h,result);
  RETURN result;
END $$;


-- Estimates never enter the withdrawal ledger.
CREATE OR REPLACE FUNCTION hocalist.reward_sale_summary_internal(p_outcome uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 WITH contributions AS (
   SELECT r.*,hocalist.reward_target_collected(r.target_id) AS collected,
     coalesce((SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
       WHERE c.target_kind='buyer_reward' AND c.target_id=r.id
         AND c.entry_kind IN ('reward_hold','reward_release')),0) AS held,
     coalesce((SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
       WHERE c.target_kind='buyer_reward' AND c.target_id=r.id
         AND c.entry_kind='reward_reversed'),0) AS reversed
   FROM hocalist.buyer_rewards r WHERE r.outcome_id=p_outcome
 ), totals AS (
   SELECT count(*) AS n,coalesce(sum(amount_minor),0) AS amount,
     coalesce(sum(CASE WHEN collected THEN greatest(0,amount_minor-held-reversed) ELSE 0 END),0) AS earned,
     coalesce(sum(CASE WHEN collected THEN greatest(0,held) ELSE greatest(0,amount_minor-reversed) END),0) AS held,
     coalesce(sum(reversed),0) AS reversed,
     CASE WHEN count(DISTINCT rule_version)=1 THEN min(rule_version) ELSE NULL END AS rule
   FROM contributions
 ) SELECT jsonb_build_object('amount_minor',amount,'earned_minor',earned,'held_minor',held,
   'reversed_minor',reversed,'contribution_count',n,'rule_version',rule,
   'status',CASE WHEN n=0 THEN 'none' WHEN earned>0 AND held>0 THEN 'mixed'
     WHEN held>0 THEN 'held' WHEN earned=0 AND reversed>0 THEN 'reversed' ELSE 'earned' END)
 FROM totals;
$$;
REVOKE ALL ON FUNCTION hocalist.reward_sale_summary_internal(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $wallet$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('hocalist.commercial_reward_wallet()'::regprocedure) INTO d;
 IF strpos(d,'''estimated_minor''')=0 THEN
   IF strpos(d,'''pending_minor'',v_pending,')=0 THEN RAISE EXCEPTION 'Reward wallet definition drift'; END IF;
   d:=replace(d,'''pending_minor'',v_pending,',
     '''pending_minor'',v_pending,''estimated_minor'',hocalist.reward_pending_estimate_minor(u),');
 END IF;
 -- An outcome may now have several rewards. A reversal shortfall is still
 -- counted once, both in totals and in the deterministic first contribution.
 d:=replace(d,'JOIN hocalist.buyer_rewards w ON w.outcome_id=rv.causal_outcome_id',
   'JOIN (SELECT DISTINCT outcome_id,buyer_user_id FROM hocalist.buyer_rewards) w ON w.outcome_id=rv.causal_outcome_id');
 d:=replace(d,'AND rv.causal_outcome_id=r.outcome_id),0))',
   'AND rv.causal_outcome_id=r.outcome_id AND r.id=(SELECT rw.id FROM hocalist.buyer_rewards rw WHERE rw.outcome_id=r.outcome_id ORDER BY rw.created_at,rw.id LIMIT 1)),0))');
 EXECUTE d;
END $wallet$;


-- Settlement and delayed collection integration.
CREATE OR REPLACE FUNCTION hocalist.reward_accrue_target_internal(p_target uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t hocalist.credit_targets%ROWTYPE; s hocalist.sale_confirmations%ROWTYPE;
 p hocalist.reward_policy%ROWTYPE;
BEGIN
 SELECT * INTO t FROM hocalist.credit_targets WHERE id=p_target;
 IF NOT FOUND THEN RETURN; END IF;
 SELECT * INTO s FROM hocalist.sale_confirmations WHERE request_id=t.request_id;
 IF NOT FOUND THEN RETURN; END IF;
 IF t.user_id<>s.seller_user_id AND s.confirmed_at<
   (SELECT effective_at FROM hocalist.reward_aggregation_policy WHERE singleton) THEN RETURN; END IF;
 SELECT * INTO p FROM hocalist.reward_policy WHERE singleton;
 IF NOT FOUND THEN RETURN; END IF;
 IF hocalist.reward_target_collected(t.id) AND NOT EXISTS(
   SELECT 1 FROM hocalist.buyer_rewards WHERE target_id=t.id) THEN
   PERFORM hocalist.reward_accrue_internal(s.id,t.id,hocalist.reward_target_estimate(t.id),
     p.rule_version||CASE WHEN t.rate_version LIKE 'late-fee-%' THEN ':late' ELSE '' END);
 END IF;
END $$;
REVOKE ALL ON FUNCTION hocalist.reward_accrue_target_internal(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $settlement$
DECLARE d text; a integer; b integer;
BEGIN
 SELECT pg_get_functiondef('hocalist.credit_settle_purchase(uuid)'::regprocedure) INTO d;
 IF strpos(d,'PERFORM hocalist.reward_accrue_request_internal(p_request);')=0 THEN
   a:=strpos(d,'  IF v_won AND to_regprocedure(');
   b:=strpos(d,'  RETURN jsonb_build_object(''winning_target''');
   IF a=0 OR b<=a THEN RAISE EXCEPTION 'Purchase settlement definition drift'; END IF;
   d:=substring(d,1,a-1)||'  PERFORM hocalist.reward_accrue_request_internal(p_request);'||chr(10)||substring(d,b);
   EXECUTE d;
 END IF;
 -- A non-winning initial payment may finish after purchase confirmation.
 -- Accrue only that confirmed contribution; do not settle or charge siblings.
 SELECT pg_get_functiondef('hocalist.paygo_charge_finish(uuid,text,text,bigint,text)'::regprocedure) INTO d;
 IF strpos(d,'PERFORM hocalist.reward_accrue_target_internal(t.id);')=0 THEN
   IF strpos(d,' IF p_state=''canceled'' THEN')=0 THEN RAISE EXCEPTION 'Provider completion definition drift'; END IF;
   d:=replace(d,' IF p_state=''canceled'' THEN',
     ' IF p_state=''succeeded'' THEN PERFORM hocalist.reward_accrue_target_internal(t.id); END IF; IF p_state=''canceled'' THEN');
   EXECUTE d;
 END IF;
END $settlement$;


-- Aggregate per purchase; seller fee remains winner-specific.
CREATE OR REPLACE FUNCTION hocalist.commercial_sale_history(
  p_before_time timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid := auth.uid(); items jsonb;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501'; END IF;
  IF (p_before_time IS NULL)<>(p_before_id IS NULL) THEN
    RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023';
  END IF;
  SELECT coalesce(jsonb_agg(x.data ORDER BY x.confirmed_at DESC,x.id DESC),'[]'::jsonb)
    INTO items FROM (
    SELECT s.id,s.confirmed_at,jsonb_build_object(
      'id',s.id,'side',CASE WHEN s.buyer_user_id=u THEN 'purchase' ELSE 'sale' END,
      'confirmed_at',s.confirmed_at,'title',q.title,
      'price_minor',r.price_minor,'currency',r.currency_code,
      'reward',CASE WHEN s.buyer_user_id=u THEN hocalist.reward_sale_summary_internal(s.id) END,
      'fee',CASE WHEN s.seller_user_id=u THEN jsonb_build_object(
        'status',coalesce(t.status,'none'),
        'charged_minor',coalesce(t.charged_minor,0),
        'winning_minor',coalesce(t.winning_minor,0),
        'rate_version',t.rate_version) END) AS data
    FROM hocalist.sale_confirmations s
    JOIN hocalist.requests q ON q.id=s.request_id
    JOIN hocalist.offers o ON o.id=s.offer_id
    JOIN hocalist.offer_revisions r ON r.id=o.accepted_revision_id
    LEFT JOIN LATERAL (SELECT ct.* FROM hocalist.credit_targets ct
      WHERE ct.offer_id=s.offer_id AND ct.user_id=s.seller_user_id
      ORDER BY (ct.status='won') DESC,ct.created_at DESC,ct.id DESC LIMIT 1) t ON true
    WHERE (s.buyer_user_id=u OR s.seller_user_id=u)
      AND (p_before_time IS NULL OR (s.confirmed_at,s.id)<(p_before_time,p_before_id))
    ORDER BY s.confirmed_at DESC,s.id DESC LIMIT 25) x;
  RETURN jsonb_build_object('items',items);
END $$;

CREATE OR REPLACE FUNCTION hocalist.commercial_sale_detail(p_outcome uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  s hocalist.sale_confirmations%ROWTYPE;
  q hocalist.requests%ROWTYPE;
  r hocalist.offer_revisions%ROWTYPE;
  m hocalist.meetings%ROWTYPE;
  ms hocalist.meeting_schedule_revisions%ROWTYPE;
  rw hocalist.buyer_rewards%ROWTYPE;
  t hocalist.credit_targets%ROWTYPE;
  v_reward jsonb;
  v_fee jsonb;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501'; END IF;
  IF p_outcome IS NULL THEN RAISE EXCEPTION 'invalid_outcome' USING ERRCODE='22023'; END IF;
  SELECT * INTO s FROM hocalist.sale_confirmations WHERE id=p_outcome;
  IF NOT FOUND OR (s.buyer_user_id<>u AND s.seller_user_id<>u) THEN
    RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO q FROM hocalist.requests WHERE id=s.request_id;
  SELECT * INTO m FROM hocalist.meetings WHERE id=s.meeting_id;
  SELECT * INTO ms FROM hocalist.meeting_schedule_revisions WHERE id=s.schedule_revision_id;
  SELECT x.* INTO r FROM hocalist.offer_revisions x
    JOIN hocalist.offers o ON o.id=x.offer_id
    WHERE o.id=s.offer_id AND o.accepted_revision_id=x.id;
  SELECT * INTO t FROM hocalist.credit_targets
      WHERE offer_id=s.offer_id AND user_id=s.seller_user_id
      ORDER BY (status='won') DESC,created_at DESC,id DESC LIMIT 1;
  v_fee := jsonb_build_object(
      'status',coalesce(t.status,'none'),
      'charged_minor',coalesce(t.charged_minor,0),
      'winning_minor',coalesce(t.winning_minor,0),
      'initial_minor',coalesce(t.initial_minor,0),
      'rate_version',t.rate_version);
  IF s.buyer_user_id=u THEN
    v_reward := hocalist.reward_sale_summary_internal(s.id);
  ELSE
    -- Preserve the seller's existing own-contribution detail. Never expose
    -- the amounts contributed by other sellers through this expansion.
    SELECT jsonb_build_object('amount_minor',w.amount_minor,'rule_version',w.rule_version,
      'status',CASE WHEN hocalist.reward_target_collected(w.target_id) THEN 'earned' ELSE 'held' END)
      INTO v_reward FROM hocalist.buyer_rewards w WHERE w.outcome_id=s.id AND w.target_id=t.id;
  END IF;
  RETURN jsonb_build_object(
    'id',s.id,
    'side',CASE WHEN s.buyer_user_id=u THEN 'purchase' ELSE 'sale' END,
    'confirmed_at',s.confirmed_at,
    'request_id',s.request_id,'offer_id',s.offer_id,'meeting_id',s.meeting_id,
    'title',q.title,'description',q.description,
    'price_minor',r.price_minor,'currency',r.currency_code,
    'schedule',jsonb_build_object(
      'date',ms.schedule_date,'time',ms.schedule_time,'timezone',ms.schedule_timezone,
      'place_choice',ms.place_choice,'place_label',ms.place_label,
      'meeting_expires_at',m.meeting_expires_at),
    'reward',v_reward,
    'fee',v_fee,
    'item_payment','offline');
END $$;

NOTIFY pgrst,'reload schema';
COMMIT;

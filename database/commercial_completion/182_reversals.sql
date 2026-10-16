-- Append-only reversal and dispute correction contracts over the reviewed
-- credit/reward/withdrawal ledgers.
--
-- Boundary held by this migration:
--   * no provider call, no automatic clawback, no physical item refund;
--   * a reversal is opened only by a verified service record, then every
--     fund-moving step is an explicit admin-reviewed decision with an
--     audit event and an idempotency key;
--   * compensation can only debit the causally-linked seller ledger row, never
--     another batch, another seller, or the buyer's unrelated balance;
--   * buyer rewards tied to a reversed sale become held (not withdrawable)
--     only when the reward-hold policy is explicitly configured;
--   * holds and releases are append-only compensating entries; ledger history
--     is never rewritten;
--   * the buyer reward, seller credit and withdrawal ledgers stay separate.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.credit_batches') IS NULL
     OR to_regclass('hocalist.buyer_rewards') IS NULL THEN
    RAISE EXCEPTION 'commercial 090/091 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.withdrawal_requests') IS NULL THEN
    RAISE EXCEPTION 'withdrawals 093 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.payment_reversals') IS NOT NULL THEN
    RAISE EXCEPTION 'reversal contracts already installed';
  END IF;
END $guard$;

-- ---------------------------------------------------------------------------
-- Policy and append-only records
-- ---------------------------------------------------------------------------

-- Both policy settings stay unconfigured/false: the owner has not approved a
-- chargeback clawback rule or a reward-hold effect, so nothing activates until
-- an admin explicitly configures it.
CREATE TABLE hocalist.reversal_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  clawback_mode text CHECK (clawback_mode IS NULL OR clawback_mode IN ('same_batch_only')),
  reward_hold_enabled boolean NOT NULL DEFAULT false,
  reward_hold_days integer CHECK (reward_hold_days IS NULL OR reward_hold_days BETWEEN 1 AND 365),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.reversal_policy(singleton) VALUES (true);

CREATE TABLE hocalist.payment_reversals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_key text NOT NULL CHECK (length(btrim(provider_key)) BETWEEN 1 AND 60),
  provider_reference text NOT NULL CHECK (length(btrim(provider_reference)) BETWEEN 1 AND 200),
  kind text NOT NULL CHECK (kind IN ('chargeback','refund','dispute','correction')),
  scope text NOT NULL CHECK (scope IN ('credit_batch','buyer_reward','withdrawal','subscription')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  currency text NOT NULL DEFAULT 'USD' CHECK (currency ~ '^[A-Z]{3}$'),
  causal_outcome_id uuid REFERENCES hocalist.sale_confirmations(id),
  causal_withdrawal_id uuid REFERENCES hocalist.withdrawal_requests(id),
  causal_user_id uuid REFERENCES hocalist.profiles(id),
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open','held','dismissed','resolved')),
  hold_minor bigint NOT NULL DEFAULT 0 CHECK (hold_minor >= 0),
  -- Face value of the causal reward covered by this decision. It is recorded
  -- for audit even when nothing was recoverable, so an unrecovered shortfall
  -- is never mistaken for an active hold or an implicit debt.
  reversed_face_minor bigint NOT NULL DEFAULT 0 CHECK (reversed_face_minor >= 0),
  shortfall_minor bigint NOT NULL DEFAULT 0 CHECK (shortfall_minor >= 0),
  note text CHECK (note IS NULL OR length(note) <= 500),
  created_by uuid REFERENCES hocalist.profiles(id),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider_key, provider_reference)
);
CREATE INDEX payment_reversals_open
  ON hocalist.payment_reversals(id) WHERE state IN ('open','held');

CREATE TABLE hocalist.ledger_corrections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reversal_id uuid NOT NULL REFERENCES hocalist.payment_reversals(id),
  target_kind text NOT NULL CHECK (target_kind IN ('credit_batch','buyer_reward','withdrawal')),
  target_id uuid NOT NULL,
  entry_kind text NOT NULL CHECK (entry_kind IN
    ('hold','release_hold','compensate','reward_hold','reward_release','reward_reversed')),
  amount_minor bigint NOT NULL CHECK (amount_minor <> 0),
  reserve_delta_minor bigint NOT NULL DEFAULT 0,
  note text CHECK (note IS NULL OR length(note) <= 500),
  actor text NOT NULL CHECK (length(btrim(actor)) BETWEEN 1 AND 60),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (reversal_id, entry_kind, target_id)
);

CREATE TABLE hocalist.reversal_events (
  reversal_id uuid NOT NULL REFERENCES hocalist.payment_reversals(id),
  revision bigint NOT NULL CHECK (revision > 0),
  event text NOT NULL CHECK (length(btrim(event)) BETWEEN 1 AND 60),
  actor text NOT NULL CHECK (length(btrim(actor)) BETWEEN 1 AND 60),
  detail text CHECK (detail IS NULL OR length(detail) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (reversal_id, revision)
);

ALTER TABLE hocalist.reversal_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.payment_reversals ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.ledger_corrections ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.reversal_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.reversal_policy, hocalist.payment_reversals,
  hocalist.ledger_corrections, hocalist.reversal_events
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Verified-source intake (service path only; moves no funds)
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.reversal_open_internal(
  p_provider text, p_reference text, p_kind text, p_scope text, p_amount bigint,
  p_user uuid DEFAULT NULL, p_outcome uuid DEFAULT NULL,
  p_withdrawal uuid DEFAULT NULL, p_note text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r hocalist.payment_reversals%ROWTYPE; n bigint;
BEGIN
  IF p_provider IS NULL OR length(btrim(p_provider)) NOT BETWEEN 1 AND 60
     OR p_reference IS NULL OR length(btrim(p_reference)) NOT BETWEEN 1 AND 200
     OR p_kind IS NULL OR p_kind NOT IN ('chargeback','refund','dispute','correction')
     OR p_scope IS NULL OR p_scope NOT IN ('credit_batch','buyer_reward','withdrawal','subscription')
     OR p_amount IS NULL OR p_amount <= 0
     OR (p_note IS NOT NULL AND length(p_note) > 500) THEN
    RAISE EXCEPTION 'invalid_reversal' USING ERRCODE='22023';
  END IF;
  -- Causal linkage is required: a reversal must name the affected sale,
  -- withdrawal or account, and the withdrawal scope requires its own row.
  IF p_scope='withdrawal' AND p_withdrawal IS NULL THEN
    RAISE EXCEPTION 'causal_withdrawal_required' USING ERRCODE='22023';
  END IF;
  IF p_scope IN ('credit_batch','buyer_reward') AND p_outcome IS NULL THEN
    RAISE EXCEPTION 'causal_outcome_required' USING ERRCODE='22023';
  END IF;
  IF p_scope='subscription' AND p_user IS NULL THEN
    RAISE EXCEPTION 'causal_user_required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_provider||':'||p_reference,901));
  SELECT * INTO r FROM hocalist.payment_reversals
    WHERE provider_key=p_provider AND provider_reference=p_reference;
  IF FOUND THEN
    IF r.kind<>p_kind OR r.scope<>p_scope OR r.amount_minor<>p_amount
       OR r.causal_outcome_id IS DISTINCT FROM p_outcome
       OR r.causal_withdrawal_id IS DISTINCT FROM p_withdrawal THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
    END IF;
    RETURN jsonb_build_object('status',r.state,'reversal_id',r.id,'replayed',true);
  END IF;
  INSERT INTO hocalist.payment_reversals(
    provider_key,provider_reference,kind,scope,amount_minor,causal_outcome_id,
    causal_withdrawal_id,causal_user_id,note)
  VALUES(btrim(p_provider),btrim(p_reference),p_kind,p_scope,p_amount,p_outcome,
    p_withdrawal,p_user,left(p_note,500))
  RETURNING * INTO r;
  INSERT INTO hocalist.reversal_events(reversal_id,revision,event,actor,detail)
    VALUES(r.id,1,'opened','provider',left(coalesce(p_note,'verified provider reversal'),500));
  RETURN jsonb_build_object('status',r.state,'reversal_id',r.id,'replayed',false);
END $$;

-- ---------------------------------------------------------------------------
-- Causal recoverability of one reward
-- ---------------------------------------------------------------------------

-- Conservative, history-based proof of how much of ONE causal reward has not
-- been spent. Account-wide availability is not evidence that this reward is
-- unspent, and a later unrelated reward must never make an older loss
-- recoverable. Withdrawals are assumed to consume every non-causal reward that
-- already existed at the withdrawal's time before they can charge the causal
-- reward; the largest cumulative deficit at any withdrawal is therefore the
-- part of this reward that must have been spent. This is a provability rule
-- for one reward, not a cross-reward allocation or clawback policy: it never
-- charges another reward. It is always combined with the identity-wide
-- conservation ceiling below.
CREATE FUNCTION hocalist.reward_causal_unspent_internal(p_reward uuid)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  w hocalist.buyer_rewards%ROWTYPE;
  v_consumed bigint;
  v_corrections bigint;
BEGIN
  SELECT * INTO STRICT w FROM hocalist.buyer_rewards WHERE id=p_reward;
  SELECT least(w.amount_minor, coalesce(max(d.gap),0)) INTO v_consumed
  FROM (
    SELECT
      (sum(wo.amount_minor) OVER (ORDER BY wo.created_at, wo.id)) -
      (SELECT coalesce(sum(o.amount_minor),0)
         FROM hocalist.buyer_rewards o
         JOIN hocalist.credit_targets tg ON tg.id=o.target_id
        WHERE o.buyer_user_id=w.buyer_user_id AND o.id<>w.id AND tg.status='won'
          AND o.created_at <= wo.created_at) AS gap
    FROM hocalist.withdrawal_requests wo
    WHERE wo.user_id=w.buyer_user_id AND wo.status IN ('processing','paid')
  ) d;
  -- Any prior hold or permanent reversal of this reward already covers part
  -- of the face value.
  SELECT coalesce(sum(c.amount_minor),0) INTO v_corrections
    FROM hocalist.ledger_corrections c
   WHERE c.target_kind='buyer_reward' AND c.target_id=w.id
     AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed');
  RETURN greatest(0, w.amount_minor - coalesce(v_consumed,0) - v_corrections);
END $$;

-- Identity-wide conservation ceiling: every debit of the reward ledger
-- (processing/paid withdrawals plus every reward hold/reversal and withdrawal
-- hold) can never exceed the funds actually earned. A per-reward estimate is
-- only an upper bound on that reward's remainder; the same unspent minor unit
-- must not be recoverable twice through separate causal records, so a hold is
-- additionally capped by this pool.
CREATE FUNCTION hocalist.reward_identity_free_internal(p_user uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT greatest(0,
    coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r
      JOIN hocalist.credit_targets t ON t.id=r.target_id
      WHERE r.buyer_user_id=p_user AND t.status='won'),0)
    - coalesce((SELECT sum(w.amount_minor) FROM hocalist.withdrawal_requests w
      WHERE w.user_id=p_user AND w.status IN ('processing','paid')),0)
    - coalesce((SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
      JOIN hocalist.buyer_rewards w ON w.id=c.target_id
      WHERE c.target_kind='buyer_reward' AND w.buyer_user_id=p_user
        AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed')),0)
    - coalesce((SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
      JOIN hocalist.withdrawal_requests wd ON wd.id=c.target_id
      WHERE c.target_kind='withdrawal' AND wd.user_id=p_user
        AND c.entry_kind IN ('hold','release_hold')),0));
$$;

-- Stable disputed-pool guard. A reward can only ever have been consumed by a
-- withdrawal created at or after that reward, so the pool's membership boundary
-- is the EARLIEST such withdrawal. That boundary is derived from immutable
-- timestamps, so later clean rewards are never pulled into an old pool. Every
-- withdrawal the identity has ever had (processing or paid) is charged against
-- the pool: records cannot prove which reward funded a withdrawal, so a split
-- withdrawal sequence must reduce the pool exactly as one combined withdrawal
-- would. The remaining pool is its rewards minus all withdrawals and the
-- corrections already taken from those rewards. When no withdrawal has touched
-- the reward's era, nothing has consumed it and only its own corrections apply.
-- This remains a conservative provability bound, not a FIFO/allocation policy:
-- when the pool is exhausted (including when records cannot attribute a
-- withdrawal to another reward) the remainder is left as shortfall/manual
-- review rather than inferred.
CREATE FUNCTION hocalist.reward_disputed_pool_free_internal(p_reward uuid)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  w hocalist.buyer_rewards%ROWTYPE;
  v_boundary timestamptz;
  v_pool bigint;
  v_outflow bigint;
  v_corrections bigint;
BEGIN
  SELECT * INTO STRICT w FROM hocalist.buyer_rewards WHERE id=p_reward;
  SELECT min(wo.created_at) INTO v_boundary
    FROM hocalist.withdrawal_requests wo
   WHERE wo.user_id=w.buyer_user_id AND wo.status IN ('processing','paid')
     AND wo.created_at >= w.created_at;
  IF v_boundary IS NULL THEN
    -- No withdrawal since this reward was created: it is clean.
    SELECT coalesce(sum(c.amount_minor),0) INTO v_corrections
      FROM hocalist.ledger_corrections c
     WHERE c.target_kind='buyer_reward' AND c.target_id=w.id
       AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed');
    RETURN greatest(0, w.amount_minor - v_corrections);
  END IF;
  SELECT coalesce(sum(r.amount_minor),0) INTO v_pool
    FROM hocalist.buyer_rewards r
    JOIN hocalist.credit_targets t ON t.id=r.target_id
   WHERE r.buyer_user_id=w.buyer_user_id AND t.status='won'
     AND r.created_at <= v_boundary;
  -- Every withdrawal is charged, split or combined.
  SELECT coalesce(sum(wo.amount_minor),0) INTO v_outflow
    FROM hocalist.withdrawal_requests wo
   WHERE wo.user_id=w.buyer_user_id AND wo.status IN ('processing','paid');
  SELECT coalesce(sum(c.amount_minor),0) INTO v_corrections
    FROM hocalist.ledger_corrections c
    JOIN hocalist.buyer_rewards r ON r.id=c.target_id
   WHERE c.target_kind='buyer_reward' AND r.buyer_user_id=w.buyer_user_id
     AND r.created_at <= v_boundary
     AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed');
  RETURN greatest(0, v_pool - v_outflow - v_corrections);
END $$;

-- ---------------------------------------------------------------------------
-- Admin-reviewed decisions
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.reversal_admin_command(p_operation text, p_key text, p_input jsonb)
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
        SELECT * INTO w FROM hocalist.buyer_rewards WHERE outcome_id=r.causal_outcome_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'causal_reward_not_found' USING ERRCODE='P0001'; END IF;
        -- Serialize every reward-ledger transition for this buyer with the
        -- withdrawal admission path so a hold and a withdrawal cannot spend
        -- the same funds.
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||w.buyer_user_id::text,902));
        -- Bound the hold by the face value not already covered by other
        -- reversal decisions for this reward. Unrecovered shortfalls count
        -- toward the face bound but are never deducted from spendable funds.
        SELECT coalesce(sum(rv2.reversed_face_minor + rv2.hold_minor),0) INTO v_face_used
          FROM hocalist.payment_reversals rv2
          WHERE rv2.scope='buyer_reward' AND rv2.causal_outcome_id=r.causal_outcome_id
            AND rv2.id<>r.id AND rv2.state IN ('held','resolved');
        -- Recoverability is causal: only funds this reward provably still
        -- holds may be reserved. An unrelated reward arriving before, between
        -- or after the decisions can never make an old loss recoverable.
        v_recoverable := hocalist.reward_causal_unspent_internal(w.id);
        -- Conservation: the identity's whole unspent pool and the time-aware
        -- disputed pool also cap the hold, so two causal records can never
        -- recover the same minor unit twice and a post-withdrawal reward is
        -- never consumed by an older loss.
        v_hold := least(
          r.amount_minor,
          greatest(0, w.amount_minor - v_face_used),
          v_recoverable,
          hocalist.reward_identity_free_internal(w.buyer_user_id),
          hocalist.reward_disputed_pool_free_internal(w.id));
        IF v_hold > 0 THEN
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'buyer_reward',w.id,'reward_hold',v_hold,0,
            left(p_input->>'note',500),'admin');
        END IF;
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
        SELECT * INTO w FROM hocalist.buyer_rewards WHERE outcome_id=r.causal_outcome_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'causal_reward_not_found' USING ERRCODE='P0001'; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||w.buyer_user_id::text,902));
        -- Face value already applied or reserved by other reversals of this
        -- reward. An unrecovered shortfall counts toward the face bound but is
        -- never deducted from spendable funds.
        SELECT coalesce(sum(rv2.reversed_face_minor + rv2.hold_minor),0) INTO v_face_used
          FROM hocalist.payment_reversals rv2
          WHERE rv2.scope='buyer_reward' AND rv2.causal_outcome_id=r.causal_outcome_id
            AND rv2.id<>r.id AND rv2.state IN ('held','resolved');
        v_face := least(r.amount_minor, greatest(0, w.amount_minor - v_face_used));
        -- The temporary hold is the causal, conservatively proved recoverable
        -- amount. Compensation settles exactly that reservation and never
        -- recomputes an account-wide balance, so an unrelated reward arriving
        -- after the hold cannot be debited. Anything above it stays an
        -- explicit unrecovered shortfall for manual policy.
        SELECT coalesce(sum(cor.amount_minor),0) INTO v_reversed_amount
          FROM hocalist.ledger_corrections cor
         WHERE cor.reversal_id=r.id AND cor.entry_kind='reward_hold';
        v_reversed_amount := least(v_face, v_reversed_amount);
        -- Convert the temporary reservation into a permanent debit: release
        -- the hold, then append the final reversal (append-only, no rewrite).
        FOR v_row IN SELECT * FROM hocalist.ledger_corrections
            WHERE reversal_id=r.id AND entry_kind='reward_hold' LOOP
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'buyer_reward',v_row.target_id,'reward_release',
            -v_row.amount_minor,0,'compensation settled','admin')
          ON CONFLICT (reversal_id,entry_kind,target_id) DO NOTHING;
        END LOOP;
        IF v_reversed_amount > 0 THEN
          INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
            amount_minor,reserve_delta_minor,note,actor)
          VALUES(r.id,'buyer_reward',w.id,'reward_reversed',v_reversed_amount,0,
            left(p_input->>'note',500),'admin')
          ON CONFLICT (reversal_id,entry_kind,target_id) DO NOTHING;
        END IF;
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

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------

-- The caller's own holds only. Provider references and admin notes for other
-- accounts are never exposed.
CREATE FUNCTION hocalist.commercial_reversal_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  pol hocalist.reversal_policy%ROWTYPE;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'reversal_access_denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO pol FROM hocalist.reversal_policy WHERE singleton;
  RETURN jsonb_build_object(
    'policy', jsonb_build_object(
      'clawback_mode_configured', pol.clawback_mode IS NOT NULL,
      'clawback_mode', pol.clawback_mode,
      'reward_hold_configured', pol.reward_hold_enabled,
      'reward_hold_days', pol.reward_hold_days,
      'revision', pol.revision),
    'reward_holds', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'reversal_id',rv.id,'kind',rv.kind,'state',rv.state,
        'amount_minor',c.amount_minor,'created_at',c.created_at) ORDER BY c.created_at DESC)
      FROM hocalist.ledger_corrections c
      JOIN hocalist.payment_reversals rv ON rv.id=c.reversal_id
      JOIN hocalist.buyer_rewards w ON w.id=c.target_id
      WHERE c.target_kind='buyer_reward' AND rv.state='held'
        AND c.entry_kind IN ('reward_hold','reward_reversed')
        AND w.buyer_user_id=u),'[]'::jsonb),
    'credit_holds', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'reversal_id',rv.id,'kind',rv.kind,'state',rv.state,
        'amount_minor',c.amount_minor,'reserved_minor',c.reserve_delta_minor,
        'created_at',c.created_at) ORDER BY c.created_at DESC)
      FROM hocalist.ledger_corrections c
      JOIN hocalist.payment_reversals rv ON rv.id=c.reversal_id
      JOIN hocalist.credit_batches b ON b.id=c.target_id
      WHERE c.target_kind='credit_batch' AND rv.state='held'
        AND c.entry_kind='hold' AND b.user_id=u),'[]'::jsonb),
    'withdrawal_holds', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'reversal_id',rv.id,'kind',rv.kind,'state',rv.state,
        'amount_minor',c.amount_minor,'created_at',c.created_at) ORDER BY c.created_at DESC)
      FROM hocalist.ledger_corrections c
      JOIN hocalist.payment_reversals rv ON rv.id=c.reversal_id
      JOIN hocalist.withdrawal_requests wd ON wd.id=c.target_id
      WHERE c.target_kind='withdrawal' AND rv.state='held'
        AND c.entry_kind='hold' AND wd.user_id=u),'[]'::jsonb));
END $$;

CREATE FUNCTION hocalist.admin_reversal_queue(p_limit integer DEFAULT 50, p_cursor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); rows jsonb; next_id uuid;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  WITH found AS (
    SELECT r.id,r.kind,r.scope,r.amount_minor,r.currency,r.state,r.hold_minor,
      r.shortfall_minor,r.causal_outcome_id,r.causal_withdrawal_id,r.causal_user_id,
      r.note,r.created_at,r.updated_at
    FROM hocalist.payment_reversals r
    WHERE r.state IN ('open','held') AND (p_cursor IS NULL OR r.id>p_cursor)
    ORDER BY r.id LIMIT p_limit+1),
  page AS (SELECT * FROM found ORDER BY id LIMIT p_limit)
  SELECT coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',id,'kind',kind,'scope',scope,'amount_minor',amount_minor,'currency',currency,
      'state',state,'hold_minor',hold_minor,'shortfall_minor',shortfall_minor,
      'causal_outcome_id',causal_outcome_id,'causal_withdrawal_id',causal_withdrawal_id,
      'causal_user_id',causal_user_id,'note',note,'created_at',created_at,'updated_at',updated_at)
      ORDER BY id) FROM page),'[]'::jsonb),
    CASE WHEN (SELECT count(*) FROM found)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
    INTO rows,next_id;
  RETURN jsonb_build_object('items',rows,'next_cursor',next_id,
    'open_count',(SELECT count(*) FROM hocalist.payment_reversals WHERE state='open'),
    'held_count',(SELECT count(*) FROM hocalist.payment_reversals WHERE state='held'));
END $$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION
  hocalist.reward_causal_unspent_internal(uuid),
  hocalist.reward_identity_free_internal(uuid),
  hocalist.reward_disputed_pool_free_internal(uuid),
  hocalist.reversal_open_internal(text,text,text,text,bigint,uuid,uuid,uuid,text),
  hocalist.reversal_admin_command(text,text,jsonb),
  hocalist.commercial_reversal_status(),
  hocalist.admin_reversal_queue(integer,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  hocalist.reversal_open_internal(text,text,text,text,bigint,uuid,uuid,uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION hocalist.commercial_reversal_status(),
  hocalist.reversal_admin_command(text,text,jsonb),
  hocalist.admin_reversal_queue(integer,uuid) TO authenticated;
COMMIT;

-- Additive commercial settlement over the reviewed 090/091 foundation.
--
-- Implements the September 26 approved credit rules with batch-owned pricing:
--   * the subscription/plan determines weekly targeting capacity only;
--   * every deposit batch keeps ITS immutable initial/winning rates;
--   * before permitting a targeting interaction, reserve the full possible
--     winning fee from the oldest single batch that can cover its own winning
--     fee, and copy that batch's rates/version into the reservation;
--   * later deposits, plan changes or admin deposit-option edits never reprice
--     an existing batch or an existing reservation;
--   * charge the initial fee once both parties have sent a qualifying message,
--     and only the remaining winning difference on a PIN-confirmed purchase;
--   * release the unused reservation for non-winners, or the entire
--     reservation when no qualifying interaction occurred;
--   * an absent paid configuration is an explicit error: a chargeable action
--     is never acknowledged without its required reservation.
--
-- No fee rate is invented here. New batches are created only by the reviewed
-- provider path (`credit_deposit_internal`), which snapshots the rates of an
-- admin-managed deposit option after a confirmed payment.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.credit_targets') IS NULL THEN
    RAISE EXCEPTION 'credit batches 090 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.marketplace_plan_limits') IS NULL THEN
    RAISE EXCEPTION 'marketplace 020 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.marketplace_weekly_target_limit(uuid)') IS NULL THEN
    RAISE EXCEPTION 'marketplace weekly capacity 023 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.credit_deposit_options') IS NOT NULL THEN
    RAISE EXCEPTION 'credit settlement already installed';
  END IF;
END; $guard$;

-- ---------------------------------------------------------------------------
-- Admin-managed deposit and reward configuration
-- ---------------------------------------------------------------------------

-- A deposit option is the admin-managed 1:1 amount plus the fee rates that a
-- confirmed payment of that amount will freeze into one new batch. No option is
-- seeded: an empty table means credit deposits are not purchasable yet, and a
-- targeting attempt reports that explicitly instead of proceeding free.
CREATE TABLE hocalist.credit_deposit_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  amount_minor bigint NOT NULL UNIQUE CHECK (amount_minor > 0),
  initial_fee_minor bigint NOT NULL CHECK (initial_fee_minor >= 0),
  winning_total_minor bigint NOT NULL
    CHECK (winning_total_minor >= initial_fee_minor AND winning_total_minor <= amount_minor),
  rate_version text NOT NULL CHECK (length(btrim(rate_version)) BETWEEN 1 AND 100),
  active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Buyer reward rates remain a separate ledger from seller credits. The late
-- window is optional; when unconfigured the normal rate applies and no
-- undocumented late-window shortcut is inferred. An absent policy is visible
-- to the app as `reward_policy_configured: false`; it never blocks a sale.
CREATE TABLE hocalist.reward_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  normal_minor bigint NOT NULL CHECK (normal_minor > 0),
  late_minor bigint NOT NULL CHECK (late_minor >= normal_minor),
  late_window_hours integer CHECK (late_window_hours IS NULL OR late_window_hours BETWEEN 1 AND 168),
  rule_version text NOT NULL CHECK (length(btrim(rule_version)) BETWEEN 1 AND 100),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE hocalist.credit_targets
  ADD COLUMN offer_id uuid REFERENCES hocalist.offers(id),
  ADD COLUMN qualified_at timestamptz,
  ADD COLUMN rate_version text
    CHECK (rate_version IS NULL OR length(btrim(rate_version)) BETWEEN 1 AND 100);
-- Append-only history: one live target per seller/request, but a withdrawn and
-- re-submitted negotiation may append a new target after the old one closes.
ALTER TABLE hocalist.credit_targets DROP CONSTRAINT credit_targets_user_id_request_id_key;
CREATE UNIQUE INDEX credit_targets_live
  ON hocalist.credit_targets(user_id, request_id)
  WHERE status IN ('reserved','initial_charged','won');

ALTER TABLE hocalist.credit_deposit_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.reward_policy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.credit_deposit_options, hocalist.reward_policy
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Targeted-fee reservation (batch-owned pricing)
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS hocalist.credit_reserve_internal(uuid,uuid,date,integer);

-- Reserves the full winning fee of ONE selected batch. Only batches whose
-- remaining spendable amount covers their own winning_total_minor are
-- eligible; the oldest eligible batch wins. Its initial fee, winning total and
-- rate version are copied onto the target, so a later deposit, plan change or
-- admin edit cannot reprice this reservation.
CREATE FUNCTION hocalist.credit_reserve_internal(
  p_user uuid, p_request uuid, p_offer uuid, p_week date, p_limit integer
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  b hocalist.credit_batches%ROWTYPE;
  t hocalist.credit_targets%ROWTYPE;
  o hocalist.offers%ROWTYPE;
BEGIN
  IF p_week IS NULL OR p_limit IS NULL OR p_limit < 1 THEN
    RAISE EXCEPTION 'invalid_reservation' USING ERRCODE='22023';
  END IF;
  SELECT * INTO o FROM hocalist.offers WHERE id=p_offer AND request_id=p_request;
  IF NOT FOUND OR o.seller_user_id<>p_user THEN
    RAISE EXCEPTION 'offer_access_denied' USING ERRCODE='42501';
  END IF;
  -- Same seller lock across quota check, batch selection and all mutations.
  PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
  SELECT * INTO t FROM hocalist.credit_targets
    WHERE user_id=p_user AND request_id=p_request
      AND status IN ('reserved','initial_charged','won');
  IF FOUND THEN RETURN t.id; END IF;
  IF (SELECT count(*) FROM hocalist.credit_targets WHERE user_id=p_user AND week_start=p_week) >= p_limit THEN
    RAISE EXCEPTION 'weekly_target_limit' USING ERRCODE='P0001';
  END IF;
  SELECT * INTO b FROM hocalist.credit_batches
    WHERE user_id=p_user AND balance_minor-reserved_minor >= winning_total_minor
    ORDER BY created_at,id LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN
    -- Distinguish "buy more credits" from "the platform cannot sell credits":
    -- an absent paid configuration is an explicit error, never free targeting.
    IF EXISTS (SELECT 1 FROM hocalist.credit_deposit_options WHERE active) THEN
      RAISE EXCEPTION 'insufficient_single_batch' USING ERRCODE='P0001';
    END IF;
    RAISE EXCEPTION 'targeting_fee_unconfigured' USING ERRCODE='P0001';
  END IF;
  INSERT INTO hocalist.credit_targets(
    user_id,request_id,batch_id,offer_id,initial_minor,winning_minor,reserved_minor,week_start,rate_version)
  VALUES (p_user,p_request,b.id,p_offer,
    b.initial_fee_minor,b.winning_total_minor,b.winning_total_minor,p_week,b.rate_version)
  RETURNING * INTO t;
  UPDATE hocalist.credit_batches SET reserved_minor=reserved_minor+t.winning_minor WHERE id=b.id;
  INSERT INTO hocalist.credit_entries(batch_id,target_id,kind,amount_minor,reserve_delta_minor)
    VALUES(b.id,t.id,'reserve',0,t.winning_minor);
  RETURN t.id;
END $$;

-- Called by the marketplace command before the offer is acknowledged. Resolves
-- weekly capacity from the plan and pricing from the batch. It raises
-- `targeting_fee_unconfigured` when no deposit option exists and no eligible
-- batch can fund the action, so a chargeable interaction is never silently
-- free.
CREATE FUNCTION hocalist.credit_authorize_target(p_user uuid, p_request uuid, p_offer uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_week date := date_trunc('week', now() AT TIME ZONE 'UTC')::date;
  v_limit integer;
  v_id uuid;
  t hocalist.credit_targets%ROWTYPE;
  b hocalist.credit_batches%ROWTYPE;
BEGIN
  v_limit := coalesce(hocalist.marketplace_weekly_target_limit(p_user), 0);
  IF v_limit < 1 THEN
    RAISE EXCEPTION 'weekly_target_limit' USING ERRCODE='P0001';
  END IF;
  v_id := hocalist.credit_reserve_internal(p_user, p_request, p_offer, v_week, v_limit);
  SELECT * INTO t FROM hocalist.credit_targets WHERE id=v_id;
  SELECT * INTO b FROM hocalist.credit_batches WHERE id=t.batch_id;
  RETURN jsonb_build_object('status','reserved','target_id',t.id,'batch_id',b.id,
    'initial_fee_minor',t.initial_minor,'winning_total_minor',t.winning_minor,
    'rate_version',t.rate_version);
END $$;

-- ---------------------------------------------------------------------------
-- Qualification, release and purchase settlement
-- ---------------------------------------------------------------------------

-- A qualifying interaction is at least one buyer message and one seller
-- message in the negotiation conversation. System notices never qualify.
CREATE FUNCTION hocalist.credit_qualify_conversation(p_conversation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  o hocalist.offers%ROWTYPE;
  t hocalist.credit_targets%ROWTYPE;
BEGIN
  SELECT x.* INTO o FROM hocalist.conversations c
    JOIN hocalist.offers x ON x.id = c.offer_id
    WHERE c.id = p_conversation AND c.origin = 'targeted_request';
  IF NOT FOUND THEN RETURN jsonb_build_object('status','no_target'); END IF;
  PERFORM 1 FROM hocalist.profiles WHERE id=o.seller_user_id FOR UPDATE;
  SELECT * INTO t FROM hocalist.credit_targets
    WHERE offer_id = o.id AND user_id = o.seller_user_id
      AND status IN ('reserved','initial_charged','won') FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','no_target'); END IF;
  IF t.status <> 'reserved' THEN
    RETURN jsonb_build_object('status',t.status,'target_id',t.id);
  END IF;
  IF NOT (EXISTS (
        SELECT 1 FROM hocalist.conversation_messages m
        WHERE m.conversation_id=p_conversation AND m.sender_user_id=o.buyer_user_id
          AND m.kind IN ('text','attachment'))
      AND EXISTS (
        SELECT 1 FROM hocalist.conversation_messages m
        WHERE m.conversation_id=p_conversation AND m.sender_user_id=o.seller_user_id
          AND m.kind IN ('text','attachment'))) THEN
    RETURN jsonb_build_object('status','awaiting_qualification');
  END IF;
  PERFORM hocalist.credit_settle_internal(t.id,'initial');
  UPDATE hocalist.credit_targets SET qualified_at=now() WHERE id=t.id;
  RETURN jsonb_build_object('status','initial_charged','target_id',t.id);
END $$;

-- Releases the live reservation for one withdrawn or closed negotiation.
CREATE FUNCTION hocalist.credit_release_offer(p_offer uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t hocalist.credit_targets%ROWTYPE;
BEGIN
  SELECT * INTO t FROM hocalist.credit_targets
    WHERE offer_id=p_offer AND status IN ('reserved','initial_charged') FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','no_target'); END IF;
  PERFORM 1 FROM hocalist.profiles WHERE id=t.user_id FOR UPDATE;
  PERFORM hocalist.credit_settle_internal(t.id,'release');
  RETURN jsonb_build_object('status','released','target_id',t.id);
END $$;

-- Purchase settlement. The winning seller keeps the full winning fee from its
-- own batch (only the remaining difference is charged when the initial fee was
-- already collected); every other negotiation releases its unused reservation,
-- keeping an already charged initial/losing fee. Buyer reward accrual is a
-- separate ledger and only happens when a configured reward policy exists and
-- the winning fee was actually collected.
CREATE FUNCTION hocalist.credit_settle_purchase(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_outcome hocalist.sale_confirmations%ROWTYPE;
  v_request hocalist.requests%ROWTYPE;
  t hocalist.credit_targets%ROWTYPE;
  v_win hocalist.credit_targets%ROWTYPE;
  rp hocalist.reward_policy%ROWTYPE;
  v_amount bigint;
  v_rule text;
  v_won boolean := false;
  v_released integer := 0;
BEGIN
  IF to_regclass('hocalist.sale_confirmations') IS NULL THEN
    RAISE EXCEPTION 'sale confirmation prerequisite missing';
  END IF;
  SELECT * INTO STRICT v_outcome FROM hocalist.sale_confirmations WHERE request_id=p_request;
  SELECT * INTO v_request FROM hocalist.requests WHERE id=p_request;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found' USING ERRCODE='P0002'; END IF;

  SELECT * INTO v_win FROM hocalist.credit_targets
    WHERE user_id=v_outcome.seller_user_id AND request_id=p_request
      AND status IN ('reserved','initial_charged','won');
  IF FOUND THEN
    PERFORM 1 FROM hocalist.profiles WHERE id=v_win.user_id FOR UPDATE;
    SELECT * INTO v_win FROM hocalist.credit_targets WHERE id=v_win.id FOR UPDATE;
    IF v_win.status IN ('reserved','initial_charged') THEN
      PERFORM hocalist.credit_settle_internal(v_win.id,'win');
      SELECT * INTO v_win FROM hocalist.credit_targets WHERE id=v_win.id;
    END IF;
    v_won := v_win.status='won';
  END IF;

  FOR t IN SELECT * FROM hocalist.credit_targets
           WHERE request_id=p_request AND user_id<>v_outcome.seller_user_id
             AND status IN ('reserved','initial_charged')
           ORDER BY user_id LOOP
    PERFORM 1 FROM hocalist.profiles WHERE id=t.user_id FOR UPDATE;
    PERFORM hocalist.credit_settle_internal(t.id,'release');
    v_released := v_released + 1;
  END LOOP;

  IF v_won AND to_regprocedure('hocalist.reward_accrue_internal(uuid,uuid,bigint,text)') IS NOT NULL THEN
    SELECT * INTO rp FROM hocalist.reward_policy WHERE singleton;
    IF FOUND THEN
      v_amount := rp.normal_minor;
      v_rule := rp.rule_version;
      IF rp.late_window_hours IS NOT NULL
         AND v_request.acceptance_expires_at IS NOT NULL
         AND EXISTS (
           SELECT 1 FROM hocalist.offers o
           WHERE o.id = v_outcome.offer_id
             AND o.created_at >= v_request.acceptance_expires_at - make_interval(hours => rp.late_window_hours)) THEN
        v_amount := rp.late_minor;
        v_rule := rp.rule_version || ':late';
      END IF;
      PERFORM hocalist.reward_accrue_internal(v_outcome.id, v_win.id, v_amount, v_rule);
    END IF;
  END IF;

  RETURN jsonb_build_object('winning_target',v_win.id,'won',v_won,'released',v_released);
END $$;

-- Releases live reservations whose negotiation ended without a winning
-- purchase. A request that merely passed its discovery window keeps its
-- reservation while an accepted meeting is still valid, and while a pending
-- proposal can still be accepted for an already accepted negotiation. Only the
-- caller's own targets are ever touched; this is not a global job.
CREATE FUNCTION hocalist.credit_reconcile_internal(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  t hocalist.credit_targets%ROWTYPE;
  o hocalist.offers%ROWTYPE;
  r hocalist.requests%ROWTYPE;
  v_closed boolean;
  v_expired boolean;
  v_released integer := 0;
BEGIN
  IF p_user IS NULL THEN RAISE EXCEPTION 'invalid_user' USING ERRCODE='22023'; END IF;
  FOR t IN SELECT * FROM hocalist.credit_targets
           WHERE user_id=p_user AND status IN ('reserved','initial_charged')
           ORDER BY created_at,id LOOP
    IF t.offer_id IS NULL THEN CONTINUE; END IF;
    SELECT * INTO o FROM hocalist.offers WHERE id=t.offer_id;
    SELECT * INTO r FROM hocalist.requests WHERE id=t.request_id;
    IF o.id IS NULL OR r.id IS NULL THEN CONTINUE; END IF;
    v_closed := o.status IN ('withdrawn','declined','cancelled','expired','completed')
      OR r.status IN ('closed','cancelled');
    v_expired := r.acceptance_expires_at IS NOT NULL AND now() >= r.acceptance_expires_at;
    IF NOT (v_closed OR v_expired) THEN CONTINUE; END IF;
    IF to_regclass('hocalist.meetings') IS NOT NULL AND EXISTS (
      SELECT 1 FROM hocalist.meetings m
      WHERE m.offer_id=t.offer_id
        AND m.status IN ('accepted','reschedule_proposed')
        AND m.meeting_expires_at IS NOT NULL AND now() < m.meeting_expires_at) THEN
      CONTINUE;
    END IF;
    IF NOT v_closed AND to_regclass('hocalist.meetings') IS NOT NULL AND EXISTS (
      SELECT 1 FROM hocalist.meetings m
      WHERE m.offer_id=t.offer_id AND m.status='proposed') THEN
      -- Discovery closed but the accepted negotiation may still confirm a
      -- meeting; the reservation stays until that proposal resolves.
      CONTINUE;
    END IF;
    PERFORM 1 FROM hocalist.profiles WHERE id=t.user_id FOR UPDATE;
    PERFORM hocalist.credit_settle_internal(t.id,'release');
    v_released := v_released + 1;
  END LOOP;
  RETURN jsonb_build_object('released',v_released);
END $$;

-- ---------------------------------------------------------------------------
-- Wallet projection
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION hocalist.credit_wallet() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid:=auth.uid();
  v_week date := date_trunc('week', now() AT TIME ZONE 'UTC')::date;
BEGIN
  IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='seller' AND status='active')
   OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
   RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE='42501'; END IF;
  -- Reconciliation only releases this caller's own ended negotiations; it is
  -- idempotent and never settles a live accepted meeting.
  PERFORM hocalist.credit_reconcile_internal(u);
  RETURN jsonb_build_object('currency','HC',
   'balance_minor',coalesce((SELECT sum(balance_minor) FROM hocalist.credit_batches WHERE user_id=u),0),
   'reserved_minor',coalesce((SELECT sum(reserved_minor) FROM hocalist.credit_batches WHERE user_id=u),0),
   'weekly',jsonb_build_object(
     'used',(SELECT count(*) FROM hocalist.credit_targets WHERE user_id=u AND week_start=v_week),
     'limit',hocalist.marketplace_weekly_target_limit(u)),
   'deposit_options',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',id,'amount_minor',amount_minor,'initial_fee_minor',initial_fee_minor,
      'winning_total_minor',winning_total_minor,'rate_version',rate_version,
      'active',active,'revision',revision,'sort_order',sort_order)
      ORDER BY sort_order,amount_minor) FROM hocalist.credit_deposit_options WHERE active),'[]'::jsonb),
   'batches',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'original_minor',original_minor,'balance_minor',balance_minor,
    'reserved_minor',reserved_minor,'initial_fee_minor',initial_fee_minor,'winning_total_minor',winning_total_minor,
    'rate_version',rate_version,'created_at',created_at) ORDER BY created_at,id)
    FROM hocalist.credit_batches WHERE user_id=u),'[]'::jsonb));
END $$;

-- Reward configuration is reported explicitly so an absent rate is visible
-- instead of silently accruing nothing.
CREATE OR REPLACE FUNCTION hocalist.reward_wallet() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); p hocalist.reward_policy%ROWTYPE;
BEGIN
 IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='buyer' AND status='active')
  OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO p FROM hocalist.reward_policy WHERE singleton;
 RETURN jsonb_build_object('currency','USD','withdrawals_enabled',false,
  'reward_policy_configured',FOUND,
  'earned_minor',coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r
    JOIN hocalist.credit_targets t ON t.id=r.target_id
    WHERE r.buyer_user_id=u AND t.status='won'),0),
  'items',coalesce((SELECT jsonb_agg(x.data ORDER BY x.created_at DESC,x.id DESC) FROM (
   SELECT r.id,r.created_at,jsonb_build_object('id',r.id,'amount_minor',r.amount_minor,'created_at',r.created_at,
    'status',CASE WHEN t.status='won' THEN 'earned' ELSE 'held' END) AS data
   FROM hocalist.buyer_rewards r JOIN hocalist.credit_targets t ON t.id=r.target_id
   WHERE r.buyer_user_id=u ORDER BY r.created_at DESC,r.id DESC LIMIT 50) x),'[]'::jsonb));
END $$;

-- ---------------------------------------------------------------------------
-- Admin configuration command
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.credit_admin_command(p_operation text, p_key text, p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid:=auth.uid();
  h text;
  receipt hocalist.marketplace_receipts%ROWTYPE;
  result jsonb;
  v_id uuid;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(u);
  IF p_operation IS NULL OR p_operation NOT IN ('deposit_option.set','deposit_option.retire','reward_policy.set')
   OR p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
   OR p_input IS NULL OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  h := encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':credit_admin:'||p_operation||':'||p_key,0));
  SELECT * INTO receipt FROM hocalist.marketplace_receipts
    WHERE user_id=u AND operation='credit_admin.'||p_operation AND idempotency_key=p_key;
  IF FOUND THEN
    IF receipt.request_hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF;
    RETURN receipt.result;
  END IF;
  IF p_operation='deposit_option.set' THEN
    IF p_input - ARRAY['id','amount_minor','initial_fee_minor','winning_total_minor','rate_version','active','sort_order','expected_revision'] <> '{}'::jsonb
     OR jsonb_typeof(p_input->'active') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION 'invalid_option' USING ERRCODE='22023';
    END IF;
    IF p_input->>'id' IS NULL THEN
      INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version,active,sort_order)
      VALUES((p_input->>'amount_minor')::bigint,(p_input->>'initial_fee_minor')::bigint,
        (p_input->>'winning_total_minor')::bigint,btrim(p_input->>'rate_version'),
        (p_input->>'active')::boolean,coalesce((p_input->>'sort_order')::integer,0))
      RETURNING id INTO v_id;
    ELSE
      UPDATE hocalist.credit_deposit_options SET
        amount_minor=(p_input->>'amount_minor')::bigint,
        initial_fee_minor=(p_input->>'initial_fee_minor')::bigint,
        winning_total_minor=(p_input->>'winning_total_minor')::bigint,
        rate_version=btrim(p_input->>'rate_version'),
        active=(p_input->>'active')::boolean,
        sort_order=coalesce((p_input->>'sort_order')::integer,0),
        revision=revision+1,updated_at=now()
      WHERE id=(p_input->>'id')::uuid
        AND (p_input->'expected_revision' IS NULL OR revision=(p_input->>'expected_revision')::bigint)
      RETURNING id INTO v_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    END IF;
    result:=jsonb_build_object('id',v_id);
  ELSIF p_operation='deposit_option.retire' THEN
    IF p_input - ARRAY['id','expected_revision'] <> '{}'::jsonb THEN
      RAISE EXCEPTION 'invalid_option' USING ERRCODE='22023';
    END IF;
    UPDATE hocalist.credit_deposit_options SET active=false,revision=revision+1,updated_at=now()
    WHERE id=(p_input->>'id')::uuid
      AND (p_input->'expected_revision' IS NULL OR revision=(p_input->>'expected_revision')::bigint)
    RETURNING id INTO v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    result:=jsonb_build_object('id',v_id,'active',false);
  ELSE
    IF p_input - ARRAY['normal_minor','late_minor','late_window_hours','rule_version','expected_revision'] <> '{}'::jsonb THEN
      RAISE EXCEPTION 'invalid_policy' USING ERRCODE='22023';
    END IF;
    INSERT INTO hocalist.reward_policy(singleton,normal_minor,late_minor,late_window_hours,rule_version)
    VALUES(true,(p_input->>'normal_minor')::bigint,(p_input->>'late_minor')::bigint,
      nullif(p_input->>'late_window_hours','')::integer,btrim(p_input->>'rule_version'))
    ON CONFLICT(singleton) DO UPDATE SET normal_minor=excluded.normal_minor,late_minor=excluded.late_minor,
      late_window_hours=excluded.late_window_hours,rule_version=excluded.rule_version,
      revision=hocalist.reward_policy.revision+1,updated_at=now()
    WHERE p_input->'expected_revision' IS NULL OR hocalist.reward_policy.revision=(p_input->>'expected_revision')::bigint;
    IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
    result:=jsonb_build_object('singleton',true);
  END IF;
  INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
    VALUES(u,'credit_admin.'||p_operation,p_key,h,result);
  RETURN result;
END $$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION
  hocalist.credit_reserve_internal(uuid,uuid,uuid,date,integer),
  hocalist.credit_authorize_target(uuid,uuid,uuid),
  hocalist.credit_qualify_conversation(uuid),
  hocalist.credit_release_offer(uuid),
  hocalist.credit_settle_purchase(uuid),
  hocalist.credit_reconcile_internal(uuid),
  hocalist.credit_wallet(),
  hocalist.reward_wallet(),
  hocalist.credit_admin_command(text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.credit_wallet(), hocalist.reward_wallet(),
  hocalist.credit_admin_command(text,text,jsonb) TO authenticated;
COMMIT;

-- Additive commercial reads for the app wallet surfaces.
--
-- These functions expose only server-computed values from the reviewed
-- ledgers (090/091/092/093 and, when present, 180-183). Nothing here is
-- fabricated client-side: availability, weekly quota, holds and reward
-- eligibility are derived from committed rows, and every read is owner-scoped.
--
-- Dependencies are optional on purpose so this file can apply on the reviewed
-- checkpoint without the sibling commercial_completion migrations. When an
-- optional module is absent the corresponding field reports that it is not
-- configured instead of inventing a value.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regprocedure('hocalist.credit_wallet()') IS NULL THEN
    RAISE EXCEPTION 'credit wallet 092 prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.reward_wallet()') IS NULL THEN
    RAISE EXCEPTION 'reward wallet 091 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.sale_confirmations') IS NULL THEN
    RAISE EXCEPTION 'outcomes 080 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.commercial_credit_wallet') IS NOT NULL THEN
    RAISE EXCEPTION 'commercial reads already installed';
  END IF;
END $guard$;

-- ---------------------------------------------------------------------------
-- Authoritative reward availability (one rule for wallet, withdrawal, payout)
-- ---------------------------------------------------------------------------

-- Signed ledger corrections that reduce the withdrawable balance for one
-- buyer: temporary reward holds/releases, permanent reward reversals, and
-- withdrawal-scope logical holds/releases. Positive = reserved, negative =
-- released. Policy keeps the corrections inert: nothing is deducted until an
-- admin has configured and applied a reversal.
CREATE FUNCTION hocalist.commercial_reward_hold_minor(p_user uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT coalesce((
    SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
    JOIN hocalist.buyer_rewards w ON w.id=c.target_id
    WHERE c.target_kind='buyer_reward' AND w.buyer_user_id=p_user
      AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed')),0)
    + coalesce((
    SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
    JOIN hocalist.withdrawal_requests wd ON wd.id=c.target_id
    WHERE c.target_kind='withdrawal' AND wd.user_id=p_user
      AND c.entry_kind IN ('hold','release_hold')),0);
$$;

-- Safety correction to the reviewed 093 helper: the original body subtracted
-- only `processing` requests, so a paid withdrawal became withdrawable again.
-- The corrected body keeps the same signature and subtracts processing, paid
-- amounts AND every active/permanent correction, so the wallet projection, the
-- authenticated withdrawal command and payout admission share one rule.
-- Applied only when 093 exists.
DO $patch$ BEGIN
  IF to_regprocedure('hocalist.withdrawal_available_minor(uuid)') IS NOT NULL THEN
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION hocalist.withdrawal_available_minor(p_user uuid)
      RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
        SELECT greatest(0,
          coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r
            JOIN hocalist.credit_targets t ON t.id=r.target_id
            WHERE r.buyer_user_id=p_user AND t.status='won'),0)
          - coalesce((SELECT sum(w.amount_minor) FROM hocalist.withdrawal_requests w
            WHERE w.user_id=p_user AND w.status IN ('processing','paid')),0)
          - hocalist.commercial_reward_hold_minor(p_user));
      $$;
    $sql$;
    REVOKE ALL ON FUNCTION hocalist.withdrawal_available_minor(uuid)
      FROM PUBLIC, anon, authenticated, service_role;
  END IF;
END $patch$;

-- Serialize withdrawal admission with reversal holds for the same buyer, so a
-- hold and a withdrawal cannot both reserve the same funds. Same signature and
-- behavior as the reviewed 093 command; only the ledger lock is added before
-- the existing per-key idempotency lock.
DO $patch$ BEGIN
  IF to_regprocedure('hocalist.withdrawal_request(text,bigint)') IS NOT NULL THEN
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION hocalist.withdrawal_request(p_key text, p_amount_minor bigint)
      RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
      DECLARE
        u uuid:=auth.uid(); p hocalist.withdrawal_policy%ROWTYPE; c jsonb;
        h text; w hocalist.withdrawal_requests%ROWTYPE;
      BEGIN
        IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='buyer' AND status='active')
         OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
          RAISE EXCEPTION 'withdrawal_access_denied' USING ERRCODE='42501'; END IF;
        IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
           OR p_amount_minor IS NULL OR p_amount_minor <= 0 THEN
          RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023'; END IF;
        -- Ledger lock first, then the per-key lock: the hold path takes only
        -- the ledger lock, so this order cannot deadlock.
        PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:reward_ledger:'||u::text,902));
        PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':withdrawal:'||p_key,0));
        SELECT * INTO w FROM hocalist.withdrawal_requests WHERE user_id=u AND client_key=p_key;
        IF FOUND THEN
          RETURN jsonb_build_object('status','processing','withdrawal_id',w.id,
            'amount_minor',w.amount_minor,'fee_minor',w.fee_minor,'net_minor',w.net_minor);
        END IF;
        SELECT * INTO p FROM hocalist.withdrawal_policy WHERE singleton;
        c := hocalist.contact_verified(u);
        IF NOT (c->>'email_verified')::boolean OR NOT (c->>'phone_verified')::boolean THEN
          RAISE EXCEPTION 'contact_verification_required' USING ERRCODE='P0001'; END IF;
        IF p_amount_minor < p.minimum_minor THEN
          RAISE EXCEPTION 'below_minimum' USING ERRCODE='P0001'; END IF;
        IF p_amount_minor > hocalist.withdrawal_available_minor(u) THEN
          RAISE EXCEPTION 'insufficient_earned_balance' USING ERRCODE='P0001'; END IF;
        INSERT INTO hocalist.withdrawal_requests(user_id,client_key,amount_minor,fee_minor,net_minor)
        VALUES(u,btrim(p_key),p_amount_minor,p.fee_minor,p_amount_minor-p.fee_minor)
        RETURNING * INTO w;
        INSERT INTO hocalist.withdrawal_events(withdrawal_id,revision,event,actor,detail)
        VALUES(w.id,1,'requested','user','net '||w.net_minor::text);
        RETURN jsonb_build_object('status','processing','withdrawal_id',w.id,
          'amount_minor',w.amount_minor,'fee_minor',w.fee_minor,'net_minor',w.net_minor);
      END $$;
    $sql$;
    REVOKE ALL ON FUNCTION hocalist.withdrawal_request(text,bigint)
      FROM PUBLIC, anon, authenticated, service_role;
    GRANT EXECUTE ON FUNCTION hocalist.withdrawal_request(text,bigint) TO authenticated;
  END IF;
END $patch$;

-- ---------------------------------------------------------------------------
-- Seller credit wallet
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.commercial_credit_wallet()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  v_week date := date_trunc('week', now() AT TIME ZONE 'UTC')::date;
  v_balance bigint;
  v_reserved bigint;
  v_limit integer;
  v_has_reversals boolean := to_regclass('hocalist.ledger_corrections') IS NOT NULL;
BEGIN
  IF u IS NULL OR NOT EXISTS (
      SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id=u AND m.role='seller' AND m.status='active')
     OR EXISTS (SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id=u AND m.status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE='42501';
  END IF;
  -- Same caller-scoped reconciliation as the reviewed wallet: idempotent and
  -- never settles a live accepted meeting.
  PERFORM hocalist.credit_reconcile_internal(u);
  SELECT coalesce(sum(balance_minor),0), coalesce(sum(reserved_minor),0)
    INTO v_balance, v_reserved
  FROM hocalist.credit_batches WHERE user_id=u;
  v_limit := hocalist.marketplace_weekly_target_limit(u);
  RETURN jsonb_build_object(
    'currency','HC',
    'balance_minor',v_balance,
    'reserved_minor',v_reserved,
    'available_minor',greatest(0,v_balance-v_reserved),
    'charged_minor',coalesce((SELECT sum(charged_minor) FROM hocalist.credit_targets
      WHERE user_id=u),0),
    'deposited_minor',coalesce((SELECT sum(original_minor) FROM hocalist.credit_batches
      WHERE user_id=u),0),
    'reversal_hold_minor',CASE WHEN v_has_reversals THEN coalesce((
      SELECT sum(c.reserve_delta_minor) FROM hocalist.ledger_corrections c
      JOIN hocalist.payment_reversals rv ON rv.id=c.reversal_id
      JOIN hocalist.credit_batches b ON b.id=c.target_id
      WHERE c.target_kind='credit_batch' AND b.user_id=u
        AND rv.state='held' AND c.entry_kind='hold'),0) ELSE 0 END,
    'weekly',jsonb_build_object(
      'week_start',v_week,
      'used',(SELECT count(*) FROM hocalist.credit_targets WHERE user_id=u AND week_start=v_week),
      'limit',v_limit),
    'deposit_options',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',id,'amount_minor',amount_minor,'initial_fee_minor',initial_fee_minor,
        'winning_total_minor',winning_total_minor,'rate_version',rate_version,
        'active',active,'revision',revision,'sort_order',sort_order)
        ORDER BY sort_order,amount_minor)
      FROM hocalist.credit_deposit_options WHERE active),'[]'::jsonb),
    'batches',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',b.id,'original_minor',b.original_minor,'balance_minor',b.balance_minor,
        'reserved_minor',b.reserved_minor,
        'available_minor',greatest(0,b.balance_minor-b.reserved_minor),
        'charged_minor',coalesce((SELECT sum(t.charged_minor) FROM hocalist.credit_targets t
          WHERE t.batch_id=b.id),0),
        'initial_fee_minor',b.initial_fee_minor,'winning_total_minor',b.winning_total_minor,
        'rate_version',b.rate_version,'created_at',b.created_at)
        ORDER BY b.created_at,b.id)
      FROM hocalist.credit_batches b WHERE b.user_id=u),'[]'::jsonb),
    'targets',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',t.id,'request_id',t.request_id,'request_title',q.title,'offer_id',t.offer_id,
        'status',t.status,'initial_minor',t.initial_minor,'winning_minor',t.winning_minor,
        'charged_minor',t.charged_minor,'reserved_minor',t.reserved_minor,
        'week_start',t.week_start,'rate_version',t.rate_version,
        'qualified_at',t.qualified_at,'created_at',t.created_at)
        ORDER BY t.created_at DESC,t.id DESC)
      FROM (SELECT * FROM hocalist.credit_targets
        WHERE user_id=u ORDER BY created_at DESC,id DESC LIMIT 50) t
      LEFT JOIN hocalist.requests q ON q.id=t.request_id),'[]'::jsonb),
    'policy',jsonb_build_object(
      'deposit_options_configured',EXISTS(
        SELECT 1 FROM hocalist.credit_deposit_options WHERE active),
      'weekly_limit_resolved',v_limit));
END $$;

-- ---------------------------------------------------------------------------
-- Buyer reward wallet (separate ledger, explicit held/available split)
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.commercial_reward_wallet()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  u uuid := auth.uid();
  v_earned bigint;
  v_pending bigint;
  v_holds bigint := 0;
  v_reward_hold bigint := 0;
  v_withdrawal_hold bigint := 0;
  v_reversed bigint := 0;
  v_shortfall bigint := 0;
  v_processing bigint := 0;
  v_paid bigint := 0;
  v_minimum bigint;
  v_fee bigint;
  v_email boolean := false;
  v_phone boolean := false;
  v_has_reversals boolean := to_regclass('hocalist.ledger_corrections') IS NOT NULL;
  v_has_withdrawals boolean := to_regprocedure('hocalist.withdrawal_available_minor(uuid)') IS NOT NULL;
  v_has_payout boolean := to_regclass('hocalist.payout_policy') IS NOT NULL;
  pol hocalist.reward_policy%ROWTYPE;
BEGIN
  IF u IS NULL OR NOT EXISTS (
      SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id=u AND m.role='buyer' AND m.status='active')
     OR EXISTS (SELECT 1 FROM hocalist.memberships m
      WHERE m.user_id=u AND m.status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT coalesce(sum(r.amount_minor),0) INTO v_earned
  FROM hocalist.buyer_rewards r JOIN hocalist.credit_targets t ON t.id=r.target_id
  WHERE r.buyer_user_id=u AND t.status='won';
  SELECT coalesce(sum(r.amount_minor),0) INTO v_pending
  FROM hocalist.buyer_rewards r JOIN hocalist.credit_targets t ON t.id=r.target_id
  WHERE r.buyer_user_id=u AND t.status<>'won';
  IF v_has_reversals THEN
    -- One authoritative deduction rule, shared with withdrawal admission.
    -- Temporary holds and permanent reversals are reported separately so the
    -- per-item rows can be reconciled with the totals.
    v_holds := hocalist.commercial_reward_hold_minor(u);
    SELECT coalesce(sum(c.amount_minor),0) INTO v_reward_hold
    FROM hocalist.ledger_corrections c
    JOIN hocalist.buyer_rewards w ON w.id=c.target_id
    WHERE c.target_kind='buyer_reward' AND w.buyer_user_id=u
      AND c.entry_kind IN ('reward_hold','reward_release');
    SELECT coalesce(sum(c.amount_minor),0) INTO v_withdrawal_hold
    FROM hocalist.ledger_corrections c
    JOIN hocalist.withdrawal_requests wd ON wd.id=c.target_id
    WHERE c.target_kind='withdrawal' AND wd.user_id=u
      AND c.entry_kind IN ('hold','release_hold');
    SELECT coalesce(sum(c.amount_minor),0) INTO v_reversed
    FROM hocalist.ledger_corrections c
    JOIN hocalist.buyer_rewards w ON w.id=c.target_id
    WHERE c.target_kind='buyer_reward' AND w.buyer_user_id=u
      AND c.entry_kind='reward_reversed';
    -- Unrecovered reversal losses are audit history only: they are never an
    -- implicit debt against future or unrelated rewards.
    SELECT coalesce(sum(rv.shortfall_minor),0) INTO v_shortfall
    FROM hocalist.payment_reversals rv
    JOIN hocalist.buyer_rewards w ON w.outcome_id=rv.causal_outcome_id
    WHERE rv.scope='buyer_reward' AND rv.state='resolved' AND w.buyer_user_id=u;
  END IF;
  IF v_has_withdrawals THEN
    SELECT coalesce(sum(w.amount_minor),0) INTO v_processing
    FROM hocalist.withdrawal_requests w WHERE w.user_id=u AND w.status='processing';
    SELECT coalesce(sum(w.amount_minor),0) INTO v_paid
    FROM hocalist.withdrawal_requests w WHERE w.user_id=u AND w.status='paid';
    SELECT minimum_minor, fee_minor INTO v_minimum, v_fee
    FROM hocalist.withdrawal_policy WHERE singleton;
    v_email := (hocalist.contact_verified(u)->>'email_verified')::boolean;
    v_phone := (hocalist.contact_verified(u)->>'phone_verified')::boolean;
  END IF;
  SELECT * INTO pol FROM hocalist.reward_policy WHERE singleton;
  RETURN jsonb_build_object(
    'currency','USD',
    'earned_minor',v_earned,
    'held_minor',greatest(0,v_pending+v_reward_hold+v_withdrawal_hold),
    'pending_minor',v_pending,
    'hold_minor',greatest(0,v_reward_hold),
    'withdrawal_hold_minor',greatest(0,v_withdrawal_hold),
    'reversed_minor',greatest(0,v_reversed),
    'shortfall_minor',greatest(0,v_shortfall),
    'processing_minor',v_processing,
    'paid_minor',v_paid,
    'available_minor',greatest(0,v_earned-v_processing-v_paid-v_holds),
    'reward_policy_configured',FOUND,
    'normal_minor',CASE WHEN FOUND THEN pol.normal_minor END,
    'late_minor',CASE WHEN FOUND THEN pol.late_minor END,
    'late_window_hours',CASE WHEN FOUND THEN pol.late_window_hours END,
    'withdrawal',jsonb_build_object(
      'configured',v_has_withdrawals,
      'minimum_minor',v_minimum,'fee_minor',v_fee,
      'email_verified',v_email,'phone_verified',v_phone),
    'payout',jsonb_build_object(
      'provider_configured',CASE WHEN v_has_payout THEN EXISTS(
        SELECT 1 FROM hocalist.payout_policy WHERE singleton AND provider_key IS NOT NULL) ELSE false END,
      'execution_enabled',CASE WHEN v_has_payout THEN EXISTS(
        SELECT 1 FROM hocalist.payout_policy WHERE singleton AND execution_enabled) ELSE false END,
      'provider_neutral',true),
    'reversal_policy',jsonb_build_object(
      'clawback_mode_configured',CASE WHEN v_has_reversals THEN EXISTS(
        SELECT 1 FROM hocalist.reversal_policy WHERE singleton AND clawback_mode IS NOT NULL) ELSE false END,
      'reward_hold_configured',CASE WHEN v_has_reversals THEN EXISTS(
        SELECT 1 FROM hocalist.reversal_policy WHERE singleton AND reward_hold_enabled) ELSE false END),
    'items',coalesce((SELECT jsonb_agg(x.data ORDER BY x.created_at DESC,x.id DESC) FROM (
      SELECT r.id,r.created_at,jsonb_build_object(
        'id',r.id,'amount_minor',r.amount_minor,'created_at',r.created_at,
        'status',CASE WHEN t.status='won'
          AND coalesce((SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
            WHERE c.target_kind='buyer_reward' AND c.target_id=r.id
              AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed')),0)=0
          THEN 'earned' ELSE 'held' END,
        'hold_minor',CASE WHEN v_has_reversals THEN greatest(0,coalesce((
          SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
          WHERE c.target_kind='buyer_reward' AND c.target_id=r.id
            AND c.entry_kind IN ('reward_hold','reward_release')),0)) ELSE 0 END,
        'reversed_minor',CASE WHEN v_has_reversals THEN greatest(0,coalesce((
          SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
          WHERE c.target_kind='buyer_reward' AND c.target_id=r.id
            AND c.entry_kind='reward_reversed'),0)) ELSE 0 END,
        'shortfall_minor',CASE WHEN v_has_reversals THEN greatest(0,coalesce((
          SELECT sum(rv.shortfall_minor) FROM hocalist.payment_reversals rv
          WHERE rv.scope='buyer_reward' AND rv.state='resolved'
            AND rv.causal_outcome_id=r.outcome_id),0)) ELSE 0 END,
        'item_title',q.title) AS data
      FROM hocalist.buyer_rewards r
      JOIN hocalist.credit_targets t ON t.id=r.target_id
      LEFT JOIN hocalist.sale_confirmations s ON s.id=r.outcome_id
      LEFT JOIN hocalist.requests q ON q.id=s.request_id
      WHERE r.buyer_user_id=u ORDER BY r.created_at DESC,r.id DESC LIMIT 50) x),'[]'::jsonb));
END $$;

-- ---------------------------------------------------------------------------
-- Role-aware sale history and drill-down
-- ---------------------------------------------------------------------------

CREATE FUNCTION hocalist.commercial_sale_history(
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
      'reward',CASE WHEN s.buyer_user_id=u THEN jsonb_build_object(
        'amount_minor',rw.amount_minor,
        'status',CASE WHEN rw.id IS NULL THEN 'none'
          WHEN t.status='won' THEN 'earned' ELSE 'held' END,
        'rule_version',rw.rule_version) END,
      'fee',CASE WHEN s.seller_user_id=u THEN jsonb_build_object(
        'status',coalesce(t.status,'none'),
        'charged_minor',coalesce(t.charged_minor,0),
        'winning_minor',coalesce(t.winning_minor,0),
        'rate_version',t.rate_version) END) AS data
    FROM hocalist.sale_confirmations s
    JOIN hocalist.requests q ON q.id=s.request_id
    JOIN hocalist.offers o ON o.id=s.offer_id
    JOIN hocalist.offer_revisions r ON r.id=o.accepted_revision_id
    LEFT JOIN hocalist.buyer_rewards rw ON rw.outcome_id=s.id
    LEFT JOIN hocalist.credit_targets t ON t.id=rw.target_id
    WHERE (s.buyer_user_id=u OR s.seller_user_id=u)
      AND (p_before_time IS NULL OR (s.confirmed_at,s.id)<(p_before_time,p_before_id))
    ORDER BY s.confirmed_at DESC,s.id DESC LIMIT 25) x;
  RETURN jsonb_build_object('items',items);
END $$;

CREATE FUNCTION hocalist.commercial_sale_detail(p_outcome uuid)
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
  SELECT * INTO rw FROM hocalist.buyer_rewards WHERE outcome_id=s.id;
  IF FOUND THEN
    SELECT * INTO t FROM hocalist.credit_targets WHERE id=rw.target_id;
    v_reward := jsonb_build_object(
      'amount_minor',rw.amount_minor,'rule_version',rw.rule_version,
      'status',CASE WHEN t.status='won' THEN 'earned' ELSE 'held' END);
    v_fee := jsonb_build_object(
      'status',coalesce(t.status,'none'),
      'charged_minor',coalesce(t.charged_minor,0),
      'winning_minor',coalesce(t.winning_minor,0),
      'initial_minor',coalesce(t.initial_minor,0),
      'rate_version',t.rate_version);
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

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION
  hocalist.commercial_reward_hold_minor(uuid),
  hocalist.commercial_credit_wallet(),
  hocalist.commercial_reward_wallet(),
  hocalist.commercial_sale_history(timestamptz,uuid),
  hocalist.commercial_sale_detail(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  hocalist.commercial_credit_wallet(),
  hocalist.commercial_reward_wallet(),
  hocalist.commercial_sale_history(timestamptz,uuid),
  hocalist.commercial_sale_detail(uuid) TO authenticated;
COMMIT;

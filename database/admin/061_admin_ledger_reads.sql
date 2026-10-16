-- Additive administrator-only commercial ledger reads (061, draft).
--
-- Aggregated HocaCredit batch/target totals and separate buyer reward totals
-- for operations review. No names, contacts, payment identifiers, provider
-- payloads or money-moving capability are exposed, and no reconciliation or
-- payout state is inferred: buyer withdrawals are not connected yet.
--
-- Not an instruction to apply to a live project. Generate a guarded rollout
-- bundle and obtain coordinating review before applying.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $admin_ledger_guard$
BEGIN
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL
     OR to_regclass('hocalist.credit_batches') IS NULL
     OR to_regclass('hocalist.credit_targets') IS NULL
     OR to_regclass('hocalist.buyer_rewards') IS NULL THEN
    RAISE EXCEPTION 'Admin ledger reads require admin, credit and reward foundations';
  END IF;
  IF to_regprocedure('hocalist.admin_credit_summary(integer,uuid)') IS NOT NULL
     OR to_regprocedure('hocalist.admin_reward_summary(integer,uuid)') IS NOT NULL
     OR to_regprocedure('hocalist.admin_credit_detail(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Admin ledger read objects already exist; review before replacement';
  END IF;
END
$admin_ledger_guard$;

CREATE FUNCTION hocalist.admin_credit_summary(
  p_limit integer DEFAULT 50,
  p_cursor uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rows jsonb;
  v_more boolean;
  v_cursor uuid;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_admin_query' USING ERRCODE='22023';
  END IF;
  WITH per_user AS (
    SELECT b.user_id,
      count(*)::integer AS batch_count,
      sum(b.original_minor)::bigint AS original_minor,
      sum(b.balance_minor)::bigint AS remaining_minor,
      sum(b.reserved_minor)::bigint AS reserved_minor,
      max(b.created_at) AS last_deposit_at
    FROM hocalist.credit_batches b
    GROUP BY b.user_id
  ), targets AS (
    SELECT t.user_id,
      count(*)::integer AS target_count,
      count(*) FILTER (WHERE t.status = 'won')::integer AS won_count,
      count(*) FILTER (WHERE t.status IN ('released','refunded'))::integer AS released_count
    FROM hocalist.credit_targets t
    GROUP BY t.user_id
  ), windowed AS (
    SELECT p.user_id,
      p.batch_count,
      p.original_minor,
      p.remaining_minor,
      p.reserved_minor,
      (p.remaining_minor - p.reserved_minor) AS available_minor,
      CASE WHEN p.original_minor = 0 THEN 0
           ELSE round(100.0 * (p.original_minor - p.remaining_minor) / p.original_minor)::integer
      END AS spent_percent,
      coalesce(t.target_count, 0) AS target_count,
      coalesce(t.won_count, 0) AS won_count,
      coalesce(t.released_count, 0) AS released_count,
      p.last_deposit_at
    FROM per_user p
    LEFT JOIN targets t ON t.user_id = p.user_id
    WHERE p_cursor IS NULL OR p.user_id > p_cursor
    ORDER BY p.user_id
    LIMIT p_limit + 1
  ), visible AS (SELECT * FROM windowed ORDER BY user_id LIMIT p_limit)
  SELECT
    coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', user_id,
        'batch_count', batch_count,
        'original_minor', original_minor,
        'remaining_minor', remaining_minor,
        'reserved_minor', reserved_minor,
        'available_minor', available_minor,
        'spent_percent', spent_percent,
        'target_count', target_count,
        'won_count', won_count,
        'released_count', released_count,
        'last_deposit_at', last_deposit_at
      ) ORDER BY user_id)
      FROM visible), '[]'::jsonb),
    (SELECT count(*) > p_limit FROM windowed),
    (SELECT user_id FROM visible ORDER BY user_id DESC LIMIT 1)
    INTO v_rows, v_more, v_cursor;
  RETURN jsonb_build_object(
    'items', v_rows,
    'next_cursor', CASE WHEN v_more THEN v_cursor ELSE NULL END);
END; $$;

CREATE FUNCTION hocalist.admin_reward_summary(
  p_limit integer DEFAULT 50,
  p_cursor uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rows jsonb;
  v_more boolean;
  v_cursor uuid;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid_admin_query' USING ERRCODE='22023';
  END IF;
  WITH per_buyer AS (
    SELECT r.buyer_user_id,
      count(*)::integer AS reward_count,
      sum(r.amount_minor)::bigint AS total_minor,
      max(r.created_at) AS last_reward_at
    FROM hocalist.buyer_rewards r
    GROUP BY r.buyer_user_id
  ), windowed AS (
    SELECT * FROM per_buyer
    WHERE p_cursor IS NULL OR buyer_user_id > p_cursor
    ORDER BY buyer_user_id
    LIMIT p_limit + 1
  ), visible AS (SELECT * FROM windowed ORDER BY buyer_user_id LIMIT p_limit)
  SELECT
    coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'buyer_user_id', buyer_user_id,
        'reward_count', reward_count,
        'total_minor', total_minor,
        'last_reward_at', last_reward_at
      ) ORDER BY buyer_user_id)
      FROM visible), '[]'::jsonb),
    (SELECT count(*) > p_limit FROM windowed),
    (SELECT buyer_user_id FROM visible ORDER BY buyer_user_id DESC LIMIT 1)
    INTO v_rows, v_more, v_cursor;
  RETURN jsonb_build_object(
    'items', v_rows,
    'next_cursor', CASE WHEN v_more THEN v_cursor ELSE NULL END);
END; $$;

-- One seller's batch/target detail for operations drill-down. Bounded to the
-- 20 most recent targets and the seller's own batches; no contact or provider
-- payload is projected.
CREATE FUNCTION hocalist.admin_credit_detail(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_batches jsonb;
  v_targets jsonb;
  v_available bigint;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF p_user IS NULL OR NOT EXISTS (
       SELECT 1 FROM hocalist.profiles WHERE id = p_user) THEN
    RAISE EXCEPTION 'invalid_admin_query' USING ERRCODE='22023';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', b.id,
      'original_minor', b.original_minor,
      'balance_minor', b.balance_minor,
      'reserved_minor', b.reserved_minor,
      'initial_fee_minor', b.initial_fee_minor,
      'winning_total_minor', b.winning_total_minor,
      'rate_version', b.rate_version,
      'created_at', b.created_at
    ) ORDER BY b.created_at, b.id), '[]'::jsonb),
    coalesce(sum(b.balance_minor - b.reserved_minor), 0)
    INTO v_batches, v_available
    FROM hocalist.credit_batches b WHERE b.user_id = p_user;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id,
      'request_id', t.request_id,
      'batch_id', t.batch_id,
      'status', t.status,
      'charged_minor', t.charged_minor,
      'reserved_minor', t.reserved_minor,
      'week_start', t.week_start,
      'created_at', t.created_at
    ) ORDER BY t.created_at DESC, t.id DESC), '[]'::jsonb)
    INTO v_targets
    FROM (
      SELECT * FROM hocalist.credit_targets WHERE user_id = p_user
      ORDER BY created_at DESC, id DESC LIMIT 20
    ) t;
  RETURN jsonb_build_object(
    'user_id', p_user,
    'available_minor', v_available,
    'batches', v_batches,
    'targets', v_targets);
END; $$;

REVOKE ALL ON FUNCTION hocalist.admin_credit_summary(integer,uuid),
  hocalist.admin_reward_summary(integer,uuid),
  hocalist.admin_credit_detail(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_credit_summary(integer,uuid),
  hocalist.admin_reward_summary(integer,uuid),
  hocalist.admin_credit_detail(uuid)
  TO authenticated;

DO $hocalist_admin_ledger_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT has_function_privilege('authenticated','hocalist.admin_credit_summary(integer,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.admin_reward_summary(integer,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.admin_credit_detail(uuid)','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_credit_summary(integer,uuid)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_credit_summary(integer,uuid)','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_reward_summary(integer,uuid)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_reward_summary(integer,uuid)','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_credit_detail(uuid)','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_credit_detail(uuid)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'admin ledger read grants are wrong');
  END IF;
  IF has_table_privilege('authenticated','hocalist.credit_batches','SELECT')
     OR has_table_privilege('authenticated','hocalist.buyer_rewards','SELECT') THEN
    v_issues := array_append(v_issues, 'private ledger tables became client-readable');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist admin ledger post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_admin_ledger_postapply$;
COMMIT;

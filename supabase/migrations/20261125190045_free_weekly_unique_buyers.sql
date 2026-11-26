BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE INDEX IF NOT EXISTS credit_targets_user_week_idx
  ON hocalist.credit_targets (user_id, week_start);

-- Offer and payment records stay separate for each request. Only the Free
-- weekly allowance groups those records by the request owner's account.
CREATE FUNCTION hocalist.weekly_target_usage(p_user uuid, p_week date)
RETURNS bigint LANGUAGE plpgsql STABLE SET search_path = '' AS $$
BEGIN
  IF hocalist.marketplace_seller_plan(p_user) = 'free' THEN
    RETURN (
      SELECT count(DISTINCT r.buyer_user_id)
      FROM hocalist.credit_targets t
      JOIN hocalist.requests r ON r.id = t.request_id
      WHERE t.user_id = p_user AND t.week_start = p_week
    );
  END IF;

  RETURN (
    SELECT count(*) FROM hocalist.credit_targets
    WHERE user_id = p_user AND week_start = p_week
  );
END $$;

-- Callers hold the seller's existing row lock until the target is written.
CREATE FUNCTION hocalist.weekly_target_quota_reached(
  p_user uuid, p_request uuid, p_week date, p_limit integer
) RETURNS boolean LANGUAGE plpgsql STABLE SET search_path = '' AS $$
BEGIN
  IF hocalist.weekly_target_usage(p_user, p_week) < p_limit THEN
    RETURN false;
  END IF;

  IF hocalist.marketplace_seller_plan(p_user) = 'free' THEN
    RETURN NOT EXISTS (
      SELECT 1
      FROM hocalist.credit_targets t
      JOIN hocalist.requests r ON r.id = t.request_id
      JOIN hocalist.requests incoming ON incoming.id = p_request
        AND incoming.buyer_user_id = r.buyer_user_id
      WHERE t.user_id = p_user AND t.week_start = p_week
    );
  END IF;

  RETURN true;
END $$;

REVOKE ALL ON FUNCTION hocalist.weekly_target_usage(uuid,date),
  hocalist.weekly_target_quota_reached(uuid,uuid,date,integer)
  FROM PUBLIC, anon, authenticated, service_role;

-- Replace only quota expressions, retaining validations, funding, grants,
-- locks and any other changes in the installed function definitions.
DO $patch$
DECLARE
  routine regprocedure;
  definition text;
  old_count constant text :=
    '(SELECT count(*) FROM hocalist.credit_targets WHERE user_id=p_user AND week_start=p_week)';
  old_wallet_count constant text :=
    '(SELECT count(*) FROM hocalist.credit_targets WHERE user_id=u AND week_start=v_week)';
BEGIN
  FOREACH routine IN ARRAY ARRAY[
    'hocalist.credit_reserve_internal(uuid,uuid,uuid,date,integer)'::regprocedure,
    'hocalist.paygo_reserve_target(uuid,uuid,uuid,date,integer)'::regprocedure
  ] LOOP
    definition := pg_get_functiondef(routine);
    IF position(old_count IN definition) = 0 THEN
      RAISE EXCEPTION 'Weekly target reservation definition drift: %', routine;
    END IF;
    definition := replace(definition, old_count || ' >= p_limit',
      'hocalist.weekly_target_quota_reached(p_user, p_request, p_week, p_limit)');
    definition := replace(definition, old_count || '>=p_limit',
      'hocalist.weekly_target_quota_reached(p_user, p_request, p_week, p_limit)');
    IF position(old_count IN definition) > 0 THEN
      RAISE EXCEPTION 'Weekly target reservation expression drift: %', routine;
    END IF;
    EXECUTE definition;
  END LOOP;

  FOREACH routine IN ARRAY ARRAY[
    'hocalist.credit_wallet()'::regprocedure,
    'hocalist.commercial_credit_wallet()'::regprocedure
  ] LOOP
    definition := pg_get_functiondef(routine);
    IF position(old_wallet_count IN definition) = 0 THEN
      RAISE EXCEPTION 'Weekly target wallet definition drift: %', routine;
    END IF;
    EXECUTE replace(definition, old_wallet_count,
      'hocalist.weekly_target_usage(u, v_week)');
  END LOOP;
END $patch$;

COMMIT;

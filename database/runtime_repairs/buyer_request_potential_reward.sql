BEGIN;

-- A read-only estimate, scoped to the signed-in buyer and one request.
-- Use the settlement system's qualification markers and reward rates.
CREATE OR REPLACE FUNCTION hocalist.commercial_request_potential_reward(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  buyer uuid := auth.uid();
  request_row hocalist.requests%ROWTYPE;
  estimate bigint := 0;
BEGIN
  SELECT * INTO request_row
  FROM hocalist.requests
  WHERE id = p_request AND buyer_user_id = buyer;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hocalist.sale_confirmations WHERE request_id = p_request)
    AND ((request_row.status = 'active' AND
      (request_row.acceptance_expires_at IS NULL OR request_row.acceptance_expires_at > now()))
      OR EXISTS (
        SELECT 1 FROM hocalist.meetings
        WHERE request_id = p_request AND status IN ('accepted', 'reschedule_proposed')
          AND meeting_expires_at > now()
      )) THEN
    SELECT coalesce(sum(hocalist.reward_target_estimate(target.id)), 0)
    INTO estimate
    FROM hocalist.credit_targets AS target
    WHERE target.request_id = p_request AND target.qualified_at <= now()
      AND (
        (target.status IN ('reserved', 'initial_charged') AND target.winning_minor > 0)
        OR (target.status = 'released' AND target.initial_minor > 0
          AND target.charged_minor >= target.initial_minor)
      );
  END IF;

  RETURN jsonb_build_object('estimated_minor', estimate);
END;
$$;

REVOKE ALL ON FUNCTION hocalist.commercial_request_potential_reward(uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION hocalist.commercial_request_potential_reward(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';

COMMIT;

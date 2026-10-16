-- Additive seller outcome projection for the approved Meets completion state.
--
-- The Meets screen may only show a meeting as completed when a confirmed
-- purchase outcome exists for it. This read returns the seller's own
-- confirmed outcomes with their meeting ids; it carries no buyer contacts,
-- address or PIN material.
--
-- Prerequisites: outcomes/080 (sale_confirmations) and marketplace/020.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.sale_confirmations') IS NULL
     OR to_regprocedure('hocalist.marketplace_assert_role(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'marketplace/outcomes prerequisite missing';
  END IF;
  IF to_regprocedure('hocalist.marketplace_seller_outcomes(integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'seller outcomes already installed';
  END IF;
END; $guard$;

CREATE FUNCTION hocalist.marketplace_seller_outcomes(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u uuid := auth.uid();
  v_size integer;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u, 'seller');
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  v_size := p_limit;
  RETURN jsonb_build_object(
    'items', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'outcome_id', s.id,
        'meeting_id', s.meeting_id,
        'request_id', s.request_id,
        'offer_id', s.offer_id,
        'confirmed_at', s.confirmed_at)
        ORDER BY s.confirmed_at DESC, s.id DESC)
      FROM (SELECT * FROM hocalist.sale_confirmations
            WHERE seller_user_id = u
            ORDER BY confirmed_at DESC, id DESC LIMIT v_size) s), '[]'::jsonb));
END $$;

REVOKE ALL ON FUNCTION hocalist.marketplace_seller_outcomes(integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.marketplace_seller_outcomes(integer) TO authenticated;
COMMIT;

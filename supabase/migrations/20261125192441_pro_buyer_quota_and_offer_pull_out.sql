BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $patch$
DECLARE
  routine regprocedure;
  definition text;
  free_plan constant text := 'hocalist.marketplace_seller_plan(p_user) = ''free''';
  live_target constant text := 'IF FOUND THEN RETURN t.id; END IF;';
  withdrawn constant text := 'IF v_offer.status = ''withdrawn'' THEN';
  withdraw_revisions constant text := 'UPDATE hocalist.offer_revisions SET status = ''withdrawn''';
BEGIN
  FOREACH routine IN ARRAY ARRAY[
    'hocalist.weekly_target_usage(uuid,date)'::regprocedure,
    'hocalist.weekly_target_quota_reached(uuid,uuid,date,integer)'::regprocedure
  ] LOOP
    definition := pg_get_functiondef(routine);
    IF position(free_plan IN definition) = 0 THEN
      RAISE EXCEPTION 'Weekly buyer quota definition drift: %', routine;
    END IF;
    EXECUTE replace(definition, free_plan,
      'hocalist.marketplace_seller_plan(p_user) IN (''free'', ''pro'')');
  END LOOP;

  -- A resubmission may create a new target after withdrawal. Terminal targets
  -- remain available for their original offer and its payment reconciliation.
  routine := 'hocalist.paygo_reserve_target(uuid,uuid,uuid,date,integer)'::regprocedure;
  definition := pg_get_functiondef(routine);
  IF position('WHERE user_id=p_user AND request_id=p_request;' IN definition) = 0 THEN
    RAISE EXCEPTION 'Paygo target lookup definition drift';
  END IF;
  EXECUTE replace(definition, 'WHERE user_id=p_user AND request_id=p_request;',
    'WHERE user_id=p_user AND request_id=p_request AND status IN (''reserved'',''initial_charged'',''won'');');

  -- Both paths must only replay a reservation for the same offer. The existing
  -- seller lock and live-target index continue to serialize reservations.
  FOREACH routine IN ARRAY ARRAY[
    'hocalist.credit_reserve_internal(uuid,uuid,uuid,date,integer)'::regprocedure,
    'hocalist.paygo_reserve_target(uuid,uuid,uuid,date,integer)'::regprocedure
  ] LOOP
    definition := pg_get_functiondef(routine);
    IF position(live_target IN definition) = 0 THEN
      RAISE EXCEPTION 'Offer funding definition drift: %', routine;
    END IF;
    EXECUTE replace(definition, live_target, $guard$
      IF FOUND THEN
        IF t.offer_id IS DISTINCT FROM p_offer THEN
          RAISE EXCEPTION 'offer_funding_conflict' USING ERRCODE = 'P0001';
        END IF;
        RETURN t.id;
      END IF;$guard$);
  END LOOP;

  routine := 'hocalist.marketplace_command(text,text,jsonb)'::regprocedure;
  definition := pg_get_functiondef(routine);
  IF position(withdrawn IN definition) = 0 OR position(withdraw_revisions IN definition) = 0 THEN
    RAISE EXCEPTION 'Offer withdrawal definition drift';
  END IF;
  -- The existing ownership, offer lock, and receipt replay precede these
  -- checks. A prior successful withdrawal can still be safely replayed.
  EXECUTE replace(definition, withdraw_revisions, $withdraw$
      IF coalesce(hocalist.marketplace_seller_plan(v_user), 'free') NOT IN ('pro', 'elite') THEN
        RAISE EXCEPTION 'offer_withdraw_plan_required' USING ERRCODE = '42501';
      END IF;
      IF v_offer.accepted_revision_id IS NOT NULL
         OR EXISTS (
           SELECT 1 FROM hocalist.offer_revisions r
           WHERE r.offer_id = v_offer.id AND r.proposed_by_user_id = v_offer.buyer_user_id
         ) OR EXISTS (
           SELECT 1 FROM hocalist.conversation_messages m
           WHERE m.offer_id = v_offer.id AND m.sender_user_id = v_offer.buyer_user_id
             AND m.kind IN ('text', 'attachment')
         ) THEN
        RAISE EXCEPTION 'offer_withdraw_buyer_responded' USING ERRCODE = 'P0001';
      END IF;
      UPDATE hocalist.offer_revisions SET status = 'withdrawn'$withdraw$);
END $patch$;

COMMIT;

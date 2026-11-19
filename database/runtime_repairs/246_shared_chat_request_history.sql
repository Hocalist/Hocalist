-- Retain redacted request history for later deals in a shared participant chat.
-- No grants, private address projection, or discovery eligibility are changed.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $patch$
DECLARE
  definition text := replace(pg_get_functiondef('hocalist.marketplace_request(uuid)'::regprocedure), chr(13), '');
  old_predicate text := $old$WHERE c.request_id=p_request AND c.origin='targeted_request'$old$;
  new_predicate text := $new$WHERE (c.request_id=p_request AND c.origin='targeted_request')
      OR EXISTS (SELECT 1 FROM hocalist.offers o
        WHERE o.request_id=p_request AND o.conversation_id=c.id
          AND o.seller_user_id=u AND o.buyer_user_id=owner_id)$new$;
BEGIN
  IF position(old_predicate IN definition)>0 THEN
    IF (length(definition)-length(replace(definition,old_predicate,'')))/length(old_predicate) <> 1 THEN
      RAISE EXCEPTION 'Shared request history predicate is not unique';
    END IF;
    EXECUTE replace(definition,old_predicate,new_predicate);
  ELSIF position(new_predicate IN definition)=0 THEN
    RAISE EXCEPTION 'Shared request history definition drift';
  END IF;
END $patch$;
NOTIFY pgrst, 'reload schema';
COMMIT;

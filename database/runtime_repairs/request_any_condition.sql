-- Let a null condition represent no preference on a product request.
BEGIN;
ALTER TABLE hocalist.requests DROP CONSTRAINT request_kind_fields;
ALTER TABLE hocalist.requests ADD CONSTRAINT request_kind_fields CHECK (
  (kind = 'product' AND service_type IS NULL)
  OR (kind = 'service' AND service_type IS NOT NULL AND condition IS NULL AND quantity = 1)
);

DO $request_condition$
DECLARE
  target regprocedure := coalesce(
    to_regprocedure('hocalist.marketplace_normalize_request_before_questions(jsonb)'),
    to_regprocedure('hocalist.marketplace_normalize_request(jsonb)')
  );
  definition text := pg_get_functiondef(target);
  old_check constant text := 'IF v_condition IS NULL OR v_condition NOT IN (''new_item'',''used'') OR v_service_type IS NOT NULL THEN';
  new_check constant text := 'IF v_condition NOT IN (''new_item'',''used'') OR v_service_type IS NOT NULL THEN';
BEGIN
  IF definition IS NULL OR (strpos(definition, old_check) = 0 AND strpos(definition, new_check) = 0) THEN
    RAISE EXCEPTION 'Request condition validator drift';
  END IF;
  IF strpos(definition, old_check) > 0 THEN
    EXECUTE replace(definition, old_check, new_check);
  END IF;
END;
$request_condition$;
COMMIT;

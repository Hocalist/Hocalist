-- Prepared locally. Pin lookup activation and provider API/key review are separate.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
ALTER TABLE hocalist.places_rate_counters DROP CONSTRAINT places_rate_counters_operation_check;
ALTER TABLE hocalist.places_rate_counters ADD CONSTRAINT places_rate_counters_operation_check
  CHECK(operation IN ('autocomplete','details','coordinates'));
CREATE FUNCTION hocalist.places_coordinates_gate(p_user uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  m timestamptz := date_trunc('minute',now());
  d timestamptz := date_trunc('day',now());
  u text := 'u:' || p_user::text;
BEGIN
  IF p_user IS NULL THEN RETURN jsonb_build_object('decision','invalid_input'); END IF;
  IF NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status='active')
     OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status IN('restricted','disabled'))
  THEN RETURN jsonb_build_object('decision','membership_required'); END IF;
  -- One allowed lookup permits at most one Geocoding + one Time Zone call.
  -- Concurrent function instances share these atomic counters, not local memory.
  DELETE FROM hocalist.places_rate_counters WHERE bucket < d - interval '2 days';
  IF hocalist.places_rate_bump(u,'coordinates','minute',m)>10
    OR hocalist.places_rate_bump(u,'coordinates','day',d)>60
    OR hocalist.places_rate_bump('g','coordinates','minute',m)>15
    OR hocalist.places_rate_bump('g','coordinates','day',d)>180
  THEN RETURN jsonb_build_object('decision','rate_limited'); END IF;
  RETURN jsonb_build_object('decision','allowed','user_id',p_user);
END $$;
REVOKE ALL ON FUNCTION hocalist.places_coordinates_gate(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION hocalist.places_coordinates_gate(uuid) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

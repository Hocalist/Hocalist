BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE hocalist.request_pin_secrets
  ADD COLUMN pin_reserved boolean NOT NULL DEFAULT true;

-- Preserve the five-digit format and the existing private secret. Reserve
-- display digits across all requests while the associated PIN can be used.
CREATE FUNCTION hocalist.reserve_purchase_pin()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
  candidate text;
  previous_code text;
  stale_request uuid;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.secret = OLD.secret THEN RETURN NEW; END IF;
    previous_code := hocalist.sale_pin_digits(OLD.secret);
  END IF;
  NEW.pin_reserved := true;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('hocalist.purchase_pin_reservations', 0));
  FOR attempt IN 1..256 LOOP
    candidate := hocalist.sale_pin_digits(NEW.secret);
    IF candidate IS DISTINCT FROM previous_code THEN
      -- Release a collision after its meeting or schedule has expired.
      -- Keep the old record and its attempt counters.
      SELECT pin.request_id INTO stale_request
      FROM hocalist.request_pin_secrets AS pin
      JOIN hocalist.meetings AS meeting ON meeting.id = pin.meeting_id
      WHERE pin.pin_reserved AND pin.request_id <> NEW.request_id
        AND hocalist.sale_pin_digits(pin.secret) = candidate
        AND (meeting.status = 'cancelled' OR meeting.meeting_expires_at <= now()
             OR meeting.accepted_revision_id IS DISTINCT FROM pin.schedule_revision_id)
      LIMIT 1 FOR UPDATE OF pin SKIP LOCKED;
      IF FOUND THEN
        UPDATE hocalist.request_pin_secrets SET pin_reserved = false
          WHERE request_id = stale_request;
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM hocalist.request_pin_secrets AS pin
        WHERE pin.pin_reserved AND pin.request_id <> NEW.request_id
          AND hocalist.sale_pin_digits(pin.secret) = candidate
      ) THEN
        RETURN NEW;
      END IF;
    END IF;
    NEW.secret := gen_random_uuid();
  END LOOP;
  RAISE EXCEPTION 'purchase_pin_unavailable' USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION hocalist.reserve_purchase_pin()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER reserve_unique_purchase_pin
  BEFORE INSERT OR UPDATE OF secret ON hocalist.request_pin_secrets
  FOR EACH ROW EXECUTE FUNCTION hocalist.reserve_purchase_pin();

-- Keep the first existing reservation for a code, replacing only duplicates.
WITH ranked AS (
  SELECT request_id, row_number() OVER (
    PARTITION BY hocalist.sale_pin_digits(secret) ORDER BY created_at, request_id
  ) AS position
  FROM hocalist.request_pin_secrets
)
UPDATE hocalist.request_pin_secrets AS pin SET secret = gen_random_uuid()
FROM ranked WHERE ranked.request_id = pin.request_id AND ranked.position > 1;

CREATE UNIQUE INDEX request_pin_reserved_digits_idx
  ON hocalist.request_pin_secrets (hocalist.sale_pin_digits(secret))
  WHERE pin_reserved;

-- Preserve the installed sale and settlement behavior. A released code must
-- never verify, and the buyer can generate a new one for an eligible meetup.
DO $patch$
DECLARE
  definition text := pg_get_functiondef('hocalist.sale_pin(uuid,text,text)'::regprocedure);
  issue_condition text := 'OR request_pin_secrets.schedule_revision_id<>excluded.schedule_revision_id;';
  verify_condition text := 'OR s.schedule_revision_id<>m.accepted_revision_id THEN';
BEGIN
  IF position(issue_condition IN definition) = 0 OR position(verify_condition IN definition) = 0 THEN
    RAISE EXCEPTION 'Purchase PIN function definition differs from expected contract';
  END IF;
  EXECUTE replace(
    replace(definition, issue_condition,
      'OR request_pin_secrets.schedule_revision_id<>excluded.schedule_revision_id OR NOT request_pin_secrets.pin_reserved;'),
    verify_condition, 'OR s.schedule_revision_id<>m.accepted_revision_id OR NOT s.pin_reserved THEN');
END
$patch$;
COMMIT;

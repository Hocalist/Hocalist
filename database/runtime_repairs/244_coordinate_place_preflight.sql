-- Read-only prerequisite check. Does not enable provider traffic.
SELECT to_regprocedure('hocalist.places_gate(uuid,text,uuid,text,text)') IS NOT NULL AS existing_places_gate,
       to_regprocedure('hocalist.places_rate_bump(text,text,text,timestamptz)') IS NOT NULL AS existing_shared_counters,
       to_regclass('hocalist.memberships') IS NOT NULL AS existing_memberships,
       to_regprocedure('hocalist.places_coordinates_gate(uuid)') IS NOT NULL AS repair_already_present;
SELECT pg_get_constraintdef(oid) AS operation_constraint
FROM pg_constraint
WHERE conrelid=to_regclass('hocalist.places_rate_counters')
  AND conname='places_rate_counters_operation_check';

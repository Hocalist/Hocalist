BEGIN READ ONLY;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.marketplace_normalize_offer(jsonb)')) IS DISTINCT FROM '53d709735f09544b91a6ab2b5aefc4b3' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: marketplace_normalize_offer';
  END IF;
  IF has_function_privilege('anon','hocalist.marketplace_normalize_offer(jsonb)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_normalize_offer(jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.marketplace_normalize_offer(jsonb)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.marketplace_normalize_offer(jsonb)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: marketplace_normalize_offer';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.marketplace_revision_json(uuid)')) IS DISTINCT FROM '469fed2ad69e5368e8b39374efa8e0e5' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: marketplace_revision_json';
  END IF;
  IF has_function_privilege('anon','hocalist.marketplace_revision_json(uuid)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_revision_json(uuid)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.marketplace_revision_json(uuid)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.marketplace_revision_json(uuid)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: marketplace_revision_json';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)')) IS DISTINCT FROM '8b97abe37830ec8b67abcf2ffc011286' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: marketplace_command';
  END IF;
  IF has_function_privilege('anon','hocalist.marketplace_command(text,text,jsonb)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.marketplace_command(text,text,jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.marketplace_command(text,text,jsonb)','EXECUTE')
      IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: marketplace_command';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_normalize_schedule(jsonb)')) IS DISTINCT FROM 'b5a6cf4bce96a4342bd46590bbae1537' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_normalize_schedule';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_normalize_schedule(jsonb)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_normalize_schedule(jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_normalize_schedule(jsonb)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_normalize_schedule(jsonb)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_normalize_schedule';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)')) IS DISTINCT FROM 'd42ff578c099e4080823113610d19929' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_revision_json';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)','EXECUTE')
      IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_revision_json';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)')) IS DISTINCT FROM '78ad91f34f48a44342c8845c7c29e063' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_propose';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_propose(uuid,jsonb,text)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_propose(uuid,jsonb,text)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_propose(uuid,jsonb,text)','EXECUTE')
      IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_propose';
  END IF;
END $guard$;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)')) IS DISTINCT FROM 'de0e4dce750f951ff4a240411879ebf5' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: meeting_reschedule_propose';
  END IF;
  IF has_function_privilege('anon','hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)','EXECUTE')
    OR has_function_privilege('service_role','hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)','EXECUTE')
      IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: meeting_reschedule_propose';
  END IF;
END $guard$;
ROLLBACK;

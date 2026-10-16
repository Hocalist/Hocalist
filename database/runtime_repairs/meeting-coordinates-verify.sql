BEGIN READ ONLY;
DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\r\n', E'\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.marketplace_normalize_offer(jsonb)')) IS DISTINCT FROM '8a56e9c38aa1bfdf99ae437e53acdf99' THEN
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
    WHERE oid=to_regprocedure('hocalist.marketplace_revision_json(uuid)')) IS DISTINCT FROM '4c4389bc5e67e3948a3b91f16171b734' THEN
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
    WHERE oid=to_regprocedure('hocalist.marketplace_command(text,text,jsonb)')) IS DISTINCT FROM 'c4d2d6dfc061a8fd588577547a91b9b5' THEN
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
    WHERE oid=to_regprocedure('hocalist.meeting_normalize_schedule(jsonb)')) IS DISTINCT FROM '6cba775454b1ed71c5e124a0e1a786d9' THEN
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
    WHERE oid=to_regprocedure('hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)')) IS DISTINCT FROM 'f83d6494b4da6b69f6b9996043e8d8f9' THEN
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
    WHERE oid=to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)')) IS DISTINCT FROM 'dbbc3139676df6e2312b6622de7a17c0' THEN
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
    WHERE oid=to_regprocedure('hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)')) IS DISTINCT FROM '81f4d38048b005f6c9286eb84e7ed0df' THEN
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

BEGIN READ ONLY;
DO $verify$ DECLARE t text;r text;priv text;f oid; BEGIN
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.buyer_rewards')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: buyer_rewards'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.buyer_rewards',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: buyer_rewards % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.buyer_rewards','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: buyer_rewards'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.buyer_rewards'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: buyer_rewards'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.buyer_rewards'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: buyer_rewards'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.buyer_rewards'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: buyer_rewards'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.call_settings')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: call_settings'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.call_settings',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: call_settings % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.call_settings','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: call_settings'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.call_settings'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: call_settings'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.call_settings'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: call_settings'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.call_settings'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: call_settings'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.call_settings_audit')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: call_settings_audit'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.call_settings_audit',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: call_settings_audit % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.call_settings_audit','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: call_settings_audit'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.call_settings_audit'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: call_settings_audit'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.call_settings_audit'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: call_settings_audit'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.call_settings_audit'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: call_settings_audit'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.call_signals')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: call_signals'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.call_signals',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: call_signals % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.call_signals','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: call_signals'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.call_signals'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: call_signals'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.call_signals'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: call_signals'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.call_signals'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: call_signals'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.calls')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: calls'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.calls',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: calls % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.calls','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: calls'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.calls'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: calls'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.calls'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: calls'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.calls'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: calls'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.credit_batches')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: credit_batches'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.credit_batches',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: credit_batches % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.credit_batches','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: credit_batches'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.credit_batches'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: credit_batches'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.credit_batches'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: credit_batches'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.credit_batches'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: credit_batches'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.credit_entries')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: credit_entries'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.credit_entries',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: credit_entries % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.credit_entries','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: credit_entries'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.credit_entries'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: credit_entries'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.credit_entries'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: credit_entries'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.credit_entries'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: credit_entries'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.credit_targets')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: credit_targets'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.credit_targets',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: credit_targets % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.credit_targets','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: credit_targets'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.credit_targets'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: credit_targets'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.credit_targets'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: credit_targets'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.credit_targets'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: credit_targets'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.media_images')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: media_images'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.media_images',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: media_images % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.media_images','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: media_images'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.media_images'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: media_images'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.media_images'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: media_images'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.media_images'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: media_images'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.media_windows')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: media_windows'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.media_windows',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: media_windows % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.media_windows','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: media_windows'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.media_windows'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: media_windows'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.media_windows'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: media_windows'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.media_windows'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: media_windows'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.request_pin_secrets')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: request_pin_secrets'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.request_pin_secrets',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: request_pin_secrets % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.request_pin_secrets','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: request_pin_secrets'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.request_pin_secrets'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: request_pin_secrets'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.request_pin_secrets'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: request_pin_secrets'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.request_pin_secrets'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: request_pin_secrets'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.sale_confirmations')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: sale_confirmations'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.sale_confirmations',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: sale_confirmations % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.sale_confirmations','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: sale_confirmations'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.sale_confirmations'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: sale_confirmations'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.sale_confirmations'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: sale_confirmations'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.sale_confirmations'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: sale_confirmations'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.meetings'::regclass AND tgname='sale_final_meeting' AND tgenabled='O' AND md5(pg_get_triggerdef(oid))='0537d9a7bb9fc605613148ba40f35a06') THEN RAISE EXCEPTION 'Trigger drift: sale_final_meeting'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.offer_revisions'::regclass AND tgname='validate_offer_media' AND tgenabled='O' AND md5(pg_get_triggerdef(oid))='3fec917dfa1a63b625859697b98d489e') THEN RAISE EXCEPTION 'Trigger drift: validate_offer_media'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.requests'::regclass AND tgname='sale_final_request' AND tgenabled='O' AND md5(pg_get_triggerdef(oid))='35400bfb091ab614106faa2badcd90ef') THEN RAISE EXCEPTION 'Trigger drift: sale_final_request'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.store_listings'::regclass AND tgname='validate_store_media' AND tgenabled='O' AND md5(pg_get_triggerdef(oid))='1962604f4ed74b54c33d880b3f7dbb13') THEN RAISE EXCEPTION 'Trigger drift: validate_store_media'; END IF;
f:=to_regprocedure('hocalist.call_admin_settings(boolean,bigint)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'1513de4bb8410c05e2acf35915a38aa3' THEN RAISE EXCEPTION 'Function drift: hocalist.call_admin_settings(boolean,bigint)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.call_admin_settings(boolean,bigint)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.call_admin_settings(boolean,bigint) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.call_command(text,jsonb)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'49221a424fc1c80032f56da8a71de9bd' THEN RAISE EXCEPTION 'Function drift: hocalist.call_command(text,jsonb)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.call_command(text,jsonb)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.call_command(text,jsonb) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'55a81f0fc32a0f491cfb961d0da425d9' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.credit_reserve_internal(uuid,uuid,date,integer)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'e421ff54b6828e30ec09c309dd56d637' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_reserve_internal(uuid,uuid,date,integer)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.credit_reserve_internal(uuid,uuid,date,integer)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.credit_reserve_internal(uuid,uuid,date,integer) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.credit_settle_internal(uuid,text)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'90b8852109c1c612f7a5cc94ab389bd2' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_settle_internal(uuid,text)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.credit_settle_internal(uuid,text)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.credit_settle_internal(uuid,text) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.credit_wallet()');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'ade39ebd47e0ebf915a901e4e587b2e4' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_wallet()'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.credit_wallet()'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.credit_wallet() %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'b88abb275cc2fd083efcfb7f407c3488' THEN RAISE EXCEPTION 'Function drift: hocalist.media_gateway(uuid,text,jsonb)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['service_role']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.media_gateway(uuid,text,jsonb)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['service_role']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.media_gateway(uuid,text,jsonb) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.media_validate_references()');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'5b74ed0d1f3b4a54022f00a1e468e1a1' THEN RAISE EXCEPTION 'Function drift: hocalist.media_validate_references()'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.media_validate_references()'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.media_validate_references() %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.reward_accrue_internal(uuid,uuid,bigint,text)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'406401847ece809b5b1430f3e412aed8' THEN RAISE EXCEPTION 'Function drift: hocalist.reward_accrue_internal(uuid,uuid,bigint,text)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.reward_accrue_internal(uuid,uuid,bigint,text)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.reward_accrue_internal(uuid,uuid,bigint,text) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.reward_wallet()');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'bd5248bf235b034fcdeed1d5d5a0113c' THEN RAISE EXCEPTION 'Function drift: hocalist.reward_wallet()'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.reward_wallet()'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.reward_wallet() %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.sale_history(timestamp with time zone,uuid)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'4dc9bccc3ae24ee859b891919fb78c8b' THEN RAISE EXCEPTION 'Function drift: hocalist.sale_history(timestamp with time zone,uuid)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.sale_history(timestamp with time zone,uuid)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.sale_history(timestamp with time zone,uuid) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.sale_keep_final()');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c7d38610c3a485095b71ad79aeeb94db' THEN RAISE EXCEPTION 'Function drift: hocalist.sale_keep_final()'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.sale_keep_final()'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.sale_keep_final() %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.sale_pin(uuid,text,text)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c935b662860d575095ba45ed6daaf5c5' THEN RAISE EXCEPTION 'Function drift: hocalist.sale_pin(uuid,text,text)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.sale_pin(uuid,text,text)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.sale_pin(uuid,text,text) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.sale_pin_digits(uuid)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'52d6a0f0c08573903e0a1275a61358e6' THEN RAISE EXCEPTION 'Function drift: hocalist.sale_pin_digits(uuid)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.sale_pin_digits(uuid)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.sale_pin_digits(uuid) %',r; END IF;
 END LOOP;
 IF (SELECT enabled FROM hocalist.call_settings WHERE singleton) IS DISTINCT FROM false THEN RAISE EXCEPTION 'Calls must remain off during rollout'; END IF;
END $verify$;
ROLLBACK;

// Generate reviewable local-only rollout; never opens a live connection.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {setup} from '../outcomes/tests/fixture.mjs';
const base=new URL('./',import.meta.url);
const paths=['../outcomes/080_sale_confirmation.sql','../commercial/090_credit_batches.sql','../commercial/091_buyer_rewards.sql','../media/100_private_images.sql','../calls/110_call_signaling.sql'];
const db=await setup(false);
const quote=x=>"'"+x.replaceAll("'","''")+"'";
try{
 const before=(await db.query("SELECT p.oid::regprocedure::text AS signature,md5(replace(pg_get_functiondef(p.oid),chr(13),'')) AS hash FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='hocalist' AND p.proname IN ('meeting_assert_participant','chat_assert_participant','marketplace_assert_admin') ORDER BY 1")).rows;
 const oldTables=new Set((await db.query("SELECT tablename FROM pg_tables WHERE schemaname='hocalist'")).rows.map(x=>x.tablename));
 const oldFns=new Set((await db.query("SELECT p.oid::regprocedure::text AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='hocalist'")).rows.map(x=>x.signature));
 const triggerQuery="SELECT t.tgname,c.relname,md5(pg_get_triggerdef(t.oid)) AS hash,t.tgenabled FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hocalist' AND NOT t.tgisinternal ORDER BY c.relname,t.tgname";
 const oldTriggers=new Set((await db.query(triggerQuery)).rows.map(t=>t.relname+'.'+t.tgname));
 const chunks=[];
 for(const path of paths){const sql=await readFile(new URL(path,base),'utf8');await db.exec(sql);chunks.push(sql.replace(/^BEGIN;\s*$/m,'').replace(/^COMMIT;\s*$/m,''));}
 const tables=(await db.query("SELECT tablename FROM pg_tables WHERE schemaname='hocalist' ORDER BY 1")).rows.map(x=>x.tablename).filter(x=>!oldTables.has(x));
 const triggers=(await db.query(triggerQuery)).rows.filter(t=>!oldTriggers.has(t.relname+'.'+t.tgname));
 const fns=(await db.query("SELECT p.oid::regprocedure::text AS signature,md5(replace(pg_get_functiondef(p.oid),chr(13),'')) AS hash FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='hocalist' ORDER BY 1")).rows.filter(x=>!oldFns.has(x.signature));
 for(const f of fns) f.roles=(await db.query("SELECT rolname FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role') AND has_function_privilege(oid,$1,'EXECUTE') ORDER BY 1",[f.signature])).rows.map(x=>x.rolname);
 const preflight=`DO $guard$ BEGIN\n${before.map(f=>`IF to_regprocedure(${quote(f.signature)}) IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure(${quote(f.signature)})),chr(13),''))<>${quote(f.hash)} THEN RAISE EXCEPTION 'Prerequisite function drift: ${f.signature}'; END IF;`).join('\n')}\n${tables.map(t=>`IF to_regclass('hocalist.${t}') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: ${t}'; END IF;`).join('\n')}\n${fns.map(f=>`IF to_regprocedure(${quote(f.signature)}) IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: ${f.signature}'; END IF;`).join('\n')}\nEND $guard$;\n`;
 const verify=`DO $verify$ DECLARE t text;r text;priv text;f oid; BEGIN\n${tables.map(t=>`IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.${t}')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: ${t}'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.${t}',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: ${t} % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.${t}','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: ${t}'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.${t}'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: ${t}'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.${t}'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: ${t}'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.${t}'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: ${t}'; END IF;`).join('\n')}
${triggers.map(t=>`IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.${t.relname}'::regclass AND tgname=${quote(t.tgname)} AND tgenabled=${quote(t.tgenabled)} AND md5(pg_get_triggerdef(oid))=${quote(t.hash)}) THEN RAISE EXCEPTION 'Trigger drift: ${t.tgname}'; END IF;`).join('\n')}
${fns.map(fn=>`f:=to_regprocedure(${quote(fn.signature)});
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>${quote(fn.hash)} THEN RAISE EXCEPTION 'Function drift: ${fn.signature}'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[${fn.roles.map(quote).join(',')}]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: ${fn.signature}'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[${fn.roles.map(quote).join(',')}]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: ${fn.signature} %',r; END IF;
 END LOOP;`).join('\n')}
 IF (SELECT enabled FROM hocalist.call_settings WHERE singleton) IS DISTINCT FROM false THEN RAISE EXCEPTION 'Calls must remain off during rollout'; END IF;
END $verify$;\n`;
 await mkdir(new URL('rollout/',base),{recursive:true});
 await writeFile(new URL('rollout/preflight.sql',base),'BEGIN READ ONLY;\n'+preflight+'ROLLBACK;\n');
 await writeFile(new URL('rollout/apply.sql',base),"BEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='60s';\n"+preflight+chunks.join('\n')+'\n'+verify+'COMMIT;\n');
 await writeFile(new URL('rollout/verify.sql',base),'BEGIN READ ONLY;\n'+verify+'ROLLBACK;\n');
 await writeFile(new URL('rollout/containment.sql',base),'BEGIN;\n'+fns.map(f=>`REVOKE ALL ON FUNCTION ${f.signature} FROM PUBLIC,anon,authenticated,service_role;`).join('\n')+"\nUPDATE hocalist.call_settings SET enabled=false;\nUPDATE hocalist.calls SET state='ended' WHERE state IN ('ringing','accepted');\nDELETE FROM hocalist.call_signals;\nCOMMIT;\n");
 console.log(`Generated local rollout: ${tables.length} private tables, ${fns.length} functions; no live connection.`);
}finally{await db.close();}

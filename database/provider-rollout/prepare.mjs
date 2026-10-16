// Generates a guarded provider bundle from reviewed source; uses disposable PGlite only.
import {readFile,writeFile} from 'node:fs/promises';
import {createDisposableDb,applySignupSeed,applyStripeInbox} from '../tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const tables=['stripe_test_plans','stripe_test_customers','stripe_test_checkouts','stripe_test_subscriptions','stripe_test_worker_lock','push_devices','notifications','push_deliveries'];
const userFunctions=['stripe_test_billing_status','push_device_register','push_device_disable'];
const workerFunctions=['stripe_test_checkout_begin','stripe_test_checkout_bind','stripe_test_checkout_expire','stripe_test_claim','stripe_test_customer_context','stripe_test_finish','notification_enqueue','push_claim','push_delivery_target','push_finish'];
const billing=await read('../drafts/006_stripe_test_subscriptions.sql');
const push=await read('../drafts/007_push_delivery.sql');
const account=await read('../rollout/verify.sql');
const accountCheck=account.slice(account.indexOf('\nDO $hocalist_postapply$')+1,account.indexOf('$hocalist_postapply$;')+'$hocalist_postapply$;'.length);
const db=await createDisposableDb();
let expected,policyHash;
try {
 await applySignupSeed(db); await applyStripeInbox(db);
 await db.exec(await read('../rollout/account_apply.sql'));
 await db.exec(billing); await db.exec(push);
 expected=(await db.query(`SELECT oid::regprocedure::text signature,proname,md5(replace(pg_get_functiondef(oid),chr(13),'')) digest
 FROM pg_proc WHERE pronamespace='hocalist'::regnamespace AND proname=ANY($1::text[]) ORDER BY proname`,[[...userFunctions,...workerFunctions]])).rows;
 policyHash=(await db.query("SELECT md5(pg_get_expr(polqual,polrelid)) digest FROM pg_policy WHERE polrelid='hocalist.notifications'::regclass AND polname='own_notification_read'")).rows[0].digest;
} finally {await db.close();}
if(expected.length!==userFunctions.length+workerFunctions.length) throw Error('Function inventory mismatch');
const quote=s=>"'"+s.replaceAll("'","''")+"'";
const verify=`${accountCheck}
DO $provider_verify$
DECLARE t text; r text; p text; f record; allowed_role text;
BEGIN
 FOREACH t IN ARRAY ARRAY[${tables.map(quote).join(',')}] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('hocalist.'||t) AND relrowsecurity AND relowner='postgres'::regrole) THEN
   RAISE EXCEPTION 'Provider table owner/RLS mismatch: %',t; END IF;
  IF EXISTS(SELECT 1 FROM pg_class c,aclexplode(c.relacl) a WHERE c.oid=to_regclass('hocalist.'||t)
   AND NOT(a.grantee='postgres'::regrole OR(t='notifications' AND a.grantee='authenticated'::regrole AND a.privilege_type='SELECT' AND NOT a.is_grantable))) THEN
   RAISE EXCEPTION 'Provider table ACL mismatch: %',t; END IF;
  IF EXISTS(SELECT 1 FROM pg_attribute a,aclexplode(a.attacl) x WHERE a.attrelid=to_regclass('hocalist.'||t) AND x.grantee<>'postgres'::regrole) THEN
   RAISE EXCEPTION 'Unexpected provider column grant: %',t; END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   FOREACH p IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
    IF has_table_privilege(r,'hocalist.'||t,p) IS DISTINCT FROM (t='notifications' AND r='authenticated' AND p='SELECT') THEN
     RAISE EXCEPTION 'Unexpected provider permission: % % %',t,r,p; END IF;
   END LOOP;
  END LOOP;
 END LOOP;
 IF (SELECT count(*) FROM pg_policy WHERE polrelid='hocalist.notifications'::regclass)<>1
 OR NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.notifications'::regclass AND polname='own_notification_read'
  AND polcmd='r' AND polpermissive AND polroles=ARRAY['authenticated'::regrole::oid] AND polwithcheck IS NULL
  AND md5(pg_get_expr(polqual,polrelid))=${quote(policyHash)}) THEN RAISE EXCEPTION 'Notification policy mismatch'; END IF;
 FOR f IN SELECT * FROM (VALUES
 ${expected.map(f=>`(${quote(f.signature)},${quote(f.digest)},${quote(userFunctions.includes(f.proname)?'authenticated':'service_role')})`).join(',\n ')}
 ) AS expected(signature,digest,grantee) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(f.signature) AND prosecdef AND proowner='postgres'::regrole
   AND md5(replace(pg_get_functiondef(oid),chr(13),''))=f.digest AND proacl IS NOT NULL) THEN RAISE EXCEPTION 'Provider function mismatch: %',f.signature; END IF;
  IF EXISTS(SELECT 1 FROM pg_proc q,aclexplode(q.proacl) a WHERE q.oid=to_regprocedure(f.signature)
   AND NOT(a.grantee='postgres'::regrole OR(a.grantee=f.grantee::regrole AND a.privilege_type='EXECUTE' AND NOT a.is_grantable))) THEN
   RAISE EXCEPTION 'Provider function ACL mismatch: %',f.signature; END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_function_privilege(r,f.signature,'EXECUTE') IS DISTINCT FROM (r=f.grantee) THEN
    RAISE EXCEPTION 'Unexpected provider execution permission: % %',f.signature,r; END IF;
  END LOOP;
 END LOOP;
 IF EXISTS(SELECT 1 FROM hocalist.stripe_test_plans WHERE enabled) THEN RAISE EXCEPTION 'Plans must stay disabled at foundation rollout'; END IF;
END;
$provider_verify$;`;
const body=s=>s.replace(/^BEGIN;\r?\n/m,'').replace(/COMMIT;\s*$/,'');
await writeFile(new URL('apply.sql',import.meta.url),`-- Generated by prepare.mjs. Requires account rollout; no scheduler or sending activation.\nBEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='60s';\n${accountCheck}\n${body(billing)}\n${body(push)}\n${verify}\nCOMMIT;\nSELECT 'PASS: provider foundation applied; plans disabled; no schedules created' AS provider_rollout;\n`);
await writeFile(new URL('verify.sql',import.meta.url),`-- Read-only foundation verification, before plan activation.\nBEGIN READ ONLY;\n${verify}\nSELECT 'PASS: provider foundation permissions and disabled plans verified' AS provider_verify;\nROLLBACK;\n`);
console.log('Generated provider apply/verify with exact function/policy fingerprints and explicit ACL checks.');

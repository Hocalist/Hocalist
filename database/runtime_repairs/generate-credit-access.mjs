import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const source=await readFile(new URL('194_credit_subscription.sql',import.meta.url),'utf8');
const hash=s=>createHash('md5').update(s.replace(/\r\n/g,'\n')).digest('hex');
const entries=[...source.matchAll(/CREATE OR REPLACE FUNCTION hocalist\.(\w+)\([\s\S]*?AS \$\$([\s\S]*?)\$\$;/g)].map(([sql,name,body])=>{
 const fixed=name==='stripe_test_deposit_begin'
  ? body.replace(/  IF NOT EXISTS \(SELECT 1 FROM hocalist\.stripe_test_subscriptions s[\s\S]*?RAISE EXCEPTION 'subscription_required'[\s\S]*?  END IF;\r?\n/,'')
  : body.replace(/'credit_purchase_allowed', EXISTS \(SELECT 1 FROM hocalist\.stripe_test_subscriptions s[\s\S]*?sc\.requires_review\)\),/,"'credit_purchase_allowed', NOT EXISTS (SELECT 1 FROM hocalist.stripe_test_customers sc WHERE sc.membership_id=m.id AND sc.requires_review),");
 if(fixed===body)throw Error(`missing gate: ${name}`);
 return {name,args:name==='stripe_test_deposit_begin'?'uuid,uuid,uuid':'uuid',before:hash(body),after:hash(fixed),sql:sql.replace(body,fixed)};
});
if(entries.length!==2)throw Error('expected exactly two functions');
const guard=after=>entries.map(e=>`DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.${e.name}(${e.args})') AND md5(replace(prosrc,E'\\r\\n',E'\\n'))='${after?e.after:e.before}' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Credit access definition drift: ${e.name}'; END IF;
 IF has_function_privilege('anon','hocalist.${e.name}(${e.args})','EXECUTE') OR has_function_privilege('${e.name==='stripe_test_deposit_begin'?'authenticated':'service_role'}','hocalist.${e.name}(${e.args})','EXECUTE') OR NOT has_function_privilege('${e.name==='stripe_test_deposit_begin'?'service_role':'authenticated'}','hocalist.${e.name}(${e.args})','EXECUTE') OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(p.proacl) a WHERE p.oid=to_regprocedure('hocalist.${e.name}(${e.args})') AND a.grantee=0) THEN RAISE EXCEPTION 'Credit access privilege drift'; END IF;
END $guard$;`).join('\n');
await writeFile(new URL('credit-access-preflight.sql',import.meta.url),`BEGIN READ ONLY;\n${guard(false)}\nROLLBACK;\n`);
await writeFile(new URL('206_credit_access.sql',import.meta.url),`-- Credit deposits do not require a paid subscription. Seller/safety checks remain.\nBEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='30s';\n${guard(false)}\n${entries.map(e=>e.sql).join('\n')}\n${guard(true)}\nNOTIFY pgrst,'reload schema';\nCOMMIT;\n`);
await writeFile(new URL('credit-access-verify.sql',import.meta.url),`BEGIN READ ONLY;\n${guard(true)}\nROLLBACK;\n`);

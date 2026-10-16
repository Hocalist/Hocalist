import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';

const hash = body => createHash('md5').update(body.replace(/\r\n/g,'\n')).digest('hex');
const predicate = membership => `EXISTS (SELECT 1 FROM hocalist.stripe_test_subscriptions s
      WHERE s.membership_id=${membership} AND s.provider_status='active'
        AND s.plan_code IS NOT NULL AND s.paid_until>now() AND NOT s.requires_review
        AND NOT EXISTS (SELECT 1 FROM hocalist.stripe_test_customers sc
          WHERE sc.membership_id=s.membership_id AND sc.requires_review))`;
const specs = [
  ['../commercial/094_deposit_checkout.sql','stripe_test_deposit_begin','uuid,uuid,uuid', body => {
    const marker = "  IF p_key IS NULL THEN";
    if (!body.includes(marker)) throw Error('begin gate insertion missing');
    return body.replace(marker, `  IF NOT ${predicate('m.id')} THEN
    RAISE EXCEPTION 'subscription_required' USING ERRCODE='P0001';
  END IF;
${marker}`);
  }],
  ['../website_completion/172_website_purchase_status.sql','website_purchase_status','uuid', body => {
    const marker = "    'subscription', (";
    if (!body.includes(marker)) throw Error('status gate insertion missing');
    return body.replace(marker, `    'credit_purchase_allowed', ${predicate('m.id')},\n${marker}`);
  }],
];
const entries=[];
for (const [path,name,args,transform] of specs) {
  const source = await readFile(new URL(path, import.meta.url),'utf8');
  const statement = source.match(new RegExp(`CREATE FUNCTION hocalist\\.${name}\\([\\s\\S]*?\\$\\$;`))?.[0];
  if (!statement) throw Error(`missing ${name}`);
  const body = statement.match(/AS \$\$([\s\S]*)\$\$;/)[1];
  const fixed = transform(body);
  entries.push({name,args,before:hash(body),after:hash(fixed),sql:statement.replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION').replace(body,fixed)});
}
function guard(after) { return entries.map(e => `DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('hocalist.${e.name}(${e.args})')
    AND md5(replace(p.prosrc,E'\\r\\n',E'\\n'))='${after?e.after:e.before}' AND p.prosecdef
    AND p.proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Credit subscription definition drift: ${e.name}'; END IF;
  IF has_function_privilege('anon','hocalist.${e.name}(${e.args})','EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.${e.name}(${e.args})') AND a.grantee=0)
    OR NOT has_function_privilege('${e.name==='stripe_test_deposit_begin'?'service_role':'authenticated'}','hocalist.${e.name}(${e.args})','EXECUTE')
    OR has_function_privilege('${e.name==='stripe_test_deposit_begin'?'authenticated':'service_role'}','hocalist.${e.name}(${e.args})','EXECUTE') THEN
    RAISE EXCEPTION 'Credit subscription privilege drift: ${e.name}'; END IF;
END; $guard$;`).join('\n'); }
await writeFile(new URL('credit-subscription-preflight.sql',import.meta.url),`BEGIN READ ONLY;\n${guard(false)}\nROLLBACK;\n`);
await writeFile(new URL('194_credit_subscription.sql',import.meta.url),`-- Owner rule: a verified active paid seller subscription precedes new credit checkout.\n-- Does not grant subscriptions, change balances or cancel existing provider sessions.\nBEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='30s';\n${guard(false)}\n${entries.map(e=>e.sql).join('\n')}\n${guard(true)}\nNOTIFY pgrst,'reload schema';\nCOMMIT;\n`);
await writeFile(new URL('credit-subscription-verify.sql',import.meta.url),`BEGIN READ ONLY;\n${guard(true)}\nROLLBACK;\n`);

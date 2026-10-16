import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const definitions = [
  ['140_discovery_leads.sql', 'marketplace_discovery_leads', 'text,uuid,text,integer,text,text,integer,text,bigint,bigint'],
  ['141_recommended_leads.sql', 'marketplace_recommended_leads', 'integer'],
];
const hash = body => createHash('md5').update(body.replace(/\r\n/g, '\n')).digest('hex');
const originals = [], replacements = [], corrected = [];
for (const [file, name, args] of definitions) {
  const source = await readFile(new URL(`../discovery_completion/${file}`, import.meta.url), 'utf8');
  const statement = source.match(new RegExp(`CREATE FUNCTION hocalist\\.${name}\\([\\s\\S]*?\\$\\$;`))[0];
  const body = statement.match(/AS \$\$([\s\S]*)\$\$;/)[1];
  const fixed = body.replace(/coalesce\((rp0?|r[p]?).area_label, (r0?|r).city, \2.region, ''\)/g,
    (_, profile, request) => `coalesce(nullif(btrim(${profile}.area_label), ''), nullif(btrim(${request}.city), ''), nullif(btrim(${request}.region), ''))`);
  if (fixed === body || fixed.includes("coalesce(rp.area_label, r.city, r.region, '')") || fixed.includes("coalesce(rp0.area_label, r0.city, r0.region, '')")) throw Error(`Missing reviewed repair: ${name}`);
  originals.push({name,args,hash:hash(body)});
  corrected.push({name,args,hash:hash(fixed)});
  replacements.push(statement.replace('CREATE FUNCTION', 'CREATE OR REPLACE FUNCTION').replace(body,fixed));
}
const guard = entries => entries.map(({name,args,hash:expected}) => `DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid = to_regprocedure('hocalist.${name}(${args})')
    AND md5(replace(p.prosrc, E'\\r\\n', E'\\n')) = '${expected}'
    AND p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'Service-area function definition drift: ${name}';
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.${name}(${args})','EXECUTE')
    OR has_function_privilege('anon','hocalist.${name}(${args})','EXECUTE')
    OR has_function_privilege('service_role','hocalist.${name}(${args})','EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.${name}(${args})')
      AND (a.grantee = 0 OR a.is_grantable AND a.grantee <> p.proowner)) THEN
    RAISE EXCEPTION 'Service-area function privilege drift: ${name}';
  END IF;
END;
$guard$;`).join('\n');
await writeFile(new URL('./area-match-preflight.sql',import.meta.url),`BEGIN READ ONLY;\n${guard(originals)}\nROLLBACK;\n`);
await writeFile(new URL('./191_discovery_area_match.sql',import.meta.url),`-- Missing/blank buyer areas cannot match arbitrary seller service areas.\n-- No records, signatures, authentication or privileges change.\nBEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='30s';\n${guard(originals)}\n${replacements.join('\n')}\n${guard(corrected)}\nCOMMIT;\n`);
await writeFile(new URL('./area-match-verify.sql',import.meta.url),`BEGIN READ ONLY;\n${guard(corrected)}\nROLLBACK;\n`);

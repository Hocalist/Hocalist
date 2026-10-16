import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const source = await readFile(new URL('../marketplace/020_marketplace_foundation.sql', import.meta.url), 'utf8');
const original = source.match(/CREATE FUNCTION hocalist\.marketplace_timezones\(\)[\s\S]*?AS \$\$([\s\S]*?)\$\$;/)[1];
const corrected = original.replace('WHERE hocalist.marketplace_valid_timezone(n.name)', () => `WHERE n.name ~ '^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)+$'
      AND n.name NOT LIKE 'Etc/%'
      AND n.name NOT LIKE 'posix/%'
      AND n.name NOT LIKE 'SystemV/%'`);
if (corrected === original) throw new Error('Reviewed timezone predicate missing');
const hash = body => createHash('md5').update(body.replace(/\r\n/g, '\n')).digest('hex');
const guard = expected => `DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid = to_regprocedure('hocalist.marketplace_timezones()')
    AND md5(replace(p.prosrc, E'\\r\\n', E'\\n')) = '${expected}'
    AND p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'Timezone function definition drift';
  END IF;
  IF NOT has_function_privilege('authenticated', 'hocalist.marketplace_timezones()', 'EXECUTE')
    OR has_function_privilege('anon', 'hocalist.marketplace_timezones()', 'EXECUTE')
    OR has_function_privilege('service_role', 'hocalist.marketplace_timezones()', 'EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid = to_regprocedure('hocalist.marketplace_timezones()') AND (a.grantee = 0 OR a.is_grantable AND a.grantee <> p.proowner)) THEN
    RAISE EXCEPTION 'Timezone function privilege drift';
  END IF;
END;
$guard$;`;
await mkdir(new URL('./', import.meta.url), { recursive: true });
await writeFile(new URL('./preflight.sql', import.meta.url), `BEGIN READ ONLY;\n${guard(hash(original))}\nROLLBACK;\n`);
await writeFile(new URL('./190_timezone_catalogue.sql', import.meta.url), `-- One catalogue scan; authentication, result shape, accepted zones and ACLs unchanged.\nBEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='30s';\n${guard(hash(original))}\nCREATE OR REPLACE FUNCTION hocalist.marketplace_timezones() RETURNS jsonb\nLANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$${corrected}$$;\n${guard(hash(corrected))}\nCOMMIT;\n`);
await writeFile(new URL('./verify.sql', import.meta.url), `BEGIN READ ONLY;\n${guard(hash(corrected))}\nROLLBACK;\n`);

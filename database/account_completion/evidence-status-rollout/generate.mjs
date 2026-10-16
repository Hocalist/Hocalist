import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const base = await readFile(new URL('../../trust/120_review_workflow.sql', import.meta.url), 'utf8');
const original = base.match(/CREATE FUNCTION hocalist\.verification_status\(\)[\s\S]*?END \$\$;/)[0];
const updated = original.replace('CREATE FUNCTION', 'CREATE OR REPLACE FUNCTION')
  .replace("'evidence_count',jsonb_array_length(v.evidence_media_ids),", "'evidence_count',jsonb_array_length(v.evidence_media_ids),\n      'evidence_media_ids',v.evidence_media_ids,");
const hash = sql => createHash('md5').update(sql.match(/AS \$\$([\s\S]*)\$\$;/)[1].replaceAll('\r', '')).digest('hex');
const before = hash(original), after = hash(updated);
const guard = (expected, label) => `DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='hocalist' AND p.proname='verification_status'
      AND p.pronargs=0 AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']
      AND md5(replace(p.prosrc,chr(13),''))='${expected}') THEN
    RAISE EXCEPTION '${label}: verification_status definition drift';
  END IF;
  IF has_function_privilege('anon','hocalist.verification_status()','EXECUTE')
     OR has_function_privilege('service_role','hocalist.verification_status()','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.verification_status()','EXECUTE') THEN
    RAISE EXCEPTION '${label}: verification_status privilege drift';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p, LATERAL aclexplode(p.proacl) a
    WHERE p.oid='hocalist.verification_status()'::regprocedure
      AND a.grantee <> p.proowner
      AND (a.grantee <> (SELECT oid FROM pg_roles WHERE rolname='authenticated')
        OR a.privilege_type <> 'EXECUTE' OR a.is_grantable))
    OR (SELECT proacl IS NULL FROM pg_proc WHERE oid='hocalist.verification_status()'::regprocedure) THEN
    RAISE EXCEPTION '${label}: verification_status ACL drift';
  END IF;
END $guard$;\n`;
await writeFile(new URL('preflight.sql', import.meta.url), guard(before, 'Preflight'));
await writeFile(new URL('apply.sql', import.meta.url), `BEGIN;\n${guard(before, 'Preflight')}${updated}\n${guard(after, 'Verify')}COMMIT;\n`);
await writeFile(new URL('verify.sql', import.meta.url), guard(after, 'Verify'));
await writeFile(new URL('containment.sql', import.meta.url), `BEGIN;\n${guard(after, 'Containment')}${original.replace('CREATE FUNCTION', 'CREATE OR REPLACE FUNCTION')}\n${guard(before, 'Verify')}COMMIT;\n`);

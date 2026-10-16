import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

// Generate reviewed replacements without editing historical migrations.
const entries = [
  ['marketplace/020_marketplace_foundation.sql', 'marketplace_normalize_offer', 'jsonb'],
  ['marketplace/020_marketplace_foundation.sql', 'marketplace_revision_json', 'uuid'],
  ['marketplace/023_multi_negotiation.sql', 'marketplace_command', 'text,text,jsonb'],
  ['meetings/040_meetings_foundation.sql', 'meeting_normalize_schedule', 'jsonb'],
  ['meetings/040_meetings_foundation.sql', 'meeting_revision_json', 'hocalist.meeting_schedule_revisions'],
  ['meetings/040_meetings_foundation.sql', 'meeting_propose', 'uuid,jsonb,text'],
  ['meetings/040_meetings_foundation.sql', 'meeting_reschedule_propose', 'uuid,jsonb,bigint,text'],
];
const hash = body => createHash('md5').update(body.replace(/\r\n/g, '\n')).digest('hex');
const before = [], after = [], statements = [];
for (const [file, name, args] of entries) {
  const source = await readFile(new URL(`../${file}`, import.meta.url), 'utf8');
  const statement = source.match(new RegExp(`CREATE(?: OR REPLACE)? FUNCTION hocalist\\.${name}\\([\\s\\S]*?\\$\\$;`))?.[0];
  if (!statement) throw Error(`Missing definition: ${name}`);
  const body = statement.match(/AS \$\$([\s\S]*)\$\$;/)[1];
  let fixed = body;
  if (name === 'marketplace_normalize_offer') {
    fixed = fixed.replace("'place_address','place_id'];", "'place_address','place_id','place_latitude','place_longitude'];");
    fixed = fixed.replace('  RETURN jsonb_build_object(', `  IF (p_input->>'place_latitude' IS NULL) <> (p_input->>'place_longitude' IS NULL)
    OR (p_input->>'place_latitude' IS NOT NULL AND (
      jsonb_typeof(p_input->'place_latitude') <> 'number'
      OR jsonb_typeof(p_input->'place_longitude') <> 'number')) THEN
    RAISE EXCEPTION 'invalid_place_coordinates' USING ERRCODE='P0001';
  END IF;
  IF p_input->>'place_latitude' IS NOT NULL AND (
    (p_input->>'place_latitude')::numeric NOT BETWEEN -90 AND 90
    OR (p_input->>'place_longitude')::numeric NOT BETWEEN -180 AND 180) THEN
    RAISE EXCEPTION 'invalid_place_coordinates' USING ERRCODE='P0001';
  END IF;
  RETURN jsonb_build_object(`);
    fixed = fixed.replace("'place_id', v_place_id", "'place_id', v_place_id,\n    'place_latitude', p_input->'place_latitude',\n    'place_longitude', p_input->'place_longitude'");
  } else if (name === 'meeting_normalize_schedule') {
    fixed = fixed.replace("'place_id', p_input->>'place_id'", "'place_id', p_input->>'place_id',\n    'place_latitude', p_input->'place_latitude',\n    'place_longitude', p_input->'place_longitude'");
  } else if (name.endsWith('revision_json')) {
    const row = name.startsWith('marketplace') ? 'v' : 'p_revision';
    fixed = fixed.replace(`'place_id', ${row}.place_id,`, `'place_id', ${row}.place_id,\n    'place_latitude', ${row}.place_latitude,\n    'place_longitude', ${row}.place_longitude,`);
  } else {
    fixed = fixed.replaceAll('place_id, proposed_by_user_id)', 'place_id, place_latitude, place_longitude, proposed_by_user_id)');
    fixed = fixed.replaceAll("v_norm->>'place_id',", "v_norm->>'place_id',\n      (v_norm->>'place_latitude')::double precision,\n      (v_norm->>'place_longitude')::double precision,");
  }
  if (fixed === body || !fixed.includes('place_latitude')) throw Error(`No repair: ${name}`);
  before.push({name,args,hash:hash(body)}); after.push({name,args,hash:hash(fixed)});
  statements.push(statement.replace(/^CREATE(?: OR REPLACE)? FUNCTION/, 'CREATE OR REPLACE FUNCTION').replace(body, () => fixed));
}
const guards = list => list.map(e => `DO $guard$ BEGIN
  IF (SELECT md5(replace(prosrc, E'\\r\\n', E'\\n')) FROM pg_catalog.pg_proc
    WHERE oid=to_regprocedure('hocalist.${e.name}(${e.args})')) IS DISTINCT FROM '${e.hash}' THEN
    RAISE EXCEPTION 'Confirmed-coordinate definition drift: ${e.name}';
  END IF;
  IF has_function_privilege('anon','hocalist.${e.name}(${e.args})','EXECUTE')
    OR has_function_privilege('service_role','hocalist.${e.name}(${e.args})','EXECUTE')
    OR has_function_privilege('authenticated','hocalist.${e.name}(${e.args})','EXECUTE')
      IS DISTINCT FROM ${['marketplace_command','meeting_propose','meeting_reschedule_propose'].includes(e.name)}
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure('hocalist.${e.name}(${e.args})')
      AND (a.grantee=0 OR a.is_grantable AND a.grantee<>p.proowner)) THEN
    RAISE EXCEPTION 'Confirmed-coordinate privilege drift: ${e.name}';
  END IF;
END $guard$;`).join('\n');
const columns = ['offer_revisions','meeting_schedule_revisions'].map(table => `ALTER TABLE hocalist.${table}
  ADD COLUMN place_latitude double precision,
  ADD COLUMN place_longitude double precision,
  ADD CONSTRAINT ${table}_place_coordinates CHECK (
    (place_latitude IS NULL AND place_longitude IS NULL) OR
    (place_latitude IS NOT NULL AND place_longitude IS NOT NULL
      AND place_latitude BETWEEN -90 AND 90 AND place_longitude BETWEEN -180 AND 180));`).join('\n');
await writeFile(new URL('./meeting-coordinates-preflight.sql',import.meta.url), `BEGIN READ ONLY;\n${guards(before)}\nROLLBACK;\n`);
await writeFile(new URL('./192_confirmed_meeting_coordinates.sql',import.meta.url), `-- Participant-only confirmed pins; no new grants or public coordinate projection.\nBEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='30s';\n${guards(before)}\n${columns}\n${statements.join('\n')}\n${guards(after)}\nCOMMIT;\n`);
await writeFile(new URL('./meeting-coordinates-verify.sql',import.meta.url), `BEGIN READ ONLY;\n${guards(after)}\nROLLBACK;\n`);

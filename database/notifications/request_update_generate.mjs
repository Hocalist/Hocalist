// Generate the reviewable local-only rollout bundle for the request-update
// producer draft. Opens a disposable PGlite database; never a live connection.
//
//   node database/notifications/request_update_generate.mjs
//
// Output: database/notifications/request-update-rollout/{preflight,apply,verify,containment}.sql
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../tests/fixture.mjs';

const base = new URL('./', import.meta.url);
const draftPath = '033_request_update_producer.sql';
const draft = await readFile(new URL(draftPath, base), 'utf8');

const block = (text, tag) => {
  const marker = `DO $${tag}$`;
  const start = text.indexOf(marker);
  const endMarker = `$${tag}$;`;
  const end = text.indexOf(endMarker, start) + endMarker.length;
  if (start < 0 || end <= start) throw new Error(`missing ${tag} block`);
  return text.slice(start, end);
};

const read = (path) => readFile(new URL(path, base), 'utf8');
const db = await createDisposableDb();
const quote = (value) => `'${String(value).replaceAll("'", "''")}'`;

const REPLACED_FUNCTIONS = [
  'notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)',
  'notification_preferences()',
  'notification_preferences_update(jsonb)',
  'notification_recipient_allowed(uuid)',
];

const functionState = async (signature) => {
  const rows = (
    await db.query(
      `SELECT md5(replace(pg_get_functiondef(p.oid), chr(13), '')) AS hash
       FROM pg_proc p WHERE p.oid = to_regprocedure($1)`,
      [`hocalist.${signature}`],
    )
  ).rows;
  const roles = (
    await db.query(
      `SELECT rolname FROM pg_roles
       WHERE rolname IN ('anon','authenticated','service_role')
         AND has_function_privilege(rolname, $1, 'EXECUTE')
       ORDER BY 1`,
      [`hocalist.${signature}`],
    )
  ).rows.map((row) => row.rolname);
  return { hash: rows[0]?.hash ?? null, roles };
};

const kindConstraintState = async () => {
  const rows = (
    await db.query(
      `SELECT pg_get_constraintdef(oid) AS definition
       FROM pg_constraint
       WHERE conrelid = 'hocalist.notifications'::regclass
         AND conname = 'notifications_kind_check'`,
    )
  ).rows;
  return rows[0]?.definition ?? null;
};

const triggerState = async (table, name) => {
  const rows = (
    await db.query(
      `SELECT md5(pg_get_triggerdef(t.oid)) AS hash, t.tgenabled
       FROM pg_trigger t
       WHERE t.tgrelid = to_regclass($1) AND t.tgname = $2 AND NOT t.tgisinternal`,
      [`hocalist.${table}`, name],
    )
  ).rows;
  return rows[0] ?? null;
};

try {
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  await db.exec(await read('../provider-rollout/apply.sql'));
  await db.exec(await read('../chat/010_chat_foundation.sql'));
  await db.exec(await read('../marketplace/020_marketplace_foundation.sql'));
  await db.exec(await read('../meetings/040_meetings_foundation.sql'));
  await db.exec(await read('./030_notification_inbox.sql'));
  await db.exec(await read('./producers-rollout/apply.sql'));

  const before = {};
  for (const signature of REPLACED_FUNCTIONS) {
    before[signature] = await functionState(signature);
  }
  const kindConstraintBefore = await kindConstraintState();
  if (kindConstraintBefore == null || kindConstraintBefore.includes('request_update')) {
    throw new Error('unexpected notifications kind constraint in the baseline');
  }
  const leadsColumnBefore = (
    await db.query(
      `SELECT count(*)::int AS n FROM pg_attribute
       WHERE attrelid = 'hocalist.notification_preferences'::regclass
         AND attname = 'leads' AND NOT attisdropped`,
    )
  ).rows[0].n;
  const triggerBefore = await triggerState('requests', 'notification_request_update');
  if (leadsColumnBefore !== 0 || triggerBefore != null) {
    throw new Error('request-update producer already present in the baseline');
  }

  await db.exec(
    draft.replace(/^BEGIN;\s*$/m, '').replace(/^COMMIT;\s*$/m, ''),
  );

  const kindConstraintAfter = await kindConstraintState();
  if (kindConstraintAfter == null || !kindConstraintAfter.includes('request_update')) {
    throw new Error('notifications kind constraint was not extended');
  }

  const after = {};
  for (const signature of [
    'notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb)',
    'notification_preferences()',
    'notification_preferences_update(jsonb)',
    'notification_on_request_update()',
  ]) {
    after[signature] = await functionState(signature);
  }
  const triggerAfter = await triggerState('requests', 'notification_request_update');
  if (triggerAfter == null) throw new Error('producer trigger missing after draft');
  const leadsColumnAfter = (
    await db.query(
      `SELECT attnotnull, pg_get_expr(d.adbin, d.adrelid) AS default_expr
       FROM pg_attribute a
       LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
       WHERE a.attrelid = 'hocalist.notification_preferences'::regclass
         AND a.attname = 'leads' AND NOT a.attisdropped`,
    )
  ).rows[0];
  if (!leadsColumnAfter?.attnotnull || leadsColumnAfter.default_expr !== 'true') {
    throw new Error('leads column is not NOT NULL DEFAULT true');
  }

  const guardBlock = block(draft, 'request_update_producer_guard');
  const postapplyBlock = block(draft, 'hocalist_request_update_producer_postapply');

  const driftChecks = Object.entries(before)
    .map(
      ([signature, state]) =>
        `IF to_regprocedure(${quote(`hocalist.${signature}`)}) IS NULL
     OR md5(replace(pg_get_functiondef(to_regprocedure(${quote(`hocalist.${signature}`)})), chr(13), '')) <> ${quote(state.hash)} THEN
  RAISE EXCEPTION 'Prerequisite function drift: ${signature}';
END IF;`,
    )
    .join('\n');
  const driftGuard = `DO $request_update_drift_guard$
BEGIN
${driftChecks}
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'hocalist.notifications'::regclass
      AND conname = 'notifications_kind_check'
      AND pg_get_constraintdef(oid) = ${quote(kindConstraintBefore)}) THEN
    RAISE EXCEPTION 'Notification kind constraint drift';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'hocalist.notification_preferences'::regclass
      AND attname = 'leads' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'leads preference column already exists';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'hocalist.requests'::regclass
      AND tgname = 'notification_request_update' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'request-update producer trigger already exists';
  END IF;
END
$request_update_drift_guard$;`;

  const stateChecks = [
    ...Object.entries(after).map(
      ([signature, state]) =>
        `IF to_regprocedure(${quote(`hocalist.${signature}`)}) IS NULL
     OR md5(replace(pg_get_functiondef(to_regprocedure(${quote(`hocalist.${signature}`)})), chr(13), '')) <> ${quote(state.hash)} THEN
  RAISE EXCEPTION 'Function drift: ${signature}';
END IF;
IF has_function_privilege('anon', ${quote(`hocalist.${signature}`)}, 'EXECUTE') IS DISTINCT FROM ${state.roles.includes('anon')}
   OR has_function_privilege('authenticated', ${quote(`hocalist.${signature}`)}, 'EXECUTE') IS DISTINCT FROM ${state.roles.includes('authenticated')}
   OR has_function_privilege('service_role', ${quote(`hocalist.${signature}`)}, 'EXECUTE') IS DISTINCT FROM ${state.roles.includes('service_role')} THEN
  RAISE EXCEPTION 'Function privilege drift: ${signature}';
END IF;`,
    ),
    `IF NOT EXISTS (
  SELECT 1 FROM pg_constraint
  WHERE conrelid = 'hocalist.notifications'::regclass
    AND conname = 'notifications_kind_check'
    AND pg_get_constraintdef(oid) = ${quote(kindConstraintAfter)}) THEN
  RAISE EXCEPTION 'Notification kind constraint drift';
END IF;`,
    `IF NOT EXISTS (
  SELECT 1 FROM pg_trigger
  WHERE tgrelid = 'hocalist.requests'::regclass
    AND tgname = 'notification_request_update' AND tgenabled = ${quote(triggerAfter.tgenabled)}
    AND md5(pg_get_triggerdef(oid)) = ${quote(triggerAfter.hash)}) THEN
  RAISE EXCEPTION 'Trigger drift: notification_request_update';
END IF;`,
    `IF NOT EXISTS (
  SELECT 1 FROM pg_attribute a
  JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE a.attrelid = 'hocalist.notification_preferences'::regclass
    AND a.attname = 'leads' AND a.attnotnull AND NOT a.attisdropped
    AND pg_get_expr(d.adbin, d.adrelid) = 'true') THEN
  RAISE EXCEPTION 'leads preference column drift';
END IF;`,
  ].join('\n');
  const stateVerify = `DO $request_update_state_verify$
BEGIN
${stateChecks}
END
$request_update_state_verify$;`;

  const preflightSql = `BEGIN READ ONLY;
${guardBlock}
${driftGuard}
ROLLBACK;
`;
  const applySql = `-- Hocalist request-update producer rollout: guarded single-transaction
-- apply of the request-update lead producer (draft 033). This file is the
-- reviewed draft with this header; database/notifications/tests/
-- request_update_producer.test.mjs asserts the draft text is present verbatim.
--
-- Prerequisites already deployed and preserved (never re-run here): account
-- 003/004, push 007, notification inbox 030, producer 031, chat 010,
-- marketplace 020 and meetings 040. Recipients derive from committed offer
-- rows only.
--
-- On any drift or pre-existing producer object the guard aborts the whole
-- transaction; nothing is dropped, cascaded or overwritten.
${draft}
`;
  const verifySql = `BEGIN READ ONLY;
${postapplyBlock}
${stateVerify}
ROLLBACK;
`;
  const containmentSql = `BEGIN;
-- Contains the producer only: the trigger stops firing while the extended
-- kind constraint, functions and the optional leads topic remain installed.
DROP TRIGGER IF EXISTS notification_request_update ON hocalist.requests;
COMMIT;
`;

  const out = new URL('request-update-rollout/', base);
  await mkdir(out, { recursive: true });
  await writeFile(new URL('preflight.sql', out), preflightSql);
  await writeFile(new URL('apply.sql', out), applySql);
  await writeFile(new URL('verify.sql', out), verifySql);
  await writeFile(new URL('containment.sql', out), containmentSql);
  console.log('Generated request-update rollout: 1 replaced emitter, 1 topic column, 1 trigger; no live connection.');
} finally {
  await db.close();
}

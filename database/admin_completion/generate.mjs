// Generate the reviewable local-only admin completion bundle (160-169 range).
//
// Uses disposable PGlite only; never opens a live connection. The bundle is
// additive over the local checkpoint baseline: it adds administrator-only read
// contracts and creates no table, seeds no configuration and grants no
// configuration command.
//
// Prerequisites captured as exact function hashes and column checks:
//   marketplace 020 + 023, support 070, commercial 090-094, trust 120,
//   calls 110 and the September 26 upgrade chunks required by them.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { applyAdminBaseline } from './tests/fixture.mjs';

const base = new URL('./', import.meta.url);
const quote = (x) => "'" + x.replaceAll("'", "''") + "'";
const read = (name) => readFile(new URL(name, base), 'utf8');

const chunks = [
  '160_admin_commercial_config.sql',
  '161_admin_review_queue.sql',
  '162_admin_event_operations.sql',
  '163_admin_audit_feed.sql',
];

// Functions whose reviewed definition this bundle sits on. A change there must
// be reviewed before this bundle is applied.
const prerequisiteFunctions = [
  'hocalist.marketplace_assert_admin(uuid)',
  'hocalist.credit_admin_command(text,text,jsonb)',
  'hocalist.admin_trust_command(text,text,jsonb)',
];

// Required columns prove the dependency shape, not only table existence.
const prerequisiteColumns = [
  ['credit_deposit_options', 'revision'],
  ['credit_deposit_options', 'sort_order'],
  ['credit_deposit_options', 'rate_version'],
  ['reward_policy', 'late_window_hours'],
  ['reward_policy', 'rule_version'],
  ['stripe_test_inbox', 'attempts'],
  ['stripe_test_inbox', 'available_at'],
  ['stripe_test_inbox', 'last_error'],
  ['verification_submissions', 'evidence_media_ids'],
  ['verification_submissions', 'revision'],
  ['account_restrictions', 'revision'],
  ['account_restrictions', 'revoked_by'],
  ['restriction_appeals', 'revision'],
  ['withdrawal_events', 'actor'],
];

// New administrator-only reads created by this bundle.
const newFunctions = [
  'hocalist.admin_commercial_config()',
  'hocalist.admin_review_queue(integer,text,text,text,text,text,text)',
  'hocalist.admin_evidence_reference(uuid,uuid)',
  'hocalist.admin_failed_events(integer,text,text,text)',
  'hocalist.admin_failed_event_detail(text)',
  'hocalist.admin_audit_feed(integer,text,text,uuid,text)',
];

const fnHashQuery =
  "SELECT p.oid::regprocedure::text AS signature, md5(replace(pg_get_functiondef(p.oid),chr(13),'')) AS hash " +
  "FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='hocalist'";

const db = await applyAdminBaseline();
try {
  const beforeRows = (await db.query(fnHashQuery)).rows;
  const beforeMap = new Map(beforeRows.map((row) => [row.signature, row.hash]));
  const before = prerequisiteFunctions.map((signature) => {
    const hash = beforeMap.get(signature);
    if (!hash) throw new Error(`missing prerequisite function ${signature}`);
    return { signature, hash };
  });
  for (const [table, column] of prerequisiteColumns) {
    const found = (
      await db.query(
        "SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name=$1 AND column_name=$2",
        [table, column],
      )
    ).rows;
    if (!found.length) throw new Error(`missing prerequisite column hocalist.${table}.${column}`);
  }
  for (const signature of newFunctions) {
    const found = (await db.query('SELECT to_regprocedure($1) AS oid', [signature])).rows[0].oid;
    if (found) throw new Error(`admin completion object already installed: ${signature}`);
  }

  for (const name of chunks) {
    await db.exec(await read(name));
  }

  const afterRows = (await db.query(fnHashQuery)).rows;
  const afterMap = new Map(afterRows.map((row) => [row.signature, row.hash]));
  const after = newFunctions.map((signature) => {
    const hash = afterMap.get(signature);
    if (!hash) throw new Error(`bundle did not create ${signature}`);
    return { signature, hash };
  });

  const preflight =
    'DO $guard$ BEGIN\n' +
    before
      .map(
        (f) =>
          `IF to_regprocedure(${quote(f.signature)}) IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure(${quote(f.signature)})),chr(13),''))<>${quote(f.hash)} THEN RAISE EXCEPTION 'Prerequisite drift: ${f.signature}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    prerequisiteColumns
      .map(
        ([table, column]) =>
          `IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name=${quote(table)} AND column_name=${quote(column)}) THEN RAISE EXCEPTION 'Prerequisite column missing: hocalist.${table}.${column}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    newFunctions
      .map(
        (signature) =>
          `IF to_regprocedure(${quote(signature)}) IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: ${signature}'; END IF;`,
      )
      .join('\n') +
    '\nEND $guard$;\n';

  const verify =
    'DO $verify$ DECLARE f oid; r text; BEGIN\n' +
    after
      .map(
        (f) =>
          `f:=to_regprocedure(${quote(f.signature)});\nIF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>${quote(f.hash)} THEN RAISE EXCEPTION 'Function drift: ${f.signature}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    newFunctions
      .map(
        (signature) =>
          `FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure(${quote(signature)}),'EXECUTE') IS DISTINCT FROM (r='authenticated') THEN RAISE EXCEPTION 'Function privilege drift: ${signature} %',r; END IF; END LOOP;`,
      )
      .join('\n') +
    '\nEND $verify$;\n';

  const generated = [];
  for (const name of chunks) {
    const sql = await read(name);
    generated.push(
      sql.replace(/^BEGIN;\s*$/m, '').replace(/^COMMIT;\s*$/m, ''),
    );
  }

  await mkdir(new URL('rollout/', base), { recursive: true });
  await writeFile(new URL('rollout/preflight.sql', base), 'BEGIN READ ONLY;\n' + preflight + 'ROLLBACK;\n');
  await writeFile(
    new URL('rollout/apply.sql', base),
    "BEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='120s';\n" +
      preflight +
      generated.join('\n') +
      '\n' +
      verify +
      'COMMIT;\n',
  );
  await writeFile(new URL('rollout/verify.sql', base), 'BEGIN READ ONLY;\n' + verify + 'ROLLBACK;\n');
  await writeFile(
    new URL('rollout/containment.sql', base),
    '-- Containment for a suspicious apply: remove every administrator read this\n' +
      '-- bundle added. No table, row, ledger or audit history is deleted.\n' +
      'BEGIN;\n' +
      newFunctions
        .map((signature) => `REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC,anon,authenticated,service_role;`)
        .join('\n') +
      '\nCOMMIT;\n',
  );
  console.log(
    `Generated admin completion bundle: ${chunks.length} migrations, ` +
      `${after.length} verified functions, ${prerequisiteColumns.length} prerequisite column checks; no live connection.`,
  );
} finally {
  await db.close();
}

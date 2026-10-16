// Generate the reviewable commercial_completion upgrade bundle (180-184).
//
// Uses the disposable PGlite fixture only; never opens a live connection. The
// generated preflight hashes the exact pre-upgrade status of every replaced
// function, the verify block re-hashes the installed bodies and asserts RLS,
// table privileges and per-signature EXECUTE grants, and containment revokes
// every capability the bundle adds without deleting ledger history.
import { mkdir, writeFile } from 'node:fs/promises';
import { createCommercialDb } from './tests/fixture.mjs';

const base = new URL('./', import.meta.url);
const quote = (x) => "'" + x.replaceAll("'", "''") + "'";

const migrations = [
  '180_entitlement_lifecycle.sql',
  '181_reconciliation_orchestration.sql',
  '182_reversals.sql',
  '183_payout_execution.sql',
  '184_commercial_reads.sql',
];

const newTables = [
  'entitlement_policy',
  'reconciliation_policy',
  'reconciliation_runs',
  'reversal_policy',
  'payment_reversals',
  'ledger_corrections',
  'reversal_events',
  'payout_policy',
  'payout_attempts',
];

// Table names that must exist before the bundle applies.
const prerequisiteTables = [
  'profiles', 'memberships', 'role_profiles', 'platform_admins',
  'marketplace_plan_limits', 'seller_entitlements', 'marketplace_receipts',
  'requests', 'offers', 'conversations', 'meetings', 'sale_confirmations',
  'credit_batches', 'credit_targets', 'credit_entries', 'buyer_rewards',
  'withdrawal_requests',
];

// Client-facing reads/commands with their reviewed grant set.
const clientGrants = {
  'hocalist.account_entitlement()': ['authenticated'],
  'hocalist.entitlement_plan_preview(text)': ['authenticated'],
  'hocalist.entitlement_admin_command(text,text,jsonb)': ['authenticated'],
  'hocalist.reconciliation_admin_command(text,jsonb)': ['authenticated'],
  'hocalist.admin_reconciliation_overview(integer)': ['authenticated'],
  'hocalist.reversal_admin_command(text,text,jsonb)': ['authenticated'],
  'hocalist.commercial_reversal_status()': ['authenticated'],
  'hocalist.admin_reversal_queue(integer,uuid)': ['authenticated'],
  'hocalist.payout_admin_command(text,jsonb)': ['authenticated'],
  'hocalist.admin_payout_reconciliation_queue(integer)': ['authenticated'],
  'hocalist.commercial_credit_wallet()': ['authenticated'],
  'hocalist.commercial_reward_wallet()': ['authenticated'],
  'hocalist.commercial_sale_history(timestamptz,uuid)': ['authenticated'],
  'hocalist.commercial_sale_detail(uuid)': ['authenticated'],
};
// Service-role execution only.
const serviceOnly = [
  'hocalist.commercial_reconcile_sweep(integer,text)',
  'hocalist.reversal_open_internal(text,text,text,text,bigint,uuid,uuid,uuid,text)',
  'hocalist.payout_claim_internal(integer,text)',
  'hocalist.payout_lease_expire_internal(integer)',
  'hocalist.payout_reconcile_batch_internal(integer)',
  'hocalist.payout_settle_internal(uuid,text,text,text)',
  'hocalist.payout_poll_batch_internal(integer)',
];
// Internal helpers: no client or service grant.
const serverOnly = [
  'hocalist.entitlement_readings_internal(uuid)',
  'hocalist.entitlement_resolve_internal(uuid)',
  'hocalist.credit_reconcile_target_internal(uuid)',
  'hocalist.withdrawal_available_minor(uuid)',
  'hocalist.commercial_reward_hold_minor(uuid)',
  'hocalist.reward_causal_unspent_internal(uuid)',
  'hocalist.reward_identity_free_internal(uuid)',
  'hocalist.reward_disputed_pool_free_internal(uuid)',
];
// Reviewed baseline functions whose bodies this bundle replaces. Preflight
// verifies the exact pre-upgrade body; verify re-hashes the installed body.
const replaced = [
  'hocalist.withdrawal_available_minor(uuid)',
  'hocalist.withdrawal_request(text,bigint)',
  'hocalist.marketplace_seller_plan(uuid)',
  'hocalist.marketplace_store_limit(uuid)',
  'hocalist.marketplace_weekly_target_limit(uuid)',
];
const allFunctions = Object.keys(clientGrants).concat(serviceOnly, serverOnly);

const fnHashQuery =
  "SELECT md5(replace(pg_get_functiondef(to_regprocedure($1)),chr(13),'')) AS hash";

const db = await createCommercialDb({ completion: false });
try {
  const hashOf = async (signatures) => {
    const out = [];
    for (const signature of signatures) {
      const rows = (await db.query(fnHashQuery, [signature])).rows;
      const hash = rows[0]?.hash;
      if (!hash) throw new Error(`missing prerequisite function ${signature}`);
      out.push({ signature, hash });
    }
    return out;
  };
  const before = await hashOf(replaced);
  const beforeTables = new Set(
    (await db.query("SELECT tablename FROM pg_tables WHERE schemaname='hocalist'")).rows
      .map((r) => r.tablename),
  );
  for (const table of prerequisiteTables) {
    if (!beforeTables.has(table)) throw new Error(`missing prerequisite table ${table}`);
  }
  for (const table of newTables) {
    if (beforeTables.has(table)) throw new Error(`upgrade table already present: ${table}`);
  }

  const chunks = [];
  for (const name of migrations) {
    const sql = await readUrl(new URL(name, base));
    await db.exec(sql);
    chunks.push(
      sql
        .replace(/^BEGIN;\s*$/m, '')
        .replace(/^COMMIT;\s*$/m, '')
        .trim(),
    );
  }

  const after = await hashOf(allFunctions);
  const afterTables = new Set(
    (await db.query("SELECT tablename FROM pg_tables WHERE schemaname='hocalist'")).rows
      .map((r) => r.tablename),
  );
  for (const table of newTables) {
    if (!afterTables.has(table)) throw new Error(`upgrade did not create ${table}`);
  }

  const preflightBody =
    'DO $guard$ BEGIN\n' +
    before
      .map(
        (f) =>
          `IF to_regprocedure(${quote(f.signature)}) IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure(${quote(f.signature)})),chr(13),''))<>${quote(f.hash)} THEN RAISE EXCEPTION 'Prerequisite drift: ${f.signature}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    newTables
      .map(
        (t) =>
          `IF to_regclass('hocalist.${t}') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: ${t}'; END IF;`,
      )
      .join('\n') +
    '\nEND $guard$;\n';

  const verifyBody =
    'DO $verify$ DECLARE f oid; r text; priv text; BEGIN\n' +
    after
      .map(
        (f) =>
          `f:=to_regprocedure(${quote(f.signature)});\nIF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>${quote(f.hash)} THEN RAISE EXCEPTION 'Function drift: ${f.signature}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    newTables
      .map(
        (t) =>
          `IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.${t}')),false) THEN RAISE EXCEPTION 'Missing RLS: ${t}'; END IF;\nFOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.${t}',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: ${t} % %',r,priv; END IF; END LOOP; END LOOP;`,
      )
      .join('\n') +
    '\n' +
    Object.entries(clientGrants)
      .map(
        ([signature, roles]) =>
          `FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure(${quote(signature)}),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[${roles.map(quote).join(',')}]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: ${signature} %',r; END IF; END LOOP;`,
      )
      .join('\n') +
    '\n' +
    serviceOnly
      .map(
        (signature) =>
          `FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure(${quote(signature)}),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: ${signature}'; END IF; END LOOP;\nIF NOT has_function_privilege('service_role',to_regprocedure(${quote(signature)}),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: ${signature}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    serverOnly
      .map(
        (signature) =>
          `FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure(${quote(signature)}),'EXECUTE') THEN RAISE EXCEPTION 'Internal helper exposed: ${signature}'; END IF; END LOOP;`,
      )
      .join('\n') +
    '\nEND $verify$;\n';

  const containment =
    'BEGIN;\n' +
    '-- Revoke every client and service capability added by this bundle. Ledger,\n' +
    '-- reversal, reconciliation and payout history rows are preserved.\n' +
    allFunctions
      .map(
        (signature) =>
          `REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC, anon, authenticated, service_role;`,
      )
      .join('\n') +
    '\nCOMMIT;\n';

  await mkdir(new URL('rollout/', base), { recursive: true });
  await writeFile(new URL('rollout/preflight.sql', base), 'BEGIN READ ONLY;\n' + preflightBody + 'ROLLBACK;\n');
  await writeFile(
    new URL('rollout/apply.sql', base),
    "BEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='120s';\n" +
      preflightBody +
      '\n' +
      chunks.join('\n\n') +
      '\n' +
      verifyBody +
      'COMMIT;\n',
  );
  await writeFile(new URL('rollout/verify.sql', base), 'BEGIN READ ONLY;\n' + verifyBody + 'ROLLBACK;\n');
  await writeFile(new URL('rollout/containment.sql', base), containment);

  // Full post-upgrade hash map for review and drift inspection.
  await writeFile(
    new URL('rollout/functions.json', base),
    JSON.stringify(
      Object.fromEntries(after.map((f) => [f.signature, { hash: f.hash }])),
      null,
      2,
    ) + '\n',
  );
  console.log(
    `commercial_completion bundle generated: ${newTables.length} tables, ${allFunctions.length} functions, ${migrations.length} migrations`,
  );
} finally {
  await db.close();
}

async function readUrl(url) {
  const { readFile } = await import('node:fs/promises');
  return readFile(url, 'utf8');
}

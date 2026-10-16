// Generate the reviewable local-only website-completion bundle (waitlist 170
// and billing-portal contract 171). Disposable PGlite only; never opens a live
// connection.
//
// Baseline prerequisites: Hocalist signup seed (profiles) plus the provider
// rollout receipt/subscription foundation (005/006 via provider-rollout
// apply.sql as loaded by the shared fixture).
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { setup } from '../outcomes/tests/fixture.mjs';

const base = new URL('./', import.meta.url);
const read = (path) => readFile(new URL(path, base), 'utf8');
const quote = (value) => "'" + value.replaceAll("'", "''") + "'";

const migrations = [
  '../website_completion/170_website_waitlist.sql',
  '../website_completion/171_website_billing_portal.sql',
  '../website_completion/172_website_purchase_status.sql',
  '../website_completion/173_website_checkout_context.sql',
];

// Reviewed commercial/provider baseline beyond what setup(false) applies.
const baseline = [
  '../marketplace/021_request_coordinates.sql',
  '../marketplace/023_multi_negotiation.sql',
  '../outcomes/080_sale_confirmation.sql',
  '../commercial/090_credit_batches.sql',
  '../commercial/091_buyer_rewards.sql',
  '../commercial/092_credit_settlement.sql',
  '../commercial/094_deposit_checkout.sql',
];

// Prerequisite objects that must exist before the upgrade (checked by name).
const prerequisiteRelations = [
  'hocalist.profiles',
  'hocalist.stripe_test_plans',
  'hocalist.stripe_test_customers',
  'hocalist.stripe_test_checkouts',
  'hocalist.stripe_test_subscriptions',
  'hocalist.credit_deposit_options',
  'hocalist.credit_batches',
];

// Prerequisite columns (094 adds the checkout kind contract).
const prerequisiteColumns = [
  { table: 'stripe_test_checkouts', column: 'kind' },
];

// Relations created by the upgrade (must be absent before, RLS-locked after).
const newTables = [
  'website_waitlist_signups',
  'website_waitlist_admissions',
  'website_waitlist_config',
];

// Client-facing RPCs added by the upgrade and their reviewed role grants.
const clientGrants = {
  'hocalist.website_waitlist_join(text,text,text,text,text)': ['anon', 'authenticated'],
  'hocalist.website_purchase_status(uuid)': ['authenticated'],
};
// Server-only helpers: service-role execute, never a client grant.
const serviceOnly = [
  'hocalist.stripe_test_portal_access(uuid)',
  'hocalist.website_waitlist_configure(text)',
  'hocalist.website_waitlist_set_caps(integer,integer)',
  'hocalist.website_checkout_context(text)',
];

const fnHashQuery =
  "SELECT p.oid::regprocedure::text AS signature, md5(replace(pg_get_functiondef(p.oid),chr(13),'')) AS hash " +
  "FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='hocalist'";

const db = await setup(false);
const hashOf = async (signatures) => {
  const rows = (await db.query(fnHashQuery)).rows;
  const map = new Map(rows.map((row) => [row.signature, row.hash]));
  return signatures.map((signature) => {
    const hash = map.get(signature);
    if (!hash) throw new Error(`missing function after apply ${signature}`);
    return { signature, hash };
  });
};
const tableSet = async () =>
  new Set(
    (await db.query("SELECT tablename FROM pg_tables WHERE schemaname='hocalist'")).rows
      .map((row) => row.tablename),
  );

try {
  for (const path of baseline) await db.exec(await read(path));
  for (const relation of prerequisiteRelations) {
    const found = (await db.query('SELECT to_regclass($1) AS oid', [relation])).rows[0].oid;
    if (!found) throw new Error(`missing prerequisite relation ${relation}`);
  }
  for (const column of prerequisiteColumns) {
    const found = (await db.query(
      `SELECT 1 FROM information_schema.columns
       WHERE table_schema='hocalist' AND table_name=$1 AND column_name=$2`,
      [column.table, column.column],
    )).rows.length;
    if (!found) {
      throw new Error(`missing prerequisite column ${column.table}.${column.column}`);
    }
  }

  const chunks = [];
  for (const path of migrations) {
    const sql = await read(path);
    await db.exec(sql);
    chunks.push(sql.replace(/^BEGIN;\s*$/m, '').replace(/^COMMIT;\s*$/m, ''));
  }

  const after = await hashOf(
    Object.keys(clientGrants).concat(serviceOnly),
  );
  const afterTables = await tableSet();
  for (const table of newTables) {
    if (!afterTables.has(table)) throw new Error(`upgrade did not create ${table}`);
  }

  const preflight =
    'DO $guard$ BEGIN\n' +
    prerequisiteRelations
      .map(
        (relation) =>
          `IF to_regclass(${quote(relation)}) IS NULL THEN RAISE EXCEPTION 'Missing prerequisite relation: ${relation}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    prerequisiteColumns
      .map(
        (column) =>
          `IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='hocalist' AND table_name=${quote(column.table)} AND column_name=${quote(column.column)}) THEN RAISE EXCEPTION 'Missing prerequisite column: ${column.table}.${column.column}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    newTables
      .map(
        (table) =>
          `IF to_regclass('hocalist.${table}') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: ${table}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    Object.keys(clientGrants)
      .concat(serviceOnly)
      .map(
        (signature) =>
          `IF to_regprocedure(${quote(signature)}) IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: ${signature}'; END IF;`,
      )
      .join('\n') +
    '\nEND $guard$;\n';

  const verify =
    'DO $verify$ DECLARE f oid; r text; priv text; BEGIN\n' +
    after
      .map(
        (fn) =>
          `f:=to_regprocedure(${quote(fn.signature)});\nIF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>${quote(fn.hash)} THEN RAISE EXCEPTION 'Function drift: ${fn.signature}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    newTables
      .map(
        (table) =>
          `IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.${table}')),false) THEN RAISE EXCEPTION 'Missing RLS: ${table}'; END IF;\nFOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.${table}',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: ${table} % %',r,priv; END IF; END LOOP; END LOOP;`,
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
          `FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure(${quote(signature)}),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on server-only helper: ${signature}'; END IF; END LOOP;\nIF NOT has_function_privilege('service_role',to_regprocedure(${quote(signature)}),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: ${signature}'; END IF;`,
      )
      .join('\n') +
    '\nEND $verify$;\n';

  await mkdir(new URL('rollout/', base), { recursive: true });
  await writeFile(new URL('rollout/preflight.sql', base), 'BEGIN READ ONLY;\n' + preflight + 'ROLLBACK;\n');
  await writeFile(
    new URL('rollout/apply.sql', base),
    "BEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='60s';\n" +
      preflight +
      chunks.join('\n') +
      '\n' +
      verify +
      'COMMIT;\n',
  );
  await writeFile(new URL('rollout/verify.sql', base), 'BEGIN READ ONLY;\n' + verify + 'ROLLBACK;\n');
  await writeFile(
    new URL('rollout/containment.sql', base),
    '-- Containment for a suspicious apply: remove the public waitlist intake and\n' +
      '-- the service-role portal helper without deleting stored signups.\n' +
      '-- The waitlist table and its history stay in place; this is not a\n' +
      '-- destructive rollback and not a repair script for arbitrary drift.\n' +
      'BEGIN;\n' +
      Object.keys(clientGrants)
        .concat(serviceOnly)
        .map(
          (signature) =>
            `REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC,anon,authenticated,service_role;`,
        )
        .join('\n') +
      '\nCOMMIT;\n',
  );
  console.log(
    `Generated website-completion bundle: ${chunks.length} migrations, ${newTables.length} new table(s), ` +
      `${after.length} verified functions; no live connection.`,
  );
} finally {
  await db.close();
}

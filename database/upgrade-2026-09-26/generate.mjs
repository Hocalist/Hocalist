// Generate the reviewable local-only upgrade bundle for the September 26
// approved rules. Uses disposable PGlite only; never opens a live connection.
//
// Baseline prerequisites (captured as exact function hashes):
//   provider rollout (account 003/004, receipt 005, billing 006, push 007)
//   chat 010, marketplace 020 + 021, meetings 040, outcomes 080,
//   commercial 090 + 091, support 070.
//
// Upgrade chunks (applied in order):
//   marketplace 023, outcomes 081, commercial 092 + 093, chat 012, trust 120.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { setup } from '../outcomes/tests/fixture.mjs';

const base = new URL('./', import.meta.url);
const read = (path) => readFile(new URL(path, base), 'utf8');
const quote = (x) => "'" + x.replaceAll("'", "''") + "'";

// setup(false) already applies account/provider rollout, chat 010, marketplace
// 020 and meetings 040 (plus the shared synthetic seed).
const baseline = [
  '../marketplace/021_request_coordinates.sql',
  '../outcomes/080_sale_confirmation.sql',
  '../commercial/090_credit_batches.sql',
  '../commercial/091_buyer_rewards.sql',
  '../support/070_support_cases.sql',
  '../notifications/030_notification_inbox.sql',
  '../notifications/031_notification_producers.sql',
];
const upgrade = [
  '../marketplace/023_multi_negotiation.sql',
  '../outcomes/081_purchase_seller.sql',
  '../commercial/092_credit_settlement.sql',
  '../commercial/093_withdrawals.sql',
  '../chat/012_credit_qualification.sql',
  '../trust/120_review_workflow.sql',
  '../commercial/094_deposit_checkout.sql',
  '../notifications/034_outcome_review_producers.sql',
];

// Functions replaced by the upgrade: verify the pre-upgrade definition exactly.
const replaced = [
  'hocalist.marketplace_request_json(uuid)',
  'hocalist.marketplace_lead_json(uuid)',
  'hocalist.marketplace_offer_json(uuid)',
  'hocalist.marketplace_request(uuid)',
  'hocalist.marketplace_seller_leads(text,uuid,text,integer,text)',
  'hocalist.marketplace_command(text,text,jsonb)',
  'hocalist.sale_pin(uuid,text,text)',
  'hocalist.meeting_json(uuid)',
  'hocalist.credit_wallet()',
  'hocalist.reward_wallet()',
];
const dropped = ['hocalist.credit_reserve_internal(uuid,uuid,date,integer)'];

// New tables created by the upgrade (must be absent before, RLS-locked after).
const newTables = [
  'credit_deposit_options',
  'reward_policy',
  'conversation_credit_hook',
  'withdrawal_policy',
  'withdrawal_requests',
  'withdrawal_events',
  'verification_submissions',
  'health_review_notes',
  'account_restrictions',
  'restriction_appeals',
];

// New or replaced client-facing RPCs and their reviewed role grants.
const clientGrants = {
  'hocalist.credit_wallet()': ['authenticated'],
  'hocalist.reward_wallet()': ['authenticated'],
  'hocalist.credit_admin_command(text,text,jsonb)': ['authenticated'],
  'hocalist.withdrawal_status()': ['authenticated'],
  'hocalist.withdrawal_request(text,bigint)': ['authenticated'],
  'hocalist.admin_withdrawal_queue(integer,uuid)': ['authenticated'],
  'hocalist.credit_deposit_status()': ['authenticated'],
  'hocalist.verification_submit(text,jsonb)': ['authenticated'],
  'hocalist.verification_status()': ['authenticated'],
  'hocalist.account_health_status()': ['authenticated'],
  'hocalist.restriction_appeal_submit(text,jsonb)': ['authenticated'],
  'hocalist.admin_trust_queue(integer)': ['authenticated'],
  'hocalist.admin_trust_command(text,text,jsonb)': ['authenticated'],
  'hocalist.marketplace_command(text,text,jsonb)': ['authenticated'],
};
// Server-only helpers introduced by the upgrade: no client or service grant.
const serverOnly = [
  'hocalist.credit_authorize_target(uuid,uuid,uuid)',
  'hocalist.credit_qualify_conversation(uuid)',
  'hocalist.credit_release_offer(uuid)',
  'hocalist.credit_settle_purchase(uuid)',
  'hocalist.credit_reconcile_internal(uuid)',
  'hocalist.contact_verified(uuid)',
  'hocalist.trust_contact_verified(uuid)',
  'hocalist.notification_on_sale_confirmed()',
  'hocalist.notification_on_verification_decision()',
  'hocalist.notification_on_restriction()',
  'hocalist.notification_on_appeal_decision()',
  'hocalist.notification_on_withdrawal()',
];
// Stripe TEST deposit functions keep the same service-role-only boundary as
// 006 and must never gain a client grant.
const serviceOnly = [
  'hocalist.stripe_test_deposit_begin(uuid,uuid,uuid)',
  'hocalist.stripe_test_deposit_bind(uuid,text,text,text)',
  'hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text)',
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
    if (!hash) throw new Error(`missing prerequisite function ${signature}`);
    return { signature, hash };
  });
};
const tableSet = async () =>
  new Set((await db.query("SELECT tablename FROM pg_tables WHERE schemaname='hocalist'")).rows.map((r) => r.tablename));

try {
  for (const path of baseline) await db.exec(await read(path));
  const before = await hashOf(replaced);
  for (const signature of dropped) {
    const found = (await db.query('SELECT to_regprocedure($1) AS oid', [signature])).rows[0].oid;
    if (!found) throw new Error(`missing prerequisite function ${signature}`);
  }
  const beforeTables = await tableSet();

  const chunks = [];
  for (const path of upgrade) {
    const sql = await read(path);
    await db.exec(sql);
    chunks.push(sql.replace(/^BEGIN;\s*$/m, '').replace(/^COMMIT;\s*$/m, ''));
  }

  const after = await hashOf(
    Object.keys(clientGrants)
      .concat(serverOnly)
      .concat(serviceOnly)
      .concat(['hocalist.meeting_json(uuid)']),
  );
  const afterTables = await tableSet();
  for (const table of newTables) {
    if (!afterTables.has(table)) throw new Error(`upgrade did not create ${table}`);
  }

  const preflight =
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

  const verify =
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
    serverOnly
      .map(
        (signature) =>
          `FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure(${quote(signature)}),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: ${signature}'; END IF; END LOOP;`,
      )
      .join('\n') +
    '\n' +
    serviceOnly
      .map(
        (signature) =>
          `FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure(${quote(signature)}),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on provider helper: ${signature}'; END IF; END LOOP;\nIF NOT has_function_privilege('service_role',to_regprocedure(${quote(signature)}),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: ${signature}'; END IF;`,
      )
      .join('\n') +
    '\nEND $verify$;\n';

  await mkdir(new URL('rollout/', base), { recursive: true });
  await writeFile(new URL('rollout/preflight.sql', base), 'BEGIN READ ONLY;\n' + preflight + 'ROLLBACK;\n');
  await writeFile(
    new URL('rollout/apply.sql', base),
    "BEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='120s';\n" +
      preflight +
      chunks.join('\n') +
      '\n' +
      verify +
      'COMMIT;\n',
  );
  await writeFile(new URL('rollout/verify.sql', base), 'BEGIN READ ONLY;\n' + verify + 'ROLLBACK;\n');
  await writeFile(
    new URL('rollout/containment.sql', base),
    '-- Containment for a suspicious apply: remove every client capability the\n' +
      '-- upgrade added without deleting ledger, review or withdrawal history.\n' +
      '-- Replaced function bodies stay in place; this is not a destructive rollback.\n' +
      'BEGIN;\n' +
      Object.keys(clientGrants)
        .map((signature) => `REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC,anon,authenticated,service_role;`)
        .join('\n') +
      '\n' +
      serviceOnly
        .map((signature) => `REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC,anon,authenticated,service_role;`)
        .join('\n') +
      "\nREVOKE ALL ON FUNCTION hocalist.withdrawal_settle_internal(uuid,text,text,text,text) FROM service_role;\n" +
      "GRANT EXECUTE ON FUNCTION hocalist.marketplace_command(text,text,jsonb) TO authenticated;\n" +
      'COMMIT;\n',
  );
  console.log(
    `Generated upgrade bundle: ${chunks.length} migrations, ${newTables.length} new tables, ` +
      `${after.length} verified functions; no live connection.`,
  );
} finally {
  await db.close();
}

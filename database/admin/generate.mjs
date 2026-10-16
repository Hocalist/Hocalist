// Generate the guarded admin 061-063 reads rollout bundle.
//
// Runs against disposable PGlite only; never opens a live connection. The
// bundle is additive on top of the deployed admin 060 reads, the remaining
// foundation (080/090/091/100/110), notifications 030/032 and the
// provider/account/chat/marketplace/meeting baseline.
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../tests/fixture.mjs';
import {
  absenceGuard,
  driftGuard,
  functionHashes,
  functionVerify,
  migrationBody,
  presenceGuard,
  writeBundle,
} from '../tests/rollout_bundle.mjs';

const base = new URL('./', import.meta.url);
const read = (path) => readFile(new URL(path, base), 'utf8');

const BASELINE = [
  '../provider-rollout/apply.sql',
  '../chat/010_chat_foundation.sql',
  '../marketplace/020_marketplace_foundation.sql',
  '../meetings/040_meetings_foundation.sql',
  '../outcomes/080_sale_confirmation.sql',
  '../commercial/090_credit_batches.sql',
  '../commercial/091_buyer_rewards.sql',
  '../notifications/030_notification_inbox.sql',
  '../notifications/032_push_queue_bridge.sql',
  '../calls/110_call_signaling.sql',
  './060_admin_reads.sql',
];

const MIGRATIONS = [
  '061_admin_ledger_reads.sql',
  '062_admin_delivery_reads.sql',
  '063_admin_call_audit.sql',
];

const PREREQUISITE_FUNCTIONS = [
  'hocalist.admin_records(text,integer,uuid,text,text)',
  'hocalist.admin_overview()',
  'hocalist.marketplace_assert_admin(uuid)',
];
const PREREQUISITE_RELATIONS = [
  { test: "to_regclass('hocalist.credit_batches') IS NOT NULL", label: 'hocalist.credit_batches' },
  { test: "to_regclass('hocalist.credit_targets') IS NOT NULL", label: 'hocalist.credit_targets' },
  { test: "to_regclass('hocalist.buyer_rewards') IS NOT NULL", label: 'hocalist.buyer_rewards' },
  { test: "to_regclass('hocalist.push_deliveries') IS NOT NULL", label: 'hocalist.push_deliveries' },
  { test: "to_regclass('hocalist.call_settings_audit') IS NOT NULL", label: 'hocalist.call_settings_audit' },
];
const ABSENT_OBJECTS = [
  { test: "to_regprocedure('hocalist.admin_credit_summary(integer,uuid)') IS NOT NULL", label: 'hocalist.admin_credit_summary(integer,uuid)' },
  { test: "to_regprocedure('hocalist.admin_reward_summary(integer,uuid)') IS NOT NULL", label: 'hocalist.admin_reward_summary(integer,uuid)' },
  { test: "to_regprocedure('hocalist.admin_credit_detail(uuid)') IS NOT NULL", label: 'hocalist.admin_credit_detail(uuid)' },
  { test: "to_regprocedure('hocalist.admin_delivery_overview()') IS NOT NULL", label: 'hocalist.admin_delivery_overview()' },
  { test: "to_regprocedure('hocalist.admin_call_settings_history()') IS NOT NULL", label: 'hocalist.admin_call_settings_history()' },
];
const INSTALLED_FUNCTIONS = [
  'hocalist.admin_credit_summary(integer,uuid)',
  'hocalist.admin_reward_summary(integer,uuid)',
  'hocalist.admin_credit_detail(uuid)',
  'hocalist.admin_delivery_overview()',
  'hocalist.admin_call_settings_history()',
];
const GRANTS = {
  'hocalist.admin_records(text,integer,uuid,text,text)': ['authenticated'],
  'hocalist.admin_overview()': ['authenticated'],
  'hocalist.admin_credit_summary(integer,uuid)': ['authenticated'],
  'hocalist.admin_reward_summary(integer,uuid)': ['authenticated'],
  'hocalist.admin_credit_detail(uuid)': ['authenticated'],
  'hocalist.admin_delivery_overview()': ['authenticated'],
  'hocalist.admin_call_settings_history()': ['authenticated'],
};

const db = await createDisposableDb();
try {
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  for (const path of BASELINE) await db.exec(await read(path));

  const before = await functionHashes(db, PREREQUISITE_FUNCTIONS);
  const chunks = [];
  for (const migration of MIGRATIONS) {
    const text = await read(`./${migration}`);
    await db.exec(text);
    chunks.push(`-- ${migration}\n${migrationBody(text, migration)}`);
  }
  const after = await functionHashes(db, INSTALLED_FUNCTIONS);

  const preflight = [
    '-- Admin 060 plus deployed credit/reward, push and call prerequisites; targets absent.',
    presenceGuard(PREREQUISITE_RELATIONS),
    driftGuard(before),
    absenceGuard(ABSENT_OBJECTS),
  ].join('\n');
  const verify = [
    '-- 060 stays intact and the new read contracts carry the exact admin-only grants.',
    functionVerify(new Map([...before, ...after]), GRANTS),
  ].join('\n');
  const containment = [
    '-- Revokes the read contracts this bundle added; 060 and all ledger, queue and',
    '-- audit rows stay in place, so this is not a destructive rollback.',
    'BEGIN;',
    ...INSTALLED_FUNCTIONS.map(
      (signature) => `REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC,anon,authenticated,service_role;`,
    ),
    'COMMIT;',
  ].join('\n');

  await writeBundle(base, {
    generator: 'database/admin/generate.mjs',
    title: 'Guarded admin 061-063 reads rollout.',
    preflight,
    body: chunks.join('\n'),
    verify,
    containment,
  });
  console.log(`Generated admin 061-063 bundle: ${after.size} verified read functions; no live connection.`);
} finally {
  await db.close();
}

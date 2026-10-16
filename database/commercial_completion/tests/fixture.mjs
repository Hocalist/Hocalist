// Disposable-PGlite fixture for the commercial_completion package (180-189).
//
// Applies the reviewed baseline (account, provider, chat, marketplace,
// meetings, outcomes, commercial 090-093), then the package migrations. PGlite
// is single-connection deterministic proof only; it is never concurrency or
// live-JWT proof. See tests/concurrency.test.mjs for the opt-in real-PostgreSQL
// harness.
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

const BASE = [
  '../../provider-rollout/apply.sql',
  '../../chat/010_chat_foundation.sql',
  '../../marketplace/020_marketplace_foundation.sql',
  '../../marketplace/021_request_coordinates.sql',
  '../../marketplace/023_multi_negotiation.sql',
  '../../meetings/040_meetings_foundation.sql',
  '../../outcomes/080_sale_confirmation.sql',
  '../../outcomes/081_purchase_seller.sql',
  '../../commercial/090_credit_batches.sql',
  '../../commercial/091_buyer_rewards.sql',
  '../../commercial/092_credit_settlement.sql',
  '../../commercial/093_withdrawals.sql',
];

export const COMPLETION = [
  '../180_entitlement_lifecycle.sql',
  '../181_reconciliation_orchestration.sql',
  '../182_reversals.sql',
  '../183_payout_execution.sql',
  '../184_commercial_reads.sql',
];

export const IDS = Object.freeze({
  buyer: '00000000-0000-4000-8000-00000000000a',
  seller: '00000000-0000-4000-8000-00000000000b',
  seller2: '00000000-0000-4000-8000-00000000000c',
  outsider: '00000000-0000-4000-8000-00000000000d',
  admin: '00000000-0000-4000-8000-00000000000e',
  buyerMembership: '10000000-0000-4000-8000-00000000000a',
  sellerMembership: '10000000-0000-4000-8000-00000000000b',
  seller2Membership: '10000000-0000-4000-8000-00000000000c',
  adminMembership: '10000000-0000-4000-8000-00000000000e',
});

export async function createCommercialDb({ completion = true } = {}) {
  const db = await createDisposableDb();
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  for (const path of BASE) await db.exec(await read(path));
  if (completion) {
    for (const path of COMPLETION) await db.exec(await read(path));
  }
  await seedIdentities(db);
  return db;
}

export async function seedIdentities(db) {
  const { buyer, seller, seller2, outsider, admin } = IDS;
  const { buyerMembership, sellerMembership, seller2Membership, adminMembership } = IDS;
  await db.exec(`
    ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz;
    ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS phone_confirmed_at timestamptz;
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${buyer}','{}'),('${seller}','{}'),('${seller2}','{}'),
      ('${outsider}','{}'),('${admin}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${buyerMembership}','${buyer}','buyer','active'),
      ('${sellerMembership}','${seller}','seller','active'),
      ('${seller2Membership}','${seller2}','seller','active'),
      ('${adminMembership}','${admin}','seller','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
      ('${buyerMembership}','Buyer A'),('${sellerMembership}','Seller B'),
      ('${seller2Membership}','Seller C'),('${adminMembership}','Admin');
    INSERT INTO hocalist.platform_admins(user_id) VALUES ('${admin}');
  `);
}

export async function asRole(db, role, user, body) {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return await body();
  } finally {
    await db.exec('RESET ROLE');
  }
}

export async function callAs(db, role, user, sql, params = []) {
  return asRole(db, role, user, async () => (await db.query(sql, params)).rows);
}

export async function expectRejected(promise, messagePart, code = '42501') {
  try {
    await promise;
  } catch (error) {
    assertCode(error, messagePart, code);
    return error;
  }
  throw new Error(`expected SQLSTATE ${code} for ${messagePart}, but the call succeeded`);
}

function assertCode(error, messagePart, code) {
  if (error.code !== code) {
    throw new Error(
      `${messagePart}: expected ${code}, got ${error.code} ${error.message}`,
    );
  }
  if (messagePart && !new RegExp(messagePart).test(error.message)) {
    throw new Error(`${messagePart}: message was ${error.message}`);
  }
}

// Shared disposable-PostgreSQL baseline for the admin completion contracts.
//
// Applies the reviewed package migrations that the admin 160-169 reads depend
// on, in the coordinator bundle order. PGlite is single-connection deterministic
// SQL proof; it is not live JWT, PostgREST or multi-connection proof.
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

export const ADMIN = '00000000-0000-4000-8000-00000000000e';
export const BUYER = '00000000-0000-4000-8000-00000000000a';
export const SELLER = '00000000-0000-4000-8000-00000000000b';
export const OUTSIDER = '00000000-0000-4000-8000-00000000000f';
export const M_BUYER = '10000000-0000-4000-8000-00000000000a';
export const M_SELLER = '10000000-0000-4000-8000-00000000000b';
export const M_ADMIN = '10000000-0000-4000-8000-00000000000e';
export const M_OUTSIDER = '10000000-0000-4000-8000-00000000000f';

export const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

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

export async function applyAdminBaseline() {
  const db = await createDisposableDb();
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  for (const path of [
    '../../provider-rollout/apply.sql',
    '../../chat/010_chat_foundation.sql',
    '../../marketplace/020_marketplace_foundation.sql',
    '../../marketplace/021_request_coordinates.sql',
    '../../meetings/040_meetings_foundation.sql',
    '../../outcomes/080_sale_confirmation.sql',
    '../../commercial/090_credit_batches.sql',
    '../../commercial/091_buyer_rewards.sql',
    '../../support/070_support_cases.sql',
    '../../notifications/030_notification_inbox.sql',
    '../../notifications/031_notification_producers.sql',
    '../../marketplace/023_multi_negotiation.sql',
    '../../outcomes/081_purchase_seller.sql',
    '../../commercial/092_credit_settlement.sql',
    '../../commercial/093_withdrawals.sql',
    '../../chat/012_credit_qualification.sql',
    '../../trust/120_review_workflow.sql',
    '../../commercial/094_deposit_checkout.sql',
    '../../notifications/034_outcome_review_producers.sql',
    '../../calls/110_call_signaling.sql',
  ]) {
    await db.exec(await read(path));
  }
  return db;
}

export async function seedAdminIdentities(db) {
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${ADMIN}','{}'),('${BUYER}','{}'),('${SELLER}','{}'),('${OUTSIDER}','{}');
    INSERT INTO hocalist.profiles(id) VALUES
      ('${ADMIN}'),('${BUYER}'),('${SELLER}'),('${OUTSIDER}')
      ON CONFLICT DO NOTHING;
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${M_BUYER}','${BUYER}','buyer','active'),
      ('${M_SELLER}','${SELLER}','seller','active'),
      ('${M_ADMIN}','${ADMIN}','seller','active'),
      ('${M_OUTSIDER}','${OUTSIDER}','buyer','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
      ('${M_BUYER}','Admin Baseline Buyer'),
      ('${M_SELLER}','Admin Baseline Seller'),
      ('${M_ADMIN}','Admin Baseline Operator'),
      ('${M_OUTSIDER}','Admin Baseline Outsider');
    INSERT INTO hocalist.platform_admins(user_id) VALUES ('${ADMIN}');
  `);
}

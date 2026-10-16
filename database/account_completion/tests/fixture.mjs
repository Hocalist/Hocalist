// Shared disposable-database fixture for the account-completion migrations.
//
// PGlite is single-connection, in-memory proof only. It is not live JWT,
// PostgREST, multi-connection or provider proof.
import { readFile } from 'node:fs/promises';
import { setup } from '../../outcomes/tests/fixture.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

// Baseline modules the upgrade bundle expects beyond outcomes/meetings.
const BASELINE = [
  '../../marketplace/021_request_coordinates.sql',
  '../../outcomes/080_sale_confirmation.sql',
  '../../commercial/090_credit_batches.sql',
  '../../commercial/091_buyer_rewards.sql',
  '../../support/070_support_cases.sql',
  '../../notifications/030_notification_inbox.sql',
  '../../notifications/031_notification_producers.sql',
];

export const ACCOUNT_COMPLETION_MIGRATIONS = [
  '../130_account_lifecycle.sql',
  '../131_profile_categories.sql',
  '../132_review_evidence.sql',
  '../133_media_cleanup.sql',
];

/**
 * Builds the current checkpoint plus the pending September 26 upgrade bundle
 * and media 100/101, then applies the requested account-completion migrations.
 * `includeUpgrade: false` stops before the bundle so sequencing can be tested.
 */
export async function createAccountCompletionDb({
  includeUpgrade = true,
  includeMedia = true,
  migrations = ACCOUNT_COMPLETION_MIGRATIONS,
} = {}) {
  const db = await setup(false);
  for (const path of BASELINE) await db.exec(await read(path));
  if (includeUpgrade) {
    await db.exec(await read('../../upgrade-2026-09-26/rollout/apply.sql'));
  }
  if (includeMedia) {
    await db.exec(await read('../../media/100_private_images.sql'));
    await db.exec(await read('../../media/101_profile_avatar.sql'));
    // Chat attachments add the message media references cleanup must respect.
    await db.exec(await read('../../chat/011_chat_attachments.sql'));
  }
  for (const path of migrations) await db.exec(await read(path));
  return db;
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
    if (code && error.code !== code) {
      throw new Error(
        `expected SQLSTATE ${code} for ${messagePart}, got ${error.code}: ${error.message}`,
      );
    }
    if (messagePart && !new RegExp(messagePart).test(error.message)) {
      throw new Error(
        `expected ${messagePart} in "${error.message}" (SQLSTATE ${error.code})`,
      );
    }
    return error;
  }
  throw new Error(`expected SQLSTATE ${code} for ${messagePart}, but it succeeded`);
}

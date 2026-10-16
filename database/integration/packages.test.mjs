// Complete guarded-rollout proof for the pending Hocalist database work.
//
// Disposable PGlite only; this fixture cannot use a live database URL, JWT,
// provider or existing project. It reconstructs the verified live baseline
// from the same reviewed drafts that were deployed (account/provider, chat
// 010, marketplace 020/021, meetings 040, outcomes 080, commercial 090/091,
// support 070, notifications 030/031/032, media 100, calls 110, admin 060),
// then runs every pending bundle's guarded preflight/apply/verify in
// dependency order and finishes with the cross-package verification.
//
// Order rationale:
// - The September 26 upgrade replaces marketplace/commercial/trust functions
//   the packages hash as prerequisites.
// - Media 101 and chat 011 must precede account 132, which is the last
//   media_gateway replacement; they accept each other's gateway body.
// - Notifications 033 extends the kind constraint before communications 153.
// - Admin 061-063 only add reads on the deployed remaining/notification/call
//   foundation.
// - Website 172 and commercial 184 depend on upgrade 092/093 tables.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../tests/fixture.mjs';

const sql = (path) => readFile(new URL(path, import.meta.url), 'utf8');

// Reviewed drafts already deployed to the live Hocalist schema.
const LIVE_BASELINE = [
  '../provider-rollout/apply.sql',
  '../chat/010_chat_foundation.sql',
  '../marketplace/020_marketplace_foundation.sql',
  '../marketplace/021_request_coordinates.sql',
  '../meetings/040_meetings_foundation.sql',
  '../outcomes/080_sale_confirmation.sql',
  '../commercial/090_credit_batches.sql',
  '../commercial/091_buyer_rewards.sql',
  '../support/070_support_cases.sql',
  '../notifications/030_notification_inbox.sql',
  '../notifications/031_notification_producers.sql',
  '../notifications/032_push_queue_bridge.sql',
  '../media/100_private_images.sql',
  '../calls/110_call_signaling.sql',
  '../admin/060_admin_reads.sql',
];

// Pending bundles in dependency order; every step is preflight/apply/verify.
const PENDING_BUNDLES = [
  ['upgrade-2026-09-26', '../upgrade-2026-09-26/rollout'],
  ['media 101 profile avatar', '../media/rollout'],
  ['chat 011 attachments', '../chat/attachments-rollout'],
  ['notifications 033 request-update', '../notifications/request-update-rollout'],
  ['admin 061-063 reads', '../admin/rollout'],
  ['account_completion 130-133', '../account_completion/rollout'],
  ['discovery_completion 140-146', '../discovery_completion/rollout'],
  ['communication_completion 150-155', '../communication_completion/rollout'],
  ['admin_completion 160-163', '../admin_completion/rollout'],
  ['website_completion 170-173', '../website_completion/rollout'],
  ['commercial_completion 180-184', '../commercial_completion/rollout'],
];

// Bundles whose verify scripts stay valid after every later bundle. The
// upgrade, media 101 and chat 011 verifies are intentionally step-local:
// account 132 and commercial 184 supersede the media_gateway and withdrawal
// bodies they install, which final_verify.sql covers instead.
const FINAL_VERIFIES = [
  '../notifications/request-update-rollout/verify.sql',
  '../admin/rollout/verify.sql',
  '../account_completion/rollout/verify.sql',
  '../discovery_completion/rollout/verify.sql',
  '../communication_completion/rollout/verify.sql',
  '../admin_completion/rollout/verify.sql',
  '../website_completion/rollout/verify.sql',
  '../commercial_completion/rollout/verify.sql',
];

test('complete guarded rollout applies in dependency order and coexists', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    for (const path of LIVE_BASELINE) await db.exec(await sql(path));

    for (const [name, dir] of PENDING_BUNDLES) {
      await t.test(name, async () => {
        await db.exec(await sql(`${dir}/preflight.sql`));
        await db.exec(await sql(`${dir}/apply.sql`));
        await db.exec(await sql(`${dir}/verify.sql`));
      });
    }

    await t.test('final verification after all bundles coexist', async () => {
      for (const path of FINAL_VERIFIES) {
        try {
          await db.exec(await sql(path));
        } catch (error) {
          throw new Error(`${path} re-verification failed: ${error.message}`);
        }
      }
      await db.exec(await sql('./final_verify.sql'));
      const { rows } = await db.query(`SELECT
        has_table_privilege('anon','hocalist.profile_contacts','SELECT') AS public_contacts,
        has_table_privilege('authenticated','hocalist.conversation_messages','SELECT') AS direct_messages,
        has_function_privilege('authenticated','hocalist.media_cleanup_hash(integer,jsonb,jsonb)','EXECUTE') AS cleanup_hash,
        has_function_privilege('authenticated','hocalist.website_checkout_context(text)','EXECUTE') AS checkout_context`);
      assert.deepEqual(rows[0], {
        public_contacts: false,
        direct_messages: false,
        cleanup_hash: false,
        checkout_context: false,
      });
    });
  } finally {
    await db.close();
  }
});

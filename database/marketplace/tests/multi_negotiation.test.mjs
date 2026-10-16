// Disposable PostgreSQL checks for the September 26 approved marketplace rules:
// first-acceptance countdown, multiple accepted negotiations, one final
// purchase, discovery closure, batch-owned credit pricing, qualification,
// settlement, release and the explicit unconfigured-configuration error.
//
// Deposit batches are seeded exactly as the reviewed provider path would create
// them (`credit_deposit_internal` snapshots the confirmed option rates). The
// suite proves that a later option edit or a later deposit never reprices an
// existing batch or reservation.
//
// PGlite is single-connection: this is deterministic SQL proof, not real JWT,
// PostgREST or concurrent-writer proof. A separate opt-in harness owns real
// multi-connection concurrency.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const C = '00000000-0000-4000-8000-00000000000c';
const D = '00000000-0000-4000-8000-00000000000d';
const E = '00000000-0000-4000-8000-00000000000e';
const F = '00000000-0000-4000-8000-00000000000f';
const G = '00000000-0000-4000-8000-000000000010';
const ADM = '00000000-0000-4000-8000-000000000011';
const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MC = '10000000-0000-4000-8000-00000000000c';
const MD = '10000000-0000-4000-8000-00000000000d';
const ME = '10000000-0000-4000-8000-00000000000e';
const MF = '10000000-0000-4000-8000-00000000000f';
const MG = '10000000-0000-4000-8000-000000000010';
const MADM = '10000000-0000-4000-8000-000000000011';
const CATEGORY = '20000000-0000-4000-8000-000000000001';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

async function asRole(db, role, user, body) {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return await body();
  } finally {
    await db.exec('RESET ROLE');
  }
}

async function callAs(db, role, user, sql, params = []) {
  return asRole(db, role, user, async () => (await db.query(sql, params)).rows);
}

async function expectRejected(promise, messagePart, code = '42501') {
  try {
    await promise;
  } catch (error) {
    assert.equal(error.code, code, `${messagePart}: got ${error.code} ${error.message}`);
    if (messagePart) assert.match(error.message, new RegExp(messagePart));
    return error;
  }
  assert.fail(`expected SQLSTATE ${code} for ${messagePart}`);
}

const command = (db, user, op, key, input) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS result',
    [op, key, JSON.stringify(input)]);

const creditAdmin = (db, user, op, key, input) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.credit_admin_command($1,$2,$3::jsonb) AS data',
    [op, key, JSON.stringify(input)]);

const creditWallet = (db, user) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.credit_wallet() AS data');

const rewardWallet = (db, user) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.reward_wallet() AS data');

const salePin = (db, user, meeting, action, pin = null) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.sale_pin($1,$2,$3) AS data',
    [meeting, action, pin]);

const chatSend = (db, user, conversation, key, text) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.chat_send($1,$2,$3) AS data',
    [conversation, key, text]);

const meetingCall = (db, user, fn, params) =>
  callAs(db, 'authenticated', user, `SELECT hocalist.${fn} AS data`, params);

const propose = (db, user, conversation, key, overrides = {}) =>
  meetingCall(db, user, 'meeting_propose($1,$2,$3)',
    [conversation, JSON.stringify(schedule(overrides)), key]);

const respond = (db, user, meeting, revision, accept, key) =>
  meetingCall(db, user, 'meeting_respond($1,$2,$3,$4)', [meeting, accept, revision, key]);

const requestInput = (overrides = {}) => ({
  kind: 'product',
  title: 'iPad Air, 5th gen or newer',
  description: 'Needs to be in good condition.',
  condition: 'used',
  quantity: 1,
  budget_minimum_minor: 35000,
  budget_maximum_minor: 48000,
  currency_code: 'USD',
  accepts_higher_offers: false,
  use_home_address: true,
  category_id: CATEGORY,
  ...overrides,
});

const offerInput = (requestId, overrides = {}) => ({
  request_id: requestId,
  price_minor: 42000,
  currency_code: 'USD',
  message: 'Can meet tomorrow.',
  image_media_ids: [],
  schedule_date: '2026-11-05',
  schedule_time: '18:30',
  schedule_timezone: 'America/New_York',
  place_choice: 'specific_place',
  place_label: 'Cross County Mall',
  place_address: '123 Synthetic Ave',
  ...overrides,
});

const schedule = (overrides = {}) => ({
  schedule_date: '2026-11-05',
  schedule_time: '18:30',
  schedule_timezone: 'America/New_York',
  place_choice: 'specific_place',
  place_label: 'Cross County Mall',
  place_address: '123 Synthetic Ave',
  ...overrides,
});

async function seed(db) {
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${A}','{}'),('${B}','{}'),('${C}','{}'),('${D}','{}'),
      ('${E}','{}'),('${F}','{}'),('${G}','{}'),('${ADM}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${MA}','${A}','buyer','active'),
      ('${MB}','${B}','seller','active'),
      ('${MC}','${C}','seller','active'),
      ('${MD}','${D}','seller','active'),
      ('${ME}','${E}','seller','active'),
      ('${MF}','${F}','seller','active'),
      ('${MG}','${G}','seller','active'),
      ('${MADM}','${ADM}','seller','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name,area_label) VALUES
      ('${MA}','Buyer A','Yonkers, NY'),('${MB}','Seller B','Yonkers, NY'),
      ('${MC}','Seller C','Queens, NY'),('${MD}','Seller D','Queens, NY'),
      ('${ME}','Seller E','Queens, NY'),('${MF}','Seller F','Queens, NY'),
      ('${MG}','Seller G','Queens, NY'),('${MADM}','Admin','Yonkers, NY');
    INSERT INTO hocalist.platform_admins(user_id) VALUES ('${ADM}');
    INSERT INTO hocalist.catalogue_categories(id,label,scope,status,sort_order)
      VALUES ('${CATEGORY}','Electronics','product','active',1);
    INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source)
      VALUES ('${B}','elite','admin'),('${C}','elite','admin'),('${E}','elite','admin'),
             ('${G}','elite','admin');
  `);
}

// The reviewed provider path: a confirmed deposit snapshots the option rates
// into one immutable batch. Tests call the internal helper directly.
const deposit = (db, user, reference, amount, initial, win, rate) =>
  db.query('SELECT hocalist.credit_deposit_internal($1,$2,$3,$4,$5,$6) AS id',
    [user, reference, amount, initial, win, rate]);

test('multi-negotiation, countdown, purchase and batch-owned credit settlement', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    for (const path of [
      '../../provider-rollout/apply.sql',
      '../../chat/010_chat_foundation.sql',
      '../020_marketplace_foundation.sql',
      '../021_request_coordinates.sql',
      '../023_multi_negotiation.sql',
      '../../meetings/040_meetings_foundation.sql',
      '../../outcomes/080_sale_confirmation.sql',
      '../../outcomes/081_purchase_seller.sql',
      '../../commercial/090_credit_batches.sql',
      '../../commercial/091_buyer_rewards.sql',
      '../../commercial/092_credit_settlement.sql',
      '../../chat/012_credit_qualification.sql',
    ]) {
      await db.exec(await read(path));
    }
    await seed(db);

    // Batch-owned rates: $40 at 1.45/3.25 HC, $20 at 1.55/3.75 HC.
    await deposit(db, B, 'dep-b-40', 4000, 145, 325, 'deposit-40-v1');
    await deposit(db, B, 'dep-b-20', 2000, 155, 375, 'deposit-20-v1');
    await deposit(db, C, 'dep-c-20', 2000, 155, 375, 'deposit-20-v1');

    await creditAdmin(db, ADM, 'reward_policy.set', 'reward-1', {
      normal_minor: 15, late_minor: 30, late_window_hours: 12, rule_version: 'reward-2026-09',
    });

    const request = (await command(db, A, 'request.create', 'req-main', requestInput()))[0].result;
    const offerB = (await command(db, B, 'offer.submit', 'offer-b', offerInput(request.id)))[0].result;
    const offerC = (await command(db, C, 'offer.submit', 'offer-c', offerInput(request.id)))[0].result;

    let firstAcceptedAt;
    let acceptanceExpiresAt;
    let conversationB;
    let conversationC;

    await t.test('the reservation copies the oldest eligible batch, not current settings', async () => {
      const walletB = (await creditWallet(db, B))[0].data;
      assert.equal(walletB.reserved_minor, 325, 'the $40 batch covers its own 325 winning fee');
      assert.equal(walletB.batches[0].initial_fee_minor, 145);
      assert.equal(walletB.batches[0].winning_total_minor, 325);
      assert.equal(walletB.batches[1].reserved_minor, 0, 'the newer $20 batch is untouched');
      const target = await db.query(
        'SELECT initial_minor, winning_minor, rate_version, batch_id FROM hocalist.credit_targets WHERE user_id=$1 AND request_id=$2',
        [B, request.id]);
      const batch = await db.query(
        "SELECT id FROM hocalist.credit_batches WHERE user_id=$1 AND rate_version='deposit-40-v1'", [B]);
      assert.deepEqual(target.rows[0], {
        initial_minor: 145, winning_minor: 325, rate_version: 'deposit-40-v1',
        batch_id: batch.rows[0].id,
      });
      assert.equal(walletB.weekly.used, 1);
      assert.equal(walletB.weekly.limit, 100);
      assert.equal('fee_policy' in walletB, false, 'no plan-level fee policy exists');
      const walletC = (await creditWallet(db, C))[0].data;
      assert.equal(walletC.reserved_minor, 375);
    });

    await t.test('first acceptance starts the seven-day countdown exactly once', async () => {
      const selectedB = (await command(db, A, 'offer.select', 'select-b', {
        offer_id: offerB.id,
        revision_id: offerB.revisions[0].id,
        expected_offer_revision: offerB.revision,
      }))[0].result;
      assert.equal(selectedB.status, 'selected');
      firstAcceptedAt = selectedB.request_first_accepted_at;
      acceptanceExpiresAt = selectedB.request_acceptance_expires_at;
      assert.ok(firstAcceptedAt);
      assert.equal(new Date(acceptanceExpiresAt) - new Date(firstAcceptedAt), 7 * 24 * 60 * 60 * 1000);
    });

    await t.test('a second acceptance is allowed and never resets the countdown', async () => {
      const selectedC = (await command(db, A, 'offer.select', 'select-c', {
        offer_id: offerC.id,
        revision_id: offerC.revisions[0].id,
        expected_offer_revision: offerC.revision,
      }))[0].result;
      assert.equal(selectedC.status, 'selected');
      assert.equal(selectedC.request_first_accepted_at, firstAcceptedAt);
      assert.equal(selectedC.request_acceptance_expires_at, acceptanceExpiresAt);
      const owner = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.marketplace_request($1) AS data', [request.id]))[0].data;
      assert.equal(owner.discovery_open, true);
    });

    await t.test('each accepted negotiation opens its own conversation', async () => {
      conversationB = (await command(db, A, 'conversation.open_offer', 'open-b', {
        offer_id: offerB.id,
      }))[0].result.conversation_id;
      conversationC = (await command(db, A, 'conversation.open_offer', 'open-c', {
        offer_id: offerC.id,
      }))[0].result.conversation_id;
      assert.ok(conversationB);
      assert.ok(conversationC);
      assert.notEqual(conversationB, conversationC);
    });

    await t.test('qualifying messages charge the batch initial fee once', async () => {
      await chatSend(db, A, conversationB, 'msg-a-1', 'Hello, is Saturday fine?');
      const afterBuyer = await db.query(
        'SELECT status FROM hocalist.credit_targets WHERE request_id=$1 AND user_id=$2',
        [request.id, B]);
      assert.equal(afterBuyer.rows[0].status, 'reserved', 'one message alone does not qualify');
      await chatSend(db, B, conversationB, 'msg-b-1', 'Saturday works.');
      const rows = await db.query(
        `SELECT t.status, t.charged_minor, t.reserved_minor, t.rate_version,
                b.balance_minor, b.reserved_minor AS batch_reserved, b.rate_version AS batch_rate
         FROM hocalist.credit_targets t JOIN hocalist.credit_batches b ON b.id=t.batch_id
         WHERE t.request_id=$1 AND t.user_id=$2`, [request.id, B]);
      assert.deepEqual(rows.rows[0], {
        status: 'initial_charged', charged_minor: 145, reserved_minor: 180,
        rate_version: 'deposit-40-v1',
        balance_minor: 3855, batch_reserved: 180, batch_rate: 'deposit-40-v1',
      });
      await chatSend(db, B, conversationB, 'msg-b-2', 'Second message cannot double-charge.');
      const replay = await db.query(
        'SELECT charged_minor FROM hocalist.credit_targets WHERE request_id=$1 AND user_id=$2',
        [request.id, B]);
      assert.equal(replay.rows[0].charged_minor, 145);
    });

    await t.test('discovery expiry blocks new offers but keeps accepted negotiations', async () => {
      await db.exec(
        `UPDATE hocalist.requests SET first_accepted_at=now()-interval '8 days',
          acceptance_expires_at=now()-interval '1 hour' WHERE id='${request.id}'`);
      await expectRejected(
        command(db, D, 'offer.submit', 'offer-d-2', offerInput(request.id, { price_minor: 41000 })),
        'request_expired',
        'P0001',
      );
      const leads = (await callAs(db, 'authenticated', D,
        'SELECT hocalist.marketplace_seller_leads(NULL,NULL,NULL,50,NULL) AS data'))[0].data;
      assert.equal(leads.items.length, 0, 'an expired request leaves discovery');
      await expectRejected(
        command(db, A, 'request.reopen', 'reopen-late', {
          request_id: request.id, expected_revision: 1,
        }),
        'request_not_reopenable',
        'P0001',
      );
      const owner = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.marketplace_request($1) AS data', [request.id]))[0].data;
      assert.equal(owner.discovery_open, false);
    });

    await t.test('an accepted meeting survives discovery expiry', async () => {
      const proposed = (await propose(db, A, conversationB, 'propose-b'))[0].data;
      const accepted = (await respond(db, B, proposed.id, proposed.revision, true, 'accept-b'))[0].data;
      assert.equal(accepted.status, 'accepted');
      await creditWallet(db, B);
      const target = await db.query(
        'SELECT status FROM hocalist.credit_targets WHERE request_id=$1 AND user_id=$2',
        [request.id, B]);
      assert.equal(target.rows[0].status, 'initial_charged', 'accepted meeting keeps its reserve');
    });

    let meetingB;
    let meetingC;

    await t.test('the buyer designates the final purchase seller; others cannot confirm', async () => {
      const proposedC = (await propose(db, A, conversationC, 'propose-c'))[0].data;
      const acceptedC = (await respond(db, C, proposedC.id, proposedC.revision, true, 'accept-c'))[0].data;
      meetingC = acceptedC.id;
      meetingB = (await db.query(
        "SELECT id FROM hocalist.meetings WHERE conversation_id=$1 AND status='accepted'",
        [conversationB])).rows[0].id;

      const designated = (await command(db, A, 'purchase.select', 'purchase-b', {
        offer_id: offerB.id, expected_offer_revision: offerB.revision + 1,
      }))[0].result;
      assert.equal(designated.purchase_selected, true);
      const pin = (await salePin(db, A, meetingB, 'display'))[0].data;
      assert.equal(pin.status, 'ready');
      const denied = (await salePin(db, C, meetingC, 'verify', '00000'))[0].data;
      assert.equal(denied.status, 'purchase_seller_required');
      const wrong = (await salePin(db, B, meetingB, 'verify', '00000'))[0].data;
      assert.equal(wrong.status, 'incorrect');
      const confirmed = (await salePin(db, B, meetingB, 'verify', pin.pin))[0].data;
      assert.equal(confirmed.status, 'confirmed');
    });

    await t.test('confirmation closes every other negotiation and charges only the difference', async () => {
      const rows = await db.query(`SELECT
        (SELECT status FROM hocalist.offers WHERE id='${offerB.id}') AS b_offer,
        (SELECT status FROM hocalist.offers WHERE id='${offerC.id}') AS c_offer,
        (SELECT status FROM hocalist.meetings WHERE conversation_id='${conversationC}') AS c_meeting,
        (SELECT status FROM hocalist.requests WHERE id='${request.id}') AS request_status,
        (SELECT status FROM hocalist.credit_targets WHERE user_id='${B}' AND request_id='${request.id}') AS b_target,
        (SELECT charged_minor FROM hocalist.credit_targets WHERE user_id='${B}' AND request_id='${request.id}') AS b_charged,
        (SELECT status FROM hocalist.credit_targets WHERE user_id='${C}' AND request_id='${request.id}') AS c_target,
        (SELECT balance_minor FROM hocalist.credit_batches WHERE user_id='${B}' AND rate_version='deposit-40-v1') AS b_balance,
        (SELECT balance_minor FROM hocalist.credit_batches WHERE user_id='${B}' AND rate_version='deposit-20-v1') AS b_leftover,
        (SELECT balance_minor FROM hocalist.credit_batches WHERE user_id='${C}') AS c_balance,
        (SELECT reserved_minor FROM hocalist.credit_batches WHERE user_id='${B}' AND rate_version='deposit-40-v1') AS b_reserved`);
      assert.deepEqual(rows.rows[0], {
        b_offer: 'completed', c_offer: 'declined', c_meeting: 'cancelled',
        request_status: 'closed', b_target: 'won', b_charged: 325,
        c_target: 'released', b_balance: 3675, b_leftover: 2000,
        c_balance: 2000, b_reserved: 0,
      });
      const statusC = (await salePin(db, C, meetingC, 'status'))[0].data;
      assert.equal(statusC.status, 'completed_elsewhere');
    });

    await t.test('buyer reward accrues separately only after the winning fee is collected', async () => {
      const wallet = (await rewardWallet(db, A))[0].data;
      assert.equal(wallet.reward_policy_configured, true);
      // The synthetic offer was submitted inside the final 12 hours of the
      // (manipulated) request window, so the configured late rate applies.
      assert.equal(wallet.earned_minor, 30);
      assert.equal(wallet.items[0].status, 'earned');
    });

    await t.test('an unavailable paid configuration refuses the chargeable action', async () => {
      const requestF = (await command(db, A, 'request.create', 'req-f',
        requestInput({ title: 'Unconfigured request' })))[0].result;
      await expectRejected(
        command(db, F, 'offer.submit', 'offer-f', offerInput(requestF.id)),
        'targeting_fee_unconfigured',
        'P0001',
      );
      const count = await db.query(
        'SELECT count(*)::int AS n FROM hocalist.offers WHERE seller_user_id=$1', [F]);
      assert.equal(count.rows[0].n, 0, 'no offer is acknowledged without its reservation');
      // Configuring a purchasable option turns the same action into an honest
      // insufficient-balance error instead of a free pass.
      await creditAdmin(db, ADM, 'deposit_option.set', 'option-20', {
        amount_minor: 2000, initial_fee_minor: 155, winning_total_minor: 375,
        rate_version: 'deposit-20-v1', active: true, sort_order: 0,
      });
      await expectRejected(
        command(db, F, 'offer.submit', 'offer-f2', offerInput(requestF.id)),
        'insufficient_single_batch',
        'P0001',
      );
    });

    let mixedTarget;
    await t.test('a small old remainder is skipped, kept and never mixed', async () => {
      // A $40 batch from earlier use now holds a small remainder (below its
      // own 325 winning fee), plus a $20 batch: the engine must skip the $40
      // remainder and copy the $20 batch's own rates.
      await deposit(db, E, 'dep-e-40', 4000, 145, 325, 'deposit-40-v1');
      await db.query(
        "UPDATE hocalist.credit_batches SET balance_minor=300 WHERE user_id=$1 AND deposit_reference='dep-e-40'",
        [E]);
      await deposit(db, E, 'dep-e-20', 2000, 155, 375, 'deposit-20-v1');
      const requestE = (await command(db, A, 'request.create', 'req-e',
        requestInput({ title: 'Mixed batch request' })))[0].result;
      mixedTarget = (await command(db, E, 'offer.submit', 'offer-e', offerInput(requestE.id)))[0].result;
      assert.equal(mixedTarget.status, 'submitted');
      const target = await db.query(
        `SELECT t.initial_minor, t.winning_minor, t.rate_version, b.id AS batch_id
         FROM hocalist.credit_targets t JOIN hocalist.credit_batches b ON b.id=t.batch_id
         WHERE t.user_id=$1`, [E]);
      const twenty = await db.query(
        "SELECT id FROM hocalist.credit_batches WHERE user_id=$1 AND rate_version='deposit-20-v1'", [E]);
      assert.deepEqual(target.rows[0], {
        initial_minor: 155, winning_minor: 375, rate_version: 'deposit-20-v1',
        batch_id: twenty.rows[0].id,
      });
      const batches = await db.query(
        'SELECT balance_minor, reserved_minor FROM hocalist.credit_batches WHERE user_id=$1 ORDER BY original_minor',
        [E]);
      assert.deepEqual(batches.rows, [
        { balance_minor: 2000, reserved_minor: 375 },
        { balance_minor: 300, reserved_minor: 0 },
      ]);
    });

    await t.test('later admin rate edits never reprice existing batches or reservations', async () => {
      const option = (await creditWallet(db, E))[0].data.deposit_options[0];
      await creditAdmin(db, ADM, 'deposit_option.set', 'option-20-v2', {
        id: option.id, amount_minor: 2000, initial_fee_minor: 160, winning_total_minor: 380,
        rate_version: 'deposit-20-v2', active: true, sort_order: 0,
        expected_revision: option.revision,
      });
      const target = await db.query(
        `SELECT t.initial_minor, t.winning_minor, t.rate_version, b.balance_minor, b.reserved_minor
         FROM hocalist.credit_targets t JOIN hocalist.credit_batches b ON b.id=t.batch_id
         WHERE t.user_id=$1`, [E]);
      assert.deepEqual(target.rows[0], {
        initial_minor: 155, winning_minor: 375, rate_version: 'deposit-20-v1',
        balance_minor: 2000, reserved_minor: 375,
      });
      // A new deposit uses the new option snapshot, while the old batch stays
      // priced at v1.
      await deposit(db, E, 'dep-e-20-v2', 2000, 160, 380, 'deposit-20-v2');
      const batches = await db.query(
        'SELECT rate_version, winning_total_minor FROM hocalist.credit_batches WHERE user_id=$1 ORDER BY created_at',
        [E]);
      assert.deepEqual(batches.rows, [
        { rate_version: 'deposit-40-v1', winning_total_minor: 325 },
        { rate_version: 'deposit-20-v1', winning_total_minor: 375 },
        { rate_version: 'deposit-20-v2', winning_total_minor: 380 },
      ]);
      // Reserving again still reads E's own oldest eligible batch (v1), never
      // the edited option.
      const requestE2 = (await command(db, A, 'request.create', 'req-e2',
        requestInput({ title: 'Second mixed request' })))[0].result;
      await command(db, E, 'offer.submit', 'offer-e2', offerInput(requestE2.id));
      const second = await db.query(
        `SELECT t.rate_version FROM hocalist.credit_targets t
         WHERE t.user_id=$1 AND t.request_id=$2`, [E, requestE2.id]);
      assert.equal(second.rows[0].rate_version, 'deposit-20-v1');
    });

    await t.test('the retained leftover and the losing fee stay visible', async () => {
      // Qualify E's first target (one message from each side), then release the
      // negotiation as a loss: the initial 155 stays charged, the unused 220
      // returns, and the old $40 remainder is untouched.
      const selected = (await command(db, A, 'offer.select', 'select-e', {
        offer_id: mixedTarget.id,
        revision_id: mixedTarget.revisions[0].id,
        expected_offer_revision: mixedTarget.revision,
      }))[0].result;
      assert.equal(selected.status, 'selected');
      const conversation = (await command(db, A, 'conversation.open_offer', 'open-e', {
        offer_id: mixedTarget.id,
      }))[0].result.conversation_id;
      await chatSend(db, A, conversation, 'msg-e-a', 'Still interested.');
      await chatSend(db, E, conversation, 'msg-e-b', 'Yes, tomorrow works.');
      const qualified = await db.query(
        `SELECT t.status, t.charged_minor FROM hocalist.credit_targets t
         WHERE t.offer_id=$1`, [mixedTarget.id]);
      assert.deepEqual(qualified.rows[0], { status: 'initial_charged', charged_minor: 155 });
      await db.query('SELECT hocalist.credit_release_offer($1)', [mixedTarget.id]);
      const batches = await db.query(
        `SELECT rate_version, balance_minor, reserved_minor FROM hocalist.credit_batches
         WHERE user_id=$1 ORDER BY created_at`, [E]);
      const byRate = Object.fromEntries(batches.rows.map((row) => [row.rate_version, row]));
      assert.deepEqual(byRate['deposit-40-v1'], {
        rate_version: 'deposit-40-v1', balance_minor: 300, reserved_minor: 0,
      });
      assert.deepEqual(byRate['deposit-20-v1'], {
        rate_version: 'deposit-20-v1', balance_minor: 1845, reserved_minor: 375,
      });
      assert.deepEqual(byRate['deposit-20-v2'], {
        rate_version: 'deposit-20-v2', balance_minor: 2000, reserved_minor: 0,
      });
      const first = await db.query(
        'SELECT status, charged_minor FROM hocalist.credit_targets WHERE offer_id=$1',
        [mixedTarget.id]);
      assert.deepEqual(first.rows[0], { status: 'released', charged_minor: 155 });
    });

    await t.test('weekly capacity is separate from batch pricing', async () => {
      await db.exec(`UPDATE hocalist.marketplace_plan_limits SET weekly_target_limit=2 WHERE plan_code='elite'`);
      const requestG1 = (await command(db, A, 'request.create', 'req-g1',
        requestInput({ title: 'Weekly one' })))[0].result;
      const requestG2 = (await command(db, A, 'request.create', 'req-g2',
        requestInput({ title: 'Weekly two' })))[0].result;
      const requestG3 = (await command(db, A, 'request.create', 'req-g3',
        requestInput({ title: 'Weekly three' })))[0].result;
      await deposit(db, G, 'dep-g-1', 4000, 145, 325, 'deposit-40-v1');
      await deposit(db, G, 'dep-g-2', 4000, 145, 325, 'deposit-40-v1');
      await command(db, G, 'offer.submit', 'offer-g1', offerInput(requestG1.id));
      const walletAfterOne = (await creditWallet(db, G))[0].data;
      assert.equal(walletAfterOne.weekly.used, 1);
      assert.equal(walletAfterOne.reserved_minor, 325);
      await command(db, G, 'offer.submit', 'offer-g2', offerInput(requestG2.id));
      const walletAfterTwo = (await creditWallet(db, G))[0].data;
      assert.equal(walletAfterTwo.weekly.used, 2);
      assert.equal(walletAfterTwo.reserved_minor, 650);
      await expectRejected(
        command(db, G, 'offer.submit', 'offer-g3', offerInput(requestG3.id)),
        'weekly_target_limit',
        'P0001',
      );
    });

    await t.test('retries never double-reserve, double-charge or double-settle', async () => {
      const targetsBefore = await db.query('SELECT count(*)::int AS n FROM hocalist.credit_targets');
      const entriesBefore = await db.query('SELECT count(*)::int AS n FROM hocalist.credit_entries');
      await command(db, B, 'offer.submit', 'offer-b', offerInput(request.id));
      await chatSend(db, B, conversationB, 'msg-b-1', 'Saturday works.');
      await salePin(db, B, meetingB, 'status');
      const targetsAfter = await db.query('SELECT count(*)::int AS n FROM hocalist.credit_targets');
      const entriesAfter = await db.query('SELECT count(*)::int AS n FROM hocalist.credit_entries');
      assert.equal(targetsAfter.rows[0].n, targetsBefore.rows[0].n);
      assert.equal(entriesAfter.rows[0].n, entriesBefore.rows[0].n);
      const charged = await db.query(
        'SELECT charged_minor FROM hocalist.credit_targets WHERE request_id=$1 AND user_id=$2',
        [request.id, B]);
      assert.equal(charged.rows[0].charged_minor, 325);
    });

    await t.test('retiring the deposit catalogue restores the configuration error', async () => {
      const option = (await creditWallet(db, F))[0].data.deposit_options[0];
      await creditAdmin(db, ADM, 'deposit_option.retire', 'option-20-retire', {
        id: option.id, expected_revision: option.revision,
      });
      const requestF2 = (await command(db, A, 'request.create', 'req-f2',
        requestInput({ title: 'Unconfigured again' })))[0].result;
      await expectRejected(
        command(db, F, 'offer.submit', 'offer-f3', offerInput(requestF2.id)),
        'targeting_fee_unconfigured',
        'P0001',
      );
    });
  } finally {
    await db.close();
  }
});

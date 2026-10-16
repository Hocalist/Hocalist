// Reversal/dispute contract proof (migration 182).
//
// Append-only corrections, causal linkage, policy-gated holds and
// compensation, admin-review boundary, no unrelated clawback and idempotent
// replays. PGlite is single-connection deterministic proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createCommercialDb, callAs, expectRejected, IDS } from './fixture.mjs';

const { buyer, seller, outsider, admin } = IDS;

const OUTCOME = '70000000-0000-4000-8002-000000000001';
const BATCH = '80000000-0000-4000-8002-000000000001';
const BATCH2 = '80000000-0000-4000-8002-000000000002';
const TARGET = '81000000-0000-4000-8002-000000000001';
const REWARD = '82000000-0000-4000-8002-000000000001';

async function seedWonSale(db) {
  await db.exec(`
    INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
    VALUES('30000000-0000-4000-8002-000000000001','${buyer}','${IDS.buyerMembership}',
      'product','Sold item','used','closed');
    INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
    VALUES('40000000-0000-4000-8002-000000000001','30000000-0000-4000-8002-000000000001',
      '${buyer}','${seller}','${IDS.sellerMembership}','completed');
    INSERT INTO hocalist.conversations(id,origin,request_id,offer_id)
    VALUES('60000000-0000-4000-8002-000000000001','targeted_request',
      '30000000-0000-4000-8002-000000000001','40000000-0000-4000-8002-000000000001');
    INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,
      status,meeting_expires_at)
    VALUES('50000000-0000-4000-8002-000000000001','60000000-0000-4000-8002-000000000001',
      '30000000-0000-4000-8002-000000000001','40000000-0000-4000-8002-000000000001',
      '${buyer}','${seller}','accepted',now()+interval '1 day');
    INSERT INTO hocalist.sale_confirmations(id,request_id,meeting_id,offer_id,schedule_revision_id,
      buyer_user_id,seller_user_id)
    VALUES('${OUTCOME}','30000000-0000-4000-8002-000000000001','50000000-0000-4000-8002-000000000001',
      '40000000-0000-4000-8002-000000000001',gen_random_uuid(),'${buyer}','${seller}');
    INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,
      reserved_minor,initial_fee_minor,winning_total_minor,rate_version)
    VALUES('${BATCH}','${seller}','dep-r1',400,200,0,100,200,'v1'),
          ('${BATCH2}','${seller}','dep-r2',500,500,0,100,200,'v1');
    INSERT INTO hocalist.credit_targets(id,user_id,request_id,batch_id,offer_id,initial_minor,winning_minor,
      charged_minor,reserved_minor,status,week_start,rate_version)
    VALUES('${TARGET}','${seller}','30000000-0000-4000-8002-000000000001','${BATCH}',
      '40000000-0000-4000-8002-000000000001',100,200,200,0,'won',
      date_trunc('week',now() AT TIME ZONE 'UTC')::date,'v1');
    INSERT INTO hocalist.buyer_rewards(id,outcome_id,target_id,buyer_user_id,amount_minor,rule_version)
    VALUES('${REWARD}','${OUTCOME}','${TARGET}','${buyer}',15,'reward-v1');
  `);
}

// Seeds one extra confirmed purchase and reward for the same buyer, used to
// prove that an unrelated reward is never consumed by an older reversal.
async function seedExtraReward(db, suffix, amountMinor) {
  const id = (prefix) => `${prefix}-0000-4000-8002-${suffix.padStart(12, '0')}`;
  await db.exec(`
    INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
    VALUES('${id('30000000')}','${buyer}','${IDS.buyerMembership}','product','Extra sale','used','closed');
    INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
    VALUES('${id('40000000')}','${id('30000000')}','${buyer}','${seller}','${IDS.sellerMembership}','completed');
    INSERT INTO hocalist.conversations(id,origin,request_id,offer_id)
    VALUES('${id('60000000')}','targeted_request','${id('30000000')}','${id('40000000')}');
    INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,
      status,meeting_expires_at)
    VALUES('${id('50000000')}','${id('60000000')}','${id('30000000')}','${id('40000000')}',
      '${buyer}','${seller}','accepted',now()+interval '1 day');
    INSERT INTO hocalist.sale_confirmations(id,request_id,meeting_id,offer_id,schedule_revision_id,
      buyer_user_id,seller_user_id)
    VALUES('${id('70000000')}','${id('30000000')}','${id('50000000')}','${id('40000000')}',
      gen_random_uuid(),'${buyer}','${seller}');
    INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,
      reserved_minor,initial_fee_minor,winning_total_minor,rate_version)
    VALUES('${id('80000000')}','${seller}','extra-dep-${suffix}',400,200,0,100,200,'v1');
    INSERT INTO hocalist.credit_targets(id,user_id,request_id,batch_id,offer_id,initial_minor,winning_minor,
      charged_minor,reserved_minor,status,week_start,rate_version)
    VALUES('${id('81000000')}','${seller}','${id('30000000')}','${id('80000000')}','${id('40000000')}',
      100,200,200,0,'won',date_trunc('week',now() AT TIME ZONE 'UTC')::date,'v1');
    INSERT INTO hocalist.buyer_rewards(id,outcome_id,target_id,buyer_user_id,amount_minor,rule_version)
    VALUES('${id('82000000')}','${id('70000000')}','${id('81000000')}','${buyer}',${amountMinor},'reward-v1');
  `);
}

const openReversal = (db, params) =>
  callAs(db, 'service_role', null,
    `SELECT hocalist.reversal_open_internal($1,$2,$3,$4,$5,$6,$7,$8,$9) AS data`,
    [params.provider ?? 'test-provider', params.reference, params.kind ?? 'chargeback',
      params.scope, params.amount, params.user ?? null, params.outcome ?? null,
      params.withdrawal ?? null, params.note ?? null]).then((rows) => rows[0].data);

const adminCommand = (db, user, op, key, input) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.reversal_admin_command($1,$2,$3::jsonb) AS result',
    [op, key, JSON.stringify(input)]).then((rows) => rows[0].result);

const state = (db) =>
  callAs(db, 'authenticated', buyer, 'SELECT hocalist.commercial_reversal_status() AS data')
    .then((rows) => rows[0].data);

const wallet = (db) =>
  callAs(db, 'authenticated', buyer, 'SELECT hocalist.commercial_reward_wallet() AS data')
    .then((rows) => rows[0].data);

const batch = (db, id) =>
  db.query('SELECT balance_minor, reserved_minor FROM hocalist.credit_batches WHERE id=$1', [id])
    .then((r) => r.rows[0]);

test('reversals open only through the verified service path and dedupe exactly', async () => {
  const db = await createCommercialDb();
  try {
    await seedWonSale(db);
    await expectRejected(
      callAs(db, 'authenticated', admin,
        "SELECT hocalist.reversal_open_internal('p','r','chargeback','credit_batch',100, NULL, $1, NULL, NULL)",
        [OUTCOME]),
      'permission denied',
      '42501',
    );
    // Missing causal link is refused.
    await expectRejected(
      openReversal(db, { reference: 'r-nolink', scope: 'credit_batch', amount: 100 }),
      'causal_outcome_required',
      '22023',
    );
    await expectRejected(
      openReversal(db, { reference: 'r-nolink2', scope: 'withdrawal', amount: 100 }),
      'causal_withdrawal_required',
      '22023',
    );

    const first = await openReversal(db, {
      reference: 'ch-1', scope: 'credit_batch', amount: 150, outcome: OUTCOME,
    });
    assert.equal(first.status, 'open');
    assert.equal(first.replayed, false);
    const replay = await openReversal(db, {
      reference: 'ch-1', scope: 'credit_batch', amount: 150, outcome: OUTCOME,
    });
    assert.equal(replay.replayed, true);
    assert.equal(replay.reversal_id, first.reversal_id);
    await expectRejected(
      openReversal(db, { reference: 'ch-1', scope: 'credit_batch', amount: 160, outcome: OUTCOME }),
      'idempotency_conflict',
      'P0001',
    );
    await expectRejected(
      openReversal(db, { reference: 'ch-x', scope: 'item_payment', amount: 10 }),
      'invalid_reversal',
      '22023',
    );
  } finally {
    await db.close();
  }
});

test('holds and compensation require an explicitly configured policy', async () => {
  const db = await createCommercialDb();
  try {
    await seedWonSale(db);
    const credit = await openReversal(db, {
      reference: 'ch-2', scope: 'credit_batch', amount: 150, outcome: OUTCOME,
    });
    const reward = await openReversal(db, {
      reference: 'ch-3', scope: 'buyer_reward', amount: 15, outcome: OUTCOME,
    });
    await expectRejected(
      adminCommand(db, admin, 'reversal.hold', 'h-1', { reversal_id: credit.reversal_id }),
      'reversal_policy_unconfigured',
      'P0001',
    );
    await expectRejected(
      adminCommand(db, admin, 'reversal.hold', 'h-2', { reversal_id: reward.reversal_id }),
      'reward_hold_policy_unconfigured',
      'P0001',
    );
    // Non-admin can never configure or decide.
    await expectRejected(
      adminCommand(db, seller, 'policy.set', 'p-0', { clawback_mode: 'same_batch_only' }),
      'admin_required',
      '42501',
    );
    await expectRejected(
      adminCommand(db, admin, 'reversal.compensate', 'c-0', { reversal_id: credit.reversal_id }),
      'hold_required_before_compensation',
      'P0001',
    );

    const configured = await adminCommand(db, admin, 'policy.set', 'p-1', {
      clawback_mode: 'same_batch_only',
      reward_hold_enabled: true,
      reward_hold_days: 30,
    });
    assert.equal(configured.singleton, true);
    const status = await state(db);
    assert.equal(status.policy.clawback_mode_configured, true);
    assert.equal(status.policy.reward_hold_configured, true);
    assert.equal(status.policy.reward_hold_days, 30);

    // Hold: exactly the linked batch is reserved, nothing else changes.
    const held = await adminCommand(db, admin, 'reversal.hold', 'h-3', {
      reversal_id: credit.reversal_id,
    });
    assert.equal(held.state, 'held');
    assert.equal(held.hold_minor, 150);
    assert.equal(held.shortfall_minor, 0);
    assert.deepEqual(await batch(db, BATCH), { balance_minor: 200, reserved_minor: 150 });
    assert.deepEqual(await batch(db, BATCH2), { balance_minor: 500, reserved_minor: 0 });

    // Compensation debits only the linked batch and releases the hold.
    const resolved = await adminCommand(db, admin, 'reversal.compensate', 'c-1', {
      reversal_id: credit.reversal_id,
    });
    assert.equal(resolved.state, 'resolved');
    assert.equal(resolved.compensated_minor, 150);
    assert.equal(resolved.shortfall_minor, 0);
    assert.deepEqual(await batch(db, BATCH), { balance_minor: 50, reserved_minor: 0 });
    assert.deepEqual(await batch(db, BATCH2), { balance_minor: 500, reserved_minor: 0 });

    // Append-only: the original charge and both corrections remain.
    const entries = await db.query(
      `SELECT entry_kind, amount_minor, reserve_delta_minor FROM hocalist.ledger_corrections
       WHERE reversal_id=$1`, [credit.reversal_id]);
    assert.deepEqual(
      entries.rows
        .map((r) => [r.entry_kind, r.amount_minor, r.reserve_delta_minor])
        .sort((a, b) => String(a[0]).localeCompare(String(b[0]))),
      [
        ['compensate', -150, 0],
        ['hold', 150, 150],
        ['release_hold', -150, -150],
      ],
    );

    // Reward hold then reversal: the temporary hold is released and the final
    // debit is retained, so the value is not made available again.
    const rewardHeld = await adminCommand(db, admin, 'reversal.hold', 'h-4', {
      reversal_id: reward.reversal_id,
    });
    assert.equal(rewardHeld.hold_minor, 15);
    const heldWallet = await wallet(db);
    assert.equal(heldWallet.earned_minor, 15);
    assert.equal(heldWallet.held_minor, 15);
    assert.equal(heldWallet.available_minor, 0);
    const buyerStatus = await state(db);
    assert.equal(buyerStatus.reward_holds.length, 1);
    assert.equal(buyerStatus.reward_holds[0].amount_minor, 15);
    const rewardResolved = await adminCommand(db, admin, 'reversal.compensate', 'c-2', {
      reversal_id: reward.reversal_id,
    });
    assert.equal(rewardResolved.state, 'resolved');
    assert.equal(rewardResolved.compensated_minor, 15);
    assert.equal(rewardResolved.shortfall_minor, 0);
    const afterResolve = await state(db);
    assert.equal(afterResolve.reward_holds.length, 0);
    const resolvedWallet = await wallet(db);
    assert.equal(resolvedWallet.earned_minor, 15);
    assert.equal(resolvedWallet.held_minor, 0);
    assert.equal(resolvedWallet.reversed_minor, 15);
    // Never available again: earned minus permanent reversal is zero.
    assert.equal(resolvedWallet.available_minor, 0);
    const item = resolvedWallet.items.find((row) => row.id === REWARD);
    assert.equal(item.status, 'held');
    assert.equal(item.hold_minor, 0);
    assert.equal(item.reversed_minor, 15);
    const rewardCorrections = await db.query(
      `SELECT entry_kind FROM hocalist.ledger_corrections WHERE reversal_id=$1`,
      [reward.reversal_id]);
    assert.deepEqual(
      rewardCorrections.rows.map((r) => r.entry_kind).sort(),
      ['reward_hold', 'reward_release', 'reward_reversed'],
    );
  } finally {
    await db.close();
  }
});

test('shortfalls are recorded and dismissal releases holds safely', async () => {
  const db = await createCommercialDb();
  try {
    await seedWonSale(db);
    await adminCommand(db, admin, 'policy.set', 'p-2', { clawback_mode: 'same_batch_only' });
    const over = await openReversal(db, {
      reference: 'ch-4', scope: 'credit_batch', amount: 900, outcome: OUTCOME,
    });
    const held = await adminCommand(db, admin, 'reversal.hold', 'h-5', { reversal_id: over.reversal_id });
    // Only the linked batch's unreserved balance can be held.
    assert.equal(held.hold_minor, 200);
    assert.equal(held.shortfall_minor, 700);
    assert.deepEqual(await batch(db, BATCH), { balance_minor: 200, reserved_minor: 200 });
    const dismissed = await adminCommand(db, admin, 'reversal.dismiss', 'd-1', { reversal_id: over.reversal_id });
    assert.equal(dismissed.state, 'dismissed');
    assert.equal(dismissed.released_minor, 200);
    assert.deepEqual(await batch(db, BATCH), { balance_minor: 200, reserved_minor: 0 });
    assert.deepEqual(await batch(db, BATCH2), { balance_minor: 500, reserved_minor: 0 });
    // A resolved reversal is final.
    await expectRejected(
      adminCommand(db, admin, 'reversal.hold', 'h-6', { reversal_id: over.reversal_id }),
      'reversal_final',
      'P0001',
    );
    // Replays of a decision are answers.
    const replay = await adminCommand(db, admin, 'reversal.dismiss', 'd-1', { reversal_id: over.reversal_id });
    assert.equal(replay.state, 'dismissed');
    const events = await db.query(
      'SELECT event FROM hocalist.reversal_events WHERE reversal_id=$1 ORDER BY revision',
      [over.reversal_id]);
    assert.deepEqual(events.rows.map((r) => r.event), ['opened', 'held', 'dismissed']);
  } finally {
    await db.close();
  }
});

test('holds never leak across accounts and the admin queue is fenced', async () => {
  const db = await createCommercialDb();
  try {
    await seedWonSale(db);
    await adminCommand(db, admin, 'policy.set', 'p-3', {
      clawback_mode: 'same_batch_only', reward_hold_enabled: true,
    });
    const reward = await openReversal(db, {
      reference: 'ch-5', scope: 'buyer_reward', amount: 15, outcome: OUTCOME,
    });
    await adminCommand(db, admin, 'reversal.hold', 'h-7', { reversal_id: reward.reversal_id });
    const owned = await state(db);
    assert.equal(owned.reward_holds.length, 1);
    const other = await callAs(db, 'authenticated', buyer,
      'SELECT hocalist.commercial_reversal_status() AS data').then((rows) => rows[0].data);
    assert.equal(other.reward_holds.length, 1);
    const outsiderView = await callAs(db, 'authenticated', outsider,
      'SELECT hocalist.commercial_reversal_status() AS data').then((rows) => rows[0].data);
    assert.equal(outsiderView.reward_holds.length, 0);
    assert.equal(outsiderView.credit_holds.length, 0);

    await expectRejected(
      callAs(db, 'authenticated', seller,
        'SELECT hocalist.admin_reversal_queue(10,NULL)'),
      'admin_required',
      '42501',
    );
    const queue = await callAs(db, 'authenticated', admin,
      'SELECT hocalist.admin_reversal_queue(10,NULL) AS data')
      .then((rows) => rows[0].data);
    assert.equal(queue.held_count, 1);
    assert.equal(queue.items.length, 1);
    await expectRejected(
      callAs(db, 'anon', outsider,
        'SELECT hocalist.commercial_reversal_status()'),
      'permission denied',
      '42501',
    );
    await expectRejected(
      callAs(db, 'authenticated', seller,
        "SELECT hocalist.reversal_admin_command('policy.set','x','{}'::jsonb)"),
      'admin_required',
      '42501',
    );
  } finally {
    await db.close();
  }
});

test('reward corrections stay bounded, append-only and never re-spendable', async () => {
  const db = await createCommercialDb();
  try {
    await seedWonSale(db);
    await adminCommand(db, admin, 'policy.set', 'p-100', {
      clawback_mode: 'same_batch_only', reward_hold_enabled: true,
    });
    await db.exec(`UPDATE hocalist.buyer_rewards SET amount_minor=100 WHERE id='${REWARD}'`);

    const itemOf = (walletView) => walletView.items.find((row) => row.id === REWARD);
    const reconcile = (walletView) => {
      const pending = walletView.pending_minor;
      const itemHold = walletView.items.reduce((sum, row) => sum + row.hold_minor, 0);
      const itemReversed = walletView.items.reduce((sum, row) => sum + row.reversed_minor, 0);
      assert.equal(walletView.held_minor, pending + itemHold + walletView.withdrawal_hold_minor);
      assert.equal(walletView.reversed_minor, itemReversed);
    };

    // hold -> dismiss releases the temporary reservation.
    const a = await openReversal(db, {
      reference: 'rw-a', scope: 'buyer_reward', amount: 40, outcome: OUTCOME,
    });
    const heldA = await adminCommand(db, admin, 'reversal.hold', 'rh-a', { reversal_id: a.reversal_id });
    assert.equal(heldA.hold_minor, 40);
    assert.equal(heldA.shortfall_minor, 0);
    let view = await wallet(db);
    assert.equal(view.earned_minor, 100);
    assert.equal(view.hold_minor, 40);
    assert.equal(view.available_minor, 60);
    assert.equal(itemOf(view).hold_minor, 40);
    reconcile(view);
    const dismissed = await adminCommand(db, admin, 'reversal.dismiss', 'rd-a', { reversal_id: a.reversal_id });
    assert.equal(dismissed.state, 'dismissed');
    view = await wallet(db);
    assert.equal(view.available_minor, 100);
    assert.equal(view.hold_minor, 0);
    assert.equal(itemOf(view).status, 'earned');
    reconcile(view);

    // hold -> partial/full compensate becomes a retained final debit.
    const b = await openReversal(db, {
      reference: 'rw-b', scope: 'buyer_reward', amount: 60, outcome: OUTCOME,
    });
    await adminCommand(db, admin, 'reversal.hold', 'rh-b', { reversal_id: b.reversal_id });
    const compensatedB = await adminCommand(db, admin, 'reversal.compensate', 'rc-b', {
      reversal_id: b.reversal_id,
    });
    assert.equal(compensatedB.compensated_minor, 60);
    assert.equal(compensatedB.shortfall_minor, 0);
    view = await wallet(db);
    assert.equal(view.reversed_minor, 60);
    assert.equal(view.available_minor, 40);
    assert.equal(itemOf(view).reversed_minor, 60);
    assert.equal(itemOf(view).status, 'held');
    reconcile(view);

    // A second distinct provider event is bounded by the remaining reward.
    const c = await openReversal(db, {
      reference: 'rw-c', scope: 'buyer_reward', amount: 80, outcome: OUTCOME,
    });
    const heldC = await adminCommand(db, admin, 'reversal.hold', 'rh-c', { reversal_id: c.reversal_id });
    assert.equal(heldC.hold_minor, 40);
    assert.equal(heldC.shortfall_minor, 40);
    const compensatedC = await adminCommand(db, admin, 'reversal.compensate', 'rc-c', {
      reversal_id: c.reversal_id,
    });
    assert.equal(compensatedC.compensated_minor, 40);
    // The causal face value was fully recovered; the 40 the provider event
    // could not attribute to this reward is not a reward shortfall.
    assert.equal(compensatedC.reversed_face_minor, 40);
    assert.equal(compensatedC.shortfall_minor, 0);
    view = await wallet(db);
    assert.equal(view.reversed_minor, 100);
    assert.equal(view.available_minor, 0);
    assert.equal(itemOf(view).reversed_minor, 100);
    reconcile(view);

    // Exact retries replay without new corrections.
    const countBefore = await db.query(
      'SELECT count(*)::int AS n FROM hocalist.ledger_corrections WHERE reversal_id=$1',
      [c.reversal_id]).then((r) => r.rows[0].n);
    const retry = await adminCommand(db, admin, 'reversal.compensate', 'rc-c', {
      reversal_id: c.reversal_id,
    });
    assert.equal(retry.compensated_minor, 40);
    const countAfter = await db.query(
      'SELECT count(*)::int AS n FROM hocalist.ledger_corrections WHERE reversal_id=$1',
      [c.reversal_id]).then((r) => r.rows[0].n);
    assert.equal(countAfter, countBefore);
  } finally {
    await db.close();
  }
});

test('an unrecovered reversal never consumes future unrelated rewards', async () => {
  const db = await createCommercialDb();
  try {
    await seedWonSale(db);
    await db.exec(`
      UPDATE auth.users SET email_confirmed_at=now(), phone_confirmed_at=now()
      WHERE id='${buyer}';
      UPDATE hocalist.buyer_rewards SET amount_minor=4000 WHERE id='${REWARD}';
      UPDATE hocalist.reversal_policy SET reward_hold_enabled=true, clawback_mode='same_batch_only';
    `);
    // The first reward is fully withdrawn and actually paid out.
    const withdrawal = await callAs(db, 'authenticated', buyer,
      "SELECT hocalist.withdrawal_request('rw-payout',4000) AS data").then((rows) => rows[0].data);
    await callAs(db, 'service_role', null,
      'SELECT hocalist.withdrawal_settle_internal($1,$2,$3,$4,$5) AS data',
      [withdrawal.withdrawal_id, 'paid', 'fake_payout', 'transfer-paid', null]);
    assert.equal((await wallet(db)).available_minor, 0);

    const r = await openReversal(db, {
      reference: 'rw-paid', scope: 'buyer_reward', amount: 4000, outcome: OUTCOME,
    });
    const held = await adminCommand(db, admin, 'reversal.hold', 'rh-paid', { reversal_id: r.reversal_id });
    assert.equal(held.hold_minor, 0);
    assert.equal(held.shortfall_minor, 4000);
    const compensated = await adminCommand(db, admin, 'reversal.compensate', 'rc-paid', {
      reversal_id: r.reversal_id,
    });
    // Nothing was recoverable: no debit correction, the full face value is
    // recorded, and the shortfall stays explicit for manual policy.
    assert.equal(compensated.compensated_minor, 0);
    assert.equal(compensated.reversed_face_minor, 4000);
    assert.equal(compensated.shortfall_minor, 4000);
    let view = await wallet(db);
    assert.equal(view.earned_minor, 4000);
    assert.equal(view.paid_minor, 4000);
    assert.equal(view.reversed_minor, 0);
    assert.equal(view.shortfall_minor, 4000);
    assert.equal(view.available_minor, 0);

    // A separate, unrelated confirmed purchase earns a new reward. The old
    // unrecovered loss must not consume it.
    await seedExtraReward(db, '000000000009', 3000);
    view = await wallet(db);
    assert.equal(view.earned_minor, 7000);
    assert.equal(view.paid_minor, 4000);
    assert.equal(view.reversed_minor, 0);
    assert.equal(view.shortfall_minor, 4000);
    // The unrelated 3,000 remains fully available and withdrawable.
    assert.equal(view.available_minor, 3000);
    const next = await callAs(db, 'authenticated', buyer,
      "SELECT hocalist.withdrawal_request('rw-new-reward',3000) AS data").then((rows) => rows[0].data);
    assert.equal(next.status, 'processing');
    const finalView = await wallet(db);
    assert.equal(finalView.available_minor, 0);
    assert.equal(finalView.shortfall_minor, 4000);
    assert.equal((await db.query(
      'SELECT status FROM hocalist.withdrawal_requests WHERE id=$1',
      [withdrawal.withdrawal_id])).rows[0].status, 'paid');
  } finally {
    await db.close();
  }
});

test('a partially paid reward reverses only the recoverable part', async () => {
  const db = await createCommercialDb();
  try {
    await seedWonSale(db);
    await db.exec(`
      UPDATE auth.users SET email_confirmed_at=now(), phone_confirmed_at=now()
      WHERE id='${buyer}';
      UPDATE hocalist.buyer_rewards SET amount_minor=4000 WHERE id='${REWARD}';
      UPDATE hocalist.reversal_policy SET reward_hold_enabled=true, clawback_mode='same_batch_only';
    `);
    const withdrawal = await callAs(db, 'authenticated', buyer,
      "SELECT hocalist.withdrawal_request('rw-partial',2500) AS data").then((rows) => rows[0].data);
    await callAs(db, 'service_role', null,
      'SELECT hocalist.withdrawal_settle_internal($1,$2,$3,$4,$5) AS data',
      [withdrawal.withdrawal_id, 'paid', 'fake_payout', 'transfer-partial', null]);

    const r = await openReversal(db, {
      reference: 'rw-partial', scope: 'buyer_reward', amount: 4000, outcome: OUTCOME,
    });
    const held = await adminCommand(db, admin, 'reversal.hold', 'rh-partial', { reversal_id: r.reversal_id });
    assert.equal(held.hold_minor, 1500);
    assert.equal(held.shortfall_minor, 2500);
    const compensated = await adminCommand(db, admin, 'reversal.compensate', 'rc-partial', {
      reversal_id: r.reversal_id,
    });
    assert.equal(compensated.compensated_minor, 1500);
    assert.equal(compensated.reversed_face_minor, 4000);
    assert.equal(compensated.shortfall_minor, 2500);
    let view = await wallet(db);
    assert.equal(view.available_minor, 0);
    assert.equal(view.reversed_minor, 1500);
    assert.equal(view.shortfall_minor, 2500);

    // Future earnings stay available: the recoverable part only.
    await seedExtraReward(db, '000000000010', 3000);
    view = await wallet(db);
    assert.equal(view.earned_minor, 7000);
    assert.equal(view.paid_minor, 2500);
    assert.equal(view.reversed_minor, 1500);
    assert.equal(view.shortfall_minor, 2500);
    assert.equal(view.available_minor, 3000);
  } finally {
    await db.close();
  }
});

test('an unrelated reward arriving between hold and compensation stays available', async () => {
  const db = await createCommercialDb();
  try {
    await seedWonSale(db);
    await db.exec(`
      UPDATE auth.users SET email_confirmed_at=now(), phone_confirmed_at=now()
      WHERE id='${buyer}';
      UPDATE hocalist.buyer_rewards SET amount_minor=4000 WHERE id='${REWARD}';
      UPDATE hocalist.reversal_policy SET reward_hold_enabled=true, clawback_mode='same_batch_only';
    `);
    // A is fully paid out.
    const withdrawal = await callAs(db, 'authenticated', buyer,
      "SELECT hocalist.withdrawal_request('rw-interleave',4000) AS data").then((rows) => rows[0].data);
    await callAs(db, 'service_role', null,
      'SELECT hocalist.withdrawal_settle_internal($1,$2,$3,$4,$5) AS data',
      [withdrawal.withdrawal_id, 'paid', 'fake_payout', 'transfer-interleave', null]);

    const r = await openReversal(db, {
      reference: 'rw-interleave', scope: 'buyer_reward', amount: 4000, outcome: OUTCOME,
    });
    // Nothing of A remains, so the hold reserves nothing.
    const held = await adminCommand(db, admin, 'reversal.hold', 'rh-interleave', { reversal_id: r.reversal_id });
    assert.equal(held.hold_minor, 0);
    assert.equal(held.shortfall_minor, 4000);

    // B arrives AFTER the hold and before compensation.
    await seedExtraReward(db, '000000000011', 3000);
    const compensated = await adminCommand(db, admin, 'reversal.compensate', 'rc-interleave', {
      reversal_id: r.reversal_id,
    });
    // Settlement must not grow the hold into a debit against B.
    assert.equal(compensated.compensated_minor, 0);
    assert.equal(compensated.reversed_face_minor, 4000);
    assert.equal(compensated.shortfall_minor, 4000);
    const view = await wallet(db);
    assert.equal(view.earned_minor, 7000);
    assert.equal(view.paid_minor, 4000);
    assert.equal(view.reversed_minor, 0);
    assert.equal(view.shortfall_minor, 4000);
    assert.equal(view.available_minor, 3000);
    // Real admission agrees: B can still be withdrawn in full.
    const next = await callAs(db, 'authenticated', buyer,
      "SELECT hocalist.withdrawal_request('rw-interleave-b',3000) AS data").then((rows) => rows[0].data);
    assert.equal(next.status, 'processing');
    const after = await wallet(db);
    assert.equal(after.available_minor, 0);
    assert.equal(after.shortfall_minor, 4000);
  } finally {
    await db.close();
  }
});

test('an unrelated reward already present is not charged for an older loss', async () => {
  const db = await createCommercialDb();
  try {
    await seedWonSale(db);
    await db.exec(`
      UPDATE auth.users SET email_confirmed_at=now(), phone_confirmed_at=now()
      WHERE id='${buyer}';
      UPDATE hocalist.buyer_rewards SET amount_minor=4000 WHERE id='${REWARD}';
      UPDATE hocalist.reversal_policy SET reward_hold_enabled=true, clawback_mode='same_batch_only';
    `);
    // B exists before A is fully withdrawn.
    await seedExtraReward(db, '000000000012', 3000);
    const withdrawal = await callAs(db, 'authenticated', buyer,
      "SELECT hocalist.withdrawal_request('rw-before',4000) AS data").then((rows) => rows[0].data);
    await callAs(db, 'service_role', null,
      'SELECT hocalist.withdrawal_settle_internal($1,$2,$3,$4,$5) AS data',
      [withdrawal.withdrawal_id, 'paid', 'fake_payout', 'transfer-before', null]);
    // The withdrawal could only be funded by B (3,000) plus 1,000 of A, so
    // A's unspent part is 3,000 and B is already gone.
    const r = await openReversal(db, {
      reference: 'rw-before', scope: 'buyer_reward', amount: 4000, outcome: OUTCOME,
    });
    const held = await adminCommand(db, admin, 'reversal.hold', 'rh-before', { reversal_id: r.reversal_id });
    assert.equal(held.hold_minor, 3000);
    const compensated = await adminCommand(db, admin, 'reversal.compensate', 'rc-before', {
      reversal_id: r.reversal_id,
    });
    assert.equal(compensated.compensated_minor, 3000);
    assert.equal(compensated.reversed_face_minor, 4000);
    assert.equal(compensated.shortfall_minor, 1000);
    const view = await wallet(db);
    assert.equal(view.earned_minor, 7000);
    assert.equal(view.paid_minor, 4000);
    assert.equal(view.reversed_minor, 3000);
    assert.equal(view.shortfall_minor, 1000);
    assert.equal(view.available_minor, 0);
  } finally {
    await db.close();
  }
});

test('processing then confirmed failure restores funds with the loss retained', async () => {
  const db = await createCommercialDb();
  try {
    await seedWonSale(db);
    await db.exec(`
      UPDATE auth.users SET email_confirmed_at=now(), phone_confirmed_at=now()
      WHERE id='${buyer}';
      UPDATE hocalist.buyer_rewards SET amount_minor=4000 WHERE id='${REWARD}';
      UPDATE hocalist.reversal_policy SET reward_hold_enabled=true, clawback_mode='same_batch_only';
    `);
    const withdrawal = await callAs(db, 'authenticated', buyer,
      "SELECT hocalist.withdrawal_request('rw-processing',4000) AS data").then((rows) => rows[0].data);
    const r = await openReversal(db, {
      reference: 'rw-processing', scope: 'buyer_reward', amount: 4000, outcome: OUTCOME,
    });
    await adminCommand(db, admin, 'reversal.hold', 'rh-processing', { reversal_id: r.reversal_id });
    const compensated = await adminCommand(db, admin, 'reversal.compensate', 'rc-processing', {
      reversal_id: r.reversal_id,
    });
    assert.equal(compensated.compensated_minor, 0);
    assert.equal(compensated.shortfall_minor, 4000);
    assert.equal((await wallet(db)).available_minor, 0);

    // The provider confirms the withdrawal failed; the reserved funds are
    // restored and the recorded shortfall is retained, not erased.
    await callAs(db, 'service_role', null,
      'SELECT hocalist.withdrawal_settle_internal($1,$2,$3,$4,$5) AS data',
      [withdrawal.withdrawal_id, 'failed', null, null, 'bank_rejected']);
    const restored = await wallet(db);
    assert.equal(restored.available_minor, 4000);
    assert.equal(restored.shortfall_minor, 4000);
    const again = await callAs(db, 'authenticated', buyer,
      "SELECT hocalist.withdrawal_request('rw-restored',4000) AS data").then((rows) => rows[0].data);
    assert.equal(again.status, 'processing');
  } finally {
    await db.close();
  }
});

const assertConserved = async (db) => {
  const row = await db.query(`
    SELECT
      coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r
        JOIN hocalist.credit_targets t ON t.id=r.target_id
        WHERE r.buyer_user_id=$1 AND t.status='won'),0) AS earned,
      coalesce((SELECT sum(w.amount_minor) FROM hocalist.withdrawal_requests w
        WHERE w.user_id=$1 AND w.status IN ('processing','paid')),0) AS outflow,
      coalesce((SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
        JOIN hocalist.buyer_rewards w ON w.id=c.target_id
        WHERE c.target_kind='buyer_reward' AND w.buyer_user_id=$1
          AND c.entry_kind IN ('reward_hold','reward_release','reward_reversed')),0) AS reward_corr,
      coalesce((SELECT sum(c.amount_minor) FROM hocalist.ledger_corrections c
        JOIN hocalist.withdrawal_requests wd ON wd.id=c.target_id
        WHERE c.target_kind='withdrawal' AND wd.user_id=$1
          AND c.entry_kind IN ('hold','release_hold')),0) AS withdrawal_corr
  `, [buyer]).then((r) => r.rows[0]);
  const committed =
    Number(row.outflow) + Number(row.reward_corr) + Number(row.withdrawal_corr);
  assert.ok(
    committed <= Number(row.earned),
    `outflow ${row.outflow} + corrections ${row.reward_corr}/${row.withdrawal_corr} exceeded earned ${row.earned}`,
  );
};

async function seedTwoRewardLedger(db) {
  await seedWonSale(db);
  await db.exec(`
    UPDATE auth.users SET email_confirmed_at=now(), phone_confirmed_at=now()
    WHERE id='${buyer}';
    UPDATE hocalist.buyer_rewards SET amount_minor=4000 WHERE id='${REWARD}';
    UPDATE hocalist.reversal_policy SET reward_hold_enabled=true, clawback_mode='same_batch_only';
  `);
  await seedExtraReward(db, '000000000013', 3000);
  const withdrawal = await callAs(db, 'authenticated', buyer,
    "SELECT hocalist.withdrawal_request('rw-two-rewards',4000) AS data").then((rows) => rows[0].data);
  await callAs(db, 'service_role', null,
    'SELECT hocalist.withdrawal_settle_internal($1,$2,$3,$4,$5) AS data',
    [withdrawal.withdrawal_id, 'paid', 'fake_payout', 'transfer-two', null]);
  return withdrawal;
}

test('two rewards cannot both recover the same remaining funds', async () => {
  const db = await createCommercialDb();
  try {
    await seedTwoRewardLedger(db);
    const a = await openReversal(db, {
      reference: 'two-a', scope: 'buyer_reward', amount: 4000, outcome: OUTCOME,
    });
    const b = await openReversal(db, {
      reference: 'two-b', scope: 'buyer_reward', amount: 3000,
      outcome: '70000000-0000-4000-8002-000000000013',
    });
    const heldA = await adminCommand(db, admin, 'reversal.hold', 'two-ha', { reversal_id: a.reversal_id });
    assert.equal(heldA.hold_minor, 3000);
    const compA = await adminCommand(db, admin, 'reversal.compensate', 'two-ca', { reversal_id: a.reversal_id });
    assert.equal(compA.compensated_minor, 3000);
    assert.equal(compA.shortfall_minor, 1000);
    await assertConserved(db);

    // Nothing remains, so the second causal record recovers nothing even
    // though its own estimate would claim 3,000.
    const heldB = await adminCommand(db, admin, 'reversal.hold', 'two-hb', { reversal_id: b.reversal_id });
    assert.equal(heldB.hold_minor, 0);
    assert.equal(heldB.shortfall_minor, 3000);
    const compB = await adminCommand(db, admin, 'reversal.compensate', 'two-cb', { reversal_id: b.reversal_id });
    assert.equal(compB.compensated_minor, 0);
    assert.equal(compB.shortfall_minor, 3000);

    const view = await wallet(db);
    assert.equal(view.earned_minor, 7000);
    assert.equal(view.paid_minor, 4000);
    assert.equal(view.reversed_minor, 3000);
    assert.equal(view.shortfall_minor, 4000);
    assert.equal(view.available_minor, 0);
    await assertConserved(db);

    // A later unrelated reward stays fully withdrawable.
    await seedExtraReward(db, '000000000014', 3000);
    const withC = await wallet(db);
    assert.equal(withC.earned_minor, 10000);
    assert.equal(withC.reversed_minor, 3000);
    assert.equal(withC.shortfall_minor, 4000);
    assert.equal(withC.available_minor, 3000);
    const request = await callAs(db, 'authenticated', buyer,
      "SELECT hocalist.withdrawal_request('two-c',3000) AS data").then((rows) => rows[0].data);
    assert.equal(request.status, 'processing');
    await assertConserved(db);
  } finally {
    await db.close();
  }
});

test('the reverse decision order conserves the same pool', async () => {
  const db = await createCommercialDb();
  try {
    await seedTwoRewardLedger(db);
    const a = await openReversal(db, {
      reference: 'rev-a', scope: 'buyer_reward', amount: 4000, outcome: OUTCOME,
    });
    const b = await openReversal(db, {
      reference: 'rev-b', scope: 'buyer_reward', amount: 3000,
      outcome: '70000000-0000-4000-8002-000000000013',
    });
    const heldB = await adminCommand(db, admin, 'reversal.hold', 'rev-hb', { reversal_id: b.reversal_id });
    assert.equal(heldB.hold_minor, 3000);
    const compB = await adminCommand(db, admin, 'reversal.compensate', 'rev-cb', { reversal_id: b.reversal_id });
    assert.equal(compB.compensated_minor, 3000);
    const heldA = await adminCommand(db, admin, 'reversal.hold', 'rev-ha', { reversal_id: a.reversal_id });
    assert.equal(heldA.hold_minor, 0);
    assert.equal(heldA.shortfall_minor, 4000);
    const compA = await adminCommand(db, admin, 'reversal.compensate', 'rev-ca', { reversal_id: a.reversal_id });
    assert.equal(compA.compensated_minor, 0);
    const view = await wallet(db);
    assert.equal(view.reversed_minor, 3000);
    assert.equal(view.shortfall_minor, 4000);
    assert.equal(view.available_minor, 0);
    await assertConserved(db);
  } finally {
    await db.close();
  }
});

test('holding both before compensating cannot double-reserve', async () => {
  const db = await createCommercialDb();
  try {
    await seedTwoRewardLedger(db);
    const a = await openReversal(db, {
      reference: 'both-a', scope: 'buyer_reward', amount: 4000, outcome: OUTCOME,
    });
    const b = await openReversal(db, {
      reference: 'both-b', scope: 'buyer_reward', amount: 3000,
      outcome: '70000000-0000-4000-8002-000000000013',
    });
    const heldA = await adminCommand(db, admin, 'reversal.hold', 'both-ha', { reversal_id: a.reversal_id });
    assert.equal(heldA.hold_minor, 3000);
    const heldB = await adminCommand(db, admin, 'reversal.hold', 'both-hb', { reversal_id: b.reversal_id });
    assert.equal(heldB.hold_minor, 0);
    assert.equal(heldB.shortfall_minor, 3000);
    await assertConserved(db);
    const compA = await adminCommand(db, admin, 'reversal.compensate', 'both-ca', { reversal_id: a.reversal_id });
    assert.equal(compA.compensated_minor, 3000);
    const compB = await adminCommand(db, admin, 'reversal.compensate', 'both-cb', { reversal_id: b.reversal_id });
    assert.equal(compB.compensated_minor, 0);
    const view = await wallet(db);
    assert.equal(view.reversed_minor, 3000);
    assert.equal(view.shortfall_minor, 4000);
    assert.equal(view.available_minor, 0);
    await assertConserved(db);
  } finally {
    await db.close();
  }
});

test('a reward arriving between decisions is reserved for its owner', async () => {
  const db = await createCommercialDb();
  try {
    await seedTwoRewardLedger(db);
    const a = await openReversal(db, {
      reference: 'mid-a', scope: 'buyer_reward', amount: 4000, outcome: OUTCOME,
    });
    const b = await openReversal(db, {
      reference: 'mid-b', scope: 'buyer_reward', amount: 3000,
      outcome: '70000000-0000-4000-8002-000000000013',
    });
    await adminCommand(db, admin, 'reversal.hold', 'mid-ha', { reversal_id: a.reversal_id });
    await adminCommand(db, admin, 'reversal.compensate', 'mid-ca', { reversal_id: a.reversal_id });
    await seedExtraReward(db, '000000000015', 3000);
    const heldB = await adminCommand(db, admin, 'reversal.hold', 'mid-hb', { reversal_id: b.reversal_id });
    assert.equal(heldB.hold_minor, 0);
    await adminCommand(db, admin, 'reversal.compensate', 'mid-cb', { reversal_id: b.reversal_id });
    const view = await wallet(db);
    assert.equal(view.earned_minor, 10000);
    assert.equal(view.reversed_minor, 3000);
    assert.equal(view.available_minor, 3000);
    await assertConserved(db);
  } finally {
    await db.close();
  }
});

test('a later clean withdrawal cannot move the old recovery boundary', async () => {
  const db = await createCommercialDb();
  try {
    await seedTwoRewardLedger(db);
    const a = await openReversal(db, {
      reference: 'move-a', scope: 'buyer_reward', amount: 4000, outcome: OUTCOME,
    });
    const heldA = await adminCommand(db, admin, 'reversal.hold', 'move-ha', { reversal_id: a.reversal_id });
    assert.equal(heldA.hold_minor, 3000);
    const compA = await adminCommand(db, admin, 'reversal.compensate', 'move-ca', { reversal_id: a.reversal_id });
    assert.equal(compA.compensated_minor, 3000);
    assert.equal(compA.shortfall_minor, 1000);
    assert.equal((await wallet(db)).available_minor, 0);
    await assertConserved(db);

    // A clean reward arrives and is partly withdrawn. Its withdrawal must not
    // reopen the exhausted old pool.
    await seedExtraReward(db, '000000000016', 3000);
    const cleanWithdrawal = await callAs(db, 'authenticated', buyer,
      "SELECT hocalist.withdrawal_request('move-clean',2000) AS data").then((rows) => rows[0].data);
    await callAs(db, 'service_role', null,
      'SELECT hocalist.withdrawal_settle_internal($1,$2,$3,$4,$5) AS data',
      [cleanWithdrawal.withdrawal_id, 'paid', 'fake_payout', 'transfer-move', null]);
    const before = await wallet(db);
    assert.equal(before.earned_minor, 10000);
    assert.equal(before.paid_minor, 6000);
    assert.equal(before.reversed_minor, 3000);
    assert.equal(before.available_minor, 1000);
    await assertConserved(db);

    // The old reward's reversal must fail closed, not reach into the clean
    // reward's remaining 1,000.
    const b = await openReversal(db, {
      reference: 'move-b', scope: 'buyer_reward', amount: 3000,
      outcome: '70000000-0000-4000-8002-000000000013',
    });
    const heldB = await adminCommand(db, admin, 'reversal.hold', 'move-hb', { reversal_id: b.reversal_id });
    assert.equal(heldB.hold_minor, 0);
    assert.equal(heldB.shortfall_minor, 3000);
    const compB = await adminCommand(db, admin, 'reversal.compensate', 'move-cb', { reversal_id: b.reversal_id });
    assert.equal(compB.compensated_minor, 0);
    assert.equal(compB.shortfall_minor, 3000);
    const after = await wallet(db);
    assert.equal(after.earned_minor, 10000);
    assert.equal(after.paid_minor, 6000);
    assert.equal(after.reversed_minor, 3000);
    assert.equal(after.shortfall_minor, 4000);
    assert.equal(after.available_minor, 1000);
    await assertConserved(db);

    // Real admission agrees: the clean 1,000 remains, and no more.
    await expectRejected(
      callAs(db, 'authenticated', buyer,
        "SELECT hocalist.withdrawal_request('move-over',2000)"),
      'insufficient_earned_balance',
      'P0001',
    );
  } finally {
    await db.close();
  }
});

async function seedLedgerWithWithdrawals(db, amounts) {
  await seedWonSale(db);
  await db.exec(`
    UPDATE auth.users SET email_confirmed_at=now(), phone_confirmed_at=now()
    WHERE id='${buyer}';
    UPDATE hocalist.buyer_rewards SET amount_minor=4000 WHERE id='${REWARD}';
    UPDATE hocalist.reversal_policy SET reward_hold_enabled=true, clawback_mode='same_batch_only';
  `);
  await seedExtraReward(db, '000000000017', 3000);
  let index = 0;
  for (const amount of amounts) {
    const withdrawal = await callAs(db, 'authenticated', buyer,
      `SELECT hocalist.withdrawal_request('split-${index}',${amount}) AS data`)
      .then((rows) => rows[0].data);
    await callAs(db, 'service_role', null,
      'SELECT hocalist.withdrawal_settle_internal($1,$2,$3,$4,$5) AS data',
      [withdrawal.withdrawal_id, 'paid', 'fake_payout', `split-ref-${index}`, null]);
    index += 1;
  }
}

for (const [label, amounts] of [
  ['combined', [4000]],
  ['split', [2000, 2000]],
]) {
  test(`split and combined withdrawals give ${label} protection equally`, async () => {
    const db = await createCommercialDb();
    try {
      await seedLedgerWithWithdrawals(db, amounts);
      const a = await openReversal(db, {
        reference: `match-a-${label}`, scope: 'buyer_reward', amount: 4000, outcome: OUTCOME,
      });
      const heldA = await adminCommand(db, admin, 'reversal.hold', `match-ha-${label}`, { reversal_id: a.reversal_id });
      assert.equal(heldA.hold_minor, 3000);
      const compA = await adminCommand(db, admin, 'reversal.compensate', `match-ca-${label}`, { reversal_id: a.reversal_id });
      assert.equal(compA.compensated_minor, 3000);
      assert.equal(compA.shortfall_minor, 1000);
      await assertConserved(db);

      await seedExtraReward(db, '000000000018', 3000);
      const before = await wallet(db);
      assert.equal(before.earned_minor, 10000);
      assert.equal(before.paid_minor, 4000);
      assert.equal(before.reversed_minor, 3000);
      assert.equal(before.available_minor, 3000);

      const b = await openReversal(db, {
        reference: `match-b-${label}`, scope: 'buyer_reward', amount: 3000,
        outcome: '70000000-0000-4000-8002-000000000017',
      });
      const heldB = await adminCommand(db, admin, 'reversal.hold', `match-hb-${label}`, { reversal_id: b.reversal_id });
      assert.equal(heldB.hold_minor, 0);
      assert.equal(heldB.shortfall_minor, 3000);
      const compB = await adminCommand(db, admin, 'reversal.compensate', `match-cb-${label}`, { reversal_id: b.reversal_id });
      assert.equal(compB.compensated_minor, 0);
      assert.equal(compB.shortfall_minor, 3000);

      const after = await wallet(db);
      assert.equal(after.earned_minor, 10000);
      assert.equal(after.paid_minor, 4000);
      assert.equal(after.reversed_minor, 3000);
      assert.equal(after.shortfall_minor, 4000);
      assert.equal(after.available_minor, 3000);
      await assertConserved(db);

      // C stays fully withdrawable under either withdrawal shape.
      const request = await callAs(db, 'authenticated', buyer,
        `SELECT hocalist.withdrawal_request('match-c-${label}',3000) AS data`)
        .then((rows) => rows[0].data);
      assert.equal(request.status, 'processing');
      await assertConserved(db);
    } finally {
      await db.close();
    }
  });
}

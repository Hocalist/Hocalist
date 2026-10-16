// Payout execution bridge proof (migration 183).
//
// Immutable intent identity, lease expiry vs payment finality, reference
// binding, durable late-success review through the worker RPC, provider-change
// fencing, per-attempt provider binding, and the corrected single-payout
// availability. No provider is called.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createCommercialDb, callAs, expectRejected, IDS } from './fixture.mjs';

const { buyer, seller, outsider, admin } = IDS;

const OUTCOME = '70000000-0000-4000-8003-000000000001';
const TARGET = '81000000-0000-4000-8003-000000000001';
const BATCH = '80000000-0000-4000-8003-000000000001';

async function seed(db) {
  await db.exec(`
    UPDATE auth.users SET email_confirmed_at=now(), phone_confirmed_at=now()
    WHERE id='${buyer}';
    INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
    VALUES('30000000-0000-4000-8003-000000000001','${buyer}','${IDS.buyerMembership}',
      'product','Sold item','used','closed');
    INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
    VALUES('40000000-0000-4000-8003-000000000001','30000000-0000-4000-8003-000000000001',
      '${buyer}','${seller}','${IDS.sellerMembership}','completed');
    INSERT INTO hocalist.conversations(id,origin,request_id,offer_id)
    VALUES('60000000-0000-4000-8003-000000000001','targeted_request',
      '30000000-0000-4000-8003-000000000001','40000000-0000-4000-8003-000000000001');
    INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,
      status,meeting_expires_at)
    VALUES('50000000-0000-4000-8003-000000000001','60000000-0000-4000-8003-000000000001',
      '30000000-0000-4000-8003-000000000001','40000000-0000-4000-8003-000000000001',
      '${buyer}','${seller}','accepted',now()+interval '1 day');
    INSERT INTO hocalist.sale_confirmations(id,request_id,meeting_id,offer_id,schedule_revision_id,
      buyer_user_id,seller_user_id)
    VALUES('${OUTCOME}','30000000-0000-4000-8003-000000000001','50000000-0000-4000-8003-000000000001',
      '40000000-0000-4000-8003-000000000001',gen_random_uuid(),'${buyer}','${seller}');
    INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,
      reserved_minor,initial_fee_minor,winning_total_minor,rate_version)
    VALUES('${BATCH}','${seller}','dep-p1',400,200,0,100,200,'v1');
    INSERT INTO hocalist.credit_targets(id,user_id,request_id,batch_id,offer_id,initial_minor,winning_minor,
      charged_minor,reserved_minor,status,week_start,rate_version)
    VALUES('${TARGET}','${seller}','30000000-0000-4000-8003-000000000001','${BATCH}',
      '40000000-0000-4000-8003-000000000001',100,200,200,0,'won',
      date_trunc('week',now() AT TIME ZONE 'UTC')::date,'v1');
    INSERT INTO hocalist.buyer_rewards(outcome_id,target_id,buyer_user_id,amount_minor,rule_version)
    VALUES('${OUTCOME}','${TARGET}','${buyer}',20000,'reward-v1');
  `);
}

const requestWithdrawal = (db, key, amount) =>
  callAs(db, 'authenticated', buyer,
    'SELECT hocalist.withdrawal_request($1,$2) AS data', [key, amount])
    .then((rows) => rows[0].data);

const claim = (db) =>
  callAs(db, 'service_role', null,
    'SELECT hocalist.payout_claim_internal(10,$1) AS data', ['test'])
    .then((rows) => rows[0].data);

const settle = (db, attempt, result, reference = null, reason = null) =>
  callAs(db, 'service_role', null,
    'SELECT hocalist.payout_settle_internal($1,$2,$3,$4) AS data',
    [attempt, result, reference, reason]).then((rows) => rows[0].data);

const service = (db, sql, params = []) =>
  callAs(db, 'service_role', null, sql, params).then((rows) => rows[0].data);

const configure = (db, key, input) =>
  callAs(db, 'authenticated', admin,
    'SELECT hocalist.payout_admin_command($1,$2::jsonb) AS result',
    [key, JSON.stringify(input)]).then((rows) => rows[0].result);

const withdrawal = (db, id) =>
  db.query('SELECT status, provider, provider_reference FROM hocalist.withdrawal_requests WHERE id=$1', [id])
    .then((r) => r.rows[0]);

const attemptRow = (db, id) =>
  db.query('SELECT state, request_key, provider_key, provider_reference FROM hocalist.payout_attempts WHERE id=$1', [id])
    .then((r) => r.rows[0]);

const attempts = (db, id) =>
  db.query('SELECT attempt, state, request_key, provider_key, provider_reference FROM hocalist.payout_attempts WHERE withdrawal_id=$1 ORDER BY attempt', [id])
    .then((r) => r.rows);

test('execution stays disabled and provider-neutral until configured', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    const w = await requestWithdrawal(db, 'w-1', 3000);
    const disabled = await claim(db);
    assert.equal(disabled.status, 'disabled');
    assert.equal(disabled.provider_configured, false);
    assert.equal(disabled.execution_enabled, false);
    assert.deepEqual(disabled.items, []);

    await expectRejected(
      configure(db, 'p-1', { execution_enabled: true }),
      'provider_required_before_enable',
      'P0001',
    );
    await expectRejected(
      configure(db, 'p-2', { provider_key: 'Bad Provider!' }),
      'invalid_provider_key',
      '22023',
    );
    await expectRejected(
      callAs(db, 'authenticated', seller,
        "SELECT hocalist.payout_admin_command('x','{}'::jsonb)"),
      'admin_required',
      '42501',
    );
    await expectRejected(
      callAs(db, 'authenticated', buyer,
        "SELECT hocalist.payout_claim_internal(5,'x')"),
      'permission denied',
      '42501',
    );
    await expectRejected(
      callAs(db, 'authenticated', buyer,
        "SELECT hocalist.payout_settle_internal(gen_random_uuid(),'succeeded','ref')"),
      'permission denied',
      '42501',
    );
    assert.equal((await withdrawal(db, w.withdrawal_id)).status, 'processing');
  } finally {
    await db.close();
  }
});

test('the intent is persisted before dispatch with a stable identity', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    await configure(db, 'p-3', {
      provider_key: 'fake_payout', execution_enabled: true, claim_lease_minutes: 30,
    });
    const w = await requestWithdrawal(db, 'w-2', 3000);
    const first = await claim(db);
    assert.equal(first.status, 'claimed');
    assert.equal(first.claimed, 1);
    assert.equal(first.provider_key, 'fake_payout');
    const item = first.items[0];
    // The worker wire contract: real SQL returns attempt_id and a stable key.
    assert.equal(item.withdrawal_id, w.withdrawal_id);
    assert.equal(item.request_key, w.withdrawal_id);
    assert.equal(typeof item.attempt_id, 'string');
    assert.equal(item.amount_minor, 3000);
    assert.equal(item.fee_minor, 250);
    assert.equal(item.net_minor, 2750);
    assert.equal((await attemptRow(db, item.attempt_id)).state, 'reserved');
    assert.equal((await attemptRow(db, item.attempt_id)).request_key, w.withdrawal_id);

    // A second claim cannot create a second live intent.
    const again = await claim(db);
    assert.equal(again.claimed, 0);
    assert.equal((await attempts(db, w.withdrawal_id)).length, 1);
  } finally {
    await db.close();
  }
});

test('submit and success bind one immutable reference and pay once', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    await configure(db, 'p-4', { provider_key: 'fake_payout', execution_enabled: true });
    const w = await requestWithdrawal(db, 'w-3', 3000);
    const item = (await claim(db)).items[0];
    const attempt = item.attempt_id;

    await expectRejected(
      settle(db, attempt, 'succeeded', null),
      'invalid_provider_reference',
      '22023',
    );
    const submitted = await settle(db, attempt, 'submitted', 'transfer_1');
    assert.equal(submitted.status, 'submitted');
    // A submitted reference is immutable: a different reference is an anomaly
    // and the stored transfer is preserved.
    const mismatch = await settle(db, attempt, 'submitted', 'transfer_replacement');
    assert.equal(mismatch.status, 'reference_mismatch');
    assert.equal(mismatch.expected_reference, 'transfer_1');
    assert.equal((await attemptRow(db, attempt)).provider_reference, 'transfer_1');
    // Exact submit replay is an answer.
    assert.equal((await settle(db, attempt, 'submitted', 'transfer_1')).status, 'submitted');

    const succeeded = await settle(db, attempt, 'succeeded', 'transfer_1');
    assert.equal(succeeded.status, 'succeeded');
    const paid = await withdrawal(db, w.withdrawal_id);
    assert.equal(paid.status, 'paid');
    assert.equal(paid.provider, 'fake_payout');
    assert.equal(paid.provider_reference, 'transfer_1');
    // Exact final replay is an answer; a different final reference is refused.
    assert.equal((await settle(db, attempt, 'succeeded', 'transfer_1')).replayed, true);
    await expectRejected(
      settle(db, attempt, 'succeeded', 'transfer_other'),
      'idempotency_conflict',
      'P0001',
    );
    // A late failure after payout is refused as a second-payout hazard.
    await expectRejected(
      settle(db, attempt, 'failed', null, 'late failure'),
      'late_failure_after_payout',
      'P0001',
    );
    const events = await db.query(
      "SELECT count(*)::int AS n FROM hocalist.withdrawal_events WHERE withdrawal_id=$1 AND event='paid'",
      [w.withdrawal_id]);
    assert.equal(events.rows[0].n, 1);
    const available = await callAs(db, 'authenticated', buyer,
      'SELECT hocalist.commercial_reward_wallet() AS data')
      .then((rows) => rows[0].data);
    assert.equal(available.earned_minor, 20000);
    assert.equal(available.paid_minor, 3000);
    assert.equal(available.available_minor, 17000);
    await expectRejected(
      requestWithdrawal(db, 'w-3b', 20000),
      'insufficient_earned_balance',
      'P0001',
    );
  } finally {
    await db.close();
  }
});

test('confirmed failure restores funds and a late success stays review-only', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    await configure(db, 'p-5', { provider_key: 'fake_payout', execution_enabled: true });
    const w = await requestWithdrawal(db, 'w-4', 4000);
    const item = (await claim(db)).items[0];
    const attempt = item.attempt_id;
    await settle(db, attempt, 'submitted', 'transfer_2');
    const failed = await settle(db, attempt, 'failed', null, 'bank_rejected');
    assert.equal(failed.status, 'failed');
    assert.equal((await withdrawal(db, w.withdrawal_id)).status, 'failed');
    assert.equal((await settle(db, attempt, 'failed', null, 'bank_rejected')).replayed, true);

    // The buyer can request again because the failure restored the funds.
    const again = await requestWithdrawal(db, 'w-4b', 4000);
    assert.equal(again.status, 'processing');

    // Through the worker RPC, a late success on the SAME transfer reference
    // becomes durable review evidence and never pays a second time.
    const late = await settle(db, attempt, 'succeeded', 'transfer_2', 'late success');
    assert.equal(late.status, 'late_success_review');
    assert.equal((await attemptRow(db, attempt)).state, 'late_success_review');
    assert.equal((await attemptRow(db, attempt)).provider_reference, 'transfer_2');
    assert.equal((await withdrawal(db, w.withdrawal_id)).status, 'failed');
    assert.equal((await settle(db, attempt, 'succeeded', 'transfer_2', 'late success')).replayed, true);
    await expectRejected(
      settle(db, attempt, 'succeeded', 'transfer_late_2'),
      'idempotency_conflict',
      'P0001',
    );
    const events = await db.query(
      "SELECT event FROM hocalist.withdrawal_events WHERE withdrawal_id=$1 ORDER BY revision",
      [w.withdrawal_id]);
    assert.deepEqual(events.rows.map((r) => r.event), ['requested', 'failed', 'reconciliation']);
  } finally {
    await db.close();
  }
});

test('lease expiry keeps the same intent and requires reconciliation first', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    await configure(db, 'p-6', {
      provider_key: 'fake_payout', execution_enabled: true, claim_lease_minutes: 5,
    });
    const w = await requestWithdrawal(db, 'w-5', 3000);
    const item = (await claim(db)).items[0];
    const attempt = item.attempt_id;
    await db.query(
      "UPDATE hocalist.payout_attempts SET created_at=now()-interval '1 hour' WHERE id=$1",
      [attempt]);
    const expired = await service(db, 'SELECT hocalist.payout_lease_expire_internal(10) AS data');
    assert.equal(expired.expired, 1);
    assert.equal((await attemptRow(db, attempt)).state, 'outcome_unknown');

    // No replacement intent is created; the unknown outcome is reconciled
    // through the same immutable key.
    const secondClaim = await claim(db);
    assert.equal(secondClaim.claimed, 0);
    const reconcile = await service(db, 'SELECT hocalist.payout_reconcile_batch_internal(10) AS data');
    assert.equal(reconcile.items.length, 1);
    assert.equal(reconcile.items[0].attempt_id, attempt);
    assert.equal(reconcile.items[0].request_key, w.withdrawal_id);
    assert.equal(reconcile.items[0].provider_reference, null);
    assert.equal(reconcile.items[0].amount_minor, 3000);

    const settled = await settle(db, attempt, 'succeeded', 'transfer_reconciled');
    assert.equal(settled.status, 'succeeded');
    assert.equal((await withdrawal(db, w.withdrawal_id)).status, 'paid');
    assert.equal((await attempts(db, w.withdrawal_id)).length, 1);
  } finally {
    await db.close();
  }
});

test('one reference cannot settle two withdrawals', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    await configure(db, 'p-7', { provider_key: 'fake_payout', execution_enabled: true });
    const a = await requestWithdrawal(db, 'w-6a', 3000);
    const b = await requestWithdrawal(db, 'w-6b', 3000);
    const claimed = await claim(db);
    assert.equal(claimed.claimed, 2);
    const [first, second] = claimed.items;
    assert.notEqual(first.withdrawal_id, second.withdrawal_id);
    await settle(db, first.attempt_id, 'succeeded', 'shared_reference');
    await expectRejected(
      settle(db, second.attempt_id, 'succeeded', 'shared_reference'),
      'reference_already_used',
      'P0001',
    );
    assert.equal((await withdrawal(db, b.withdrawal_id)).status, 'processing');
    // The other withdrawal can still settle with its own reference.
    assert.equal((await settle(db, second.attempt_id, 'succeeded', 'own_reference')).status, 'succeeded');
    assert.equal((await withdrawal(db, a.withdrawal_id)).status, 'paid');
    assert.equal((await withdrawal(db, b.withdrawal_id)).status, 'paid');
  } finally {
    await db.close();
  }
});

test('provider changes are fenced while unresolved intents exist', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    await configure(db, 'p-8', { provider_key: 'provider_a', execution_enabled: true });
    const w = await requestWithdrawal(db, 'w-7', 3000);
    const item = (await claim(db)).items[0];
    await expectRejected(
      configure(db, 'p-9', { provider_key: 'provider_b' }),
      'unresolved_intents_present',
      'P0001',
    );
    // Polling returns submitted attempts with their own provider binding.
    await settle(db, item.attempt_id, 'submitted', 'ref_a');
    const poll = await service(db, 'SELECT hocalist.payout_poll_batch_internal(10) AS data');
    assert.equal(poll.items.length, 1);
    assert.equal(poll.items[0].provider_key, 'provider_a');
    assert.equal(poll.items[0].attempt_id, item.attempt_id);
    assert.equal(poll.items[0].request_key, w.withdrawal_id);
    assert.equal(poll.items[0].provider_reference, 'ref_a');

    await settle(db, item.attempt_id, 'succeeded', 'ref_a');
    const changed = await configure(db, 'p-9', { provider_key: 'provider_b' });
    assert.equal(changed.singleton, true);

    // Polling works even when new claims are disabled: a dispatched intent
    // must still be settled.
    await configure(db, 'p-10', { execution_enabled: false });
    const poll3 = await service(db, 'SELECT hocalist.payout_poll_batch_internal(10) AS data');
    assert.equal(poll3.status, 'ok');
  } finally {
    await db.close();
  }
});

test('the reconciliation queue is admin-only and reports review states', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    await configure(db, 'p-11', { provider_key: 'fake_payout', execution_enabled: true });
    await expectRejected(
      callAs(db, 'authenticated', seller,
        'SELECT hocalist.admin_payout_reconciliation_queue(10)'),
      'admin_required',
      '42501',
    );
    const w = await requestWithdrawal(db, 'w-8', 3000);
    const item = (await claim(db)).items[0];
    const queue = await callAs(db, 'authenticated', admin,
      'SELECT hocalist.admin_payout_reconciliation_queue(10) AS data')
      .then((rows) => rows[0].data);
    assert.equal(queue.policy.provider_configured, true);
    assert.equal(queue.policy.execution_enabled, true);
    assert.equal(queue.processing_withdrawals, 1);
    assert.equal(queue.outcome_unknown, 0);
    assert.equal(queue.attempts.length, 1);
    assert.equal(queue.attempts[0].withdrawal_id, w.withdrawal_id);
    assert.equal(queue.attempts[0].state, 'reserved');

    await db.query(
      "UPDATE hocalist.payout_attempts SET created_at=now()-interval '1 hour' WHERE id=$1",
      [item.attempt_id]);
    await service(db, 'SELECT hocalist.payout_lease_expire_internal(10)');
    const review = await callAs(db, 'authenticated', admin,
      'SELECT hocalist.admin_payout_reconciliation_queue(10) AS data')
      .then((rows) => rows[0].data);
    assert.equal(review.outcome_unknown, 1);

    // Idempotent admin configuration.
    const replay = await configure(db, 'p-11', {
      provider_key: 'fake_payout', execution_enabled: true,
    });
    assert.equal(replay.singleton, true);
    await expectRejected(
      configure(db, 'p-11', { provider_key: 'other_provider' }),
      'idempotency_conflict',
      'P0001',
    );
  } finally {
    await db.close();
  }
});

test('a known transfer reference is immutable across late outcomes', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    await configure(db, 'p-12', { provider_key: 'fake_payout', execution_enabled: true });
    const w = await requestWithdrawal(db, 'w-9', 3000);
    const item = (await claim(db)).items[0];
    const attempt = item.attempt_id;
    await settle(db, attempt, 'submitted', 'original-transfer');
    await settle(db, attempt, 'failed', null, 'bank_rejected');

    // A different reference on the failed attempt is an anomaly: recorded,
    // rejected, and the original binding is preserved.
    const anomaly = await settle(db, attempt, 'succeeded', 'different-transfer', 'mismatch');
    assert.equal(anomaly.status, 'reference_mismatch');
    assert.equal(anomaly.expected_reference, 'original-transfer');
    assert.equal(anomaly.received_reference, 'different-transfer');
    const unchanged = await attemptRow(db, attempt);
    assert.equal(unchanged.state, 'failed');
    assert.equal(unchanged.provider_reference, 'original-transfer');
    assert.equal((await withdrawal(db, w.withdrawal_id)).status, 'failed');
    const anomalyEvents = await db.query(
      "SELECT count(*)::int AS n FROM hocalist.withdrawal_events WHERE withdrawal_id=$1 AND event='reconciliation'",
      [w.withdrawal_id]).then((r) => r.rows[0].n);
    assert.equal(anomalyEvents, 1);

    // The same known reference still produces durable review evidence.
    const late = await settle(db, attempt, 'succeeded', 'original-transfer', 'late success');
    assert.equal(late.status, 'late_success_review');
    assert.equal((await attemptRow(db, attempt)).state, 'late_success_review');
    assert.equal((await attemptRow(db, attempt)).provider_reference, 'original-transfer');
    // Repeated review replay and other-reference conflicts stay stable.
    assert.equal(
      (await settle(db, attempt, 'succeeded', 'original-transfer')).replayed,
      true,
    );
    await expectRejected(
      settle(db, attempt, 'succeeded', 'other-transfer'),
      'idempotency_conflict',
      'P0001',
    );
  } finally {
    await db.close();
  }
});

test('an initially unreferenced failure binds the first late-success reference', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    await configure(db, 'p-13', { provider_key: 'fake_payout', execution_enabled: true });
    const w = await requestWithdrawal(db, 'w-10', 3000);
    const item = (await claim(db)).items[0];
    const attempt = item.attempt_id;
    // Failure before any submission confirmation: no reference is stored yet.
    await settle(db, attempt, 'failed', null, 'provider_rejected');
    assert.equal((await attemptRow(db, attempt)).provider_reference, null);
    const late = await settle(db, attempt, 'succeeded', 'first-seen-transfer', 'late success');
    assert.equal(late.status, 'late_success_review');
    assert.equal((await attemptRow(db, attempt)).provider_reference, 'first-seen-transfer');
    assert.equal((await withdrawal(db, w.withdrawal_id)).status, 'failed');
    // A conflicting reference on the review record is still refused.
    await expectRejected(
      settle(db, attempt, 'succeeded', 'second-transfer'),
      'idempotency_conflict',
      'P0001',
    );
  } finally {
    await db.close();
  }
});

// Worker/SQL wire-contract proof.
//
// The reviewed executor is driven against the REAL migration output: every rpc
// response comes from the disposable PGlite database, not a hand-written
// fixture. The fake provider stays in the test. This is deterministic
// single-connection proof, not concurrency or provider proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createCommercialDb, callAs, IDS } from './fixture.mjs';

const { buyer, seller, admin } = IDS;
const OUTCOME = '70000000-0000-4000-8003-000000000001';
const TARGET = '81000000-0000-4000-8003-000000000001';
const BATCH = '80000000-0000-4000-8003-000000000001';

const worker = await import(
  '../../../supabase/functions/hocalist-commercial-worker/executor.ts'
).catch((error) => {
  throw new Error(`worker executor import failed: ${error.message}`);
});

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
    VALUES('${BATCH}','${seller}','dep-c1',400,200,0,100,200,'v1');
    INSERT INTO hocalist.credit_targets(id,user_id,request_id,batch_id,offer_id,initial_minor,winning_minor,
      charged_minor,reserved_minor,status,week_start,rate_version)
    VALUES('${TARGET}','${seller}','30000000-0000-4000-8003-000000000001','${BATCH}',
      '40000000-0000-4000-8003-000000000001',100,200,200,0,'won',
      date_trunc('week',now() AT TIME ZONE 'UTC')::date,'v1');
    INSERT INTO hocalist.buyer_rewards(outcome_id,target_id,buyer_user_id,amount_minor,rule_version)
    VALUES('${OUTCOME}','${TARGET}','${buyer}',20000,'reward-v1');
  `);
  await callAs(db, 'authenticated', admin,
    'SELECT hocalist.payout_admin_command($1,$2::jsonb) AS result',
    ['wc-config', JSON.stringify({
      provider_key: 'fake_payout',
      execution_enabled: true,
      claim_lease_minutes: 30,
    })]);
  await callAs(db, 'authenticated', buyer,
    "SELECT hocalist.withdrawal_request('wc-1',3000) AS data");
}

// Routes each executor rpc to the real SQL function and returns its JSON.
function realRpc(db) {
  const service = (sql, params) =>
    callAs(db, 'service_role', null, sql, params).then((rows) => rows[0].data);
  return async (functionName, params) => {
    switch (functionName) {
      case 'payout_lease_expire_internal':
        return service('SELECT hocalist.payout_lease_expire_internal($1) AS data', [params.p_limit]);
      case 'payout_claim_internal':
        return service('SELECT hocalist.payout_claim_internal($1,$2) AS data',
          [params.p_limit, params.p_runner]);
      case 'payout_reconcile_batch_internal':
        return service('SELECT hocalist.payout_reconcile_batch_internal($1) AS data',
          [params.p_limit]);
      case 'payout_poll_batch_internal':
        return service('SELECT hocalist.payout_poll_batch_internal($1) AS data',
          [params.p_limit]);
      case 'payout_settle_internal':
        return service('SELECT hocalist.payout_settle_internal($1,$2,$3,$4) AS data',
          [params.p_attempt, params.p_result, params.p_reference, params.p_reason]);
      default:
        throw new Error(`unexpected rpc ${functionName}`);
    }
  };
}

function fakeProvider({ key = 'fake_payout', pollState = 'succeeded' } = {}) {
  const intents = new Map();
  return {
    key,
    intents,
    submissions: [],
    async submit(request) {
      this.submissions.push(request.requestKey);
      let intent = intents.get(request.requestKey);
      if (!intent) {
        intent = { state: 'accepted', reference: `real-ref-${intents.size + 1}` };
        intents.set(request.requestKey, intent);
      }
      return { state: 'pending', reference: intent.reference };
    },
    async poll(reference) {
      const intent = [...intents.values()].find((i) => i.reference === reference);
      if (!intent) return { state: 'failed', reason: 'unknown_reference' };
      if (pollState === 'succeeded') {
        return { state: 'succeeded', reference };
      }
      if (pollState === 'failed') {
        return { state: 'failed', reason: 'provider_failed' };
      }
      return { state: 'pending', reference };
    },
  };
}

test('the executor consumes real claim/poll/settle SQL output end to end', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    // The executor consumes the real SQL claim response; capture it as the
    // wire contract under test.
    const provider = fakeProvider();
    let rawClaim = null;
    const capturingRpc = async (functionName, params) => {
      const data = await realRpc(db)(functionName, params);
      if (functionName === 'payout_claim_internal') rawClaim = data;
      return data;
    };
    const first = await worker.runPayoutCycle({ rpc: capturingRpc, provider });
    assert.equal(first.claimed, 1);
    assert.equal(first.succeeded, 1);
    assert.ok(rawClaim, 'claim response was not observed');
    assert.equal(rawClaim.status, 'claimed');
    assert.equal(rawClaim.items.length, 1);
    const rawItem = rawClaim.items[0];
    for (const field of [
      'attempt_id', 'withdrawal_id', 'request_key', 'provider_key',
      'amount_minor', 'fee_minor', 'net_minor', 'currency',
    ]) {
      assert.ok(field in rawItem, `real SQL claim is missing ${field}`);
    }
    assert.equal(rawItem.request_key, rawItem.withdrawal_id);

    const withdrawal = await db.query(
      'SELECT status, provider, provider_reference FROM hocalist.withdrawal_requests WHERE id=$1',
      [rawItem.withdrawal_id]).then((r) => r.rows[0]);
    assert.equal(withdrawal.status, 'paid');
    assert.equal(withdrawal.provider, 'fake_payout');
    assert.equal(withdrawal.provider_reference, 'real-ref-1');
    assert.equal(provider.intents.size, 1);
    const attempts = await db.query(
      'SELECT count(*)::int AS n FROM hocalist.payout_attempts WHERE withdrawal_id=$1',
      [rawItem.withdrawal_id]).then((r) => r.rows[0].n);
    assert.equal(attempts, 1);

    // A second cycle cannot create another intent or pay again.
    const second = await worker.runPayoutCycle({ rpc: realRpc(db), provider });
    assert.equal(second.claimed, 0);
    assert.equal(second.succeeded, 0);
    assert.equal(provider.intents.size, 1);
  } finally {
    await db.close();
  }
});

test('a real late_success_review SQL status is accepted by the executor', async () => {
  const db = await createCommercialDb();
  try {
    await seed(db);
    // Fail the withdrawal through the executor, then let the provider report a
    // late success on the next cycle.
    const failingProvider = fakeProvider({ pollState: 'failed' });
    const first = await worker.runPayoutCycle({ rpc: realRpc(db), provider: failingProvider });
    assert.equal(first.failed, 1);
    const withdrawal = await db.query(
      "SELECT id, status FROM hocalist.withdrawal_requests WHERE user_id=$1", [buyer])
      .then((r) => r.rows[0]);
    assert.equal(withdrawal.status, 'failed');

    const attempt = await db.query(
      'SELECT id, provider_reference FROM hocalist.payout_attempts WHERE withdrawal_id=$1',
      [withdrawal.id]).then((r) => r.rows[0]);
    const lateProvider = {
      key: 'fake_payout',
      async submit() {
        throw new Error('unexpected submit');
      },
      async poll(reference) {
        return { state: 'succeeded', reference };
      },
    };
    // The same reference is now reported as a success through the worker RPC.
    const late = await worker.runPayoutCycle({
      rpc: async (functionName, params) => {
        if (functionName === 'payout_settle_internal' && params.p_result === 'succeeded') {
          // Route through the real SQL with the recorded reference.
          return callAs(db, 'service_role', null,
            'SELECT hocalist.payout_settle_internal($1,$2,$3,$4) AS data',
            [attempt.id, 'succeeded', attempt.provider_reference, 'late success'])
            .then((r) => r[0].data);
        }
        if (functionName === 'payout_poll_batch_internal') {
          return {
            status: 'ok',
            provider_key: 'fake_payout',
            items: [{
              attempt_id: attempt.id,
              withdrawal_id: withdrawal.id,
              attempt: 1,
              request_key: withdrawal.id,
              provider_key: 'fake_payout',
              provider_reference: attempt.provider_reference,
            }],
          };
        }
        return realRpc(db)(functionName, params);
      },
      provider: lateProvider,
    });
    assert.equal(late.review, 1);
    assert.equal(late.succeeded, 0);
    const after = await db.query(
      'SELECT status FROM hocalist.withdrawal_requests WHERE id=$1', [withdrawal.id])
      .then((r) => r.rows[0]);
    assert.equal(after.status, 'failed');
    const reviewState = await db.query(
      'SELECT state FROM hocalist.payout_attempts WHERE id=$1', [attempt.id])
      .then((r) => r.rows[0]);
    assert.equal(reviewState.state, 'late_success_review');
  } finally {
    await db.close();
  }
});

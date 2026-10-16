// Disposable PostgreSQL checks for the provider-neutral website credit
// checkout: account-bound begin/bind, signed-event-only finish, amount
// validation, rate snapshotting and idempotent batch creation. No Stripe call.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setup } from '../../outcomes/tests/fixture.mjs';

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const C = '00000000-0000-4000-8000-00000000000c';

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

test('website credit checkout snapshots rates and never trusts a redirect', async (t) => {
  const db = await setup(false);
  try {
    for (const path of [
      '../../marketplace/021_request_coordinates.sql',
      '../../marketplace/023_multi_negotiation.sql',
      '../../outcomes/080_sale_confirmation.sql',
      '../090_credit_batches.sql',
      '../091_buyer_rewards.sql',
      '../092_credit_settlement.sql',
      '../094_deposit_checkout.sql',
    ]) {
      await db.exec(await read(path));
    }
    const option = (await db.query(
      `INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version)
       VALUES (2000,155,375,'deposit-20-v1') RETURNING id`)).rows[0].id;

    const beginWith = (user, optionId, key) =>
      callAs(db, 'service_role', '', 'SELECT hocalist.stripe_test_deposit_begin($1,$2,$3) AS data',
        [user, optionId, key]).then((rows) => rows[0].data);
    const begin = (user, key) => beginWith(user, option, key);
    const bind = (checkout, customer, session) =>
      callAs(db, 'service_role', '',
        'SELECT hocalist.stripe_test_deposit_bind($1,$2,$3,$4)',
        [checkout, customer, session, 'https://checkout.stripe.com/c/pay/test']);
    const finish = (checkout, customer, amount, reference, error = null) =>
      callAs(db, 'service_role', '',
        'SELECT hocalist.stripe_test_deposit_finish($1,$2,$3,$4,$5) AS data',
        [checkout, customer, amount, reference, error]).then((rows) => rows[0].data);

    let first;
    let firstBatchId;
    await t.test('begin creates an account-bound checkout without a batch', async () => {
      first = await begin(B, '2f0c9d1a-0000-4000-8000-000000000001');
      assert.equal(first.state, 'creating');
      assert.equal(first.amount_minor, 2000);
      assert.equal(first.initial_fee_minor, 155);
      assert.equal(first.winning_total_minor, 375);
      assert.equal(first.rate_version, 'deposit-20-v1');
      const batches = await db.query('SELECT count(*)::int AS n FROM hocalist.credit_batches');
      assert.equal(batches.rows[0].n, 0, 'a checkout is not an entitlement');
    });

    await t.test('a client cannot begin or finish a deposit checkout', async () => {
      await expectRejected(
        callAs(db, 'authenticated', B,
          'SELECT hocalist.stripe_test_deposit_begin($1,$2,$3)', [B, option, '2f0c9d1a-0000-4000-8000-000000000009']),
        'permission denied',
      );
      await expectRejected(
        callAs(db, 'authenticated', B,
          "SELECT hocalist.stripe_test_deposit_finish($1,'cus_x',2000,'pi_x',NULL)", [first.checkout_id]),
        'permission denied',
      );
    });

    await t.test('bind attaches the provider customer and session', async () => {
      await bind(first.checkout_id, 'cus_testdeposit1', 'cs_test_session1');
      const status = (await callAs(db, 'authenticated', B,
        'SELECT hocalist.credit_deposit_status() AS data'))[0].data;
      assert.equal(status.options[0].amount_minor, 2000);
      assert.equal(status.checkouts[0].state, 'open');
    });

    await t.test('a mismatched paid amount is refused and creates nothing', async () => {
      await expectRejected(
        finish(first.checkout_id, 'cus_testdeposit1', 1900, 'pi_wrong'),
        'amount_mismatch',
        'P0001',
      );
      const batches = await db.query('SELECT count(*)::int AS n FROM hocalist.credit_batches');
      assert.equal(batches.rows[0].n, 0);
    });

    await t.test('a verified payment creates one batch with the snapshot rates', async () => {
      const done = await finish(first.checkout_id, 'cus_testdeposit1', 2000, 'pi_ok_1');
      assert.equal(done.status, 'complete');
      firstBatchId = done.batch_id;
      const batch = await db.query(
        'SELECT original_minor, initial_fee_minor, winning_total_minor, rate_version FROM hocalist.credit_batches WHERE id=$1',
        [done.batch_id]);
      assert.deepEqual(batch.rows[0], {
        original_minor: 2000, initial_fee_minor: 155,
        winning_total_minor: 375, rate_version: 'deposit-20-v1',
      });
      const replay = await finish(first.checkout_id, 'cus_testdeposit1', 2000, 'pi_ok_1');
      assert.equal(replay.batch_id, done.batch_id);
      const count = await db.query('SELECT count(*)::int AS n FROM hocalist.credit_batches');
      assert.equal(count.rows[0].n, 1, 'a replayed event never double-credits');
    });

    await t.test('only one deposit checkout can be open at a time', async () => {
      const second = await begin(B, '2f0c9d1a-0000-4000-8000-000000000002');
      assert.equal(second.state, 'creating');
      await expectRejected(
        begin(B, '2f0c9d1a-0000-4000-8000-000000000003'),
        'checkout_pending',
        'P0001',
      );
      // A later admin rate edit must not reprice the checkout already started.
      await db.query(
        "UPDATE hocalist.credit_deposit_options SET initial_fee_minor=160,winning_total_minor=380,rate_version='deposit-20-v2',revision=revision+1 WHERE id=$1",
        [option]);
      await bind(second.checkout_id, 'cus_testdeposit1', 'cs_test_session2');
      const done = await finish(second.checkout_id, 'cus_testdeposit1', 2000, 'pi_ok_2');
      const batch = await db.query(
        'SELECT initial_fee_minor, winning_total_minor, rate_version FROM hocalist.credit_batches WHERE id=$1',
        [done.batch_id]);
      assert.deepEqual(batch.rows[0], {
        initial_fee_minor: 155, winning_total_minor: 375, rate_version: 'deposit-20-v1',
      });
    });

    await t.test('an unchanged retry recovers the snapshot after an edit or retirement', async () => {
      const cKey = '2f0c9d1a-0000-4000-8000-0000000000c1';
      const firstC = await begin(C, cKey);
      assert.equal(firstC.rate_version, 'deposit-20-v2', 'created from the current option');
      await bind(firstC.checkout_id, 'cus_testdepositc', 'cs_test_sessionc');
      // An admin fee edit must not break the original intent.
      await db.query(
        "UPDATE hocalist.credit_deposit_options SET initial_fee_minor=165,winning_total_minor=385,rate_version='deposit-20-v3',revision=revision+1 WHERE id=$1",
        [option]);
      const afterEdit = await begin(C, cKey);
      assert.equal(afterEdit.checkout_id, firstC.checkout_id);
      assert.equal(afterEdit.rate_version, 'deposit-20-v2', 'snapshot, not current settings');
      assert.equal(afterEdit.winning_total_minor, 380, 'the pre-edit snapshot, not 385');
      // Retiring the option must not break the retry either.
      await db.query(
        'UPDATE hocalist.credit_deposit_options SET active=false,revision=revision+1 WHERE id=$1',
        [option]);
      const afterRetire = await begin(C, cKey);
      assert.equal(afterRetire.checkout_id, firstC.checkout_id);
      assert.equal(afterRetire.rate_version, 'deposit-20-v2');
      assert.equal(afterRetire.state, 'open');
      // Only a new checkout intent needs the current catalogue.
      await expectRejected(
        begin(C, '2f0c9d1a-0000-4000-8000-0000000000c2'),
        'invalid_option_or_key',
        '22023',
      );
      // A different option under the same key is a changed intent.
      const secondOption = (await db.query(
        `INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version,sort_order)
         VALUES (4000,145,325,'deposit-40-v1',1) RETURNING id`)).rows[0].id;
      await expectRejected(
        beginWith(C, secondOption, cKey),
        'idempotency_conflict',
        'P0001',
      );
      // Restore the catalogue for the later tests, then complete this checkout.
      await db.query(
        "UPDATE hocalist.credit_deposit_options SET initial_fee_minor=155,winning_total_minor=375,rate_version='deposit-20-v2',active=true,revision=revision+1 WHERE id=$1",
        [option]);
      const done = await finish(firstC.checkout_id, 'cus_testdepositc', 2000, 'pi_c_ok');
      assert.equal(done.status, 'complete');
      const replay = await finish(firstC.checkout_id, 'cus_testdepositc', 2000, 'pi_c_ok');
      assert.equal(replay.batch_id, done.batch_id);
      // Another checkout can never reuse the provider reference.
      const nextC = await begin(C, '2f0c9d1a-0000-4000-8000-0000000000c3');
      await bind(nextC.checkout_id, 'cus_testdepositc', 'cs_test_sessionc2');
      await expectRejected(
        finish(nextC.checkout_id, 'cus_testdepositc', 2000, 'pi_c_ok'),
        'idempotency_conflict',
        'P0001',
      );
    });

    await t.test('conflicting finish replays fail; identical retries return the batch', async () => {
      const replay = await finish(first.checkout_id, 'cus_testdeposit1', 2000, 'pi_ok_1');
      assert.equal(replay.batch_id, firstBatchId);
      await expectRejected(
        finish(first.checkout_id, 'cus_testdeposit1', 2000, 'pi_other'),
        'idempotency_conflict',
        'P0001',
      );
      await expectRejected(
        finish(first.checkout_id, 'cus_testdeposit1', 1, 'pi_ok_1'),
        'amount_mismatch',
        'P0001',
      );
      await expectRejected(
        finish(first.checkout_id, 'cus_testdeposit1', 2000, 'pi_ok_1', 'review_required'),
        'checkout_closed',
        'P0001',
      );
      await expectRejected(
        finish(first.checkout_id, 'cus_other', 2000, 'pi_ok_1'),
        'customer_conflict',
        'P0001',
      );
      const association = await db.query(
        'SELECT state, provider_reference, credit_batch_id FROM hocalist.stripe_test_checkouts WHERE id=$1',
        [first.checkout_id]);
      assert.deepEqual(association.rows[0], {
        state: 'complete', provider_reference: 'pi_ok_1', credit_batch_id: firstBatchId,
      });
    });

    await t.test('a review-required event blocks further deposits without crediting', async () => {
      const before = (await db.query(
        'SELECT count(*)::int AS n FROM hocalist.credit_batches')).rows[0].n;
      const third = await begin(B, '2f0c9d1a-0000-4000-8000-000000000004');
      await bind(third.checkout_id, 'cus_testdeposit1', 'cs_test_session3');
      const flagged = await finish(third.checkout_id, 'cus_testdeposit1', 2000, 'pi_review', 'review_required');
      assert.equal(flagged.status, 'review_required');
      const batches = await db.query('SELECT count(*)::int AS n FROM hocalist.credit_batches');
      assert.equal(batches.rows[0].n, before, 'a review flag credits nothing new');
      await expectRejected(
        begin(B, '2f0c9d1a-0000-4000-8000-000000000005'),
        'billing_review_required',
        'P0001',
      );
    });

    await t.test('the status read is seller-only and hides provider secrets', async () => {
      await expectRejected(
        callAs(db, 'authenticated', A, 'SELECT hocalist.credit_deposit_status()'),
        'billing_access_denied',
      );
      const status = (await callAs(db, 'authenticated', B,
        'SELECT hocalist.credit_deposit_status() AS data'))[0].data;
      const raw = JSON.stringify(status);
      assert.doesNotMatch(raw, /cus_|cs_test_|client_secret|price_/);
      assert.equal(status.checkouts.filter((row) => row.state === 'complete').length, 2);
      assert.equal(status.options[0].rate_version, 'deposit-20-v2');
    });
  } finally {
    await db.close();
  }
});

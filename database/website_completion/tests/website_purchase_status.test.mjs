// Disposable PostgreSQL checks for the website purchase read (172): the exact
// checkout lookup is account-scoped, the plan and pack catalogues come from the
// configuration, and completion time is the verified credit time. PGlite is
// local single-connection proof, not live JWT/PostgREST proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setup } from '../../outcomes/tests/fixture.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const MISSING = '00000000-0000-4000-8000-0000000000ff';

async function asRole(db, role, user, body) {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return await body();
  } finally {
    await db.exec('RESET ROLE');
    await db.query("SELECT set_config('request.jwt.claim.sub', '', false)");
  }
}

async function expectRejected(promise, messagePart, code = '42501') {
  try {
    await promise;
  } catch (error) {
    assert.equal(error.code, code, `${messagePart}: got ${error.code} ${error.message}`);
    assert.match(error.message, new RegExp(messagePart));
    return error;
  }
  assert.fail(`expected SQLSTATE ${code} for ${messagePart}`);
}

test('website purchase status projects catalogues and one exact checkout', async (t) => {
  const db = await setup(false);
  try {
    for (const path of [
      '../../marketplace/021_request_coordinates.sql',
      '../../marketplace/023_multi_negotiation.sql',
      '../../outcomes/080_sale_confirmation.sql',
      '../../commercial/090_credit_batches.sql',
      '../../commercial/091_buyer_rewards.sql',
      '../../commercial/092_credit_settlement.sql',
      '../../commercial/094_deposit_checkout.sql',
      '../172_website_purchase_status.sql',
    ]) await db.exec(await read(path));
    const { A, B, C, MB } = await import('../../outcomes/tests/fixture.mjs');
    const option = (await db.query(
      `INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version)
       VALUES (2000,155,375,'deposit-20-v1') RETURNING id`)).rows[0].id;
    const status = (user, checkout = null) => asRole(db, 'authenticated', user, async () =>
      (await db.query('SELECT hocalist.website_purchase_status($1) AS data', [checkout])).rows[0].data);

    let checkoutId;
    await t.test('catalogues and account come from stored configuration only', async () => {
      const data = await status(B);
      assert.equal(data.account.membership_id, MB);
      assert.deepEqual(data.plans.map((plan) => plan.code), ['pro', 'elite']);
      assert.deepEqual(data.plans.map((plan) => plan.amount_minor), [1500, 3000]);
      assert.equal(data.plans.every((plan) => plan.enabled === false), true);
      assert.equal(data.options.length, 1);
      assert.equal(data.options[0].id, option);
      assert.equal(data.options[0].initial_fee_minor, 155);
      assert.equal(data.deposits.length, 0);
      assert.equal(data.selected, null);
      assert.equal(data.requires_review, false);
      await db.query("UPDATE hocalist.stripe_test_plans SET enabled=true WHERE code='pro'");
      const enabled = await status(B);
      assert.equal(enabled.plans.find((plan) => plan.code === 'pro').enabled, true);
      await db.query("UPDATE hocalist.stripe_test_plans SET enabled=false WHERE code='pro'");
    });

    await t.test('a bound checkout is returned with its kind and verified credit time', async () => {
      const begin = (await asRole(db, 'service_role', '', async () =>
        (await db.query(
          'SELECT hocalist.stripe_test_deposit_begin($1,$2,$3) AS data',
          [B, option, '2f0c9d1a-0000-4000-8000-000000000001'],
        )).rows[0].data));
      checkoutId = begin.checkout_id;
      await asRole(db, 'service_role', '', async () => {
        await db.query('SELECT hocalist.stripe_test_deposit_bind($1,$2,$3,$4)',
          [checkoutId, 'cus_websitestatus1', 'cs_test_status1', 'https://checkout.stripe.com/c/pay/test']);
      });
      const open = await status(B, checkoutId);
      assert.equal(open.selected.id, checkoutId);
      assert.equal(open.selected.kind, 'credit_deposit');
      assert.equal(open.selected.state, 'open');
      assert.equal(open.selected.amount_minor, 2000);
      assert.equal(open.selected.credited_at, null);
      assert.equal(open.deposits.length, 1);
      assert.equal(open.deposits[0].id, checkoutId);

      const finished = await asRole(db, 'service_role', '', async () =>
        (await db.query(
          'SELECT hocalist.stripe_test_deposit_finish($1,$2,$3,$4) AS data',
          [checkoutId, 'cus_websitestatus1', 2000, 'pi_websitestatus1'],
        )).rows[0].data);
      assert.equal(finished.status, 'complete');
      const complete = await status(B, checkoutId);
      assert.equal(complete.selected.state, 'complete');
      assert.equal(complete.selected.batch_id, finished.batch_id);
      assert.ok(complete.selected.credited_at, 'the verified credit time is exposed, not the creation time');
      assert.notEqual(complete.selected.credited_at, complete.selected.created_at);
    });

    await t.test('the lookup hint is account-scoped and never leaks another account', async () => {
      assert.equal((await status(C, checkoutId)).selected, null, 'another seller cannot resolve the checkout');
      assert.equal((await status(B, MISSING)).selected, null, 'an unknown id resolves to nothing');
      assert.equal((await status(B, null)).selected, null);
    });

    await t.test('buyers, dual-role restrictions and unknown accounts are refused', async () => {
      await expectRejected(status(A), 'billing_access_denied');
      await expectRejected(status(MISSING), 'billing_access_denied');
      // A restricted membership in the other role must also close the gate;
      // this is the corrected contract that the baseline read lacked.
      await db.query(
        `INSERT INTO hocalist.memberships(user_id,role,status) VALUES ('${B}','buyer','restricted')`);
      await expectRejected(status(B), 'billing_access_denied');
      await db.query(`DELETE FROM hocalist.memberships WHERE user_id='${B}' AND role='buyer'`);
      assert.equal((await status(B)).account.membership_id, MB);
    });

    await t.test('client roles cannot execute the RPC but the owner can', async () => {
      await asRole(db, 'anon', '', async () => {
        await expectRejected(
          db.query('SELECT hocalist.website_purchase_status()'),
          'permission denied',
          '42501',
        );
      });
      await asRole(db, 'service_role', '', async () => {
        await expectRejected(
          db.query('SELECT hocalist.website_purchase_status()'),
          'permission denied',
          '42501',
        );
      });
    });
  } finally {
    await db.close();
  }
});

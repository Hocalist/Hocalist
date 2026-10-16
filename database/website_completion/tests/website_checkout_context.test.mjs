// Disposable PostgreSQL checks for the service-role checkout context (173):
// the reconciliation worker classifies events from the stored session/checkout
// binding, including the checkout kind. Client roles stay denied.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setup } from '../../outcomes/tests/fixture.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

async function asRole(db, role, body) {
  await db.exec(`SET ROLE ${role}`);
  try {
    return await body();
  } finally {
    await db.exec('RESET ROLE');
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

test('checkout context exposes the stored binding with its kind', async (t) => {
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
      '../173_website_checkout_context.sql',
    ]) await db.exec(await read(path));
    const { B } = await import('../../outcomes/tests/fixture.mjs');
    const option = (await db.query(
      `INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version)
       VALUES (2000,155,375,'deposit-20-v1') RETURNING id`)).rows[0].id;
    const context = (customer) => asRole(db, 'service_role', async () =>
      (await db.query('SELECT hocalist.website_checkout_context($1) AS data', [customer])).rows[0].data);

    await t.test('an unknown customer has no context and grants nothing', async () => {
      assert.equal(await context('cus_unknown1'), null);
    });

    await t.test('a bound deposit checkout is classified with its kind and amount', async () => {
      const begin = (await asRole(db, 'service_role', async () =>
        (await db.query(
          'SELECT hocalist.stripe_test_deposit_begin($1,$2,$3) AS data',
          [B, option, '2f0c9d1a-0000-4000-8000-00000000000b'],
        )).rows[0].data));
      await asRole(db, 'service_role', async () => {
        await db.query('SELECT hocalist.stripe_test_deposit_bind($1,$2,$3,$4)',
          [begin.checkout_id, 'cus_context1', 'cs_test_context1', 'https://checkout.stripe.com/c/pay/test']);
      });
      const data = await context('cus_context1');
      assert.equal(data.membership_id, begin.membership_id);
      assert.equal(data.requires_review, false);
      assert.equal(data.plans.length, 2);
      assert.equal(data.checkouts.length, 1);
      assert.equal(data.checkouts[0].id, begin.checkout_id);
      assert.equal(data.checkouts[0].kind, 'credit_deposit');
      assert.equal(data.checkouts[0].session_id, 'cs_test_context1');
      assert.equal(data.checkouts[0].amount_minor, 2000);
      assert.equal(data.checkouts[0].plan_code, null);
    });

    await t.test('only the service role can read the context', async () => {
      for (const role of ['anon', 'authenticated']) {
        await asRole(db, role, async () => {
          await expectRejected(
            db.query('SELECT hocalist.website_checkout_context($1)', ['cus_context1']),
            'permission denied',
            '42501',
          );
        });
      }
    });
  } finally {
    await db.close();
  }
});

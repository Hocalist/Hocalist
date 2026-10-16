// Disposable PostgreSQL checks for the website billing-portal read contract.
// The provider customer is derived from the verified account, never from
// request JSON; buyers, unknown accounts and restricted sellers are refused.
// PGlite is local single-connection proof, not live JWT/PostgREST proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setup } from '../../outcomes/tests/fixture.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const MISSING = '00000000-0000-4000-8000-0000000000ff';

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

test('billing portal customer is derived from the verified account only', async (t) => {
  const db = await setup(false);
  try {
    await db.exec(await read('../171_website_billing_portal.sql'));
    const { A, B, C, MB, MC } = await import('../../outcomes/tests/fixture.mjs');
    const call = (user) =>
      db.query('SELECT hocalist.stripe_test_portal_access($1) AS data', [user])
        .then((result) => result.rows[0].data);

    await t.test('a seller with no provider customer gets a null customer, not a fake one', async () => {
      const access = await call(B);
      assert.equal(access.membership_id, MB);
      assert.equal(access.customer_id, null);
      assert.equal(access.requires_review, false);
    });

    await t.test('the mapped provider customer is returned and review state is exposed', async () => {
      await db.query(
        "INSERT INTO hocalist.stripe_test_customers(membership_id,customer_id,requires_review) VALUES($1,'cus_testportal1',false)",
        [MB],
      );
      const access = await call(B);
      assert.equal(access.customer_id, 'cus_testportal1');
      await db.query('UPDATE hocalist.stripe_test_customers SET requires_review=true WHERE membership_id=$1', [MB]);
      assert.equal((await call(B)).requires_review, true);
      await db.query('UPDATE hocalist.stripe_test_customers SET requires_review=false WHERE membership_id=$1', [MB]);
    });

    await t.test('buyers, unknown accounts and any restricted identity are refused', async () => {
      await expectRejected(call(A), 'billing_access_denied');
      await expectRejected(call(MISSING), 'billing_access_denied');
      await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE id=$1", [MC]);
      await expectRejected(call(C), 'billing_access_denied');
      await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1", [MC]);
      await db.query("UPDATE hocalist.memberships SET status='disabled' WHERE id=$1", [MB]);
      await expectRejected(call(B), 'billing_access_denied');
      await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1", [MB]);
    });

    await t.test('client roles cannot execute the service-role helper', async () => {
      for (const role of ['anon', 'authenticated']) {
        await db.exec(`SET ROLE ${role}`);
        try {
          await expectRejected(
            db.query('SELECT hocalist.stripe_test_portal_access($1)', [B]),
            'permission denied',
            '42501',
          );
        } finally {
          await db.exec('RESET ROLE');
        }
      }
    });
  } finally {
    await db.close();
  }
});

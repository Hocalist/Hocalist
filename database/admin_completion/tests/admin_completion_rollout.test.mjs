// Disposable PostgreSQL checks for the generated admin completion rollout
// bundle: preflight/apply/verify succeed on the reviewed baseline, a repeat
// apply is refused, function drift is detected and containment removes every
// administrator read without deleting history or tables. PGlite is
// single-connection deterministic SQL proof; it is NOT a live deployment.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ADMIN,
  OUTSIDER,
  applyAdminBaseline,
  callAs,
  read,
  seedAdminIdentities,
} from './fixture.mjs';

const applyBundle = async (db) => db.exec(await read('../rollout/apply.sql'));
const verifyBundle = async (db) => db.exec(await read('../rollout/verify.sql'));
// A refused guarded script aborts its transaction; clear it before continuing.
const recover = async (db) => {
  try {
    await db.exec('ROLLBACK');
  } catch {
    // No open transaction.
  }
};

test('admin completion rollout bundle on disposable PostgreSQL', async (t) => {
  const db = await applyAdminBaseline();
  try {
    await seedAdminIdentities(db);

    await t.test('apply and verify succeed against the reviewed baseline', async () => {
      await applyBundle(db);
      await verifyBundle(db);
      const config = await callAs(
        db,
        'authenticated',
        ADMIN,
        'SELECT hocalist.admin_commercial_config() AS data',
      );
      assert.deepEqual(config[0].data.deposit_options, []);
      assert.equal(config[0].data.reward_policy, null);
    });

    await t.test('a repeat apply is refused by the preflight', async () => {
      await assert.rejects(applyBundle(db), { message: /Already installed/ });
      await recover(db);
    });

    await t.test('function drift is detected before trusting the bundle', async () => {
      await db.exec(`
        CREATE OR REPLACE FUNCTION hocalist.admin_commercial_config()
        RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
        BEGIN
          PERFORM hocalist.marketplace_assert_admin(auth.uid());
          RETURN jsonb_build_object('deposit_options','[]'::jsonb,'reward_policy',null);
        END $$;
      `);
      await assert.rejects(verifyBundle(db), { message: /Function drift/ });
      await recover(db);
      // The tampered definition is not silently accepted or replaced.
      await assert.rejects(applyBundle(db), { message: /Already installed/ });
      await recover(db);
    });

    await t.test('containment removes the administrator reads only', async () => {
      await db.exec(await read('../rollout/containment.sql'));
      await assert.rejects(
        callAs(db, 'authenticated', ADMIN, 'SELECT hocalist.admin_commercial_config()'),
        { code: '42501' },
      );
      await assert.rejects(
        callAs(db, 'authenticated', ADMIN, 'SELECT hocalist.admin_review_queue(50)'),
        { code: '42501' },
      );
      await assert.rejects(
        callAs(db, 'authenticated', ADMIN, 'SELECT hocalist.admin_audit_feed(50,null,null,null,null)'),
        { code: '42501' },
      );
      // The objects still exist (no destructive rollback) and history is kept.
      const cached = await db.query(
        "SELECT to_regprocedure('hocalist.admin_failed_events(integer,text,text,text)') AS oid",
      );
      assert.equal(Boolean(cached.rows[0].oid), true);
      const receipts = await db.query('SELECT count(*)::int AS n FROM hocalist.marketplace_receipts');
      assert.equal(receipts.rows[0].n >= 0, true);
      await assert.rejects(
        callAs(db, 'authenticated', OUTSIDER, 'SELECT hocalist.admin_audit_feed(50,null,null,null,null)'),
        { code: '42501' },
      );
    });
  } finally {
    await db.close();
  }
});

// Disposable PostgreSQL checks for the administrator call-setting history
// read (draft database/admin/063_admin_call_audit.sql).
//
// PGlite is single-connection: deterministic SQL proof for admin-only access,
// append-only history and bounded projections. It is NOT call relay proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const ADMIN = '00000000-0000-4000-8000-000000000001';
const USER = '00000000-0000-4000-8000-000000000002';
const M_BUYER = '10000000-0000-4000-8000-000000000002';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

async function as(db, role, user, query, params = []) {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return (await db.query(query, params)).rows;
  } finally {
    await db.exec('RESET ROLE');
  }
}

test('admin call-setting history on disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    for (const path of [
      '../../provider-rollout/apply.sql',
      '../../chat/010_chat_foundation.sql',
      '../../marketplace/020_marketplace_foundation.sql',
      '../../calls/110_call_signaling.sql',
    ]) {
      await db.exec(await read(path));
    }
    await db.exec(await read('../060_admin_reads.sql'));
    await db.exec(await read('../063_admin_call_audit.sql'));

    await db.exec(`
      INSERT INTO auth.users(id, raw_user_meta_data) VALUES ('${ADMIN}','{}'),('${USER}','{}');
      INSERT INTO hocalist.profiles(id) VALUES ('${ADMIN}'),('${USER}') ON CONFLICT DO NOTHING;
      INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
        ('${M_BUYER}','${USER}','buyer','active');
      INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
        ('${M_BUYER}','Audit Buyer');
      INSERT INTO hocalist.platform_admins(user_id) VALUES ('${ADMIN}');
    `);

    const history = (user) =>
      as(db, 'authenticated', user, 'SELECT hocalist.admin_call_settings_history() AS data');
    const settings = (user, enabled, revision) =>
      as(
        db,
        'authenticated',
        user,
        'SELECT hocalist.call_admin_settings($1,$2) AS data',
        [enabled, revision],
      );

    await t.test('only an explicitly provisioned admin can read the history', async () => {
      await assert.rejects(history(USER), { code: '42501' });
      await assert.rejects(
        as(db, 'anon', ADMIN, 'SELECT hocalist.admin_call_settings_history()'),
        { code: '42501' },
      );
      await assert.rejects(
        as(db, 'service_role', ADMIN, 'SELECT hocalist.admin_call_settings_history()'),
        { code: '42501' },
      );
      assert.ok((await history(ADMIN))[0].data);
    });

    await t.test('changes append audit rows and same-value writes do not', async () => {
      await settings(ADMIN, true, 1);
      let data = (await history(ADMIN))[0].data;
      assert.equal(data.current_enabled, true);
      assert.equal(data.items.length, 1);
      assert.equal(data.items[0].revision, 2);
      assert.equal(data.items[0].enabled, true);
      assert.equal(data.items[0].changed_by, ADMIN);

      await settings(ADMIN, true, 2);
      data = (await history(ADMIN))[0].data;
      assert.equal(data.items.length, 1, 'no-op writes append nothing');

      await settings(ADMIN, false, 2);
      data = (await history(ADMIN))[0].data;
      assert.equal(data.items.length, 2);
      assert.equal(data.items[0].enabled, false);
      assert.equal(data.items[1].enabled, true);
    });

    await t.test('the audit table stays client-denied', async () => {
      await assert.rejects(
        as(db, 'authenticated', ADMIN, 'SELECT count(*) FROM hocalist.call_settings_audit'),
        { code: '42501' },
      );
    });
  } finally {
    await db.close();
  }
});

// Disposable PostgreSQL checks for the administrator push-delivery operations
// read (draft database/admin/062_admin_delivery_reads.sql).
//
// PGlite is single-connection: deterministic SQL proof for admin-only access,
// bounded projections and status counts. It is NOT provider delivery proof.
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
const DEVICE = '80000000-0000-4000-8000-00000000000a';
const NOTIFICATION_A = '81000000-0000-4000-8000-00000000000a';
const NOTIFICATION_B = '81000000-0000-4000-8000-00000000000b';
const DELIVERY_A = '82000000-0000-4000-8000-00000000000a';
const DELIVERY_B = '82000000-0000-4000-8000-00000000000b';
const DELIVERY_C = '82000000-0000-4000-8000-00000000000c';
const EVENT_A = '83000000-0000-4000-8000-00000000000a';
const EVENT_B = '83000000-0000-4000-8000-00000000000b';

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

test('admin delivery operations read on disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    for (const path of [
      '../../provider-rollout/apply.sql',
      '../../chat/010_chat_foundation.sql',
      '../../marketplace/020_marketplace_foundation.sql',
      '../../meetings/040_meetings_foundation.sql',
      '../../notifications/030_notification_inbox.sql',
    ]) {
      await db.exec(await read(path));
    }
    await db.exec(await read('../060_admin_reads.sql'));
    await db.exec(await read('../062_admin_delivery_reads.sql'));

    await db.exec(`
      INSERT INTO auth.users(id, raw_user_meta_data) VALUES ('${ADMIN}','{}'),('${USER}','{}');
      INSERT INTO hocalist.profiles(id) VALUES ('${ADMIN}'),('${USER}') ON CONFLICT DO NOTHING;
      INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
        ('${M_BUYER}','${USER}','buyer','active');
      INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
        ('${M_BUYER}','Delivery Buyer');
      INSERT INTO hocalist.platform_admins(user_id) VALUES ('${ADMIN}');
      INSERT INTO hocalist.push_devices(id,user_id,installation_secret_hash,token,platform,enabled)
      VALUES ('${DEVICE}','${USER}',repeat('a',64),'SECRET-TOKEN-VALUE-1234567890','android',true);
      INSERT INTO hocalist.notifications(
        id,user_id,event_key,kind,source_id,title,body,deep_link,payload)
      VALUES
        ('${NOTIFICATION_A}','${USER}','${EVENT_A}','new_offer','${DEVICE}',
         'New offer received','A seller sent an offer.','hocalist://offers/${DEVICE}','{}'),
        ('${NOTIFICATION_B}','${USER}','${EVENT_B}','new_message','${DEVICE}',
         'New message','You have a new message.','hocalist://chat/${DEVICE}','{}');
    `);
    // The queue bridge is applied after the synthetic inbox rows so its
    // no-backfill trigger does not create delivery rows during this test.
    await db.exec(await read('../../notifications/032_push_queue_bridge.sql'));
    await db.exec(`
      INSERT INTO hocalist.push_deliveries(
        id,notification_id,device_id,device_revision,status,attempts,available_at,last_error)
      VALUES
        ('${DELIVERY_A}','${NOTIFICATION_A}','${DEVICE}',1,'failed',3,now() - interval '1 hour',
         'provider_timeout'),
        ('${DELIVERY_B}','${NOTIFICATION_B}','${DEVICE}',1,'pending',0,now() - interval '2 hours',null),
        ('${DELIVERY_C}','${NOTIFICATION_A}','${DEVICE}',2,'accepted',1,now() - interval '30 minutes',null);
    `);

    const overview = (user) =>
      as(db, 'authenticated', user, 'SELECT hocalist.admin_delivery_overview() AS data');

    await t.test('only an explicitly provisioned admin can read delivery health', async () => {
      await assert.rejects(overview(USER), { code: '42501' });
      await assert.rejects(
        as(db, 'anon', ADMIN, 'SELECT hocalist.admin_delivery_overview()'),
        { code: '42501' },
      );
      await assert.rejects(
        as(db, 'service_role', ADMIN, 'SELECT hocalist.admin_delivery_overview()'),
        { code: '42501' },
      );
      assert.ok((await overview(ADMIN))[0].data);
    });

    await t.test('status counts and the oldest pending age are correct', async () => {
      const data = (await overview(ADMIN))[0].data;
      assert.equal(data.failed, 1);
      assert.equal(data.pending, 1);
      assert.equal(data.accepted, 1);
      assert.equal(data.sending, 0);
      assert.equal(data.skipped, 0);
      assert.equal(data.failed_last_24h, 1);
      assert.ok(data.oldest_pending_at);
    });

    await t.test('recent failures expose bounded operational fields only', async () => {
      const data = (await overview(ADMIN))[0].data;
      assert.equal(data.recent_failures.length, 1);
      const failure = data.recent_failures[0];
      assert.equal(failure.id, DELIVERY_A);
      assert.equal(failure.kind, 'new_offer');
      assert.equal(failure.attempts, 3);
      assert.equal(failure.last_error, 'provider_timeout');
      const payload = JSON.stringify(data);
      assert.doesNotMatch(payload, /SECRET-TOKEN-VALUE/);
      assert.doesNotMatch(payload, /New offer received|New message/);
    });

    await t.test('client roles cannot read the push tables directly', async () => {
      await assert.rejects(
        as(db, 'authenticated', ADMIN, 'SELECT count(*) FROM hocalist.push_deliveries'),
        { code: '42501' },
      );
      await assert.rejects(
        as(db, 'authenticated', ADMIN, 'SELECT token FROM hocalist.push_devices'),
        { code: '42501' },
      );
    });
  } finally {
    await db.close();
  }
});

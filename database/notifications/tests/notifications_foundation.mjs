// Disposable PostgreSQL checks for the notification inbox foundation.
//
// PGlite is single-connection: this is deterministic SQL proof for
// preferences, dedupe, inbox paging, read markers and privileges. It is NOT
// real JWT, PostgREST, push delivery or concurrency proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const EVENT_1 = '30000000-0000-4000-8000-000000000001';
const EVENT_2 = '30000000-0000-4000-8000-000000000002';
const EVENT_3 = '30000000-0000-4000-8000-000000000003';
const SOURCE = '40000000-0000-4000-8000-000000000001';

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

async function expectDenied(promise, code) {
  try {
    await promise;
  } catch (error) {
    if (error.code !== code) {
      throw new Error(`expected SQLSTATE ${code}, got ${error.code}: ${error.message}`);
    }
    return error;
  }
  throw new Error(`expected SQLSTATE ${code}, but the statement succeeded`);
}

async function seed(db) {
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${A}','{}'),('${B}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${MA}','${A}','buyer','active'),
      ('${MB}','${B}','seller','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
      ('${MA}','Buyer A'),('${MB}','Seller B');
  `);
}

async function emit(db, user, event, kind, title) {
  return db.query(
    'SELECT hocalist.notification_emit($1,$2,$3,$4,$5,$6,$7,$8) AS id',
    [user, event, kind, SOURCE, title, 'Body text', 'hocalist://chat/1', JSON.stringify({ k: 1 })],
  );
}

test('notification inbox foundation in disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    await db.exec(await readFile(new URL('../../provider-rollout/apply.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../030_notification_inbox.sql', import.meta.url), 'utf8'));
    await seed(db);

    await t.test('preferences default, update and safety rules', async () => {
      const defaults = (await callAs(
        db, 'authenticated', A, 'SELECT hocalist.notification_preferences() AS data',
      ))[0].data;
      assert.deepEqual(defaults, {
        offers: true,
        messages: true,
        deals: true,
        safety: true,
        revision: 0,
        updated_at: null,
      });

      const updated = (await callAs(
        db, 'authenticated', A,
        "SELECT hocalist.notification_preferences_update($1::jsonb) AS data",
        [JSON.stringify({ offers: false, messages: true, deals: true, expected_revision: 0 })],
      ))[0].data;
      assert.equal(updated.offers, false);
      assert.equal(updated.revision, 1);

      const reread = (await callAs(
        db, 'authenticated', A, 'SELECT hocalist.notification_preferences() AS data',
      ))[0].data;
      assert.equal(reread.offers, false);
      assert.equal(reread.revision, 1);

      await expectDenied(
        callAs(
          db, 'authenticated', A,
          "SELECT hocalist.notification_preferences_update($1::jsonb)",
          [JSON.stringify({ offers: true, messages: true, deals: true, expected_revision: 0 })],
        ),
        'P0001',
      );
      await expectDenied(
        callAs(
          db, 'authenticated', A,
          "SELECT hocalist.notification_preferences_update($1::jsonb)",
          [JSON.stringify({ offers: true, messages: true, deals: true, safety: false, expected_revision: 1 })],
        ),
        '22023',
      );
      await expectDenied(
        callAs(
          db, 'authenticated', A,
          "SELECT hocalist.notification_preferences_update($1::jsonb)",
          [JSON.stringify({ offers: true, messages: true, deals: true, expected_revision: 1, extra: 1 })],
        ),
        '22023',
      );
    });

    await t.test('emit dedupes, respects disabled topics and keeps safety', async () => {
      // Re-enable offers first (the preference subtest disabled it).
      await callAs(
        db, 'authenticated', A,
        "SELECT hocalist.notification_preferences_update($1::jsonb) AS data",
        [JSON.stringify({ offers: true, messages: true, deals: true, expected_revision: 1 })],
      );
      const first = (await emit(db, A, EVENT_1, 'new_offer', 'New offer')).rows[0].id;
      const replay = (await emit(db, A, EVENT_1, 'new_offer', 'New offer')).rows[0].id;
      assert.equal(first, replay);

      await callAs(
        db, 'authenticated', A,
        "SELECT hocalist.notification_preferences_update($1::jsonb) AS data",
        [JSON.stringify({ offers: false, messages: true, deals: true, expected_revision: 2 })],
      );
      const skipped = (await emit(db, A, EVENT_2, 'new_offer', 'Second offer')).rows[0].id;
      assert.equal(skipped, null);

      const safety = (await emit(db, A, EVENT_3, 'account_update', 'Security notice')).rows[0].id;
      assert.notEqual(safety, null);
      const count = (await db.query(
        "SELECT count(*)::int AS n FROM hocalist.notifications WHERE user_id = $1", [A],
      )).rows[0].n;
      assert.equal(count, 2);
    });

    await t.test('inbox pages newest first with an unread count', async () => {
      const page = (await callAs(
        db, 'authenticated', A,
        'SELECT hocalist.notification_inbox(1, NULL) AS data',
      ))[0].data;
      assert.equal(page.items.length, 1);
      assert.equal(page.unread_count, 2);
      assert.equal(page.items[0].title, 'Security notice');
      assert.ok(page.next_cursor);

      const second = (await callAs(
        db, 'authenticated', A,
        'SELECT hocalist.notification_inbox(1, $1) AS data',
        [page.next_cursor],
      ))[0].data;
      assert.equal(second.items.length, 1);
      assert.equal(second.items[0].title, 'New offer');
      assert.equal(second.next_cursor, null);

      await expectDenied(
        callAs(db, 'authenticated', A, 'SELECT hocalist.notification_inbox(0, NULL)'),
        '22023',
      );
      await expectDenied(
        callAs(db, 'authenticated', A, 'SELECT hocalist.notification_inbox(10, $1)', ['not-a-cursor']),
        '22023',
      );
    });

    await t.test('read markers are idempotent and caller-scoped', async () => {
      const id = (await db.query(
        "SELECT id FROM hocalist.notifications WHERE user_id = $1 AND event_key = $2",
        [A, EVENT_1],
      )).rows[0].id;
      const first = (await callAs(
        db, 'authenticated', A,
        'SELECT hocalist.notification_mark_read($1) AS data', [id],
      ))[0].data;
      assert.ok(first.read_at);
      const second = (await callAs(
        db, 'authenticated', A,
        'SELECT hocalist.notification_mark_read($1) AS data', [id],
      ))[0].data;
      assert.equal(second.read_at, first.read_at);

      await expectDenied(
        callAs(db, 'authenticated', B, 'SELECT hocalist.notification_mark_read($1)', [id]),
        '42501',
      );
      const marked = (await callAs(
        db, 'authenticated', A, 'SELECT hocalist.notification_mark_all_read() AS data',
      ))[0].data.marked;
      assert.equal(marked, 1);
    });

    await t.test('inbox is caller-scoped and anon has no access', async () => {
      const other = (await callAs(
        db, 'authenticated', B, 'SELECT hocalist.notification_inbox(10, NULL) AS data',
      ))[0].data;
      assert.deepEqual(other.items, []);
      assert.equal(other.unread_count, 0);

      await expectDenied(
        callAs(db, 'anon', null, 'SELECT hocalist.notification_inbox(10, NULL)'),
        '42501',
      );
    });

    await t.test('internal producer stays client-denied', async () => {
      await expectDenied(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.notification_emit($1,$2,$3,$4,$5,$6,$7,$8)',
          [A, EVENT_1, 'new_offer', SOURCE, 'x', 'y', null, null]),
        '42501',
      );
      await expectDenied(
        callAs(db, 'authenticated', A, 'SELECT * FROM hocalist.notification_preferences LIMIT 1'),
        '42501',
      );
    });

    await t.test('the deployed notification read policy stays own-row only', async () => {
      const own = await callAs(
        db, 'authenticated', A,
        'SELECT count(*)::int AS n FROM hocalist.notifications',
      );
      assert.equal(own[0].n, 2);
      const other = await callAs(
        db, 'authenticated', B,
        'SELECT count(*)::int AS n FROM hocalist.notifications',
      );
      assert.equal(other[0].n, 0);
    });

    await t.test('the deployed push enqueue path still works', async () => {
      const result = await db.query(
        'SELECT hocalist.notification_enqueue($1,$2,$3,$4) AS id',
        [B, EVENT_2, 'new_message', SOURCE],
      );
      assert.ok(result.rows[0].id);
      const inbox = (await callAs(
        db, 'authenticated', B, 'SELECT hocalist.notification_inbox(10, NULL) AS data',
      ))[0].data;
      assert.equal(inbox.items.length, 1);
      assert.equal(inbox.items[0].title, 'Hocalist update');
    });
  } finally {
    await db.close();
  }
});

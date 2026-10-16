// Disposable PostgreSQL checks for the administrator failed-event operations
// read (draft database/admin_completion/162_admin_event_operations.sql).
//
// Covers admin-only access, bounded keyset pagination, status/type filters,
// sanitized projections (no provider object id, payload, amount or token) and
// the explicit "email events not ingested" state. PGlite is single-connection
// deterministic SQL proof; it is NOT live Stripe or worker-reconciliation proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ADMIN,
  BUYER,
  OUTSIDER,
  applyAdminBaseline,
  callAs,
  read,
  seedAdminIdentities,
} from './fixture.mjs';

const ACCOUNT = 'acct_1Le6hqDmHEV44E5Y';

const events = (db, user, params = [50, null, null, null]) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.admin_failed_events($1,$2,$3,$4) AS data',
    params,
  ).then((rows) => rows[0].data);

const detail = (db, user, eventId) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.admin_failed_event_detail($1) AS data',
    [eventId],
  ).then((rows) => rows[0].data);

test('admin failed-event operations read on disposable PostgreSQL', async (t) => {
  const db = await applyAdminBaseline();
  try {
    await seedAdminIdentities(db);
    await db.exec(await read('../162_admin_event_operations.sql'));
    await db.exec(`
      INSERT INTO hocalist.stripe_test_inbox(
        account_id,event_id,event_type,object_id,event_created,livemode,
        status,received_at,attempts,available_at,last_error)
      VALUES
        ('${ACCOUNT}','evt_QuarantineOne','invoice.payment_failed','in_Private001',1700000001,false,
         'quarantined', '2026-09-26T10:00:00Z', 10, '2026-09-26T10:30:00Z', 'provider_or_storage_unavailable'),
        ('${ACCOUNT}','evt_PendingTwo','invoice.payment_failed','in_Private002',1700000002,false,
         'pending', '2026-09-26T11:00:00Z', 2, '2026-09-26T11:05:00Z', 'provider_or_storage_unavailable'),
        ('${ACCOUNT}','evt_ProcessedThree','checkout.session.completed','cs_test_Private003',1700000003,false,
         'processed', '2026-09-26T12:00:00Z', 1, '2026-09-26T12:00:00Z', NULL);
    `);

    await t.test('only an explicitly provisioned admin can read failed events', async () => {
      await assert.rejects(events(db, BUYER), { code: '42501' });
      await assert.rejects(events(db, OUTSIDER), { code: '42501' });
      await assert.rejects(
        callAs(db, 'anon', ADMIN, 'SELECT hocalist.admin_failed_events(50,null,null,null)'),
        { code: '42501' },
      );
      await assert.rejects(
        callAs(db, 'service_role', ADMIN, 'SELECT hocalist.admin_failed_events(50,null,null,null)'),
        { code: '42501' },
      );
      await assert.rejects(events(db, ADMIN, [0, null, null, null]), { code: '22023' });
      await assert.rejects(events(db, ADMIN, [101, null, null, null]), { code: '22023' });
      await assert.rejects(events(db, ADMIN, [50, null, 'lost', null]), { code: '22023' });
      await assert.rejects(events(db, ADMIN, [50, null, null, 'made.up']), { code: '22023' });
      await assert.rejects(events(db, ADMIN, [50, 'not-a-cursor', null, null]), { code: '22023' });
    });

    await t.test('the list is bounded, sanitized and newest first', async () => {
      const data = await events(db, ADMIN);
      assert.equal(data.email_events_available, false);
      assert.equal(data.retry_available, false);
      assert.deepEqual(
        data.items.map((row) => row.event_id),
        ['evt_ProcessedThree', 'evt_PendingTwo', 'evt_QuarantineOne'],
      );
      const row = data.items[1];
      assert.equal(row.event_type, 'invoice.payment_failed');
      assert.equal(row.status, 'pending');
      assert.equal(row.attempts, 2);
      assert.equal(row.error_class, 'provider_or_storage_unavailable');
      const payload = JSON.stringify(data);
      // No provider object id, amount, payload, customer or credential.
      assert.doesNotMatch(payload, /Private00|in_Private|cs_test_|amount|card|token|secret/i);
    });

    await t.test('status and type filters narrow the read', async () => {
      const quarantined = await events(db, ADMIN, [50, null, 'quarantined', null]);
      assert.deepEqual(quarantined.items.map((row) => row.event_id), ['evt_QuarantineOne']);
      const invoices = await events(db, ADMIN, [50, null, null, 'invoice.payment_failed']);
      assert.deepEqual(
        invoices.items.map((row) => row.event_id),
        ['evt_PendingTwo', 'evt_QuarantineOne'],
      );
      const none = await events(db, ADMIN, [50, null, 'pending', 'checkout.session.completed']);
      assert.deepEqual(none.items, []);
      assert.equal(none.next_cursor, null);
    });

    await t.test('keyset pagination has no repeated rows', async () => {
      const first = await events(db, ADMIN, [2, null, null, null]);
      assert.equal(first.items.length, 2);
      assert.ok(first.next_cursor);
      const second = await events(db, ADMIN, [2, first.next_cursor, null, null]);
      assert.equal(second.items.length, 1);
      const firstIds = first.items.map((row) => row.event_id);
      assert.equal(second.items.some((row) => firstIds.includes(row.event_id)), false);
      assert.equal(second.next_cursor, null);
    });

    await t.test('detail exposes only sanitized operational metadata', async () => {
      const row = await detail(db, ADMIN, 'evt_QuarantineOne');
      assert.equal(row.event_type, 'invoice.payment_failed');
      assert.equal(row.object_kind, 'invoice');
      assert.equal(row.attempts, 10);
      assert.equal(row.livemode, false);
      assert.equal(row.error_class, 'provider_or_storage_unavailable');
      assert.doesNotMatch(JSON.stringify(row), /Private00|in_Private|token|secret/i);

      await assert.rejects(detail(db, ADMIN, 'not-an-event'), { code: '22023' });
      await assert.rejects(detail(db, ADMIN, 'evt_MissingEvent'), { code: 'P0002' });
      await assert.rejects(detail(db, BUYER, 'evt_QuarantineOne'), { code: '42501' });
    });

    await t.test('the receipt inbox stays client-denied', async () => {
      await assert.rejects(
        callAs(db, 'authenticated', ADMIN, 'SELECT count(*) FROM hocalist.stripe_test_inbox'),
        { code: '42501' },
      );
      await assert.rejects(
        callAs(db, 'anon', ADMIN, 'SELECT count(*) FROM hocalist.stripe_test_inbox'),
        { code: '42501' },
      );
    });

    await t.test('a repeat apply is refused before any replacement', async () => {
      await assert.rejects(db.exec(await read('../162_admin_event_operations.sql')), {
        message: /already exist/,
      });
    });
  } finally {
    await db.close();
  }
});

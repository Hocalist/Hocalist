// Disposable PostgreSQL checks for the meeting/reschedule foundation.
//
// PGlite is single-connection: this is deterministic SQL proof for participant
// authorization (including restricted and revoked access), schedule revision
// history, propose/reject/re-propose, idempotent mutation retries, reschedule
// races, expiry computation and the absence of PIN objects. It is NOT real
// JWT, PostgREST or concurrent-writer proof.
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
const C = '00000000-0000-4000-8000-00000000000c';
const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MC = '10000000-0000-4000-8000-00000000000c';
const CATEGORY = '20000000-0000-4000-8000-000000000001';

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

async function expectDenied(promise, messagePart, code = '42501') {
  try {
    await promise;
  } catch (error) {
    assert.equal(error.code, code, `${messagePart}: got ${error.code} ${error.message}`);
    if (messagePart) assert.match(error.message, new RegExp(messagePart));
    return error;
  }
  assert.fail(`expected SQLSTATE ${code} for ${messagePart}`);
}

const command = (db, user, op, key, input) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS result',
    [op, key, JSON.stringify(input)],
  );

const meetingCall = (db, user, fn, params) =>
  callAs(
    db,
    'authenticated',
    user,
    `SELECT hocalist.${fn} AS data`,
    params,
  );

const propose = (db, user, conversation, input, key) =>
  meetingCall(db, user, 'meeting_propose($1,$2,$3)', [
    conversation,
    JSON.stringify(input),
    key,
  ]);

const respond = (db, user, meeting, accept, revision, key) =>
  meetingCall(db, user, 'meeting_respond($1,$2,$3,$4)', [
    meeting,
    accept,
    revision,
    key,
  ]);

const reschedule = (db, user, meeting, input, revision, key) =>
  meetingCall(db, user, 'meeting_reschedule_propose($1,$2,$3,$4)', [
    meeting,
    JSON.stringify(input),
    revision,
    key,
  ]);

const cancel = (db, user, meeting, revision, key) =>
  meetingCall(db, user, 'meeting_cancel($1,$2,$3)', [meeting, revision, key]);

const schedule = (overrides = {}) => ({
  schedule_date: '2026-10-01',
  schedule_time: '18:30',
  schedule_timezone: 'America/New_York',
  place_choice: 'specific_place',
  place_label: 'Cross County Mall',
  place_address: '123 Synthetic Ave',
  ...overrides,
});

async function seed(db) {
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${A}','{}'),('${B}','{}'),('${C}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${MA}','${A}','buyer','active'),
      ('${MB}','${B}','seller','active'),
      ('${MC}','${C}','seller','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
      ('${MA}','Buyer A'),('${MB}','Seller B'),('${MC}','Seller C');
    INSERT INTO hocalist.catalogue_categories(id,label,scope,status,sort_order)
    VALUES ('${CATEGORY}','Electronics','product','active',1);
  `);
}

async function acceptedDeal(db) {
  const request = (await command(db, A, 'request.create', 'req-1', {
    kind: 'product',
    title: 'iPad Air, 5th gen or newer',
    description: 'Good condition',
    condition: 'used',
    quantity: 1,
    budget_minimum_minor: 35000,
    budget_maximum_minor: 48000,
    currency_code: 'USD',
    accepts_higher_offers: false,
    use_home_address: true,
    category_id: CATEGORY,
  }))[0].result;
  const offer = (await command(db, B, 'offer.submit', 'offer-1', {
    request_id: request.id,
    price_minor: 42000,
    currency_code: 'USD',
    message: 'Can meet tomorrow.',
    image_media_ids: [],
    ...schedule(),
  }))[0].result;
  await command(db, A, 'offer.select', 'select-1', {
    offer_id: offer.id,
    revision_id: offer.revisions[0].id,
    expected_offer_revision: offer.revision,
  });
  const opened = (await command(db, A, 'conversation.open_offer', 'open-1', {
    offer_id: offer.id,
  }))[0].result;
  return { requestId: request.id, offerId: offer.id, conversationId: opened.conversation_id, acceptedRevisionId: offer.revisions[0].id };
}

test('meeting foundation in disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    await db.exec(await readFile(new URL('../../provider-rollout/apply.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../../chat/010_chat_foundation.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../../marketplace/020_marketplace_foundation.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../040_meetings_foundation.sql', import.meta.url), 'utf8'));
    await seed(db);
    const deal = await acceptedDeal(db);

    let meeting;

    await t.test('only participants can propose', async () => {
      await expectDenied(
        propose(db, C, deal.conversationId, schedule(), 'propose-c'),
        'meeting_access_denied',
      );
    });

    await t.test('a participant proposes the first schedule', async () => {
      meeting = (await propose(db, A, deal.conversationId, schedule(), 'propose-1'))[0].data;
      assert.equal(meeting.status, 'proposed');
      assert.equal(meeting.revision, 1);
      assert.equal(meeting.meeting_expires_at, null);
      assert.equal(meeting.revisions.length, 1);
      assert.equal(meeting.revisions[0].schedule_offset_minutes, -240);
      assert.equal(
        new Date(meeting.revisions[0].schedule_instant).toISOString(),
        '2026-10-01T22:30:00.000Z',
      );
      assert.equal(meeting.pending_schedule.sequence, 1);
      assert.deepEqual(meeting.offer_summary, {
        title: 'iPad Air, 5th gen or newer',
        price_minor: 42000,
        currency_code: 'USD',
        revision_id: deal.acceptedRevisionId,
      });
    });

    await t.test('a lost-response retry replays the committed proposal', async () => {
      const replay = (await propose(db, A, deal.conversationId, schedule(), 'propose-1'))[0].data;
      assert.deepEqual(replay, meeting);
      const rows = await db.query(`
        SELECT
          (SELECT count(*)::int FROM hocalist.meetings) AS meetings,
          (SELECT count(*)::int FROM hocalist.meeting_schedule_revisions) AS revisions
      `);
      assert.deepEqual(rows.rows[0], { meetings: 1, revisions: 1 });
    });

    await t.test('the same key with a changed payload is refused', async () => {
      await expectDenied(
        propose(
          db,
          A,
          deal.conversationId,
          schedule({ schedule_time: '19:00' }),
          'propose-1',
        ),
        'idempotency_conflict',
        'P0001',
      );
    });

    await t.test('restricted membership denies meeting reads and writes', async () => {
      await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE id=$1", [MB]);
      try {
        await expectDenied(
          meetingCall(db, B, 'meeting_detail($1)', [meeting.id]),
          'account_restricted',
        );
        await expectDenied(
          meetingCall(db, B, 'meeting_list($1,$2,$3)', [null, 10, null]),
          'account_restricted',
        );
        await expectDenied(
          respond(db, B, meeting.id, false, 1, 'reject-restricted'),
          'account_restricted',
        );
      } finally {
        await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1", [MB]);
      }
    });

    await t.test('a pending role membership denies the matching side', async () => {
      await db.query("UPDATE hocalist.memberships SET status='pending' WHERE id=$1", [MB]);
      try {
        await expectDenied(
          meetingCall(db, B, 'meeting_detail($1)', [meeting.id]),
          'role_not_active',
        );
        const list = (await meetingCall(db, B, 'meeting_list($1,$2,$3)', [
          null,
          10,
          null,
        ]))[0].data;
        assert.deepEqual(list.items, [], 'inactive role hides the meeting from the list');
        await expectDenied(
          respond(db, B, meeting.id, false, 1, 'reject-pending'),
          'role_not_active',
        );
      } finally {
        await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1", [MB]);
      }
    });

    await t.test('a revoked conversation member is denied', async () => {
      await db.query(
        'UPDATE hocalist.conversation_members SET revoked_at=now() WHERE conversation_id=$1 AND user_id=$2',
        [deal.conversationId, B],
      );
      try {
        await expectDenied(
          meetingCall(db, B, 'meeting_detail($1)', [meeting.id]),
          'meeting_access_denied',
        );
      } finally {
        await db.query(
          'UPDATE hocalist.conversation_members SET revoked_at=NULL WHERE conversation_id=$1 AND user_id=$2',
          [deal.conversationId, B],
        );
      }
    });

    await t.test('the proposer cannot accept their own proposal', async () => {
      await expectDenied(
        respond(db, A, meeting.id, true, 1, 'self-accept'),
        'meeting_self_accept',
        'P0001',
      );
    });

    await t.test('rejecting the initial proposal keeps the meeting open', async () => {
      const rejected = (await respond(db, B, meeting.id, false, 1, 'reject-1'))[0].data;
      assert.equal(rejected.status, 'proposed');
      assert.equal(rejected.revision, 2);
      assert.equal(rejected.accepted_revision_id, null);
      assert.equal(rejected.pending_schedule, null);
      assert.equal(rejected.revisions.length, 1);
      assert.equal(rejected.revisions[0].status, 'rejected');
      meeting = rejected;

      const replay = (await respond(db, B, meeting.id, false, 1, 'reject-1'))[0].data;
      assert.deepEqual(replay, meeting, 'a lost-response retry replays the rejection');
      const count = await db.query(
        'SELECT count(*)::int AS n FROM hocalist.meeting_schedule_revisions WHERE meeting_id=$1',
        [meeting.id],
      );
      assert.equal(count.rows[0].n, 1);
    });

    await t.test('a changed decision under the same key conflicts', async () => {
      await expectDenied(
        respond(db, B, meeting.id, true, 1, 'reject-1'),
        'idempotency_conflict',
        'P0001',
      );
    });

    await t.test('a second proposal after rejection preserves history and one meeting', async () => {
      const proposed = (await propose(
        db,
        B,
        deal.conversationId,
        schedule({ schedule_date: '2026-10-03' }),
        'propose-2',
      ))[0].data;
      assert.equal(proposed.id, meeting.id, 'the same meeting is reused');
      assert.equal(proposed.status, 'proposed');
      assert.equal(proposed.revision, 3);
      assert.equal(proposed.pending_schedule.sequence, 2);
      assert.equal(proposed.revisions.length, 2);
      assert.equal(proposed.revisions[0].status, 'rejected');
      assert.equal(proposed.revisions[1].status, 'proposed');
      meeting = proposed;
    });

    await t.test('the other participant accepts the new proposal', async () => {
      const accepted = (await respond(db, A, meeting.id, true, 3, 'accept-1'))[0].data;
      assert.equal(accepted.status, 'accepted');
      assert.equal(accepted.revision, 4);
      assert.equal(accepted.accepted_schedule.sequence, 2);
      assert.equal(
        new Date(accepted.meeting_expires_at).toISOString(),
        '2026-10-04T04:00:00.000Z',
      );
      const replay = (await respond(db, A, meeting.id, true, 3, 'accept-1'))[0].data;
      assert.deepEqual(replay, accepted);
      meeting = accepted;
    });

    await t.test('a stale revision is refused', async () => {
      await expectDenied(
        reschedule(
          db,
          A,
          meeting.id,
          schedule({ schedule_time: '19:00' }),
          1,
          'reschedule-stale',
        ),
        'revision_conflict',
        'P0001',
      );
    });

    await t.test('a reschedule keeps the accepted schedule until accepted', async () => {
      const proposed = (await reschedule(
        db,
        B,
        meeting.id,
        schedule({ schedule_date: '2026-10-05', schedule_time: '12:00' }),
        4,
        'reschedule-1',
      ))[0].data;
      assert.equal(proposed.status, 'reschedule_proposed');
      assert.equal(proposed.revision, 5);
      assert.equal(proposed.accepted_schedule.sequence, 2);
      assert.equal(proposed.pending_schedule.sequence, 3);

      await expectDenied(
        reschedule(
          db,
          B,
          meeting.id,
          schedule({ schedule_date: '2026-10-06' }),
          5,
          'reschedule-2',
        ),
        'meeting_reschedule_pending',
        'P0001',
      );

      const accepted = (await respond(db, A, meeting.id, true, 5, 'accept-2'))[0].data;
      assert.equal(accepted.status, 'accepted');
      assert.equal(accepted.accepted_schedule.sequence, 3);
      assert.equal(
        new Date(accepted.meeting_expires_at).toISOString(),
        '2026-10-06T04:00:00.000Z',
      );
      assert.equal(accepted.revisions.length, 3);
      assert.equal(accepted.revisions[0].status, 'rejected');
      assert.equal(accepted.revisions[1].status, 'superseded');
      meeting = accepted;
    });

    await t.test('a rejected reschedule keeps the accepted schedule', async () => {
      const proposed = (await reschedule(
        db,
        A,
        meeting.id,
        schedule({ schedule_date: '2026-10-08' }),
        6,
        'reschedule-3',
      ))[0].data;
      assert.equal(proposed.status, 'reschedule_proposed');
      const rejected = (await respond(db, B, meeting.id, false, 7, 'reject-2'))[0].data;
      assert.equal(rejected.status, 'accepted');
      assert.equal(rejected.accepted_schedule.sequence, 3);
      assert.equal(rejected.pending_schedule, null);
      meeting = rejected;
    });

    await t.test('cancel clears expiry and replays on retry', async () => {
      const cancelled = (await cancel(db, A, meeting.id, 8, 'cancel-1'))[0].data;
      assert.equal(cancelled.status, 'cancelled');
      assert.equal(cancelled.meeting_expires_at, null);
      const replay = (await cancel(db, A, meeting.id, 8, 'cancel-1'))[0].data;
      assert.deepEqual(replay, cancelled);
    });

    await t.test('a cancelled meeting cannot be proposed again', async () => {
      await expectDenied(
        propose(db, A, deal.conversationId, schedule(), 'propose-3'),
        'meeting_cancelled',
        'P0001',
      );
    });

    await t.test('a non-participant cannot read or list the meeting', async () => {
      await expectDenied(
        meetingCall(db, C, 'meeting_detail($1)', [meeting.id]),
        'meeting_access_denied',
      );
      const list = (await meetingCall(db, C, 'meeting_list($1,$2,$3)', [
        null,
        10,
        null,
      ]))[0].data;
      assert.deepEqual(list.items, []);
      const own = (await meetingCall(db, B, 'meeting_list($1,$2,$3)', [
        null,
        10,
        null,
      ]))[0].data;
      assert.equal(own.items.length, 1);
    });

    await t.test('PIN objects stay absent from the meeting foundation', async () => {
      const columns = await db.query(`
        SELECT column_name FROM information_schema.columns
        WHERE table_schema='hocalist' AND table_name IN ('meetings','meeting_schedule_revisions')
          AND column_name ILIKE '%pin%'
      `);
      assert.deepEqual(columns.rows, []);
      const functions = await db.query(`
        SELECT proname FROM pg_proc
        WHERE pronamespace='hocalist'::regnamespace AND proname ILIKE '%pin%'
      `);
      assert.deepEqual(functions.rows, []);
    });
  } finally {
    await db.close();
  }
});

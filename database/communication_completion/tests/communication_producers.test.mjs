// Disposable PostgreSQL checks for the communication notification producers
// (153). PGlite is single-connection deterministic proof for recipient policy,
// deterministic dedupe, preference enforcement and timezone-safe reminder keys.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  A,
  B,
  acceptedDeal,
  callAs,
  propose,
  respond,
  schedule,
  setup,
} from '../../outcomes/tests/fixture.mjs';
import { endSuite, expectDenied, rpc } from './support.mjs';

const signalingSql = await readFile(
  new URL('../../calls/110_call_signaling.sql', import.meta.url),
  'utf8',
);
const inboxSql = await readFile(
  new URL('../../notifications/030_notification_inbox.sql', import.meta.url),
  'utf8',
);
const producersSql = await readFile(
  new URL('../../notifications/031_notification_producers.sql', import.meta.url),
  'utf8',
);
const communicationSql = await readFile(
  new URL('../153_communication_producers.sql', import.meta.url),
  'utf8',
);
const blockSql = await readFile(
  new URL('../150_chat_block.sql', import.meta.url),
  'utf8',
);

const command = (db, user, action, input) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.call_command($1,$2) AS v', [
    action,
    JSON.stringify(input),
  ]);

const inbox = async (db, user) =>
  (await rpc(db, user, 'notification_inbox($1,$2)', [50, null]))[0].v;

const callId = (result) => result[0].v.call.id;

test('call and reminder producers respect policy, dedupe and preferences', async () => {
  const db = await setup();
  try {
    await db.exec(signalingSql);
    await db.exec(inboxSql);
    await db.exec(producersSql);
    await db.exec(blockSql);
    await db.exec(communicationSql);
    const deal = await acceptedDeal(db);
    const pending = (await propose(db, A, deal.conversationId, schedule(), 'p1'))[0].data;
    await respond(db, B, pending.id, true, pending.revision, 'r1');
    await db.query('INSERT INTO hocalist.platform_admins(user_id) VALUES($1)', [A]);
    await callAs(db, 'authenticated', A, 'SELECT hocalist.call_admin_settings($1,$2) AS v', [true, 1]);

    // Incoming invitation: exactly one notification for the callee, and a
    // retried invite never duplicates it.
    const invite = {
      conversation_id: deal.conversationId,
      key: '92000000-0000-4000-8000-000000000001',
    };
    const first = await command(db, A, 'invite', invite);
    const id = callId(first);
    await command(db, A, 'invite', invite);
    const afterInvite = await inbox(db, B);
    assert.equal(
      afterInvite.items.filter((row) => row.title === 'Incoming Hocalist call').length,
      1,
    );
    assert.equal(afterInvite.items[0].title, 'Incoming Hocalist call');
    assert.equal(afterInvite.items[0].payload.call_id, id);

    // Caller cancels while ringing: the callee gets one missed-call row.
    await command(db, A, 'end', { call_id: id });
    const afterMissed = await inbox(db, B);
    assert.equal(afterMissed.items.filter((row) => row.title === 'Missed call').length, 1);

    // Callee declines: the caller gets one declined row; no missed row.
    const second = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '92000000-0000-4000-8000-000000000002',
    });
    await command(db, B, 'decline', { call_id: callId(second) });
    const callerInbox = await inbox(db, A);
    assert.equal(callerInbox.items.filter((row) => row.title === 'Call declined').length, 1);
    assert.equal(
      (await inbox(db, B)).items.filter((row) => row.title === 'Missed call').length,
      1,
    );

    // A connected call that ends notifies nobody.
    const third = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '92000000-0000-4000-8000-000000000003',
    });
    await command(db, B, 'accept', { call_id: callId(third) });
    await command(db, A, 'end', { call_id: callId(third) });
    assert.equal(
      (await inbox(db, B)).items.filter(
        (row) => row.payload?.call_id === callId(third) && row.title === 'Missed call',
      ).length,
      0,
    );

    // Restricted recipients cannot be called at all, and the producer never
    // writes a row for them.
    const ringingBefore = (
      await db.query(
        "SELECT count(*)::int AS n FROM hocalist.notifications WHERE user_id=$1 AND title='Incoming Hocalist call'",
        [B],
      )
    ).rows[0].n;
    await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE user_id=$1", [B]);
    await expectDenied(
      command(db, A, 'invite', {
        conversation_id: deal.conversationId,
        key: '92000000-0000-4000-8000-000000000004',
      }),
      /account_restricted|conversation_access_denied/,
    );
    assert.equal(
      (
        await db.query(
          "SELECT count(*)::int AS n FROM hocalist.notifications WHERE user_id=$1 AND title='Incoming Hocalist call'",
          [B],
        )
      ).rows[0].n,
      ringingBefore,
    );
    await db.query("UPDATE hocalist.memberships SET status='active' WHERE user_id=$1", [B]);

    // Deals topic opt-out suppresses call notifications through the emitter.
    await db.query(
      `INSERT INTO hocalist.notification_preferences(user_id, offers, messages, deals, safety)
       VALUES($1, true, true, false, true)
       ON CONFLICT (user_id) DO UPDATE SET deals = false, revision = hocalist.notification_preferences.revision + 1`,
      [B],
    );
    const fifth = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '92000000-0000-4000-8000-000000000005',
    });
    assert.equal(
      (await inbox(db, B)).items.filter((row) => row.payload?.call_id === callId(fifth)).length,
      0,
    );
    await command(db, A, 'end', { call_id: callId(fifth) });
    await db.query(
      "UPDATE hocalist.notification_preferences SET deals = true WHERE user_id=$1",
      [B],
    );

    // Reminder producer: accepted meeting inside the window queues exactly one
    // reminder per participant, repeats are idempotent and a reschedule (new
    // revision + instant) produces a fresh reminder.
    await db.query(
      `UPDATE hocalist.meeting_schedule_revisions
       SET schedule_instant = now() + interval '30 minutes'
       WHERE id = (SELECT accepted_revision_id FROM hocalist.meetings WHERE conversation_id=$1)`,
      [deal.conversationId],
    );
    const firstRun = (
      await callAs(db, 'service_role', A, 'SELECT hocalist.notification_enqueue_meeting_reminders($1,$2) AS v', [60, 100])
    )[0].v;
    assert.equal(firstRun.queued, 2);
    const repeatRun = (
      await callAs(db, 'service_role', A, 'SELECT hocalist.notification_enqueue_meeting_reminders($1,$2) AS v', [60, 100])
    )[0].v;
    assert.equal(repeatRun.queued, 0);
    assert.equal(
      (await inbox(db, A)).items.filter((row) => row.title === 'Meeting reminder').length,
      1,
    );

    await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE user_id=$1", [B]);
    await db.query(
      `UPDATE hocalist.meetings SET revision = revision + 1,
         updated_at = now() WHERE conversation_id=$1`,
      [deal.conversationId],
    );
    await db.query(
      `UPDATE hocalist.meeting_schedule_revisions
       SET schedule_instant = now() + interval '45 minutes'
       WHERE id = (SELECT accepted_revision_id FROM hocalist.meetings WHERE conversation_id=$1)`,
      [deal.conversationId],
    );
    const afterReschedule = (
      await callAs(db, 'service_role', A, 'SELECT hocalist.notification_enqueue_meeting_reminders($1,$2) AS v', [60, 100])
    )[0].v;
    assert.equal(afterReschedule.queued, 1);
    assert.equal(
      (await inbox(db, A)).items.filter((row) => row.title === 'Meeting reminder').length,
      2,
    );
    await db.query("UPDATE hocalist.memberships SET status='active' WHERE user_id=$1", [B]);

    // An expired ringing call becomes missed on the next status sweep and
    // notifies the callee exactly once.
    const expired = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '92000000-0000-4000-8000-000000000006',
    });
    await db.query(
      "UPDATE hocalist.calls SET expires_at = now() - interval '1 second' WHERE id=$1",
      [callId(expired)],
    );
    await command(db, B, 'poll', { call_id: callId(expired) });
    assert.equal(
      (await inbox(db, B)).items.filter(
        (row) => row.payload?.call_id === callId(expired) && row.title === 'Missed call',
      ).length,
      1,
    );

    // Blocking a ringing call ends it deterministically; no missed-call alert
    // is emitted for a call the blocker deliberately stopped.
    const blockedCall = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '92000000-0000-4000-8000-000000000007',
    });
    const blockedId = callId(blockedCall);
    await rpc(db, A, 'chat_block($1,$2)', [deal.conversationId, null]);
    assert.equal(
      (await db.query('SELECT state FROM hocalist.calls WHERE id=$1', [blockedId])).rows[0].state,
      'ended',
    );
    assert.equal(
      (
        await db.query(
          "SELECT count(*)::int AS n FROM hocalist.notifications WHERE user_id=$1 AND event_key = md5('call:missed:' || $2::text)::uuid",
          [B, blockedId],
        )
      ).rows[0].n,
      0,
    );
    await rpc(db, A, 'chat_unblock($1)', [deal.conversationId]);

    // The reminder entry point is never client-executable.
    await expectDenied(
      callAs(db, 'authenticated', A, 'SELECT hocalist.notification_enqueue_meeting_reminders($1,$2)', [60, 100]),
      /permission denied/,
    );
    await expectDenied(
      callAs(db, 'anon', A, 'SELECT hocalist.notification_enqueue_meeting_reminders($1,$2)', [60, 100]),
      /permission denied/,
    );
  } finally {
    await endSuite(db);
  }
});

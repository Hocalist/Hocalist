// Disposable PostgreSQL checks for the call lifecycle read/resume contract
// (152) on top of the deployed call signaling (110) and chat block (150).
//
// PGlite is single-connection: deterministic proof for participant-only status,
// deterministic terminal states, timeout sweeps, reconnect reads, duplicate-ring
// prevention and the block/off-switch interactions. It is NOT real JWT,
// PostgREST, media or device proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  A,
  B,
  C,
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
const blockSql = await readFile(
  new URL('../150_chat_block.sql', import.meta.url),
  'utf8',
);
const statusSql = await readFile(
  new URL('../152_call_status.sql', import.meta.url),
  'utf8',
);

const command = (db, user, action, input) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.call_command($1,$2) AS v', [
    action,
    JSON.stringify(input),
  ]);

const status = async (db, user, id, cursor = 0) =>
  (await rpc(db, user, 'call_status($1,$2)', [id, cursor]))[0].v;

const callId = (result) => result[0].v.call.id;

test('call status is participant-only with deterministic terminal states', async () => {
  const db = await setup();
  try {
    const deal = await acceptedDeal(db);
    const pending = (await propose(db, A, deal.conversationId, schedule(), 'p1'))[0].data;
    await respond(db, B, pending.id, true, pending.revision, 'r1');
    await db.exec(signalingSql);
    await db.exec(blockSql);
    await db.exec(statusSql);
    await db.query('INSERT INTO hocalist.platform_admins(user_id) VALUES($1)', [A]);
    await callAs(db, 'authenticated', A, 'SELECT hocalist.call_admin_settings($1,$2) AS v', [true, 1]);

    // Invitation/accept/signal and the read path.
    const first = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '91000000-0000-4000-8000-000000000001',
    });
    const id = callId(first);
    assert.equal(first[0].v.call.state, 'ringing');
    assert.equal((await command(db, B, 'incoming', {}))[0].v.call.id, id);
    await command(db, B, 'accept', { call_id: id });
    const signal = {
      call_id: id,
      key: '91000000-0000-4000-8000-000000000002',
      kind: 'offer',
      payload: { sdp: 'synthetic' },
    };
    await command(db, A, 'signal', signal);
    const seen = await status(db, B, id);
    assert.equal(seen.call.state, 'accepted');
    assert.equal(seen.call.terminal, false);
    assert.equal(seen.enabled, true);
    assert.equal(typeof seen.call.expires_at, 'string');
    assert.equal(typeof seen.server_now, 'string');
    assert.equal(seen.signals.length, 1);
    assert.equal(seen.signals[0].kind, 'offer');
    // Cursor replay never repeats a signal.
    assert.equal((await status(db, B, id, seen.signals[0].seq)).signals.length, 0);

    // Duplicate ringing: the same intent key returns the same call, a different
    // key while active returns busy instead of a second ringing row.
    const replay = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '91000000-0000-4000-8000-000000000001',
    });
    assert.equal(callId(replay), id);
    const busy = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '91000000-0000-4000-8000-000000000003',
    });
    assert.equal(busy[0].v.status, 'busy');
    assert.equal(
      (await db.query('SELECT count(*)::int AS n FROM hocalist.calls')).rows[0].n,
      1,
    );

    // Either side ends; both reads converge on the terminal state.
    await command(db, B, 'end', { call_id: id });
    assert.equal((await status(db, A, id)).call.state, 'ended');
    assert.equal((await status(db, A, id)).call.terminal, true);

    // Timeout is deterministic: an expired accepted call becomes ended on the
    // next status read, regardless of which participant polls first.
    const second = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '91000000-0000-4000-8000-000000000004',
    });
    const secondId = callId(second);
    await command(db, B, 'accept', { call_id: secondId });
    await db.query(
      "UPDATE hocalist.calls SET expires_at = now() - interval '1 second' WHERE id=$1",
      [secondId],
    );
    assert.equal((await status(db, B, secondId)).call.state, 'ended');

    // A ringing timeout becomes missed.
    const third = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '91000000-0000-4000-8000-000000000005',
    });
    const thirdId = callId(third);
    await db.query(
      "UPDATE hocalist.calls SET expires_at = now() - interval '1 second' WHERE id=$1",
      [thirdId],
    );
    assert.equal((await status(db, A, thirdId)).call.state, 'missed');
    assert.equal((await command(db, B, 'incoming', {}))[0].v.call, null);

    // Outsider and anonymous callers have no read path.
    await expectDenied(status(db, C, thirdId), /call_access_denied/);
    await expectDenied(
      callAs(db, 'anon', A, 'SELECT hocalist.call_status($1,$2)', [thirdId, 0]),
      /permission denied/,
    );
    await expectDenied(
      rpc(db, A, 'call_status($1,$2)', ['00000000-0000-4000-8000-0000000000ff', 0]),
      /call_not_found/,
      'P0002',
    );

    // Blocking during a ringing call terminates it deterministically; the
    // blocked participant can still read the terminal state to close media.
    const fourth = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '91000000-0000-4000-8000-000000000006',
    });
    const fourthId = callId(fourth);
    await rpc(db, B, 'chat_block($1,$2)', [deal.conversationId, 'safety']);
    assert.equal(
      (await db.query('SELECT state FROM hocalist.calls WHERE id=$1', [fourthId])).rows[0].state,
      'ended',
    );
    const blockedRead = await status(db, A, fourthId);
    assert.equal(blockedRead.call.terminal, true);
    await expectDenied(
      command(db, A, 'signal', {
        call_id: fourthId,
        key: '91000000-0000-4000-8000-000000000007',
        kind: 'offer',
        payload: { sdp: 'x' },
      }),
      /conversation_blocked|call_not_accepted/,
    );
    await expectDenied(
      command(db, A, 'invite', {
        conversation_id: deal.conversationId,
        key: '91000000-0000-4000-8000-000000000008',
      }),
      /conversation_blocked/,
    );
    await rpc(db, B, 'chat_unblock($1)', [deal.conversationId]);

    // The admin off switch ends active calls and reports disabled; status
    // remains readable so clients close media.
    const fifth = await command(db, A, 'invite', {
      conversation_id: deal.conversationId,
      key: '91000000-0000-4000-8000-000000000009',
    });
    const fifthId = callId(fifth);
    await callAs(db, 'authenticated', A, 'SELECT hocalist.call_admin_settings($1,$2) AS v', [false, 2]);
    const off = await status(db, B, fifthId);
    assert.equal(off.enabled, false);
    assert.equal(off.call.terminal, true);
    assert.equal(off.call.state, 'ended');
  } finally {
    await endSuite(db);
  }
});

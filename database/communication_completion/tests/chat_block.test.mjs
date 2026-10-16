// Disposable PostgreSQL checks for the chat block/unblock contract (150).
//
// PGlite is single-connection: this is deterministic SQL proof for durable
// block state, participant/outsider authorization, read/send denial, idempotency
// and the guarantee that a block never changes deal or message history. It is
// NOT real JWT, PostgREST or concurrency proof.
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
import { chat, endSuite, expectDenied, rpc } from './support.mjs';

const blockSql = await readFile(
  new URL('../150_chat_block.sql', import.meta.url),
  'utf8',
);

const messageCount = async (db, conversation) =>
  (
    await db.query(
      'SELECT count(*)::int AS n FROM hocalist.conversation_messages WHERE conversation_id=$1',
      [conversation],
    )
  ).rows[0].n;

const activeBlocks = async (db, conversation) =>
  (
    await db.query(
      `SELECT count(*)::int AS n FROM hocalist.conversation_blocks
       WHERE conversation_id=$1 AND revoked_at IS NULL`,
      [conversation],
    )
  ).rows[0].n;

test('chat block is durable, authorized and non-destructive', async () => {
  const db = await setup();
  try {
    const deal = await acceptedDeal(db);
    const pending = (await propose(db, A, deal.conversationId, schedule(), 'p1'))[0].data;
    await respond(db, B, pending.id, true, pending.revision, 'r1');
    await db.exec(blockSql);

    const sentA = (await chat(db, A, 'send', deal.conversationId, ['a-1', 'Hello from buyer']))[0].v;
    const sentB = (await chat(db, B, 'send', deal.conversationId, ['b-1', 'Hello from seller']))[0].v;
    assert.equal(sentA.text, 'Hello from buyer');
    assert.equal(sentB.text, 'Hello from seller');

    // The outsider can never reach the conversation through any path.
    await expectDenied(
      chat(db, C, 'send', deal.conversationId, ['c-1', 'I should not send']),
      /conversation_access_denied/,
    );
    await expectDenied(chat(db, C, 'messages', deal.conversationId), /conversation_access_denied/);
    await expectDenied(
      rpc(db, C, 'chat_block_state($1)', [deal.conversationId]),
      /conversation_access_denied/,
    );
    await expectDenied(
      rpc(db, C, 'chat_block($1,$2)', [deal.conversationId, null]),
      /conversation_access_denied/,
    );

    // Seller blocks the buyer.
    const blocked = (await rpc(db, B, 'chat_block($1,$2)', [deal.conversationId, 'safety']))[0].v;
    assert.equal(blocked.is_blocked_by_me, true);
    assert.equal(blocked.blocked_by_counterpart, false);
    assert.equal(blocked.can_message, false);

    const seenByBlocked = (await rpc(db, A, 'chat_block_state($1)', [deal.conversationId]))[0].v;
    assert.equal(seenByBlocked.is_blocked_by_me, false);
    assert.equal(seenByBlocked.blocked_by_counterpart, true);
    assert.equal(seenByBlocked.can_message, false);

    // Blocked party cannot send or read through the RPCs.
    await expectDenied(
      chat(db, A, 'send', deal.conversationId, ['a-2', 'blocked message']),
      /conversation_blocked/,
    );
    await expectDenied(chat(db, A, 'messages', deal.conversationId), /conversation_blocked/);
    await expectDenied(
      rpc(db, A, 'chat_conversation($1)', [deal.conversationId]),
      /conversation_blocked/,
    );
    await expectDenied(
      rpc(db, A, 'chat_mark_read($1,$2)', [deal.conversationId, sentB.id]),
      /conversation_blocked/,
    );

    // The blocked conversation disappears from the blocked member's inbox but
    // stays visible for the blocker, who needs the reverse action.
    const inboxA = (await rpc(db, A, 'chat_inbox($1,$2)', [50, null]))[0].v;
    assert.deepEqual(inboxA.items, []);
    const inboxB = (await rpc(db, B, 'chat_inbox($1,$2)', [50, null]))[0].v;
    assert.equal(inboxB.items.length, 1);

    // The blocker keeps read access to their own history.
    const history = (await chat(db, B, 'messages', deal.conversationId))[0].v;
    assert.equal(history.items.length, 2);

    // Neither side can add messages while the block is active, including a
    // direct table insert that bypasses the send RPCs.
    await expectDenied(
      chat(db, B, 'send', deal.conversationId, ['b-2', 'blocker should not send']),
      /conversation_blocked/,
    );
    await expectDenied(
      db.query(
        `INSERT INTO hocalist.conversation_messages
           (conversation_id,sender_user_id,sender_profile_id,kind,text)
         VALUES ($1,$2,(SELECT id FROM hocalist.memberships WHERE user_id=$2 LIMIT 1),'system_notice','x')`,
        [deal.conversationId, A],
      ),
      /conversation_blocked/,
    );

    // Repeating the block is idempotent: exactly one active row.
    await rpc(db, B, 'chat_block($1,$2)', [deal.conversationId, 'other']);
    assert.equal(await activeBlocks(db, deal.conversationId), 1);

    // Blocking changed nothing commercial or historical.
    assert.equal(await messageCount(db, deal.conversationId), 2);
    assert.equal(
      (await db.query('SELECT status FROM hocalist.meetings WHERE conversation_id=$1', [deal.conversationId]))
        .rows[0].status,
      'accepted',
    );

    // Unblock restores both sides; history is intact.
    const unblocked = (await rpc(db, B, 'chat_unblock($1)', [deal.conversationId]))[0].v;
    assert.equal(unblocked.can_message, true);
    assert.equal(unblocked.is_blocked_by_me, false);
    await rpc(db, B, 'chat_unblock($1)', [deal.conversationId]);
    assert.equal(await activeBlocks(db, deal.conversationId), 0);
    const after = ((await chat(db, A, 'send', deal.conversationId, ['a-3', 'Back']))[0]).v;
    assert.equal(after.text, 'Back');
    assert.equal(await messageCount(db, deal.conversationId), 3);
  } finally {
    await endSuite(db);
  }
});

test('chat block objects are not client-accessible without a grant', async () => {
  const db = await setup();
  try {
    await db.exec(blockSql);
    await expectDenied(
      callAs(db, 'authenticated', A, 'SELECT * FROM hocalist.conversation_blocks'),
      /permission denied/,
    );
    await expectDenied(
      callAs(db, 'anon', A, 'SELECT hocalist.chat_block_state($1)', [
        '50000000-0000-4000-8000-000000000001',
      ]),
      /permission denied/,
    );
    assert.equal(
      (
        await db.query(
          "SELECT has_table_privilege('authenticated','hocalist.conversation_blocks','SELECT') AS v",
        )
      ).rows[0].v,
      false,
    );
    assert.equal(
      (
        await db.query(
          "SELECT has_function_privilege('authenticated','hocalist.chat_block_enforce_insert()','EXECUTE') AS v",
        )
      ).rows[0].v,
      false,
    );
  } finally {
    await endSuite(db);
  }
});

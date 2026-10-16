// Disposable PostgreSQL checks for server-side chat search (151).
//
// PGlite is single-connection: deterministic proof for participant-only paging,
// cross-conversation scoping, outsider denial, block interaction and query
// validation. It is NOT real JWT, PostgREST or concurrency proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { A, B, C, callAs, setup } from '../../outcomes/tests/fixture.mjs';
import { chat, endSuite, expectDenied, rpc } from './support.mjs';

const blockSql = await readFile(
  new URL('../150_chat_block.sql', import.meta.url),
  'utf8',
);
const searchSql = await readFile(
  new URL('../151_chat_search.sql', import.meta.url),
  'utf8',
);

const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MC = '10000000-0000-4000-8000-00000000000c';
const REQUEST_TWO = '20000000-0000-4000-8000-00000000000c';

const openConversation = async (db, request, participants) =>
  (
    await db.query(
      `SELECT hocalist.chat_open_internal('targeted_request',$1,NULL,NULL,NULL,$2::jsonb) AS id`,
      [request, JSON.stringify(participants)],
    )
  ).rows[0].id;

const search = async (db, user, query, { size = 25, cursor = null, conversation = null } = {}) =>
  (
    await rpc(db, user, 'chat_search($1,$2,$3,$4)', [
      query,
      size,
      cursor,
      conversation,
    ])
  )[0].v;

test('chat search is participant-only, paged and block-aware', async () => {
  const db = await setup();
  try {
    await db.exec(blockSql);
    await db.exec(searchSql);
    const requestOne = '20000000-0000-4000-8000-00000000000b';
    const convOne = await openConversation(db, requestOne, [
      { user_id: A, profile_id: MA, role: 'buyer' },
      { user_id: B, profile_id: MB, role: 'seller' },
    ]);
    const convTwo = await openConversation(db, REQUEST_TWO, [
      { user_id: A, profile_id: MA, role: 'buyer' },
      { user_id: C, profile_id: MC, role: 'seller' },
    ]);
    await chat(db, A, 'send', convOne, ['s-1', 'apple pie recipe']);
    await chat(db, B, 'send', convOne, ['s-2', 'I have apples']);
    await chat(db, A, 'send', convTwo, ['s-3', 'apple picking trip']);
    await chat(db, C, 'send', convTwo, ['s-4', 'trip planned']);

    const all = await search(db, A, 'APPLE');
    assert.equal(all.items.length, 3);
    assert.equal(all.next_cursor, null);
    const targetConversations = new Set(all.items.map((row) => row.conversation_id));
    assert.deepEqual(targetConversations, new Set([convOne, convTwo]));
    assert.equal(all.items[0].message.text, 'apple picking trip');
    assert.ok(['Buyer A', 'Seller B', 'Seller C'].includes(all.items[0].counterpart_display_name));

    // Each participant only sees their own conversations.
    assert.equal((await search(db, B, 'apple')).items.length, 2);
    assert.equal((await search(db, B, 'apple')).items.every(
      (row) => row.conversation_id === convOne,
    ), true);
    assert.equal((await search(db, C, 'apple')).items.length, 1);
    assert.equal((await search(db, C, 'apple')).items[0].conversation_id, convTwo);

    // Conversations are blocked for outsider rows for the blocked counterpart.
    await expectDenied(
      rpc(db, C, 'chat_search($1,$2,$3,$4)', ['apple', 25, null, convOne]),
      /conversation_access_denied/,
    );

    // Paging: newest-first, no overlap, deterministic cursor.
    const first = await search(db, A, 'apple', { size: 2 });
    assert.equal(first.items.length, 2);
    assert.equal(typeof first.next_cursor, 'string');
    const second = await search(db, A, 'apple', { size: 2, cursor: first.next_cursor });
    assert.equal(second.items.length, 1);
    assert.equal(second.next_cursor, null);
    const ids = new Set([...first.items, ...second.items].map((row) => row.message.id));
    assert.equal(ids.size, 3);
    await expectDenied(
      rpc(db, A, 'chat_search($1,$2,$3,$4)', ['apple', 25, 'not-a-cursor', null]),
      /invalid_cursor/,
      '22023',
    );

    // Validation is bounded and never echoes the query text.
    const tooShort = await expectDenied(
      rpc(db, A, 'chat_search($1,$2,$3,$4)', ['7', 25, null, null]),
      /invalid_field: p_query/,
      '22023',
    );
    assert.equal(tooShort.message.includes('7'), false);
    await expectDenied(
      rpc(db, A, 'chat_search($1,$2,$3,$4)', [null, 25, null, null]),
      /invalid_field: p_query/,
      '22023',
    );

    // Inbox name search returns only the caller's conversations.
    const inboxA = (await rpc(db, A, 'chat_search_inbox($1,$2,$3)', ['seller', 25, null]))[0].v;
    assert.equal(inboxA.items.length, 2);
    const inboxB = (await rpc(db, B, 'chat_search_inbox($1,$2,$3)', ['buyer', 25, null]))[0].v;
    assert.equal(inboxB.items.length, 1);
    assert.equal(inboxB.items[0].conversation.id, convOne);
    assert.equal(
      (await rpc(db, B, 'chat_search_inbox($1,$2,$3)', ['zebra', 25, null]))[0].v.items.length,
      0,
    );

    // Blocking hides the blocked member's search results but not the blocker's
    // own scoped history search.
    await rpc(db, B, 'chat_block($1,$2)', [convOne, null]);
    assert.equal((await search(db, A, 'apple')).items.length, 1);
    assert.equal((await search(db, A, 'apple')).items[0].conversation_id, convTwo);
    assert.equal((await search(db, B, 'apple')).items.length, 2);
    await expectDenied(
      rpc(db, A, 'chat_search($1,$2,$3,$4)', ['apple', 25, null, convOne]),
      /conversation_blocked/,
    );
    await rpc(db, B, 'chat_unblock($1)', [convOne]);
    assert.equal((await search(db, A, 'apple')).items.length, 3);

    // Anonymous callers have no search path.
    await expectDenied(
      callAs(db, 'anon', A, 'SELECT hocalist.chat_search($1,$2,$3,$4)', ['apple', 25, null, null]),
      /permission denied/,
    );
  } finally {
    await endSuite(db);
  }
});

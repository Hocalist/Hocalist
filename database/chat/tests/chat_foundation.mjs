// Disposable PostgreSQL checks for the persistent text-chat foundation.
//
// PGlite is single-connection: this is deterministic SQL proof for
// participation, idempotency, pagination, read/mute state and privileges.
// It is NOT real JWT, PostgREST, Realtime or concurrency proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const C = '00000000-0000-4000-8000-00000000000c';
const D = '00000000-0000-4000-8000-00000000000d';
const E = '00000000-0000-4000-8000-00000000000e';
const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MC = '10000000-0000-4000-8000-00000000000c';
const MD = '10000000-0000-4000-8000-00000000000d';
const ME = '10000000-0000-4000-8000-00000000000e';
const REQUEST = '20000000-0000-4000-8000-000000000001';
const LISTING = '30000000-0000-4000-8000-000000000001';
const TOPIC = '40000000-0000-4000-8000-000000000001';

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

async function openConversation(db, origin, subjects, participants) {
  const rows = await db.query(
    `SELECT hocalist.chat_open_internal($1,$2,$3,$4,$5,$6::jsonb) AS id`,
    [
      origin,
      subjects.request ?? null,
      subjects.offer ?? null,
      subjects.listing ?? null,
      subjects.topic ?? null,
      JSON.stringify(participants),
    ],
  );
  return rows.rows[0].id;
}

async function seed(db) {
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${A}','{}'),('${B}','{}'),('${C}','{}'),('${D}','{}'),('${E}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${MA}','${A}','buyer','active'),
      ('${MB}','${B}','seller','active'),
      ('${MC}','${C}','buyer','active'),
      ('${MD}','${D}','seller','active'),
      ('${ME}','${E}','buyer','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
      ('${MA}','Buyer A'),('${MB}','Seller B'),('${MC}','Buyer C'),
      ('${MD}','Seller D'),('${ME}','Buyer E');
  `);
}

const member = (user, profile, role) => ({ user_id: user, profile_id: profile, role });

test('persistent text chat foundation in disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyAccountDrafts(db);
    await db.exec(
      await readFile(new URL('../010_chat_foundation.sql', import.meta.url), 'utf8'),
    );
    await seed(db);

    const conv1 = await openConversation(
      db,
      'targeted_request',
      { request: REQUEST },
      [member(A, MA, 'buyer'), member(B, MB, 'seller')],
    );
    const conv2 = await openConversation(
      db,
      'store_listing',
      { listing: LISTING },
      [member(B, MB, 'seller'), member(C, MC, 'buyer')],
    );
    const conv3 = await openConversation(
      db,
      'hocatrends_enquiry',
      { topic: TOPIC },
      [member(B, MB, 'seller'), member(D, MD, 'seller')],
    );
    const conv4 = await openConversation(
      db,
      'store_listing',
      { listing: '30000000-0000-4000-8000-000000000004' },
      [member(B, MB, 'seller'), member(E, ME, 'buyer')],
    );

    const sendAs = (role, user, conversation, key, text) =>
      callAs(
        db,
        role,
        user,
        'SELECT hocalist.chat_send($1,$2,$3) AS message',
        [conversation, key, text],
      );

    await t.test('origins and subjects are separated', async () => {
      const rows = await db.query(
        'SELECT id, origin, request_id, listing_id, discovery_topic_id FROM hocalist.conversations ORDER BY id',
      );
      const byId = new Map(rows.rows.map((row) => [row.id, row]));
      assert.equal(byId.get(conv1).origin, 'targeted_request');
      assert.equal(byId.get(conv1).request_id, REQUEST);
      assert.equal(byId.get(conv2).origin, 'store_listing');
      assert.equal(byId.get(conv2).listing_id, LISTING);
      assert.equal(byId.get(conv3).origin, 'hocatrends_enquiry');
      assert.equal(byId.get(conv3).discovery_topic_id, TOPIC);
      await expectDenied(
        db.query(
          `SELECT hocalist.chat_open_internal('store_listing',$1,NULL,NULL,NULL,$2::jsonb)`,
          [REQUEST, JSON.stringify([member(A, MA, 'buyer'), member(B, MB, 'seller')])],
        ),
        'invalid_subject',
        '22023',
      );
      await expectDenied(
        db.query(
          `SELECT hocalist.chat_open_internal('targeted_request',$1,NULL,NULL,NULL,$2::jsonb)`,
          [
            REQUEST,
            JSON.stringify([member(A, MA, 'buyer'), member(C, MC, 'seller')]),
          ],
        ),
        'invalid_participants',
        '22023',
      );
    });

    await t.test('participants read their own conversation only', async () => {
      const aInbox = (await callAs(db, 'authenticated', A, 'SELECT hocalist.chat_inbox(50,NULL) AS data'))[0].data;
      assert.equal(aInbox.items.length, 1);
      assert.equal(aInbox.items[0].conversation.id, conv1);
      assert.equal(aInbox.items[0].counterpart_profile_id, MB);
      assert.equal(aInbox.items[0].counterpart_display_name, 'Seller B');
      assert.equal(aInbox.items[0].unread_count, 0);
      assert.equal(aInbox.items[0].latest_message, null);
      assert.equal(aInbox.next_cursor, null);

      const bInbox = (await callAs(db, 'authenticated', B, 'SELECT hocalist.chat_inbox(50,NULL) AS data'))[0].data;
      assert.equal(bInbox.items.length, 4);

      const conversation = (await callAs(
        db,
        'authenticated',
        A,
        'SELECT hocalist.chat_conversation($1) AS data',
        [conv1],
      ))[0].data;
      assert.equal(conversation.id, conv1);
      assert.equal(conversation.origin, 'targeted_request');
      assert.equal(conversation.status, 'open');
      assert.equal(conversation.members.length, 2);
      assert.equal(conversation.revision, 1);
      assert.ok(conversation.created_at && conversation.updated_at);
    });

    await t.test('outsider, anon and non-participants are denied everywhere', async () => {
      await expectDenied(
        callAs(db, 'authenticated', C, 'SELECT hocalist.chat_conversation($1)', [conv1]),
        'conversation_access_denied',
      );
      await expectDenied(
        callAs(db, 'authenticated', C, 'SELECT hocalist.chat_messages($1,50,NULL)', [conv1]),
        'conversation_access_denied',
      );
      await expectDenied(
        callAs(db, 'authenticated', C, 'SELECT hocalist.chat_send($1,$2,$3)', [conv1, 'c-key', 'intrusion']),
        'conversation_access_denied',
      );
      await expectDenied(
        callAs(db, 'authenticated', C, 'SELECT hocalist.chat_mark_read($1,$2)', [conv1, REQUEST]),
        'conversation_access_denied',
      );
      await expectDenied(
        callAs(db, 'authenticated', C, 'SELECT hocalist.chat_set_muted($1,true)', [conv1]),
        'conversation_access_denied',
      );
      await expectDenied(
        callAs(db, 'anon', '', 'SELECT hocalist.chat_inbox(50,NULL)'),
        'permission denied',
      );
      await expectDenied(
        callAs(db, 'anon', '', 'SELECT hocalist.chat_conversation($1)', [conv1]),
        'permission denied',
      );
      const cInbox = (await callAs(db, 'authenticated', C, 'SELECT hocalist.chat_inbox(50,NULL) AS data'))[0].data;
      assert.deepEqual(cInbox.items.map((item) => item.conversation.id), [conv2]);
      assert.equal(cInbox.items[0].unread_count, 0);
      assert.equal(cInbox.items[0].latest_message, null);
    });

    await t.test('restricted and inactive memberships deny reads and writes', async () => {
      await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE id=$1", [MD]);
      await expectDenied(
        callAs(db, 'authenticated', D, 'SELECT hocalist.chat_conversation($1)', [conv3]),
        'account_restricted',
      );
      await expectDenied(
        callAs(db, 'authenticated', D, 'SELECT hocalist.chat_send($1,$2,$3)', [conv3, 'd-key', 'blocked']),
        'account_restricted',
      );
      await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1", [MD]);

      await db.query("UPDATE hocalist.memberships SET status='pending' WHERE id=$1", [ME]);
      await expectDenied(
        callAs(db, 'authenticated', E, 'SELECT hocalist.chat_conversation($1)', [conv4]),
        'role_not_active',
      );
      await expectDenied(
        callAs(db, 'authenticated', E, 'SELECT hocalist.chat_send($1,$2,$3)', [conv4, 'e-key', 'pending']),
        'role_not_active',
      );
      const pendingInbox = (await callAs(db, 'authenticated', E, 'SELECT hocalist.chat_inbox(50,NULL) AS data'))[0].data;
      assert.deepEqual(pendingInbox.items, []);
      await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1", [ME]);
    });

    await t.test('sender, role and ownership are server-assigned', async () => {
      await expectDenied(
        asRole(db, 'authenticated', A, () =>
          db.query(
            "INSERT INTO hocalist.conversation_messages(conversation_id,sender_user_id,sender_profile_id,text,client_message_id,request_hash) VALUES ($1,$2,$3,'forged','k','h')",
            [conv1, B, MB],
          ),
        ),
        'permission denied',
      );
      await expectDenied(
        asRole(db, 'authenticated', A, () =>
          db.query('UPDATE hocalist.conversation_members SET role=$1', ['seller']),
        ),
        'permission denied',
      );
      await expectDenied(
        callAs(db, 'authenticated', A, 'SELECT hocalist.chat_open_internal($1,$2,NULL,NULL,NULL,$3::jsonb)', [
          'targeted_request',
          REQUEST,
          JSON.stringify([member(A, MA, 'buyer'), member(B, MB, 'seller')]),
        ]),
        'permission denied',
      );
      await expectDenied(
        callAs(db, 'service_role', '', 'SELECT hocalist.chat_open_internal($1,$2,NULL,NULL,NULL,$3::jsonb)', [
          'targeted_request',
          REQUEST,
          JSON.stringify([member(A, MA, 'buyer'), member(B, MB, 'seller')]),
        ]),
        'permission denied',
      );
    });

    await t.test('idempotent sends replay, conflict on changed payload', async () => {
      const first = (await sendAs('authenticated', A, conv1, 'send-1', 'Hello B'))[0].message;
      assert.equal(first.sender_user_id, A);
      assert.equal(first.sender_profile_id, MA);
      assert.equal(first.kind, 'text');
      assert.equal(first.text, 'Hello B');
      assert.equal(first.client_message_id, 'send-1');
      assert.ok(first.seq > 0 && first.sent_at);

      const replay = (await sendAs('authenticated', A, conv1, 'send-1', 'Hello B'))[0].message;
      assert.equal(replay.id, first.id);
      assert.equal(
        (await db.query('SELECT count(*)::int AS n FROM hocalist.conversation_messages WHERE conversation_id=$1', [conv1])).rows[0].n,
        1,
      );
      await expectDenied(
        callAs(db, 'authenticated', A, 'SELECT hocalist.chat_send($1,$2,$3)', [conv1, 'send-1', 'Changed']),
        'idempotency_conflict',
        'P0001',
      );
      const otherSender = (await sendAs('authenticated', B, conv1, 'send-1', 'Hello A'))[0].message;
      assert.notEqual(otherSender.id, first.id);
      assert.equal(otherSender.sender_user_id, B);
      assert.equal(otherSender.sender_profile_id, MB);
      await expectDenied(
        callAs(db, 'authenticated', A, 'SELECT hocalist.chat_send($1,$2,$3)', [conv1, 'send-2', '   ']),
        'invalid_message',
        '22023',
      );
    });

    await t.test('pagination is deterministic with a tie-breaker', async () => {
      for (let index = 2; index <= 6; index += 1) {
        await sendAs('authenticated', A, conv1, `page-${index}`, `message ${index}`);
      }
      const all = (await callAs(db, 'authenticated', A, 'SELECT hocalist.chat_messages($1,50,NULL) AS data', [conv1]))[0].data;
      const ids = all.items.map((message) => message.id);
      assert.equal(all.next_cursor, null);
      assert.equal(new Set(ids).size, ids.length);
      const seqs = all.items.map((message) => message.seq);
      assert.deepEqual(seqs, [...seqs].sort((left, right) => left - right));

      const firstPage = (await callAs(db, 'authenticated', B, 'SELECT hocalist.chat_messages($1,3,NULL) AS data', [conv1]))[0].data;
      assert.equal(firstPage.items.length, 3);
      assert.deepEqual(firstPage.items.map((message) => message.text), ['message 4', 'message 5', 'message 6']);
      assert.equal(firstPage.next_cursor, firstPage.items[0].id);

      const secondPage = (await callAs(db, 'authenticated', B, 'SELECT hocalist.chat_messages($1,3,$2) AS data', [conv1, firstPage.next_cursor]))[0].data;
      assert.deepEqual(secondPage.items.map((message) => message.text), ['Hello A', 'message 2', 'message 3']);
      assert.equal(secondPage.next_cursor, secondPage.items[0].id);

      const thirdPage = (await callAs(db, 'authenticated', B, 'SELECT hocalist.chat_messages($1,3,$2) AS data', [conv1, secondPage.next_cursor]))[0].data;
      assert.deepEqual(thirdPage.items.map((message) => message.text), ['Hello B']);
      assert.equal(thirdPage.next_cursor, null);

      await expectDenied(
        callAs(db, 'authenticated', B, 'SELECT hocalist.chat_messages($1,3,$2)', [conv2, firstPage.items[0].id]),
        'invalid_cursor',
        '22023',
      );
    });

    await t.test('read markers are monotonic and drive unread counts', async () => {
      const messages = (await callAs(db, 'authenticated', A, 'SELECT hocalist.chat_messages($1,50,NULL) AS data', [conv1]))[0].data.items;
      // Ascending page: [Hello B(1), Hello A(2), message 2(3), ...].
      const marked = (await callAs(db, 'authenticated', A, 'SELECT hocalist.chat_mark_read($1,$2) AS member', [conv1, messages[1].id]))[0].member;
      assert.equal(marked.last_read_message_id, messages[1].id);
      assert.ok(marked.last_read_at);
      const backwards = (await callAs(db, 'authenticated', A, 'SELECT hocalist.chat_mark_read($1,$2) AS member', [conv1, messages[0].id]))[0].member;
      assert.equal(backwards.last_read_message_id, messages[1].id);
      assert.equal(backwards.last_read_seq, messages[1].seq, 'no-op returns the authoritative marker');
      const stored = (await db.query(
        'SELECT last_read_seq, last_read_message_id FROM hocalist.conversation_members WHERE conversation_id=$1 AND user_id=$2',
        [conv1, A],
      )).rows[0];
      assert.equal(stored.last_read_seq, messages[1].seq);
      assert.equal(stored.last_read_message_id, messages[1].id);

      const inbox = (await callAs(db, 'authenticated', A, 'SELECT hocalist.chat_inbox(50,NULL) AS data'))[0].data;
      assert.equal(inbox.items[0].unread_count, 0);

      const bInbox = (await callAs(db, 'authenticated', B, 'SELECT hocalist.chat_inbox(50,NULL) AS data'))[0].data;
      const conv1Row = bInbox.items.find((item) => item.conversation.id === conv1);
      assert.equal(conv1Row.unread_count, 6);

      const bMarked = (await callAs(db, 'authenticated', B, 'SELECT hocalist.chat_mark_read($1,$2) AS member', [conv1, messages[0].id]))[0].member;
      assert.equal(bMarked.last_read_message_id, messages[0].id);
      const bAfter = (await callAs(db, 'authenticated', B, 'SELECT hocalist.chat_inbox(50,NULL) AS data'))[0].data;
      const bRow = bAfter.items.find((item) => item.conversation.id === conv1);
      assert.equal(bRow.unread_count, 5);
    });

    await t.test('mute is per member and does not affect the counterpart', async () => {
      const muted = (await callAs(db, 'authenticated', A, 'SELECT hocalist.chat_set_muted($1,true) AS member', [conv1]))[0].member;
      assert.equal(muted.is_muted, true);
      const bMember = (await callAs(db, 'authenticated', B, 'SELECT hocalist.chat_conversation($1) AS data', [conv1]))[0].data.members.find((row) => row.user_id === B);
      assert.equal(bMember.is_muted, false);
      const unmuted = (await callAs(db, 'authenticated', A, 'SELECT hocalist.chat_set_muted($1,false) AS member', [conv1]))[0].member;
      assert.equal(unmuted.is_muted, false);
    });

    await t.test('closed conversations deny writes but remain readable', async () => {
      await db.query("UPDATE hocalist.conversations SET status='closed' WHERE id=$1", [conv1]);
      await expectDenied(
        callAs(db, 'authenticated', A, 'SELECT hocalist.chat_send($1,$2,$3)', [conv1, 'closed-key', 'after close']),
        'conversation_closed',
        'P0001',
      );
      const read = (await callAs(db, 'authenticated', A, 'SELECT hocalist.chat_messages($1,50,NULL) AS data', [conv1]))[0].data;
      assert.ok(read.items.length > 0);
      await db.query("UPDATE hocalist.conversations SET status='open' WHERE id=$1", [conv1]);
    });

    await t.test('inbox pagination uses the composite cursor', async () => {
      const firstPage = (await callAs(db, 'authenticated', B, 'SELECT hocalist.chat_inbox(2,NULL) AS data'))[0].data;
      assert.equal(firstPage.items.length, 2);
      assert.ok(firstPage.next_cursor);
      const secondPage = (await callAs(db, 'authenticated', B, 'SELECT hocalist.chat_inbox(2,$1) AS data', [firstPage.next_cursor]))[0].data;
      const ids = [...firstPage.items, ...secondPage.items].map((item) => item.conversation.id);
      assert.equal(new Set(ids).size, ids.length);
      assert.equal(ids.length, 4);
      await expectDenied(
        callAs(db, 'authenticated', B, 'SELECT hocalist.chat_inbox(2,$1)', ['not-a-cursor']),
        'invalid_cursor',
        '22023',
      );
    });

    await t.test('client and service roles have no direct table access', async () => {
      for (const role of ['authenticated', 'anon', 'service_role']) {
        for (const table of ['conversations', 'conversation_members', 'conversation_messages']) {
          await expectDenied(
            asRole(db, role, role === 'authenticated' ? A : '', () =>
              db.query(`SELECT * FROM hocalist.${table}`),
            ),
            'permission denied',
          );
        }
      }
      const privileges = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.chat_inbox(integer,text)','EXECUTE') AS inbox,
          has_function_privilege('authenticated','hocalist.chat_send(uuid,text,text)','EXECUTE') AS send,
          has_function_privilege('anon','hocalist.chat_inbox(integer,text)','EXECUTE') AS anon_inbox,
          has_function_privilege('service_role','hocalist.chat_inbox(integer,text)','EXECUTE') AS service_inbox,
          has_function_privilege('authenticated','hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)','EXECUTE') AS open_internal,
          has_function_privilege('authenticated','hocalist.chat_assert_participant(uuid,uuid)','EXECUTE') AS helper,
          has_function_privilege('authenticated','hocalist.chat_conversation_json(uuid)','EXECUTE') AS builder
      `);
      assert.deepEqual(privileges.rows[0], {
        inbox: true,
        send: true,
        anon_inbox: false,
        service_inbox: false,
        open_internal: false,
        helper: false,
        builder: false,
      });
      const policies = await db.query(
        "SELECT count(*)::int AS n FROM pg_policies WHERE schemaname='hocalist' AND tablename LIKE 'conversation%'",
      );
      assert.equal(policies.rows[0].n, 3);
    });
  } finally {
    await db.close();
  }
});

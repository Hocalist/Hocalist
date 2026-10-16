// Disposable PostgreSQL checks for the chat change-signal table, its
// least-exposure Realtime publication and the member/role/restriction/block
// scoped read policy (154).
//
// PGlite is single-connection: deterministic proof for signal creation,
// pruning and real RLS decisions under `SET ROLE authenticated`. It is NOT
// real Realtime delivery or JWT proof; live subscriber authorization remains a
// coordinator check.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { A, B, C, acceptedDeal, callAs, setup } from '../../outcomes/tests/fixture.mjs';
import { chat, endSuite, expectDenied, rpc } from './support.mjs';

const blockSql = await readFile(
  new URL('../150_chat_block.sql', import.meta.url),
  'utf8',
);
const signalSql = await readFile(
  new URL('../154_chat_realtime_signals.sql', import.meta.url),
  'utf8',
);

const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MD = '10000000-0000-4000-8000-00000000000d';
const ME = '10000000-0000-4000-8000-00000000000e';
const D = '00000000-0000-4000-8000-00000000000d';
const E = '00000000-0000-4000-8000-00000000000e';

const signalsSeenBy = async (db, user) =>
  (
    await callAs(
      db,
      'authenticated',
      user,
      'SELECT count(*)::int AS n FROM hocalist.chat_change_signals',
    )
  )[0].n;

test('chat change signals are content-free, member-scoped and contained', async () => {
  const db = await setup();
  try {
    await db.exec(blockSql);
    // Simulate a provisioned Realtime publication before the migration.
    await db.exec('CREATE PUBLICATION supabase_realtime;');
    await db.exec(signalSql);
    const deal = await acceptedDeal(db);

    await chat(db, A, 'send', deal.conversationId, ['s-1', 'first']);
    await chat(db, B, 'send', deal.conversationId, ['s-2', 'second']);
    const signals = await db.query(
      'SELECT conversation_id, created_at FROM hocalist.chat_change_signals ORDER BY id',
    );
    assert.equal(signals.rows.length, 2);
    assert.equal(signals.rows.every((row) => row.conversation_id === deal.conversationId), true);

    // Pruning keeps the newest window bounded.
    await db.query(
      `INSERT INTO hocalist.chat_change_signals(conversation_id, created_at)
       VALUES ($1, now() - interval '2 hours')`,
      [deal.conversationId],
    );
    await chat(db, A, 'send', deal.conversationId, ['s-3', 'third']);
    const afterPrune = await db.query('SELECT count(*)::int AS n FROM hocalist.chat_change_signals');
    assert.equal(afterPrune.rows[0].n, 3);
    const stale = await db.query(
      "SELECT count(*)::int AS n FROM hocalist.chat_change_signals WHERE created_at < now() - interval '1 hour'",
    );
    assert.equal(stale.rows[0].n, 0);

    // Members can read their own signal rows; outsiders see none under the
    // same grant because the policy fences by membership.
    assert.ok(await signalsSeenBy(db, A) >= 1);
    assert.ok(await signalsSeenBy(db, B) >= 1);
    assert.equal(await signalsSeenBy(db, C), 0);
    await expectDenied(
      callAs(db, 'anon', A, 'SELECT count(*) FROM hocalist.chat_change_signals'),
      /permission denied/,
    );

    // Only the single signal table is published for hocalist.
    const published = await db.query(
      `SELECT tablename FROM pg_publication_tables
       WHERE pubname='supabase_realtime' AND schemaname='hocalist' ORDER BY tablename`,
    );
    assert.deepEqual(published.rows.map((row) => row.tablename), ['chat_change_signals']);
    const allPublished = await db.query(
      `SELECT schemaname, tablename FROM pg_publication_tables WHERE pubname='supabase_realtime'`,
    );
    assert.equal(allPublished.rows.length, 1);

    // The signal table carries no message content.
    const columns = await db.query(
      `SELECT attname FROM pg_attribute
       WHERE attrelid='hocalist.chat_change_signals'::regclass AND attnum>0 AND NOT attisdropped
       ORDER BY attnum`,
    );
    assert.deepEqual(columns.rows.map((row) => row.attname), [
      'id',
      'conversation_id',
      'created_at',
    ]);
  } finally {
    await endSuite(db);
  }
});

test('signal reads honor role, restriction, revocation and block policy', async () => {
  const db = await setup();
  try {
    await db.exec(blockSql);
    await db.exec(signalSql);
    const deal = await acceptedDeal(db);
    await chat(db, A, 'send', deal.conversationId, ['s-1', 'hello']);

    // Extra identities: D is a conversation member whose seller membership is
    // later moved to pending; E is an active buyer whose member row is changed
    // to a seller for the wrong-role case.
    await db.exec(`
      INSERT INTO auth.users(id, raw_user_meta_data) VALUES ('${D}','{}'),('${E}','{}');
      INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
        ('${MD}','${D}','seller','active'),
        ('${ME}','${E}','buyer','active');
      INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
        ('${MD}','Seller D'),('${ME}','Buyer E');
    `);
    const convD = (
      await db.query(
        `SELECT hocalist.chat_open_internal('targeted_request',$1,NULL,NULL,NULL,$2::jsonb) AS id`,
        [
          '20000000-0000-4000-8000-00000000000d',
          JSON.stringify([
            { user_id: A, profile_id: MA, role: 'buyer' },
            { user_id: D, profile_id: MD, role: 'seller' },
          ]),
        ],
      )
    ).rows[0].id;
    await chat(db, A, 'send', convD, ['s-2', 'to d']);

    // Normal counterpart and blocker access.
    assert.ok(await signalsSeenBy(db, A) >= 1);
    assert.ok(await signalsSeenBy(db, B) >= 1);
    assert.ok(await signalsSeenBy(db, D) >= 1);

    // Restricted/disabled accounts see nothing.
    await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE user_id=$1", [B]);
    assert.equal(await signalsSeenBy(db, B), 0);
    await db.query("UPDATE hocalist.memberships SET status='disabled' WHERE user_id=$1", [B]);
    assert.equal(await signalsSeenBy(db, B), 0);
    await db.query("UPDATE hocalist.memberships SET status='active' WHERE user_id=$1", [B]);
    assert.ok(await signalsSeenBy(db, B) >= 1);

    // Directional block: the blocked party sees nothing; the blocker keeps
    // their own conversation signals.
    await rpc(db, A, 'chat_block($1,$2)', [deal.conversationId, null]);
    assert.equal(await signalsSeenBy(db, B), 0);
    assert.ok(await signalsSeenBy(db, A) >= 1);
    await rpc(db, A, 'chat_unblock($1)', [deal.conversationId]);

    // Pending membership and a revoked member row are denied.
    await db.query("UPDATE hocalist.memberships SET status='pending' WHERE user_id=$1", [D]);
    assert.equal(await signalsSeenBy(db, D), 0);
    await db.query("UPDATE hocalist.memberships SET status='active' WHERE user_id=$1", [D]);
    assert.ok(await signalsSeenBy(db, D) >= 1);
    await db.query(
      'UPDATE hocalist.conversation_members SET revoked_at = now() WHERE conversation_id=$1 AND user_id=$2',
      [convD, D],
    );
    assert.equal(await signalsSeenBy(db, D), 0);

    // Wrong-role member row: buyer membership presented as a seller member.
    await db.query(
      'INSERT INTO hocalist.conversation_members(conversation_id,user_id,profile_id,role) VALUES ($1,$2,$3,$4)',
      [convD, E, ME, 'seller'],
    );
    assert.equal(await signalsSeenBy(db, E), 0);

    // The internal helper stays unexecutable by clients.
    await expectDenied(
      callAs(db, 'authenticated', A, 'SELECT hocalist.chat_is_member($1,$2)', [convD, A]),
      /permission denied/,
    );
    await expectDenied(
      callAs(db, 'authenticated', A, 'SELECT hocalist.chat_signal_on_message()'),
      /permission denied/,
    );
  } finally {
    await endSuite(db);
  }
});

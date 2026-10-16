// Disposable PostgreSQL checks for authorized chat image attachments (draft
// database/chat/011_chat_attachments.sql).
//
// PGlite is single-connection: deterministic SQL proof for participant
// authorization, media ownership, idempotency, shape constraints and media
// read authorization. It is NOT real JWT/PostgREST, storage or device proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';
import { readFile } from 'node:fs/promises';

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const C = '00000000-0000-4000-8000-00000000000c';
const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MC = '10000000-0000-4000-8000-00000000000c';
const LISTING = '30000000-0000-4000-8000-000000000001';
const IMAGE_A = '50000000-0000-4000-8000-00000000000a';
const IMAGE_A2 = '50000000-0000-4000-8000-00000000000b';
const M_SELLER_BUYER = '10000000-0000-4000-8000-00000000000d';

const sql = (path) => readFile(new URL(path, import.meta.url), 'utf8');

async function asRole(db, role, user, body) {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return await body();
  } finally {
    await db.exec('RESET ROLE');
  }
}

const callAs = (db, role, user, statement, params = []) =>
  asRole(db, role, user, async () => (await db.query(statement, params)).rows);

async function expectFailure(promise, code, messagePart) {
  try {
    await promise;
  } catch (error) {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}: ${error.message}`);
    if (messagePart) assert.match(error.message, new RegExp(messagePart));
    return;
  }
  assert.fail(`expected SQLSTATE ${code}`);
}

async function baseline() {
  const db = await createDisposableDb();
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  await db.exec(await sql('../../provider-rollout/apply.sql'));
  await db.exec(await sql('../010_chat_foundation.sql'));
  await db.exec(await sql('../../marketplace/020_marketplace_foundation.sql'));
  await db.exec(await sql('../../media/100_private_images.sql'));
  await db.exec(await sql('../011_chat_attachments.sql'));
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${A}','{}'),('${B}','{}'),('${C}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${MA}','${A}','buyer','active'),
      ('${MB}','${B}','seller','active'),
      ('${MC}','${C}','buyer','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
      ('${MA}','Buyer A'),('${MB}','Seller B'),('${MC}','Buyer C');
    INSERT INTO hocalist.media_images(
      id, owner_user_id, intent_key, purpose, state, size_bytes, width, height, content_hash)
    VALUES
      ('${IMAGE_A}','${A}','60000000-0000-4000-8000-00000000000a','chat','ready',1000,100,100,
        repeat('a',64)),
      ('${IMAGE_A2}','${A}','60000000-0000-4000-8000-00000000000b','chat','ready',1000,100,100,
        repeat('b',64));
  `);
  return db;
}

async function openConversation(db) {
  return (
    await db.query(
      `SELECT hocalist.chat_open_internal('store_listing', null, null, $1, null, $2::jsonb) AS id`,
      [
        LISTING,
        JSON.stringify([
          { user_id: A, profile_id: MA, role: 'buyer' },
          { user_id: B, profile_id: MB, role: 'seller' },
        ]),
      ],
    )
  ).rows[0].id;
}

const gatewayReadAs = (db, user, imageId) =>
  callAs(
    db,
    'service_role',
    'service_role',
    `SELECT hocalist.media_gateway($1,'read',$2::jsonb) AS image`,
    [user, JSON.stringify({ id: imageId })],
  );

test('authorized chat attachments in disposable PostgreSQL', async (t) => {
  const db = await baseline();
  try {
    const conversation = await openConversation(db);
    let sent;

    await t.test('a participant sends an owned, ready chat image', async () => {
      sent = (
        await callAs(
          db,
          'authenticated',
          A,
          `SELECT hocalist.chat_send_attachment($1,$2,$3,$4::jsonb) AS message`,
          [conversation, 'attach-1', 'Look at this.', JSON.stringify([IMAGE_A])],
        )
      )[0].message;
      assert.equal(sent.kind, 'attachment');
      assert.deepEqual(sent.attachment_media_ids, [IMAGE_A]);
      assert.equal(sent.text, 'Look at this.');

      const page = (
        await callAs(
          db,
          'authenticated',
          B,
          `SELECT hocalist.chat_messages($1, 50, null) AS page`,
          [conversation],
        )
      )[0].page;
      assert.equal(page.items.length, 1);
      assert.equal(page.items[0].kind, 'attachment');
      assert.deepEqual(page.items[0].attachment_media_ids, [IMAGE_A]);
    });

    await t.test('the attachment kind does not trigger a text message notification', async () => {
      const rows = await db.query(
        'SELECT count(*)::int AS n FROM hocalist.notifications WHERE kind = $1',
        ['new_message'],
      );
      assert.equal(rows.rows[0].n, 0, 'attachment messages are not text notifications');
    });

    await t.test('retrying the same intent is idempotent and a changed payload conflicts', async () => {
      const retry = (
        await callAs(
          db,
          'authenticated',
          A,
          `SELECT hocalist.chat_send_attachment($1,$2,$3,$4::jsonb) AS message`,
          [conversation, 'attach-1', 'Look at this.', JSON.stringify([IMAGE_A])],
        )
      )[0].message;
      assert.equal(retry.id, sent.id, 'same key and payload returns the stored message');
      await expectFailure(
        callAs(
          db,
          'authenticated',
          A,
          `SELECT hocalist.chat_send_attachment($1,$2,$3,$4::jsonb) AS message`,
          [conversation, 'attach-1', 'Different text.', JSON.stringify([IMAGE_A2])],
        ),
        'P0001',
        'idempotency_conflict',
      );
    });

    await t.test('another user cannot send someone else\'s image', async () => {
      await expectFailure(
        callAs(
          db,
          'authenticated',
          B,
          `SELECT hocalist.chat_send_attachment($1,$2,$3,$4::jsonb) AS message`,
          [conversation, 'attach-b1', '', JSON.stringify([IMAGE_A])],
        ),
        '22023',
        'invalid_media_reference',
      );
    });

    await t.test('outsiders cannot send or read chat images', async () => {
      await expectFailure(
        callAs(
          db,
          'authenticated',
          C,
          `SELECT hocalist.chat_send_attachment($1,$2,$3,$4::jsonb) AS message`,
          [conversation, 'attach-c1', '', JSON.stringify([IMAGE_A])],
        ),
        '42501',
      );
      await expectFailure(
        callAs(
          db,
          'service_role',
          'service_role',
          `SELECT hocalist.media_gateway($1,'read',$2::jsonb) AS image`,
          [C, JSON.stringify({ id: IMAGE_A })],
        ),
        '42501',
        'media_access_denied',
      );
    });

    await t.test('a participant reads the referenced chat image', async () => {
      const image = (await gatewayReadAs(db, B, IMAGE_A))[0].image;
      assert.equal(image.id, IMAGE_A);
      assert.equal(image.state, 'ready');
    });

    await t.test('media reads require the same active role as the conversation', async () => {
      // The matching conversation role membership must be active.
      await db.exec(
        `UPDATE hocalist.memberships SET status='restricted' WHERE id='${MB}'`,
      );
      await expectFailure(gatewayReadAs(db, B, IMAGE_A), '42501', 'media_access_denied');
      await db.exec(
        `UPDATE hocalist.memberships SET status='active' WHERE id='${MB}'`,
      );

      // A restriction in the other role blocks reads even while this role is
      // active, matching chat_assert_participant.
      await db.exec(
        `INSERT INTO hocalist.memberships(id,user_id,role,status)
         VALUES ('${M_SELLER_BUYER}','${B}','buyer','restricted')`,
      );
      await expectFailure(gatewayReadAs(db, B, IMAGE_A), '42501', 'media_access_denied');
      await db.exec(
        `DELETE FROM hocalist.memberships WHERE id='${M_SELLER_BUYER}'`,
      );

      const image = (await gatewayReadAs(db, B, IMAGE_A))[0].image;
      assert.equal(image.id, IMAGE_A, 'access returns after the restriction lifts');
    });

    await t.test('shape constraints reject malformed attachment rows', async () => {
      await expectFailure(
        db.query(
          `INSERT INTO hocalist.conversation_messages(
             conversation_id, sender_user_id, sender_profile_id, kind, text, attachment_media_ids)
           VALUES ($1,$2,$3,'attachment','', '[]'::jsonb)`,
          [conversation, A, MA],
        ),
        '23514',
      );
      await expectFailure(
        db.query(
          `INSERT INTO hocalist.conversation_messages(
             conversation_id, sender_user_id, sender_profile_id, kind, text, attachment_media_ids)
           VALUES ($1,$2,$3,'text','hello', $4::jsonb)`,
          [conversation, A, MA, JSON.stringify([IMAGE_A])],
        ),
        '23514',
      );
    });

    await t.test('the attachment send RPC is client-executable and internal helpers are not', async () => {
      const grants = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.chat_send_attachment(uuid,text,text,jsonb)','EXECUTE') AS send_authenticated,
          has_function_privilege('anon','hocalist.chat_send_attachment(uuid,text,text,jsonb)','EXECUTE') AS send_anon,
          has_function_privilege('authenticated','hocalist.chat_validate_attachments()','EXECUTE') AS validate_authenticated,
          has_function_privilege('authenticated','hocalist.media_gateway(uuid,text,jsonb)','EXECUTE') AS gateway_authenticated
      `);
      assert.deepEqual(grants.rows[0], {
        send_authenticated: true,
        send_anon: false,
        validate_authenticated: false,
        gateway_authenticated: false,
      });
    });
  } finally {
    await db.close();
  }
});

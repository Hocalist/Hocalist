// Disposable PostgreSQL checks for the notification event producers.
//
// PGlite is single-connection: this is deterministic SQL proof for recipient
// derivation, deterministic dedupe keys, disabled-topic skipping, mute/revoke
// handling and producer privileges. It is NOT push delivery, real JWT or
// concurrency proof.
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

const callAs = (db, role, user, sql, params = []) =>
  asRole(db, role, user, async () => (await db.query(sql, params)).rows);

const command = (db, user, op, key, input) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS result',
    [op, key, JSON.stringify(input)],
  );

const setPreferences = (db, user, input) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.notification_preferences_update($1::jsonb) AS data',
    [JSON.stringify(input)],
  );

const send = (db, user, conversation, key, text) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.chat_send($1,$2,$3) AS result',
    [conversation, key, text],
  );

const mute = (db, user, conversation, muted) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.chat_set_muted($1,$2) AS result',
    [conversation, muted],
  );

const propose = (db, user, conversation, input, key) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.meeting_propose($1,$2,$3) AS data',
    [conversation, JSON.stringify(input), key],
  );

const respond = (db, user, meeting, accept, revision, key) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.meeting_respond($1,$2,$3,$4) AS data',
    [meeting, accept, revision, key],
  );

const reschedule = (db, user, meeting, input, revision, key) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.meeting_reschedule_propose($1,$2,$3,$4) AS data',
    [meeting, JSON.stringify(input), revision, key],
  );

const inbox = (db, user) =>
  db.query(
    `SELECT kind, title, body, source_id, event_key, payload
     FROM hocalist.notifications WHERE user_id = $1 ORDER BY created_at, id`,
    [user],
  );

const schedule = () => ({
  schedule_date: '2026-10-01',
  schedule_time: '18:30',
  schedule_timezone: 'America/New_York',
  place_choice: 'specific_place',
  place_label: 'Cross County Mall',
  place_address: '123 Synthetic Ave',
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

const requestInput = (title) => ({
  kind: 'product',
  title,
  description: 'Good condition',
  condition: 'used',
  quantity: 1,
  budget_minimum_minor: 35000,
  budget_maximum_minor: 48000,
  currency_code: 'USD',
  accepts_higher_offers: false,
  use_home_address: true,
  category_id: CATEGORY,
});

test('notification event producers in disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    await db.exec(await readFile(new URL('../../provider-rollout/apply.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../../chat/010_chat_foundation.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../../marketplace/020_marketplace_foundation.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../../meetings/040_meetings_foundation.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../030_notification_inbox.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../031_notification_producers.sql', import.meta.url), 'utf8'));
    await seed(db);

    let request;
    let offer;
    let conversationId;
    let meeting;
    let secondRequest;
    const SOURCE = '40000000-0000-4000-8000-000000000001';

    await t.test('a submitted offer notifies only the request buyer', async () => {
      request = (await command(db, A, 'request.create', 'req-1', requestInput('iPad Air')))
        [0].result;
      offer = (await command(db, B, 'offer.submit', 'offer-1', {
        request_id: request.id,
        price_minor: 42000,
        currency_code: 'USD',
        message: 'Can meet tomorrow.',
        image_media_ids: [],
        ...schedule(),
      }))[0].result;

      const buyerRows = (await inbox(db, A)).rows;
      assert.equal(buyerRows.length, 1);
      assert.equal(buyerRows[0].kind, 'new_offer');
      assert.equal(buyerRows[0].source_id, offer.id);
      assert.equal(
        buyerRows[0].event_key,
        (await db.query("SELECT md5($1)::uuid AS key", [`offer:new:${offer.id}`])).rows[0].key,
      );
      assert.ok(!buyerRows[0].body.includes('123 Synthetic Ave'));
      assert.deepEqual(buyerRows[0].payload, {
        offer_id: offer.id,
        request_id: request.id,
      });
      assert.equal((await inbox(db, B)).rows.length, 0, 'the seller is not notified');
      assert.equal((await inbox(db, C)).rows.length, 0, 'outsiders are not notified');
    });

    await t.test('a disabled offers topic skips the emission', async () => {
      await setPreferences(db, A, {
        offers: false,
        messages: true,
        deals: true,
        expected_revision: 0,
      });
      const second = (await command(db, A, 'request.create', 'req-2', requestInput('Pixel 9')))
        [0].result;
      secondRequest = second;
      await command(db, B, 'offer.submit', 'offer-2', {
        request_id: second.id,
        price_minor: 41000,
        currency_code: 'USD',
        message: 'Available today.',
        image_media_ids: [],
        ...schedule(),
      });
      assert.equal((await inbox(db, A)).rows.length, 1, 'no new offer row');
      await setPreferences(db, A, {
        offers: true,
        messages: true,
        deals: true,
        expected_revision: 1,
      });
    });

    await t.test('a message notifies the other member and respects mute', async () => {
      await command(db, A, 'offer.select', 'select-1', {
        offer_id: offer.id,
        revision_id: offer.revisions[0].id,
        expected_offer_revision: offer.revision,
      });
      conversationId = (await command(db, A, 'conversation.open_offer', 'open-1', {
        offer_id: offer.id,
      }))[0].result.conversation_id;

      await send(db, A, conversationId, 'msg-1', 'Hello there');
      const afterSend = (await inbox(db, B)).rows;
      assert.equal(afterSend.length, 1);
      assert.equal(afterSend[0].kind, 'new_message');
      assert.equal(
        afterSend[0].payload.conversation_id,
        conversationId,
        'the payload carries the conversation, never message text',
      );
      assert.ok(!afterSend[0].payload.toString().includes('Hello there'));
      assert.equal((await inbox(db, A)).rows.length, 1, 'the sender is not notified');

      await mute(db, B, conversationId, true);
      await send(db, A, conversationId, 'msg-2', 'Are you there?');
      assert.equal((await inbox(db, B)).rows.length, 1, 'muted conversations stay quiet');
      await mute(db, B, conversationId, false);
    });

    await t.test('meeting proposals and status changes notify the participants', async () => {
      const proposed = (await propose(db, A, conversationId, schedule(), 'meeting-1'))[0].data;
      const afterProposalB = (await inbox(db, B)).rows;
      assert.equal(afterProposalB.length, 2);
      assert.equal(afterProposalB[1].kind, 'meeting_update');
      assert.equal(afterProposalB[1].source_id, proposed.id);
      assert.equal((await inbox(db, A)).rows.length, 1, 'the proposer is not notified');

      const accepted = (await respond(db, B, proposed.id, true, 1, 'meeting-respond-1'))[0].data;
      meeting = accepted;
      const afterAcceptA = (await inbox(db, A)).rows;
      const afterAcceptB = (await inbox(db, B)).rows;
      assert.equal(afterAcceptA.length, 2);
      assert.equal(afterAcceptA[1].kind, 'meeting_update');
      assert.equal(afterAcceptA[1].title, 'Meeting confirmed');
      assert.equal(afterAcceptB.length, 3);

      await respond(db, B, accepted.id, true, 1, 'meeting-respond-1');
      assert.equal((await inbox(db, A)).rows.length, 2, 'a replayed accept adds nothing');
      assert.equal((await inbox(db, B)).rows.length, 3);
    });

    await t.test('a reschedule proposal notifies the counterpart', async () => {
      const existingA = (await inbox(db, A)).rows;
      const beforeA = existingA.length;
      const existingIds = new Set(existingA.map(row => row.event_key));
      const beforeB = (await inbox(db, B)).rows.length;
      await reschedule(
        db,
        B,
        meeting.id,
        schedule({ schedule_date: '2026-10-05' }),
        2,
        'meeting-reschedule-1',
      );
      const rows = (await inbox(db, A)).rows;
      assert.equal(rows.length, beforeA + 2, 'proposal row plus status row');
      // Both triggers run in one transaction and share now(); UUID tie-breaks
      // are not emission order. Assert the exact new events by identity.
      assert.deepEqual(rows.filter(row => !existingIds.has(row.event_key)).map(row => row.title).sort(),
        ['New meeting time proposed', 'Reschedule requested'].sort());
      assert.equal(
        (await inbox(db, B)).rows.length,
        beforeB + 1,
        'the proposer only receives the status row',
      );
    });

    await t.test('restricted and revoked recipients are skipped', async () => {
      await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE id=$1", [MA]);
      try {
        await command(db, C, 'offer.submit', 'offer-3', {
          request_id: secondRequest.id,
          price_minor: 80000,
          currency_code: 'USD',
          message: 'Available.',
          image_media_ids: [],
          ...schedule(),
        });
        const rows = (await inbox(db, A)).rows;
        assert.equal(
          rows.filter((row) => row.kind === 'new_offer').length,
          1,
          'no offer row while the buyer is restricted',
        );
      } finally {
        await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1", [MA]);
      }

      await db.query(
        'UPDATE hocalist.conversation_members SET revoked_at=now() WHERE conversation_id=$1 AND user_id=$2',
        [conversationId, B],
      );
      try {
        const before = (await inbox(db, B)).rows.length;
        await send(db, A, conversationId, 'msg-4', 'still there?');
        assert.equal((await inbox(db, B)).rows.length, before, 'revoked members stay quiet');
      } finally {
        await db.query(
          'UPDATE hocalist.conversation_members SET revoked_at=NULL WHERE conversation_id=$1 AND user_id=$2',
          [conversationId, B],
        );
      }

      const before = (await inbox(db, B)).rows.length;
      await send(db, A, conversationId, 'msg-5', 'hello again');
      const rows = (await inbox(db, B)).rows;
      assert.equal(rows.length, before + 1, 'a distinct later event still emits');
      assert.equal(rows[rows.length - 1].kind, 'new_message');
    });

    await t.test('mandatory safety content ignores disabled optional topics', async () => {
      await setPreferences(db, A, {
        offers: false,
        messages: false,
        deals: false,
        expected_revision: 2,
      });
      try {
        const emitted = await db.query(
          `SELECT hocalist.notification_emit($1,$2,'account_update',$3,'Security alert','Verify your account.','hocalist://account','{}'::jsonb) AS id`,
          [A, '60000000-0000-4000-8000-0000000000aa', SOURCE],
        );
        assert.ok(emitted.rows[0].id, 'safety content is always emitted');
      } finally {
        await setPreferences(db, A, {
          offers: true,
          messages: true,
          deals: true,
          expected_revision: 3,
        });
      }
    });

    await t.test('producer functions are not client-executable', async () => {
      for (
        const fn of [
          'notification_on_offer_insert()',
          'notification_on_message_insert()',
          'notification_on_meeting_proposal()',
          'notification_on_meeting_status()',
        ]
      ) {
        await assert.rejects(
          () => callAs(db, 'authenticated', A, `SELECT hocalist.${fn}`),
          (error) => error.code === '42501',
          `authenticated must not execute ${fn}`,
        );
      }
    });

    await t.test('notification content never carries addresses or payment data', async () => {
      const rows = await db.query(
        `SELECT title, body, payload::text AS payload
         FROM hocalist.notifications`,
      );
      for (const row of rows.rows) {
        const text = `${row.title} ${row.body} ${row.payload}`;
        assert.ok(!text.includes('123 Synthetic Ave'));
        assert.ok(!/\b(pin|card|iban)\b/i.test(text));
      }
    });
  } finally {
    await db.close();
  }
});

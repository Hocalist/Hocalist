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


export { A,B,C,MA,MB,MC,seed,acceptedDeal,schedule,propose,respond,callAs };
export async function setup(includeOutcomes=true){const db=await createDisposableDb();await applySignupSeed(db);await applyStripeInbox(db);await applyAccountDrafts(db);for(const path of ['../../provider-rollout/apply.sql','../../chat/010_chat_foundation.sql','../../marketplace/020_marketplace_foundation.sql','../../meetings/040_meetings_foundation.sql',...(includeOutcomes?['../080_sale_confirmation.sql']:[])])await db.exec(await readFile(new URL(path,import.meta.url),'utf8'));await seed(db);return db;}

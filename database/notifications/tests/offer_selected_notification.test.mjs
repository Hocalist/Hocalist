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


test('selected offers notify only the seller and use the important push queue', async t => {
 const db=await createDisposableDb();
 try {
  await applySignupSeed(db); await applyStripeInbox(db); await applyAccountDrafts(db);
  for (const path of ['../../provider-rollout/apply.sql','../../chat/010_chat_foundation.sql','../../marketplace/020_marketplace_foundation.sql','../030_notification_inbox.sql','../031_notification_producers.sql']) {
   // The notification producers also require meetings.
   if(path==='../030_notification_inbox.sql') await db.exec(await readFile(new URL('../../meetings/040_meetings_foundation.sql',import.meta.url),'utf8'));
   await db.exec(await readFile(new URL(path,import.meta.url),'utf8'));
  }
  for(const path of ['../032_push_queue_bridge.sql','../../runtime_repairs/223_important_push_events.sql','../../runtime_repairs/257_offer_selected_notification.sql'])
   await db.exec(await readFile(new URL(path,import.meta.url),'utf8'));
  await seed(db);
  await db.query("INSERT INTO hocalist.push_devices(id,user_id,installation_secret_hash,token,platform,enabled,updated_at) VALUES(gen_random_uuid(),$1,'synthetic-hash','synthetic-device-token-seller','android',true,now())",[B]);
  let n=0;
  async function makeOffer(){ n++; const req=(await command(db,A,'request.create','req-'+n,requestInput('Synthetic item '+n)))[0].result;
   return (await command(db,B,'offer.submit','offer-'+n,{request_id:req.id,price_minor:42000,currency_code:'USD',message:'Test',image_media_ids:[],...schedule()}))[0].result; }
  const selected=await makeOffer();
  const input={offer_id:selected.id,revision_id:selected.revisions[0].id,expected_offer_revision:selected.revision};
  await command(db,A,'offer.select','select',input);
  await command(db,A,'offer.select','select',input);
  const rows=await db.query("SELECT * FROM hocalist.notifications WHERE payload->>'event'='offer_selected'");
  assert.equal(rows.rows.length,1);const row=rows.rows[0];
  assert.equal(row.user_id,B);assert.equal(row.title,'Your offer was selected');
  assert.equal(row.deep_link,'hocalist://offers/'+selected.id);
  assert.equal(row.payload.request_id,selected.request_id);
  assert.equal((await db.query('SELECT count(*)::int n FROM hocalist.push_deliveries WHERE notification_id=$1',[row.id])).rows[0].n,1);
  await db.query("UPDATE hocalist.offers SET status='selected' WHERE id=$1",[selected.id]);
  assert.equal((await db.query("SELECT count(*)::int n FROM hocalist.notifications WHERE payload->>'event'='offer_selected'")).rows[0].n,1);
  const disabled=await makeOffer();
  await setPreferences(db,B,{offers:false,messages:true,deals:true,expected_revision:0});
  await command(db,A,'offer.select','disabled',{offer_id:disabled.id,revision_id:disabled.revisions[0].id,expected_offer_revision:disabled.revision});
  assert.equal((await db.query("SELECT count(*)::int n FROM hocalist.notifications WHERE payload->>'event'='offer_selected'")).rows[0].n,1);
  assert.equal((await db.query("SELECT has_function_privilege('authenticated','hocalist.notification_on_offer_selected()','EXECUTE') allowed")).rows[0].allowed,false);
 } finally { await db.close(); }
});


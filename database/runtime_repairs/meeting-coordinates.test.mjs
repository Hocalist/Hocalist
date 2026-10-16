import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { applyAccountDrafts, applySignupSeed, applyStripeInbox, createDisposableDb } from '../tests/fixture.mjs';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');
test('confirmed pins survive offer and meeting revisions without public access', async () => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db); await applyStripeInbox(db); await applyAccountDrafts(db);
    for (const path of ['../provider-rollout/apply.sql','../chat/010_chat_foundation.sql',
      '../marketplace/020_marketplace_foundation.sql','../marketplace/021_request_coordinates.sql',
      '../meetings/040_meetings_foundation.sql','../marketplace/023_multi_negotiation.sql']) await db.exec(await read(path));
    await db.exec(await read('./meeting-coordinates-preflight.sql'));
    await db.exec(await read('./192_confirmed_meeting_coordinates.sql'));
    await db.exec(await read('./meeting-coordinates-verify.sql'));
    const buyer = '00000000-0000-4000-8000-00000000000a';
    const seller = '00000000-0000-4000-8000-00000000000b';
    await db.exec(`INSERT INTO auth.users(id,raw_user_meta_data) VALUES ('${buyer}','{}'),('${seller}','{}');
      INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('10000000-0000-4000-8000-00000000000a','${buyer}','buyer','active'),
      ('10000000-0000-4000-8000-00000000000b','${seller}','seller','active');
      INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
      ('10000000-0000-4000-8000-00000000000a','Buyer'),('10000000-0000-4000-8000-00000000000b','Seller');`);
    const as = async (user, sql, params) => {
      await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[user]);
      await db.exec('SET ROLE authenticated');
      try {return (await db.query(sql,params)).rows[0].data;} finally {await db.exec('RESET ROLE');}
    };
    const command = (user, op, key, input) => as(user,
      'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS data',[op,key,JSON.stringify(input)]);
    const request = await command(buyer,'request.create','pin-request',{
      kind:'product',title:'Synthetic moved pin test',description:'Test',condition:'used',quantity:1,
      budget_minimum_minor:1000,budget_maximum_minor:2000,currency_code:'USD',use_home_address:true});
    const schedule = {schedule_date:'2026-10-05',schedule_time:'15:00',schedule_timezone:'America/Chicago',
      place_choice:'specific_place',place_label:'Synthetic public place',place_address:'Synthetic address',
      place_id:'original-provider-place',place_latitude:41.8765,place_longitude:-87.629};
    const offer = await command(seller,'offer.submit','pin-offer',{
      request_id:request.id,price_minor:1500,currency_code:'USD',message:'Test',image_media_ids:[],...schedule});
    assert.equal(offer.revisions[0].place_latitude, schedule.place_latitude);
    assert.equal(offer.revisions[0].place_longitude, schedule.place_longitude);
    await command(buyer,'offer.select','pin-select',{offer_id:offer.id,revision_id:offer.revisions[0].id,expected_offer_revision:offer.revision});
    const opened = await command(buyer,'conversation.open_offer','pin-open',{offer_id:offer.id});
    const meeting = await as(buyer,'SELECT hocalist.meeting_propose($1,$2::jsonb,$3) AS data',
      [opened.conversation_id,JSON.stringify(schedule),'pin-propose']);
    assert.equal(meeting.pending_schedule.place_latitude,schedule.place_latitude);
    assert.equal(meeting.pending_schedule.place_longitude,schedule.place_longitude);
    const accepted = await as(seller,'SELECT hocalist.meeting_respond($1,$2,$3,$4) AS data',
      [meeting.id,true,meeting.revision,'pin-accept']);
    assert.equal(accepted.accepted_schedule.place_longitude,schedule.place_longitude);
    const rescheduled = await as(buyer,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS data',
      [meeting.id,JSON.stringify({...schedule,place_latitude:41.877}),accepted.revision,'pin-reschedule']);
    assert.equal(rescheduled.pending_schedule.place_latitude,41.877);
    assert.equal(rescheduled.accepted_schedule.place_latitude,schedule.place_latitude);
    const replay = await as(buyer,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS data',
      [meeting.id,JSON.stringify({...schedule,place_latitude:41.877}),accepted.revision,'pin-reschedule']);
    assert.deepEqual(replay,rescheduled);
    await assert.rejects(as(buyer,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS data',
      [meeting.id,JSON.stringify({...schedule,place_latitude:41.878}),accepted.revision,'pin-reschedule']),/idempotency_conflict/);
    await assert.rejects(as('00000000-0000-4000-8000-00000000000c',
      'SELECT hocalist.meeting_detail($1) AS data',[meeting.id]),/meeting_access_denied/);
    for (const invalid of [{place_latitude:91},{place_longitude:null},{place_latitude:'41.8'}]) {
      await assert.rejects(db.query('SELECT hocalist.meeting_normalize_schedule($1::jsonb)',
        [JSON.stringify({...schedule,...invalid})]),/invalid_place_coordinates/);
    }
    assert.equal((await db.query("SELECT has_table_privilege('authenticated','hocalist.meeting_schedule_revisions','SELECT') AS allowed")).rows[0].allowed,false);
    await assert.rejects(db.exec(await read('./192_confirmed_meeting_coordinates.sql')),/definition drift/);
    await db.exec('ROLLBACK');
    await db.exec('GRANT EXECUTE ON FUNCTION hocalist.meeting_normalize_schedule(jsonb) TO authenticated');
    await assert.rejects(db.exec(await read('./meeting-coordinates-verify.sql')),/privilege drift/);
    await db.exec('ROLLBACK');
  } finally {await db.close();}
});

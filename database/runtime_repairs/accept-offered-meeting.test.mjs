import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb, IDS, callAs} from '../commercial_completion/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
async function setup() {
  const db=await createCommercialDb();
  await db.exec(`ALTER TABLE hocalist.offer_revisions ADD COLUMN place_latitude double precision, ADD COLUMN place_longitude double precision;
    ALTER TABLE hocalist.meeting_schedule_revisions ADD COLUMN place_latitude double precision, ADD COLUMN place_longitude double precision;`);
  const coordinates=await read('./192_confirmed_meeting_coordinates.sql');
  for(const fn of ['marketplace_normalize_offer','meeting_normalize_schedule','meeting_revision_json','meeting_reschedule_propose']) {
    const start=coordinates.indexOf('CREATE OR REPLACE FUNCTION hocalist.'+fn+'(');
    await db.exec(coordinates.slice(start,coordinates.indexOf('$$;',start)+3));
  }
  await db.exec(await read('../notifications/030_notification_inbox.sql'));
  await db.exec(await read('../notifications/031_notification_producers.sql'));
  await db.exec(await read('./meeting_reschedule_single_notification.sql'));
  // Install the existing seller-counterproposal behavior before applying the delta.
  let installed=(await db.query("SELECT pg_get_functiondef('hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)'::regprocedure) AS d")).rows[0].d;
  installed=installed.replace("IF v_row.status NOT IN ('accepted','reschedule_proposed') THEN",
    "-- seller_counterproposal\nIF v_user=v_row.seller_user_id AND EXISTS(SELECT 1 FROM hocalist.meeting_schedule_revisions WHERE meeting_id=p_meeting AND status='proposed' AND proposed_by_user_id=v_row.buyer_user_id) THEN UPDATE hocalist.meeting_schedule_revisions SET status='superseded',resolved_at=now() WHERE meeting_id=p_meeting AND status='proposed'; ELSIF v_row.status NOT IN ('accepted','reschedule_proposed') THEN")
    .replace("SET status = 'reschedule_proposed',", "SET status = CASE WHEN v_row.accepted_revision_id IS NULL THEN 'proposed' ELSE 'reschedule_proposed' END,");
  await db.exec(installed);
  await db.exec(await read('../../supabase/migrations/20261121120000_accept_offered_meeting.sql'));
  await db.exec(await read('../../supabase/migrations/20261121140000_confirmed_meeting_notification.sql'));
  return db;
}
async function deal(db) {
  const request=crypto.randomUUID(),offer=crypto.randomUUID(),conversation=crypto.randomUUID();
  await db.query(`INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
    VALUES($1,$2,$3,'product','Test offered meeting','used','active')`,[request,IDS.buyer,IDS.buyerMembership]);
  await db.query(`INSERT INTO hocalist.conversations(id,origin,request_id) VALUES($1,'targeted_request',$2)`,[conversation,request]);
  await db.query(`INSERT INTO hocalist.conversation_members(conversation_id,user_id,profile_id,role)
    VALUES($1,$2,$3,'buyer'),($1,$4,$5,'seller')`,[conversation,IDS.buyer,IDS.buyerMembership,IDS.seller,IDS.sellerMembership]);
  await db.query(`INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status,conversation_id)
    VALUES($1,$2,$3,$4,$5,'selected',$6)`,[offer,request,IDS.buyer,IDS.seller,IDS.sellerMembership,conversation]);
  const revision=(await db.query(`INSERT INTO hocalist.offer_revisions(offer_id,sequence,price_minor,currency_code,
    schedule_date,schedule_time,schedule_timezone,schedule_offset_minutes,schedule_instant,place_choice,place_label,place_address,place_latitude,place_longitude,status,proposed_by_user_id)
    VALUES($1,1,65000,'USD',current_date+7,'15:00','America/Chicago',-360,(current_date+7+time '15:00') AT TIME ZONE 'America/Chicago',
      'specific_place','Test library','123 Test Road',41.88,-87.63,'accepted',$2) RETURNING id`,[offer,IDS.seller])).rows[0].id;
  await db.query('UPDATE hocalist.offers SET accepted_revision_id=$1 WHERE id=$2',[revision,offer]);
  return {request,offer,conversation,revision};
}
const accept=(db,d,{user=IDS.buyer,key='accept',offerRevision=1,meetingRevision=null}={})=>callAs(db,'authenticated',user,
  'SELECT hocalist.meeting_accept_offer($1,$2,$3,$4) AS result',[d.offer,offerRevision,meetingRevision,key]);

test('buyer accepts exact seller terms once; seller sees accepted meeting and one alert',async()=>{
 const db=await setup();try {
  const d=await deal(db); const first=(await accept(db,d))[0].result;
  assert.equal(first.status,'accepted');
  assert.deepEqual(await accept(db,d),[{result:first}]);
  const m=(await db.query('SELECT * FROM hocalist.meetings WHERE offer_id=$1',[d.offer])).rows;
  assert.equal(m.length,1);
  const r=(await db.query('SELECT * FROM hocalist.meeting_schedule_revisions WHERE meeting_id=$1',[m[0].id])).rows;
  assert.equal(r.length,1);assert.equal(r[0].status,'accepted');assert.equal(r[0].proposed_by_user_id,IDS.seller);
  assert.equal(r[0].schedule_time,'15:00:00');assert.equal(r[0].schedule_timezone,'America/Chicago');
  assert.equal(r[0].place_address,'123 Test Road');assert.equal(r[0].place_latitude,41.88);
  assert.equal((await db.query('SELECT purchase_offer_id FROM hocalist.requests WHERE id=$1',[d.request])).rows[0].purchase_offer_id,d.offer);
  assert.equal((await db.query('SELECT count(*) AS n FROM hocalist.sale_confirmations')).rows[0].n,0);
  const seller=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.meeting_detail($1) AS result',[m[0].id]))[0].result;
  assert.equal(seller.status,'accepted');
  const alerts=(await db.query("SELECT * FROM hocalist.notifications WHERE user_id=$1 AND payload->>'meeting_id'=$2",[IDS.seller,m[0].id])).rows;
  assert.equal(alerts.length,1);
  const buyerAlerts=(await db.query("SELECT title FROM hocalist.notifications WHERE user_id=$1 AND payload->>'meeting_id'=$2",[IDS.buyer,m[0].id])).rows;
  assert.equal(buyerAlerts.length,1); assert.equal(buyerAlerts[0].title,'Meeting confirmed');
  await assert.rejects(accept(db,d,{key:'accept',offerRevision:2}),/idempotency_conflict/);
 }finally{await db.close();}
});

test('unauthorized, stale, closed and past offers cannot create a meeting or select a seller',async()=>{
 const db=await setup();try {
  const d=await deal(db);
  await assert.rejects(accept(db,d,{user:IDS.seller}),/role|access/);
  await assert.rejects(accept(db,d,{user:IDS.outsider}),/role|access/);
  await assert.rejects(accept(db,d,{offerRevision:9}),/revision_conflict/);
  await db.query("UPDATE hocalist.requests SET status='cancelled' WHERE id=$1",[d.request]);
  await assert.rejects(accept(db,d),/offer_not_selected/);
  await db.query("UPDATE hocalist.requests SET status='active' WHERE id=$1",[d.request]);
  await db.query('UPDATE hocalist.offer_revisions SET schedule_date=current_date-1 WHERE id=$1',[d.revision]);
  await assert.rejects(accept(db,d),/meeting_time_passed|schedule/);
  assert.equal((await db.query('SELECT purchase_offer_id FROM hocalist.requests WHERE id=$1',[d.request])).rows[0].purchase_offer_id,null);
  assert.equal((await db.query('SELECT count(*) AS n FROM hocalist.meetings')).rows[0].n,0);
  await assert.rejects(callAs(db,'anon',null,'SELECT hocalist.meeting_accept_offer($1,1,NULL,$2)',[d.offer,'anon']),/permission denied/);
 }finally{await db.close();}
});

test('reschedule requires the other participant and stale confirmations cannot replace it',async()=>{
 const db=await setup();try {
  const d=await deal(db);let m=(await accept(db,d))[0].result;
  const date=(await db.query('SELECT (current_date+8)::text AS date')).rows[0].date;
  const input=JSON.stringify({schedule_date:date,schedule_time:'17:00',schedule_timezone:'America/Chicago',place_choice:'specific_place',place_label:'Other library',place_address:'456 Test Road',place_latitude:41.9,place_longitude:-87.7});
  m=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS result',[m.id,input,m.revision,'seller-change']))[0].result;
  await assert.rejects(accept(db,d,{key:'stale',meetingRevision:m.revision-1}),/revision_conflict/);
  m=(await accept(db,d,{key:'accept-change',meetingRevision:m.revision}))[0].result;
  assert.equal(m.status,'accepted');
  m=(await callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS result',[m.id,input,m.revision,'buyer-change']))[0].result;
  await assert.rejects(accept(db,d,{key:'self',meetingRevision:m.revision}),/meeting_self_accept/);
  const seller=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.meeting_respond($1,true,$2,$3) AS result',[m.id,m.revision,'seller-accept']))[0].result;
  assert.equal(seller.status,'accepted');
 }finally{await db.close();}
});

test('buyer counters seller pending time without confirming it; seller then accepts',async()=>{
 const db=await setup();try {
  const d=await deal(db); let m=(await accept(db,d))[0].result;
  const date=(await db.query('SELECT (current_date+9)::text AS date')).rows[0].date;
  const input=JSON.stringify({schedule_date:date,schedule_time:'14:00',schedule_timezone:'America/Chicago',place_choice:'specific_place',place_label:'Library',place_address:'123 Test Road',place_latitude:41.88,place_longitude:-87.63});
  m=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS result',[m.id,input,m.revision,'seller-proposal']))[0].result;
  const oldAccepted=(await db.query('SELECT accepted_revision_id FROM hocalist.meetings WHERE id=$1',[m.id])).rows[0].accepted_revision_id; assert.ok(oldAccepted);
  m=(await callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS result',[m.id,input,m.revision,'buyer-counter']))[0].result;
  assert.equal(m.status,'reschedule_proposed');assert.equal((await db.query('SELECT accepted_revision_id FROM hocalist.meetings WHERE id=$1',[m.id])).rows[0].accepted_revision_id,oldAccepted);
  await assert.rejects(callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4)',[m.id,input,m.revision,'own-counter']),/meeting_reschedule_pending/);
  m=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.meeting_respond($1,true,$2,$3) AS result',[m.id,m.revision,'seller-accept-counter']))[0].result;
  assert.equal(m.status,'accepted');
 }finally{await db.close();}
});

test('a failing acceptance guard rolls back seller choice and meeting, and cancelled meetings stay closed',async()=>{
 const db=await setup();try {
  const d=await deal(db);
  await db.exec("CREATE FUNCTION hocalist.test_acceptance_guard() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.status='accepted' THEN RAISE EXCEPTION 'meeting_seller_account_pending'; END IF; RETURN NEW; END;$$; CREATE TRIGGER test_acceptance_guard BEFORE INSERT OR UPDATE ON hocalist.meeting_schedule_revisions FOR EACH ROW EXECUTE FUNCTION hocalist.test_acceptance_guard();");
  await assert.rejects(accept(db,d),/meeting_seller_account_pending/);
  assert.equal((await db.query('SELECT purchase_offer_id FROM hocalist.requests WHERE id=$1',[d.request])).rows[0].purchase_offer_id,null);
  assert.equal((await db.query('SELECT count(*) AS n FROM hocalist.meetings')).rows[0].n,0);
  await db.exec('DROP TRIGGER test_acceptance_guard ON hocalist.meeting_schedule_revisions');
  let m=(await accept(db,d))[0].result;
  m=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.meeting_cancel($1,$2,$3) AS result',[m.id,m.revision,'cancel']))[0].result;
  await assert.rejects(accept(db,d,{key:'reopen',meetingRevision:m.revision}),/meeting_cancelled/);
 }finally{await db.close();}
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,C,acceptedDeal,schedule,propose,respond,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');

test('declined meeting revisions notify their proposer, preserving agreed details',async()=>{
 const db=await setup();
 try {
  for(const p of ['../notifications/030_notification_inbox.sql','../notifications/031_notification_producers.sql','./258_meeting_decline_notification.sql']) await db.exec(await read(p));
  const deal=await acceptedDeal(db);
  let m=(await propose(db,A,deal.conversationId,schedule(),'decline-initial'))[0].data;
  const declines=async()=>(await db.query("SELECT * FROM hocalist.notifications WHERE payload->>'event'='meeting_proposal_declined' ORDER BY created_at,id")).rows;
  const before=(await db.query('SELECT count(*) AS n FROM hocalist.notifications')).rows[0].n;
  let declined=(await respond(db,B,m.id,false,m.revision,'decline-response'))[0].data;
  assert.equal((await declines()).length,1);
  assert.equal((await declines())[0].user_id,A);
  assert.equal((await declines())[0].title,'Meeting proposal declined');
  await respond(db,B,m.id,false,m.revision,'decline-response');
  assert.equal((await declines()).length,1,'receipt replay must not duplicate');
  assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.notifications')).rows[0].n),Number(before)+1);
  m=(await propose(db,A,deal.conversationId,schedule(),'new-proposal'))[0].data;
  m=(await respond(db,B,m.id,true,m.revision,'accept-new'))[0].data;
  const accepted=m.accepted_schedule;
  for(const [proposer,responder,key] of [[A,B,'buyer'],[B,A,'seller']]) {
   m=(await callAs(db,'authenticated',proposer,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS d',[m.id,JSON.stringify(schedule({schedule_time:'19:30'})),m.revision,key+'-change']))[0].d;
   const count=Number((await db.query('SELECT count(*) AS n FROM hocalist.notifications')).rows[0].n);
   declined=(await respond(db,responder,m.id,false,m.revision,key+'-decline'))[0].data;
   assert.equal(declined.status,'accepted');
   assert.deepEqual(declined.accepted_schedule,accepted);
   const event=(await declines()).find(n=>n.payload.revision_id===declined.revisions.at(-1).id);
   assert.ok(event);
   assert.equal(event.user_id,proposer);
   assert.equal(event.title,'Proposed meeting change declined');
   assert.match(event.body,/original meeting is still confirmed/);
   assert.equal(event.deep_link,'hocalist://meetings/'+m.id);
   assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.notifications')).rows[0].n),count+1,'no false confirmation');
   m=declined;
  }
  await callAs(db,'authenticated',A,'SELECT hocalist.notification_preferences_update($1::jsonb)',[JSON.stringify({offers:true,messages:true,deals:false,safety:true})]);
  m=(await callAs(db,'authenticated',A,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS d',[m.id,JSON.stringify(schedule({schedule_time:'20:30'})),m.revision,'muted-change']))[0].d;
  await respond(db,B,m.id,false,m.revision,'muted-decline');
  assert.equal((await declines()).length,3,'disabled Deals preference suppresses alert');
  assert.equal((await callAs(db,'authenticated',C,'SELECT * FROM hocalist.notifications')).length,0);
  await assert.rejects(callAs(db,'authenticated',A,'SELECT hocalist.notification_on_meeting_status()'),/permission denied/);
  await db.exec(await read('./258_meeting_decline_notification.sql'));
 } finally {await db.close();}
});

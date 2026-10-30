import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,C,acceptedDeal,schedule,propose,respond,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('authenticated meeting notification context preserves inbox and push boundaries', async t=>{
 const db=await setup();
 try {
  await db.exec(await read('../notifications/030_notification_inbox.sql'));
  await db.exec(await read('./215_notification_meeting_context.sql'));
  const deal=await acceptedDeal(db);
  const pending=(await propose(db,A,deal.conversationId,schedule(),'context-proposal'))[0].data;
  const meeting=(await respond(db,B,pending.id,true,pending.revision,'context-accept'))[0].data;
  await db.query(`UPDATE hocalist.role_profiles SET display_name='Controlled Seller' WHERE membership_id IN (SELECT id FROM hocalist.memberships WHERE user_id=$1)`,[B]);
  const emit=async(user,key,title,link,payload={})=>(await db.query(`SELECT hocalist.notification_emit($1,$2,'meeting_update',$3,$4,'Generic stored body',$5,$6::jsonb) AS id`,[user,key,meeting.id,title,link,JSON.stringify(payload)])).rows[0].id;
  const id=await emit(A,'bbbbbbbb-0000-4000-8000-000000000001','Meeting confirmed','hocalist://meetings/'+meeting.id);
  const inbox=async(user)=>(await callAs(db,'authenticated',user,'SELECT hocalist.notification_inbox(10,null) AS d'))[0].d;
  await t.test('identifies the request, counterpart and event-time schedule without private location',async()=>{
   const row=(await inbox(A)).items.find(x=>x.id===id);
   assert.match(row.title,/Meeting confirmed — iPad Air/);
   assert.match(row.body,/Controlled Seller/);
   assert.match(row.body,/Oct 01, 2026/);
   assert.match(row.body,/America\/New_York/);
   assert.ok(row.body.length<250);
   assert.ok(!row.body.includes('123 Synthetic')&&!row.body.includes('PIN'));
   assert.match(row.activity_summary,/06:30 PM/);
   const stored=(await db.query('SELECT title,body FROM hocalist.notifications WHERE id=$1',[id])).rows[0];
   assert.deepEqual(stored,{title:'Meeting confirmed',body:'Generic stored body'});
  });
  await t.test('a declined later proposal never replaces the accepted schedule in a confirmation',async()=>{
   const revision=(await callAs(db,'authenticated',A,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS d',[meeting.id,JSON.stringify(schedule({schedule_time:'19:30'})),meeting.revision,'context-later']))[0].d;
   await respond(db,B,meeting.id,false,revision.revision,'context-decline');
   const row=(await inbox(A)).items.find(x=>x.id===id);
   assert.match(row.body,/06:30 PM/);
   assert.ok(!row.body.includes('07:30'));
  });
  await t.test('an outsider inbox cannot see or enrich another participant notification',async()=>{
   assert.equal((await inbox(C)).items.length,0);
   await assert.rejects(callAs(db,'authenticated',C,`SELECT hocalist.notification_with_context(n,'{}') FROM hocalist.notifications n`),/permission denied/);
  });
  await t.test('non-meeting deep links remain unchanged',async()=>{
   const other=await emit(A,'bbbbbbbb-0000-4000-8000-000000000002','Incoming Hocalist call','hocalist://chat/'+deal.conversationId);
   const row=(await inbox(A)).items.find(x=>x.id===other);
   assert.equal(row.title,'Incoming Hocalist call');
   assert.equal(row.body,'Generic stored body');
  });
  await t.test('inbox unread counts, routing and read markers remain authoritative',async()=>{
   const page=await inbox(A);assert.equal(page.unread_count,2);
   assert.equal(page.items.find(x=>x.id===id).deep_link,'hocalist://meetings/'+meeting.id);
   await callAs(db,'authenticated',A,'SELECT hocalist.notification_mark_read($1)',[id]);
   assert.equal((await inbox(A)).unread_count,1);
  });
 } finally {await db.close();}
});

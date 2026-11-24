import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,acceptedDeal,schedule,propose,respond,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');

test('one counterpart notification per reschedule, including retries and decline',async()=>{
 const db=await setup();
 try {
  for(const p of ['../notifications/030_notification_inbox.sql','../notifications/031_notification_producers.sql','./258_meeting_decline_notification.sql','./meeting_reschedule_single_notification.sql']) await db.exec(await read(p));
  const deal=await acceptedDeal(db);
  let m=(await propose(db,A,deal.conversationId,schedule(),'initial'))[0].data;
  m=(await respond(db,B,m.id,true,m.revision,'accept'))[0].data;
  for(const [sender,recipient,key] of [[A,B,'buyer'],[B,A,'seller']]) {
   const before=(await db.query('SELECT id FROM hocalist.notifications')).rows.map(n=>n.id);
   const revision=m.revision;
   const change=()=>callAs(db,'authenticated',sender,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS d',[m.id,JSON.stringify(schedule({schedule_time:'19:30'})),revision,key]);
   m=(await change())[0].d;
   await change();
   const added=(await db.query('SELECT * FROM hocalist.notifications')).rows.filter(n=>!before.includes(n.id));
   assert.equal(added.length,1);
   assert.equal(added[0].user_id,recipient);
   assert.equal(added[0].title,'New meeting time proposed');
   assert.equal(added[0].payload.meeting_id,m.id);
   assert.ok(added[0].payload.revision_id);
   m=(await respond(db,recipient,m.id,false,m.revision,key+'-decline'))[0].data;
   const declines=(await db.query("SELECT * FROM hocalist.notifications WHERE payload->>'event'='meeting_proposal_declined'")).rows;
   assert.ok(declines.some(n=>n.user_id===sender));
  }
  await db.exec(await read('./meeting_reschedule_single_notification.sql'));
  await assert.rejects(callAs(db,'authenticated',A,'SELECT hocalist.notification_on_meeting_status()'),/permission denied/);
 } finally {await db.close();}
});

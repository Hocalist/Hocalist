import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,C,acceptedDeal,propose,respond,schedule,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('meeting and purchase changes emit private chat refresh signals',async t=>{
 const db=await setup();
 try {
  for(const p of ['../communication_completion/150_chat_block.sql','../communication_completion/154_chat_realtime_signals.sql']) await db.exec(await read(p));
  const deal=await acceptedDeal(db);
  await db.exec(await read('./208_meeting_progress_signals.sql'));
  const count=async()=>Number((await db.query('SELECT count(*) AS n FROM hocalist.chat_change_signals WHERE conversation_id=$1',[deal.conversationId])).rows[0].n);
  const proposed=(await propose(db,A,deal.conversationId,schedule(),'progress-propose'))[0].data;
  const afterPropose=await count();
  await t.test('proposal, acceptance and reschedule emit signals; receipt replay does not',async()=>{
   assert.ok(afterPropose>0);
   await respond(db,B,proposed.id,true,proposed.revision,'progress-accept');
   const afterAccept=await count();assert.ok(afterAccept>afterPropose);
   await respond(db,B,proposed.id,true,proposed.revision,'progress-accept');
   assert.equal(await count(),afterAccept);
   const current=(await db.query('SELECT revision FROM hocalist.meetings WHERE id=$1',[proposed.id])).rows[0];
   const next=(await callAs(db,'authenticated',B,'SELECT hocalist.meeting_reschedule_propose($1,$2::jsonb,$3,$4) AS d',[
    proposed.id,JSON.stringify(schedule({schedule_date:'2026-10-02'})),current.revision,'progress-reschedule']))[0].d;
   assert.ok(await count()>afterAccept);
   await respond(db,A,proposed.id,true,next.revision,'progress-accept-change');
  });
  await t.test('PIN confirmation signals completion without exposing PIN data',async()=>{
   await db.query("UPDATE hocalist.meetings SET meeting_expires_at=now()+interval '1 day' WHERE id=$1",[proposed.id]);
   const before=await count();
   const pin=(await callAs(db,'authenticated',A,"SELECT hocalist.sale_pin($1,'display') AS d",[proposed.id]))[0].d.pin;
   assert.match(pin,/^\d{5}$/);
   await callAs(db,'authenticated',B,"SELECT hocalist.sale_pin($1,'verify',$2) AS d",[proposed.id,pin]);
   assert.ok(await count()>before);
   const columns=(await db.query("SELECT column_name FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='chat_change_signals' ORDER BY ordinal_position")).rows.map(x=>x.column_name);
   assert.deepEqual(columns,['id','conversation_id','created_at']);
  });
  await t.test('existing participant RLS remains; outsiders see no signal',async()=>{
   assert.ok((await callAs(db,'authenticated',A,'SELECT * FROM hocalist.chat_change_signals')).length>0);
   assert.equal((await callAs(db,'authenticated',C,'SELECT * FROM hocalist.chat_change_signals')).length,0);
   await assert.rejects(callAs(db,'authenticated',A,'SELECT hocalist.chat_signal_on_meeting_progress()'),/permission denied/);
  });
  await t.test('double apply is safe and disabled trigger drift is rejected',async()=>{
   await db.exec(await read('./208_meeting_progress_signals.sql'));
   await db.exec(await read('./meeting-progress-verify.sql'));
   await db.exec('ALTER TABLE hocalist.meetings DISABLE TRIGGER chat_signal_meeting_progress');
   await assert.rejects(db.exec(await read('./208_meeting_progress_signals.sql')),/trigger drift/);
  });
 } finally {await db.close();}
});

import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {setup,A,B,C,acceptedDeal,propose,respond,schedule,callAs} from '../../outcomes/tests/fixture.mjs';
test('Hocalist call signaling is participant-only and idempotent',async()=>{
 const db=await setup();try{
  const deal=await acceptedDeal(db);const pending=(await propose(db,A,deal.conversationId,schedule(),'p'))[0].data;
  await respond(db,B,pending.id,true,pending.revision,'a');
  await db.exec(await readFile(new URL('../110_call_signaling.sql',import.meta.url),'utf8'));
  const cmd=async(user,action,input)=>(await callAs(db,'authenticated',user,'SELECT hocalist.call_command($1,$2) AS v',[action,JSON.stringify(input)]))[0].v;
  const input={conversation_id:deal.conversationId,key:'90000000-0000-4000-8000-000000000001'};
  const setting=async(user,enabled=null,revision=null)=>(await callAs(db,'authenticated',user,'SELECT hocalist.call_admin_settings($1,$2) AS v',[enabled,revision]))[0].v;
  await assert.rejects(cmd(A,'invite',input),/calls_disabled/);
  assert.equal((await cmd(B,'incoming',{})).enabled,false);
  await assert.rejects(setting(A,true,1),/admin/);
  await db.query('INSERT INTO hocalist.platform_admins(user_id) VALUES($1)',[A]);
  assert.deepEqual(await setting(A),{enabled:false,revision:1});
  assert.deepEqual(await setting(A,true,1),{enabled:true,revision:2});
  await assert.rejects(setting(A,false,1),/revision_conflict/);
  await assert.rejects(cmd(C,'invite',input),/conversation_access_denied/);
  const first=await cmd(A,'invite',input);assert.equal(first.call.state,'ringing');assert.equal((await cmd(A,'invite',input)).call.id,first.call.id);
  assert.equal((await cmd(B,'incoming',{})).call.id,first.call.id);
  assert.equal((await cmd(B,'invite',{...input,key:'90000000-0000-4000-8000-000000000002'})).status,'busy');
  const call_id=first.call.id;
  await assert.rejects(cmd(A,'accept',{call_id}),/call_access_denied/);
  await assert.rejects(cmd(C,'poll',{call_id}),/call_access_denied/);
  assert.equal((await cmd(B,'accept',{call_id})).call.state,'accepted');
  const signal={call_id,key:'90000000-0000-4000-8000-000000000003',kind:'offer',payload:{sdp:'synthetic'}};
  await cmd(A,'signal',signal);await cmd(A,'signal',signal);
  await assert.rejects(cmd(A,'signal',{...signal,payload:{sdp:'changed'}}),/idempotency_conflict/);
  assert.equal((await cmd(A,'poll',{call_id})).signals.length,0);
  assert.equal((await cmd(B,'poll',{call_id})).signals.length,1);
  await cmd(A,'end',{call_id});assert.equal((await cmd(B,'poll',{call_id})).call.state,'ended');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.call_signals')).rows[0].n,0);
  await assert.rejects(cmd(A,'signal',{...signal,key:'90000000-0000-4000-8000-000000000004'}),/call_not_accepted/);
  const second=await cmd(A,'invite',{...input,key:'90000000-0000-4000-8000-000000000005'});
  await cmd(B,'accept',{call_id:second.call.id});
  await cmd(A,'signal',{...signal,call_id:second.call.id});
  assert.deepEqual(await setting(A,false,2),{enabled:false,revision:3});
  assert.equal((await cmd(B,'poll',{call_id:second.call.id})).call.state,'ended');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.call_signals')).rows[0].n,0);
  await assert.rejects(cmd(A,'invite',input),/calls_disabled/);
  await assert.rejects(cmd(B,'accept',{call_id:second.call.id}),/calls_disabled/);
  await assert.rejects(cmd(A,'signal',{...signal,call_id:second.call.id}),/calls_disabled/);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.call_settings_audit')).rows[0].n,2);
  await assert.rejects(callAs(db,'authenticated',B,'SELECT * FROM hocalist.call_settings'),/permission denied/);
  await setting(A,true,3);
  assert.equal((await cmd(B,'poll',{call_id:second.call.id})).call.state,'ended');
 }finally{await db.close();}
});


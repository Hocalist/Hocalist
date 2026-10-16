import {test} from 'node:test';
import assert from 'node:assert/strict';
import {setup,A,B,C,MB,acceptedDeal,schedule,propose,respond,callAs} from './fixture.mjs';
test('private request PIN and one completed sale',async t=>{
 const db=await setup();
 try{
 const deal=await acceptedDeal(db);
 const pending=(await propose(db,A,deal.conversationId,schedule(),'p'))[0].data;
 const m=(await respond(db,B,pending.id,true,pending.revision,'a'))[0].data;
 await db.query("UPDATE hocalist.meetings SET meeting_expires_at=now()+interval '1 day' WHERE id=$1",[m.id]);
 const pin=async(user,action,value=null)=>(await callAs(db,'authenticated',user,'SELECT hocalist.sale_pin($1,$2,$3) AS v',[m.id,action,value]))[0].v;
 let code;
 await t.test('outsider and seller cannot read buyer PIN',async()=>{
  await assert.rejects(pin(C,'display'),/meeting_access_denied/);
  await assert.rejects(pin(B,'display'),/sale_access_denied/);
  await assert.rejects(pin(A,'verify','12345'),/sale_access_denied/);
 });
 await t.test('repeated buyer display returns same five digits; no plaintext column',async()=>{
  const p=await pin(A,'display');code=p.pin;assert.match(code,/^\d{5}$/);
  assert.equal((await pin(A,'display')).pin,code);
  const cols=(await db.query("SELECT column_name FROM information_schema.columns WHERE table_schema='hocalist' AND table_name='request_pin_secrets'")).rows;
  assert.ok(!cols.some(x=>x.column_name==='pin'));
  await assert.rejects(callAs(db,'authenticated',A,'SELECT * FROM hocalist.request_pin_secrets'),/permission denied/);
 });
 await t.test('five committed failures lock even a correct attempt',async()=>{
  const wrong=code==='00000'?'11111':'00000';
  for(let i=0;i<4;i++)assert.equal((await pin(B,'verify',wrong)).status,'incorrect');
  assert.equal((await pin(B,'verify',wrong)).status,'locked');
  assert.equal((await pin(B,'verify',code)).status,'locked');
  assert.equal((await db.query('SELECT attempts FROM hocalist.request_pin_secrets')).rows[0].attempts,5);
  await db.exec("UPDATE hocalist.request_pin_secrets SET locked_until=now()-interval '1 second'");
 });
 await t.test('restriction and accepted-day expiry deny confirmation',async()=>{
  await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE id=$1",[MB]);
  await assert.rejects(pin(B,'verify',code),/account_restricted/);
  await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1",[MB]);
  await db.query('UPDATE hocalist.meetings SET meeting_expires_at=now() WHERE id=$1',[m.id]);
  assert.equal((await pin(B,'verify',code)).status,'expired');
  await db.query("UPDATE hocalist.meetings SET meeting_expires_at=now()+interval '1 day' WHERE id=$1",[m.id]);
 });
 await t.test('overall attempt limit survives lock expiry',async()=>{
  await db.exec('UPDATE hocalist.request_pin_secrets SET attempts=30,locked_until=NULL');
  assert.equal((await pin(B,'verify',code)).status,'support_required');
  await db.exec('UPDATE hocalist.request_pin_secrets SET attempts=5');
 });
 await t.test('successful retry returns same outcome and never settles money',async()=>{
  const one=await pin(B,'verify',code);assert.equal(one.status,'confirmed');
  assert.deepEqual(await pin(B,'verify',code),one);
  assert.deepEqual(await pin(A,'display'),one);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.sale_confirmations')).rows[0].n,1);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.request_pin_secrets')).rows[0].n,0);
  assert.equal((await db.query('SELECT status FROM hocalist.requests WHERE id=$1',[deal.requestId])).rows[0].status,'closed');
  const history=(await callAs(db,'authenticated',A,'SELECT hocalist.sale_history() AS v'))[0].v.items;
  assert.equal(history.length,1);assert.equal(history[0].meeting_id,m.id);assert.equal(history[0].price_minor,42000);
  assert.equal('pin' in history[0],false);assert.equal('place_address' in history[0],false);
  assert.equal((await callAs(db,'authenticated',A,'SELECT hocalist.sale_history($1,$2) AS v',[history[0].confirmed_at,history[0].id]))[0].v.items.length,0);
  await assert.rejects(callAs(db,'authenticated',B,'SELECT hocalist.sale_history()'),/sale_access_denied/);
 });
 await t.test('completed sale cannot be reopened or rescheduled',async()=>{
  await assert.rejects(db.query("UPDATE hocalist.requests SET status='active' WHERE id=$1",[deal.requestId]),/sale_already_confirmed/);
  await assert.rejects(db.query("UPDATE hocalist.meetings SET status='cancelled' WHERE id=$1",[m.id]),/sale_already_confirmed/);
 });
 }finally{await db.close();}
});

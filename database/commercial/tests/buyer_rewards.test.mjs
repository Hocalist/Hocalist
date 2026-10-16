import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {setup,A,B,C,acceptedDeal,propose,respond,schedule,callAs} from '../../outcomes/tests/fixture.mjs';
test('buyer rewards require a confirmed sale and collected fees, stay separate and replay once',async()=>{
 const db=await setup();try{
  for(const file of ['090_credit_batches.sql','091_buyer_rewards.sql'])await db.exec(await readFile(new URL('../'+file,import.meta.url),'utf8'));
  const deal=await acceptedDeal(db);const p=(await propose(db,A,deal.conversationId,schedule(),'p'))[0].data;
  await respond(db,B,p.id,true,p.revision,'a');
  await db.query("UPDATE hocalist.meetings SET meeting_expires_at=now()+interval '1 day' WHERE id=$1",[p.id]);
  const pin=(await callAs(db,'authenticated',A,"SELECT hocalist.sale_pin($1,'display') AS v",[p.id]))[0].v.pin;
  const outcome=(await callAs(db,'authenticated',B,"SELECT hocalist.sale_pin($1,'verify',$2) AS v",[p.id,pin]))[0].v.outcome_id;
  await db.query("SELECT hocalist.credit_deposit_internal($1,'synthetic',4000,145,325,'test')",[B]);
  const target=(await db.query("SELECT hocalist.credit_reserve_internal($1,$2,'2026-09-21',100) AS id",[B,deal.requestId])).rows[0].id;
  const accrue=async(amount=15)=>(await db.query("SELECT hocalist.reward_accrue_internal($1,$2,$3,'synthetic-policy') AS id",[outcome,target,amount])).rows[0].id;
  await assert.rejects(accrue(),/collected_sale_fee_required/);
  await db.query("SELECT hocalist.credit_settle_internal($1,'win')",[target]);
  const id=await accrue();assert.equal(await accrue(),id);await assert.rejects(accrue(30),/idempotency_conflict/);
  const wallet=async(user)=>(await callAs(db,'authenticated',user,'SELECT hocalist.reward_wallet() AS v'))[0].v;
  assert.equal((await wallet(A)).earned_minor,15);assert.equal((await wallet(A)).withdrawals_enabled,false);
  await assert.rejects(wallet(C),/wallet_access_denied/);
  await assert.rejects(wallet(B),/wallet_access_denied/);
  await assert.rejects(callAs(db,'authenticated',A,'SELECT * FROM hocalist.buyer_rewards'),/permission denied/);
  await assert.rejects(callAs(db,'service_role',null,"SELECT hocalist.reward_accrue_internal($1,$2,15,'test')",[outcome,target]),/permission denied/);
  await db.query("SELECT hocalist.credit_settle_internal($1,'refund')",[target]);
  assert.equal((await wallet(A)).earned_minor,0);assert.equal((await wallet(A)).items[0].status,'held');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.buyer_rewards')).rows[0].n,1);
 }finally{await db.close();}
});

import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {setup,A,B,C,acceptedDeal,callAs} from '../../outcomes/tests/fixture.mjs';
test('HocaCredit immutable deposit rates and single batch accounting',async t=>{
 const db=await setup();try{
 await db.exec(await readFile(new URL('../090_credit_batches.sql',import.meta.url),'utf8'));
 const deal=await acceptedDeal(db);
 const dep=async(ref,amount,initial,win)=>(await db.query('SELECT hocalist.credit_deposit_internal($1,$2,$3,$4,$5,$6) AS id',[B,ref,amount,initial,win,ref])).rows[0].id;
 const reserve=async(request=deal.requestId)=>(await db.query("SELECT hocalist.credit_reserve_internal($1,$2,'2026-09-21',100) AS id",[B,request])).rows[0].id;
 const settle=async(id,action)=>(await db.query('SELECT hocalist.credit_settle_internal($1,$2) AS v',[id,action])).rows[0].v;
 let first,second,target;
 await t.test('$40 then $20 preserves two fee snapshots and replay',async()=>{
  first=await dep('payment40',4000,145,325);second=await dep('payment20',2000,155,375);
  assert.equal(await dep('payment40',4000,145,325),first);
  await assert.rejects(dep('payment40',4000,155,375),/idempotency_conflict/);
  await db.query("UPDATE hocalist.credit_batches SET created_at=now()-interval '1 day' WHERE id=$1",[first]);
  assert.equal(Number((await db.query('SELECT sum(balance_minor) AS n FROM hocalist.credit_batches')).rows[0].n),6000);
 });
 await t.test('initial then win charges 325 total, not 470',async()=>{
  target=await reserve();assert.equal(await reserve(),target);
  assert.equal((await settle(target,'initial')).charged_minor,145);
  let b=(await db.query('SELECT * FROM hocalist.credit_batches WHERE id=$1',[first])).rows[0];
  assert.equal(Number(b.balance_minor),3855);assert.equal(Number(b.reserved_minor),180);
  assert.equal((await settle(target,'win')).charged_minor,325);
  assert.equal((await settle(target,'win')).charged_minor,325);
  b=(await db.query('SELECT * FROM hocalist.credit_batches WHERE id=$1',[first])).rows[0];
  assert.equal(Number(b.balance_minor),3675);assert.equal(Number(b.reserved_minor),0);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.credit_targets')).rows[0].n,1);
 });
 await t.test('refund appends compensation and never changes rate snapshot',async()=>{
  await settle(target,'refund');await settle(target,'refund');
  const b=(await db.query('SELECT * FROM hocalist.credit_batches WHERE id=$1',[first])).rows[0];
  assert.equal(Number(b.balance_minor),4000);assert.equal(Number(b.initial_fee_minor),145);
  assert.equal((await db.query("SELECT count(*)::int AS n FROM hocalist.credit_entries WHERE kind='refund'")).rows[0].n,1);
 });
 await t.test('client and service roles cannot credit or debit',async()=>{
  for(const role of ['authenticated','service_role','anon'])await assert.rejects(callAs(db,role,B,"SELECT hocalist.credit_settle_internal($1,'win')",[target]),/permission denied/);
  await assert.rejects(callAs(db,'authenticated',B,'SELECT * FROM hocalist.credit_batches'),/permission denied/);
  await assert.rejects(callAs(db,'authenticated',A,'SELECT hocalist.credit_wallet()'),/wallet_access_denied/);
  const own=(await callAs(db,'authenticated',B,'SELECT hocalist.credit_wallet() AS v'))[0].v;
  const other=(await callAs(db,'authenticated',C,'SELECT hocalist.credit_wallet() AS v'))[0].v;
  assert.equal(own.balance_minor,6000);assert.equal(other.balance_minor,0);assert.equal(other.batches.length,0);
 });
 await t.test('old insufficient remainder is retained and never combined; quotas count targets once',async()=>{
  const clone=async()=>(await db.query("INSERT INTO hocalist.requests SELECT (jsonb_populate_record(NULL::hocalist.requests,to_jsonb(r)||jsonb_build_object('id',gen_random_uuid()))).* FROM hocalist.requests r WHERE id=$1 RETURNING id",[deal.requestId])).rows[0].id;
  const request2=await clone();
  await assert.rejects(db.query("SELECT hocalist.credit_reserve_internal($1,$2,'2026-09-21',1)",[B,request2]),/weekly_target_limit/);
  const deposit=async(ref)=>(await db.query("SELECT hocalist.credit_deposit_internal($1,$2,200,100,150,'synthetic') AS id",[C,ref])).rows[0].id;
  const reserveC=async(request)=>(await db.query("SELECT hocalist.credit_reserve_internal($1,$2,'2026-09-21',100) AS id",[C,request])).rows[0].id;
  const old=await deposit('small-old');await db.query("UPDATE hocalist.credit_batches SET created_at=now()-interval '1 day' WHERE id=$1",[old]);
  const firstTarget=await reserveC(deal.requestId);await settle(firstTarget,'initial');await settle(firstTarget,'release');
  const newest=await deposit('small-new');const secondTarget=await reserveC(request2);
  assert.equal((await db.query('SELECT batch_id FROM hocalist.credit_targets WHERE id=$1',[secondTarget])).rows[0].batch_id,newest);
  assert.equal(Number((await db.query('SELECT balance_minor FROM hocalist.credit_batches WHERE id=$1',[old])).rows[0].balance_minor),100);
  await assert.rejects(reserveC(await clone()),/insufficient_single_batch/);
 });
 }finally{await db.close();}
});

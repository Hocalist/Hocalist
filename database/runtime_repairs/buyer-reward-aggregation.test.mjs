// Isolated contract proof; live deployment and real concurrency are separate.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,IDS,callAs} from '../commercial_completion/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('request estimates accumulate but cannot be withdrawn; collected contributors remain independent',async()=>{
 const db=await createCommercialDb();
 try {
  for(const path of ['../chat/012_credit_qualification.sql', './207_offer_submission_fee.sql', './228_target_fee_policy.sql', './231_deal_chat_threads.sql', './235_paygo_payment_setup.sql', './236_paygo_collection.sql', './249_multi_seller_buyer_rewards.sql']) await db.exec(await read(path));
  const request=crypto.randomUUID(), offers=[crypto.randomUUID(),crypto.randomUUID()];
  await db.exec("INSERT INTO hocalist.reward_policy(singleton,normal_minor,late_minor,late_window_hours,rule_version) VALUES(true,15,30,12,'synthetic-approved')");
  await db.query("INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status,first_accepted_at,acceptance_expires_at) VALUES($1,$2,$3,'product','Synthetic reward contract','used','active',now()-interval '6 days',now()+interval '1 day')",[request,IDS.buyer,IDS.buyerMembership]);
  const targets=[];
  for(const [index,seller,membership] of [[0,IDS.seller,IDS.sellerMembership],[1,IDS.seller2,IDS.seller2Membership]]) {
   await db.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES($1,$2,$3,$4,$5,'submitted')",[offers[index],request,IDS.buyer,seller,membership]);
   const batch=(await db.query("SELECT hocalist.credit_deposit_internal($1,$2,6000,200,500,'synthetic-standard') AS id",[seller,`synthetic-${index}`])).rows[0].id;
   await db.query('UPDATE hocalist.credit_batches SET balance_minor=5800,reserved_minor=300 WHERE id=$1',[batch]);
   const target=(await db.query("INSERT INTO hocalist.credit_targets(user_id,request_id,offer_id,batch_id,initial_minor,winning_minor,charged_minor,reserved_minor,status,week_start,rate_version,qualified_at) VALUES($1,$2,$3,$4,200,500,200,300,'initial_charged',current_date,'synthetic-standard',now()) RETURNING id",[seller,request,offers[index],batch])).rows[0].id;
   targets.push(target);
  }
  const estimate=async()=>Number((await db.query('SELECT hocalist.reward_pending_estimate_minor($1) AS n',[IDS.buyer])).rows[0].n);
  const collected=async(id)=>(await db.query('SELECT hocalist.reward_target_collected($1) AS ok',[id])).rows[0].ok;
  assert.equal(await estimate(),30);
  const wallet=async()=>(await callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.commercial_reward_wallet() AS d'))[0].d;
  assert.equal((await wallet()).estimated_minor,30);
  assert.equal((await wallet()).available_minor,0);
  assert.equal((await db.query('SELECT hocalist.withdrawal_available_minor($1) AS n',[IDS.buyer])).rows[0].n,0);
  assert.equal(await collected(targets[0]),false);
  await db.query('UPDATE hocalist.credit_targets SET qualified_at=NULL WHERE id=$1',[targets[1]]);
  assert.equal(await estimate(),15);
  await db.query('UPDATE hocalist.credit_targets SET qualified_at=now() WHERE id=$1',[targets[1]]);
  await db.query("UPDATE hocalist.requests SET status='expired',acceptance_expires_at=now()-interval '1 hour' WHERE id=$1",[request]);
  assert.equal(await estimate(),0);
  const conversation=crypto.randomUUID(),meeting=crypto.randomUUID();
  const revision=crypto.randomUUID();
  await db.query("INSERT INTO hocalist.offer_revisions(id,offer_id,sequence,price_minor,currency_code,message,schedule_date,schedule_time,schedule_timezone,schedule_offset_minutes,schedule_instant,place_choice,place_label,status,proposed_by_user_id) VALUES($1,$2,1,1500,'USD','','2026-11-05','18:30','America/Chicago',-360,'2026-11-06T00:30:00Z','specific_place','Synthetic place','accepted',$3)",[revision,offers[0],IDS.seller]);
  await db.query('UPDATE hocalist.offers SET accepted_revision_id=$1 WHERE id=$2',[revision,offers[0]]);
  await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)",[conversation,request,offers[0]]);
  await db.query("INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status) VALUES($1,$2,$3,$4,$5,$6,'accepted')",[meeting,conversation,request,offers[0],IDS.buyer,IDS.seller]);
  await db.query("INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id) VALUES($1,$2,$3,$4,$5,$6)",[request,meeting,offers[0],crypto.randomUUID(),IDS.buyer,IDS.seller]);
  await db.query('SELECT hocalist.credit_settle_purchase($1)',[request]);
  await db.query('SELECT hocalist.credit_settle_purchase($1)',[request]);
  const fees=(await db.query('SELECT status,charged_minor,reserved_minor FROM hocalist.credit_targets WHERE id=ANY($1::uuid[]) ORDER BY user_id',[targets])).rows;
  assert.deepEqual(fees.map(t=>[t.status,Number(t.charged_minor),Number(t.reserved_minor)]),[['won',500,0],['released',200,0]]);
  assert.equal(await estimate(),0);
  assert.equal(await collected(targets[0]),true);
  assert.equal(await collected(targets[1]),true);
  await db.query('SELECT hocalist.reward_accrue_request_internal($1)',[request]);
  await db.query('SELECT hocalist.reward_accrue_request_internal($1)',[request]);
  assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.buyer_rewards')).rows[0].n),2);
  assert.equal(Number((await db.query('SELECT hocalist.withdrawal_available_minor($1) AS n',[IDS.buyer])).rows[0].n),30);
  const summary=async()=>(await db.query('SELECT hocalist.reward_sale_summary_internal(id) AS d FROM hocalist.sale_confirmations WHERE request_id=$1',[request])).rows[0].d;
  assert.equal((await summary()).contribution_count,2);
  assert.equal((await summary()).earned_minor,30);
  assert.equal((await wallet()).estimated_minor,0);
  const buyerHistory=(await callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.commercial_sale_history() AS d'))[0].d.items;
  assert.equal(buyerHistory.length,1);
  assert.equal(buyerHistory[0].reward.amount_minor,30);
  assert.equal(buyerHistory[0].reward.contribution_count,2);
  assert.equal(buyerHistory[0].fee,null);
  const sellerHistory=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.commercial_sale_history() AS d'))[0].d.items;
  assert.equal(sellerHistory.length,1);
  assert.equal(sellerHistory[0].fee.charged_minor,500);
  assert.equal(sellerHistory[0].reward,null);
  const detail=async(user)=>(await callAs(db,'authenticated',user,'SELECT hocalist.commercial_sale_detail($1) AS d',[buyerHistory[0].id]))[0].d;
  assert.equal((await detail(IDS.buyer)).reward.amount_minor,30);
  assert.equal((await detail(IDS.buyer)).fee.charged_minor,500);
  assert.equal((await detail(IDS.seller)).reward.amount_minor,15);
  assert.equal((await detail(IDS.seller)).fee.charged_minor,500);
  await assert.rejects(detail(IDS.outsider),/sale_access_denied/);
  await assert.rejects(detail(IDS.seller2),/sale_access_denied/);
  const beforeRepeat=(await db.query('SELECT to_jsonb(r) AS d FROM hocalist.buyer_rewards r ORDER BY id')).rows;
  await db.exec(await read('./249_multi_seller_buyer_rewards.sql'));
  assert.deepEqual((await db.query('SELECT to_jsonb(r) AS d FROM hocalist.buyer_rewards r ORDER BY id')).rows,beforeRepeat);
  assert.equal((await wallet()).available_minor,30);
  await db.query('UPDATE hocalist.credit_targets SET qualified_at=NULL,reply_qualification_enabled=false WHERE id=$1',[targets[1]]);
  assert.equal(await collected(targets[1]),false,'legacy non-winning fees alone do not prove a qualifying interaction');
  await db.query("UPDATE hocalist.credit_targets SET qualified_at=(SELECT confirmed_at FROM hocalist.sale_confirmations WHERE request_id=$2)-interval '1 second',reply_qualification_enabled=true WHERE id=$1",[targets[1],request]);
  assert.equal(await collected(targets[1]),true);
  await db.query('UPDATE hocalist.credit_targets SET charged_minor=0 WHERE id=$1',[targets[1]]);
  assert.equal(await collected(targets[1]),false);
  await db.query("UPDATE hocalist.credit_targets SET charged_minor=200,status='refunded' WHERE id=$1",[targets[1]]);
  assert.equal(await collected(targets[1]),false);
  assert.equal(await collected(targets[0]),true);
  assert.equal(Number((await db.query('SELECT hocalist.withdrawal_available_minor($1) AS n',[IDS.buyer])).rows[0].n),15);
  assert.equal((await summary()).status,'mixed');
  assert.equal((await summary()).earned_minor,15);
  assert.equal((await summary()).held_minor,15);
  await assert.rejects(callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.reward_target_collected($1)',[targets[0]]),{code:'42501'});
 } finally {await db.close();}
});

test('delayed non-winning payment earns its late contribution only after verified collection',async()=>{
 const db=await createCommercialDb();
 try {
  for(const path of ['../chat/012_credit_qualification.sql', './207_offer_submission_fee.sql', './228_target_fee_policy.sql', './231_deal_chat_threads.sql', './235_paygo_payment_setup.sql', './236_paygo_collection.sql', './249_multi_seller_buyer_rewards.sql']) await db.exec(await read(path));
  const request=crypto.randomUUID(), offers=[crypto.randomUUID(),crypto.randomUUID()];
  await db.exec("INSERT INTO hocalist.reward_policy(singleton,normal_minor,late_minor,late_window_hours,rule_version) VALUES(true,15,30,12,'synthetic-approved')");
  await db.query("INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status,first_accepted_at,acceptance_expires_at) VALUES($1,$2,$3,'product','Synthetic reward contract','used','active',now()-interval '6 days',now()+interval '1 day')",[request,IDS.buyer,IDS.buyerMembership]);
  const targets=[];
  for(const [index,seller,membership] of [[0,IDS.seller,IDS.sellerMembership],[1,IDS.seller2,IDS.seller2Membership]]) {
   await db.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES($1,$2,$3,$4,$5,'submitted')",[offers[index],request,IDS.buyer,seller,membership]);
   const batch=(await db.query("SELECT hocalist.credit_deposit_internal($1,$2,6000,200,500,'synthetic-standard') AS id",[seller,`synthetic-${index}`])).rows[0].id;
   await db.query('UPDATE hocalist.credit_batches SET balance_minor=5800,reserved_minor=300 WHERE id=$1',[batch]);
   const target=(await db.query("INSERT INTO hocalist.credit_targets(user_id,request_id,offer_id,batch_id,initial_minor,winning_minor,charged_minor,reserved_minor,status,week_start,rate_version,qualified_at) VALUES($1,$2,$3,$4,200,500,200,300,'initial_charged',current_date,'synthetic-standard',now()) RETURNING id",[seller,request,offers[index],batch])).rows[0].id;
   targets.push(target);
  }
  const estimate=async()=>Number((await db.query('SELECT hocalist.reward_pending_estimate_minor($1) AS n',[IDS.buyer])).rows[0].n);
  const collected=async(id)=>(await db.query('SELECT hocalist.reward_target_collected($1) AS ok',[id])).rows[0].ok;
  assert.equal(await estimate(),30);
  const wallet=async()=>(await callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.commercial_reward_wallet() AS d'))[0].d;
  assert.equal((await wallet()).estimated_minor,30);
  assert.equal((await wallet()).available_minor,0);
  assert.equal((await db.query('SELECT hocalist.withdrawal_available_minor($1) AS n',[IDS.buyer])).rows[0].n,0);
  assert.equal(await collected(targets[0]),false);
  await db.query('UPDATE hocalist.credit_targets SET qualified_at=NULL WHERE id=$1',[targets[1]]);
  assert.equal(await estimate(),15);
  await db.query('UPDATE hocalist.credit_targets SET qualified_at=now() WHERE id=$1',[targets[1]]);
  await db.query("UPDATE hocalist.requests SET status='expired',acceptance_expires_at=now()-interval '1 hour' WHERE id=$1",[request]);
  assert.equal(await estimate(),0);
  await db.query("UPDATE hocalist.credit_batches SET balance_minor=6000,reserved_minor=0 WHERE id=(SELECT batch_id FROM hocalist.credit_targets WHERE id=$1)",[targets[1]]);
  await db.query("UPDATE hocalist.credit_targets SET funding_kind='paygo',batch_id=NULL,charged_minor=0,reserved_minor=0,status='reserved',rate_version='late-fee-v1',winning_minor=initial_minor WHERE id=$1",[targets[1]]);
  const charge=(await db.query("INSERT INTO hocalist.paygo_charges(target_id,phase,fee_minor,amount_minor,allocation_decided,customer_id,payment_method_id,payment_intent_id,state) VALUES($1,'initial',200,200,true,'cus_Delayed','pm_Delayed','pi_Delayed','pending') RETURNING id",[targets[1]])).rows[0].id;
  const conversation=crypto.randomUUID(),meeting=crypto.randomUUID();
  await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)",[conversation,request,offers[0]]);
  await db.query("INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status) VALUES($1,$2,$3,$4,$5,$6,'accepted')",[meeting,conversation,request,offers[0],IDS.buyer,IDS.seller]);
  await db.query("INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id) VALUES($1,$2,$3,$4,$5,$6)",[request,meeting,offers[0],crypto.randomUUID(),IDS.buyer,IDS.seller]);
  await db.query('SELECT hocalist.credit_settle_purchase($1)',[request]);
  await db.query('SELECT hocalist.credit_settle_purchase($1)',[request]);

  const available=async()=>Number((await db.query('SELECT hocalist.withdrawal_available_minor($1) AS n',[IDS.buyer])).rows[0].n);
  const finish=async(state,amount=200)=>callAs(db,'service_role',null,
    "SELECT hocalist.paygo_charge_finish($1,'pi_Delayed','cus_Delayed',$2,$3)",[charge,amount,state]);
  assert.equal(await available(),15);
  assert.equal(await estimate(),30,'confirmed purchase keeps uncollected contribution estimated');
  await finish('requires_action');
  assert.equal(await available(),15);
  assert.equal(await estimate(),30);
  await assert.rejects(finish('succeeded',201),/payment_identity_mismatch/);
  assert.equal(await available(),15);
  await finish('succeeded');
  assert.equal(await available(),45);
  assert.equal(await estimate(),0);
  await finish('succeeded');
  assert.equal(await available(),45);
  const fee=(await db.query('SELECT status,charged_minor,reserved_minor FROM hocalist.credit_targets WHERE id=$1',[targets[1]])).rows[0];
  assert.equal(fee.status,'released');
  assert.equal(Number(fee.charged_minor),200);
  assert.equal(Number(fee.reserved_minor),0);
  assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.paygo_charges WHERE target_id=$1',[targets[1]])).rows[0].n),1);
  assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.buyer_rewards')).rows[0].n),2);
 } finally {await db.close();}
});

test('historical contributions require separate review and repeat application preserves the cutover',async()=>{
 const db=await createCommercialDb();
 try {
  for(const path of ['../chat/012_credit_qualification.sql', './207_offer_submission_fee.sql', './228_target_fee_policy.sql', './231_deal_chat_threads.sql', './235_paygo_payment_setup.sql', './236_paygo_collection.sql', './249_multi_seller_buyer_rewards.sql']) await db.exec(await read(path));
  const request=crypto.randomUUID(), offers=[crypto.randomUUID(),crypto.randomUUID()];
  await db.exec("INSERT INTO hocalist.reward_policy(singleton,normal_minor,late_minor,late_window_hours,rule_version) VALUES(true,15,30,12,'synthetic-approved')");
  await db.query("INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status,first_accepted_at,acceptance_expires_at) VALUES($1,$2,$3,'product','Synthetic reward contract','used','active',now()-interval '6 days',now()+interval '1 day')",[request,IDS.buyer,IDS.buyerMembership]);
  const targets=[];
  for(const [index,seller,membership] of [[0,IDS.seller,IDS.sellerMembership],[1,IDS.seller2,IDS.seller2Membership]]) {
   await db.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES($1,$2,$3,$4,$5,'submitted')",[offers[index],request,IDS.buyer,seller,membership]);
   const batch=(await db.query("SELECT hocalist.credit_deposit_internal($1,$2,6000,200,500,'synthetic-standard') AS id",[seller,`synthetic-${index}`])).rows[0].id;
   await db.query('UPDATE hocalist.credit_batches SET balance_minor=5800,reserved_minor=300 WHERE id=$1',[batch]);
   const target=(await db.query("INSERT INTO hocalist.credit_targets(user_id,request_id,offer_id,batch_id,initial_minor,winning_minor,charged_minor,reserved_minor,status,week_start,rate_version,qualified_at) VALUES($1,$2,$3,$4,200,500,200,300,'initial_charged',current_date,'synthetic-standard',now()) RETURNING id",[seller,request,offers[index],batch])).rows[0].id;
   targets.push(target);
  }
  const estimate=async()=>Number((await db.query('SELECT hocalist.reward_pending_estimate_minor($1) AS n',[IDS.buyer])).rows[0].n);
  const collected=async(id)=>(await db.query('SELECT hocalist.reward_target_collected($1) AS ok',[id])).rows[0].ok;
  assert.equal(await estimate(),30);
  const wallet=async()=>(await callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.commercial_reward_wallet() AS d'))[0].d;
  assert.equal((await wallet()).estimated_minor,30);
  assert.equal((await wallet()).available_minor,0);
  assert.equal((await db.query('SELECT hocalist.withdrawal_available_minor($1) AS n',[IDS.buyer])).rows[0].n,0);
  assert.equal(await collected(targets[0]),false);
  await db.query('UPDATE hocalist.credit_targets SET qualified_at=NULL WHERE id=$1',[targets[1]]);
  assert.equal(await estimate(),15);
  await db.query('UPDATE hocalist.credit_targets SET qualified_at=now() WHERE id=$1',[targets[1]]);
  await db.query("UPDATE hocalist.requests SET status='expired',acceptance_expires_at=now()-interval '1 hour' WHERE id=$1",[request]);
  assert.equal(await estimate(),0);
  await db.query("UPDATE hocalist.credit_targets SET qualified_at=now()-interval '2 days' WHERE request_id=$1",[request]);
  const conversation=crypto.randomUUID(),meeting=crypto.randomUUID();
  const revision=crypto.randomUUID();
  await db.query("INSERT INTO hocalist.offer_revisions(id,offer_id,sequence,price_minor,currency_code,message,schedule_date,schedule_time,schedule_timezone,schedule_offset_minutes,schedule_instant,place_choice,place_label,status,proposed_by_user_id) VALUES($1,$2,1,1500,'USD','','2026-11-05','18:30','America/Chicago',-360,'2026-11-06T00:30:00Z','specific_place','Synthetic place','accepted',$3)",[revision,offers[0],IDS.seller]);
  await db.query('UPDATE hocalist.offers SET accepted_revision_id=$1 WHERE id=$2',[revision,offers[0]]);
  await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)",[conversation,request,offers[0]]);
  await db.query("INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status) VALUES($1,$2,$3,$4,$5,$6,'accepted')",[meeting,conversation,request,offers[0],IDS.buyer,IDS.seller]);
  await db.query("INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id,confirmed_at) VALUES($1,$2,$3,$4,$5,$6,now()-interval '1 day')",[request,meeting,offers[0],crypto.randomUUID(),IDS.buyer,IDS.seller]);
  await db.query('SELECT hocalist.credit_settle_purchase($1)',[request]);
  await db.query('SELECT hocalist.credit_settle_purchase($1)',[request]);

  const rows=async()=>(await db.query('SELECT target_id,amount_minor FROM hocalist.buyer_rewards ORDER BY target_id')).rows;
  assert.equal((await rows()).length,1);
  assert.equal((await rows())[0].target_id,targets[0]);
  await db.query('SELECT hocalist.reward_accrue_target_internal($1)',[targets[1]]);
  assert.equal((await rows()).length,1);
  const outcome=(await db.query('SELECT id FROM hocalist.sale_confirmations WHERE request_id=$1',[request])).rows[0].id;
  await assert.rejects(db.query("SELECT hocalist.reward_accrue_internal($1,$2,15,'synthetic-approved')",[outcome,targets[1]]),/historical_reward_review_required/);
  const cutoff=(await db.query('SELECT effective_at FROM hocalist.reward_aggregation_policy')).rows[0].effective_at;
  await db.exec(await read('./249_multi_seller_buyer_rewards.sql'));
  assert.equal((await db.query('SELECT effective_at FROM hocalist.reward_aggregation_policy')).rows[0].effective_at.getTime(),cutoff.getTime());
  assert.equal((await rows()).length,1);
 } finally {await db.close();}
});

test('multiple contributions share one bounded reversal without duplicate deductions',async()=>{
 const db=await createCommercialDb();
 try {
  for(const path of ['../chat/012_credit_qualification.sql', './207_offer_submission_fee.sql', './228_target_fee_policy.sql', './231_deal_chat_threads.sql', './235_paygo_payment_setup.sql', './236_paygo_collection.sql', './249_multi_seller_buyer_rewards.sql']) await db.exec(await read(path));
  const request=crypto.randomUUID(), offers=[crypto.randomUUID(),crypto.randomUUID()];
  await db.exec("INSERT INTO hocalist.reward_policy(singleton,normal_minor,late_minor,late_window_hours,rule_version) VALUES(true,15,30,12,'synthetic-approved')");
  await db.query("INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status,first_accepted_at,acceptance_expires_at) VALUES($1,$2,$3,'product','Synthetic reward contract','used','active',now()-interval '6 days',now()+interval '1 day')",[request,IDS.buyer,IDS.buyerMembership]);
  const targets=[];
  for(const [index,seller,membership] of [[0,IDS.seller,IDS.sellerMembership],[1,IDS.seller2,IDS.seller2Membership]]) {
   await db.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES($1,$2,$3,$4,$5,'submitted')",[offers[index],request,IDS.buyer,seller,membership]);
   const batch=(await db.query("SELECT hocalist.credit_deposit_internal($1,$2,6000,200,500,'synthetic-standard') AS id",[seller,`synthetic-${index}`])).rows[0].id;
   const target=(await db.query("INSERT INTO hocalist.credit_targets(user_id,request_id,offer_id,batch_id,initial_minor,winning_minor,charged_minor,reserved_minor,status,week_start,rate_version,qualified_at) VALUES($1,$2,$3,$4,200,500,200,300,'initial_charged',current_date,'synthetic-standard',now()) RETURNING id",[seller,request,offers[index],batch])).rows[0].id;
   targets.push(target);
  }
  const estimate=async()=>Number((await db.query('SELECT hocalist.reward_pending_estimate_minor($1) AS n',[IDS.buyer])).rows[0].n);
  const collected=async(id)=>(await db.query('SELECT hocalist.reward_target_collected($1) AS ok',[id])).rows[0].ok;
  assert.equal(await estimate(),30);
  assert.equal((await db.query('SELECT hocalist.withdrawal_available_minor($1) AS n',[IDS.buyer])).rows[0].n,0);
  assert.equal(await collected(targets[0]),false);
  await db.query('UPDATE hocalist.credit_targets SET qualified_at=NULL WHERE id=$1',[targets[1]]);
  assert.equal(await estimate(),15);
  await db.query('UPDATE hocalist.credit_targets SET qualified_at=now() WHERE id=$1',[targets[1]]);
  await db.query("UPDATE hocalist.requests SET status='expired',acceptance_expires_at=now()-interval '1 hour' WHERE id=$1",[request]);
  assert.equal(await estimate(),0);
  const conversation=crypto.randomUUID(),meeting=crypto.randomUUID();
  await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)",[conversation,request,offers[0]]);
  await db.query("INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status) VALUES($1,$2,$3,$4,$5,$6,'accepted')",[meeting,conversation,request,offers[0],IDS.buyer,IDS.seller]);
  await db.query("INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id) VALUES($1,$2,$3,$4,$5,$6)",[request,meeting,offers[0],crypto.randomUUID(),IDS.buyer,IDS.seller]);
  await db.query("UPDATE hocalist.credit_targets SET status='won',charged_minor=500,reserved_minor=0 WHERE id=$1",[targets[0]]);
  await db.query("UPDATE hocalist.credit_targets SET status='released',reserved_minor=0 WHERE id=$1",[targets[1]]);
  assert.equal(await estimate(),0);
  assert.equal(await collected(targets[0]),true);
  assert.equal(await collected(targets[1]),true);
  await db.query('SELECT hocalist.reward_accrue_request_internal($1)',[request]);
  await db.query('SELECT hocalist.reward_accrue_request_internal($1)',[request]);
  assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.buyer_rewards')).rows[0].n),2);
  assert.equal(Number((await db.query('SELECT hocalist.withdrawal_available_minor($1) AS n',[IDS.buyer])).rows[0].n),30);

  await db.exec("UPDATE hocalist.reversal_policy SET clawback_mode='same_batch_only',reward_hold_enabled=true");
  const outcome=(await db.query('SELECT id FROM hocalist.sale_confirmations WHERE request_id=$1',[request])).rows[0].id;
  const open=async(reference,amount)=>(await callAs(db,'service_role',null,
    "SELECT hocalist.reversal_open_internal('synthetic',$1,'chargeback','buyer_reward',$2,NULL,$3,NULL,NULL) AS d",[reference,amount,outcome]))[0].d.reversal_id;
  const command=async(op,key,id)=>(await callAs(db,'authenticated',IDS.admin,
    'SELECT hocalist.reversal_admin_command($1,$2,$3::jsonb) AS d',[op,key,JSON.stringify({reversal_id:id})]))[0].d;
  const available=async()=>Number((await db.query('SELECT hocalist.withdrawal_available_minor($1) AS n',[IDS.buyer])).rows[0].n);
  const first=await open('first',30);
  const held=await command('reversal.hold','first-hold',first);
  assert.equal(Number(held.hold_minor),30);
  assert.equal(await available(),0);
  assert.equal(Number((await db.query("SELECT count(*) AS n FROM hocalist.ledger_corrections WHERE reversal_id=$1 AND entry_kind='reward_hold'",[first])).rows[0].n),2);
  assert.deepEqual(await command('reversal.hold','first-hold',first),held);
  const second=await open('second',30);
  assert.equal(Number((await command('reversal.hold','second-hold',second)).hold_minor),0);
  await command('reversal.dismiss','first-dismiss',first);
  assert.equal(await available(),30);
  const third=await open('third',20);
  assert.equal(Number((await command('reversal.hold','third-hold',third)).hold_minor),20);
  const settled=await command('reversal.compensate','third-compensate',third);
  assert.equal(Number(settled.compensated_minor),20);
  assert.equal(Number(settled.reversed_face_minor),20);
  assert.equal(await available(),10);
  assert.deepEqual(await command('reversal.compensate','third-compensate',third),settled);
  const fourth=await open('fourth',30);
  assert.equal(Number((await command('reversal.hold','fourth-hold',fourth)).hold_minor),10);
  const final=await command('reversal.compensate','fourth-compensate',fourth);
  assert.equal(Number(final.compensated_minor),10);
  assert.equal(Number(final.reversed_face_minor),10);
  assert.equal(await available(),0);
  assert.equal(Number((await db.query("SELECT sum(amount_minor) AS n FROM hocalist.ledger_corrections WHERE entry_kind='reward_reversed'")).rows[0].n),30);
 } finally {await db.close();}
});

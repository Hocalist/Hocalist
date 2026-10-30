import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,IDS,callAs} from '../commercial_completion/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
async function collectionDb(){
 const db=await createCommercialDb();
 for(const p of ['../chat/012_credit_qualification.sql','./207_offer_submission_fee.sql','./228_target_fee_policy.sql','./231_deal_chat_threads.sql','./235_paygo_payment_setup.sql','./236_paygo_collection.sql','./237_paygo_event_reconciliation.sql'])await db.exec(await read(p));
 return db;
}

test('failed payment pauses only its deal messages and successful recovery reopens it',async()=>{
 const db=await collectionDb();
 try{
  await db.exec(await read('./242_paygo_chat_payment_gate.sql'));
  const conversation=crypto.randomUUID(),requests=[crypto.randomUUID(),crypto.randomUUID()],offers=[crypto.randomUUID(),crypto.randomUUID()];
  for(let i=0;i<2;i++){
   await db.query("INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status) VALUES($1,$2,$3,'product',$4,'used','active')",[requests[i],IDS.buyer,IDS.buyerMembership,`Gate request ${i}`]);
   await db.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES($1,$2,$3,$4,$5,'submitted')",[offers[i],requests[i],IDS.buyer,IDS.seller,IDS.sellerMembership]);
  }
  await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)",[conversation,requests[0],offers[0]]);
  await db.query('UPDATE hocalist.offers SET conversation_id=$1 WHERE id=ANY($2::uuid[])',[conversation,offers]);
  await db.query("INSERT INTO hocalist.conversation_members(conversation_id,user_id,profile_id,role) VALUES($1,$2,$3,'buyer'),($1,$4,$5,'seller')",[conversation,IDS.buyer,IDS.buyerMembership,IDS.seller,IDS.sellerMembership]);
  const target=(await db.query("INSERT INTO hocalist.credit_targets(user_id,request_id,offer_id,batch_id,funding_kind,initial_minor,winning_minor,reserved_minor,week_start,rate_version,qualified_at) VALUES($1,$2,$3,NULL,'paygo',200,500,0,current_date,'standard:free:1',now()) RETURNING id",[IDS.seller,requests[0],offers[0]])).rows[0].id;
  const job=(await db.query("INSERT INTO hocalist.paygo_charges(target_id,phase,fee_minor,amount_minor,customer_id,payment_method_id,state) VALUES($1,'initial',200,200,'cus_Gate','pm_Gate','requires_payment_method') RETURNING id",[target])).rows[0].id;
  const send=(user,offer,key)=>callAs(db,'authenticated',user,'SELECT hocalist.chat_deal_send($1,$2,$3,$4)',[conversation,offer,key,'Synthetic payment gate check']);
  await assert.rejects(send(IDS.seller,offers[0],'blocked-seller'),/deal_payment_required/);
  await assert.rejects(send(IDS.buyer,offers[0],'blocked-buyer'),/deal_payment_required/);
  await send(IDS.seller,offers[1],'other-deal');
  await callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.chat_deal_messages($1,$2)',[conversation,offers[0]]);
  await db.query("UPDATE hocalist.paygo_charges SET state='processing' WHERE id=$1",[job]);
  await send(IDS.seller,offers[0],'processing-not-failed');
  await db.query("UPDATE hocalist.paygo_charges SET state='requires_action' WHERE id=$1",[job]);
  await assert.rejects(send(IDS.seller,offers[0],'bank-approval'),/deal_payment_required/);
  await db.query("UPDATE hocalist.paygo_charges SET state='succeeded' WHERE id=$1",[job]);
  await send(IDS.seller,offers[0],'recovered');
  assert.equal((await db.query('SELECT count(*) AS n FROM hocalist.conversation_messages WHERE offer_id=$1',[offers[0]])).rows[0].n,2);
 }finally{await db.close();}
});
test('paygo stages distinct initial/winning charges and funds credits only after verified success',async()=>{
 const db=await createCommercialDb();
 try{
  for(const p of ['../chat/012_credit_qualification.sql','./207_offer_submission_fee.sql','./228_target_fee_policy.sql','./231_deal_chat_threads.sql','./235_paygo_payment_setup.sql','./236_paygo_collection.sql'])await db.exec(await read(p));
  const request=crypto.randomUUID(),offer=crypto.randomUUID(),conversation=crypto.randomUUID();
  await db.query("INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status) VALUES($1,$2,$3,'product','Paygo synthetic request','used','active')",[request,IDS.buyer,IDS.buyerMembership]);
  await db.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES($1,$2,$3,$4,$5,'submitted')",[offer,request,IDS.buyer,IDS.seller,IDS.sellerMembership]);
  await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)",[conversation,request,offer]);
  await db.query('UPDATE hocalist.offers SET conversation_id=$1 WHERE id=$2',[conversation,offer]);
  await db.query("INSERT INTO hocalist.conversation_members(conversation_id,user_id,profile_id,role) VALUES($1,$2,$3,'buyer'),($1,$4,$5,'seller')",[conversation,IDS.buyer,IDS.buyerMembership,IDS.seller,IDS.sellerMembership]);
  const authorize=()=>db.query('SELECT hocalist.credit_authorize_target($1,$2,$3) AS d',[IDS.seller,request,offer]);
  await assert.rejects(authorize(),/insufficient_single_batch/);
  await db.exec('UPDATE hocalist.paygo_collection_policy SET enabled=true');
  await assert.rejects(authorize(),/payment_permission_required/);
  await db.query("INSERT INTO hocalist.stripe_test_customers(membership_id,customer_id) VALUES($1,'cus_Paygo')",[IDS.sellerMembership]);
  const setup=(await callAs(db,'service_role',null,'SELECT hocalist.paygo_setup_begin($1,$2,$3) AS d',[IDS.seller,crypto.randomUUID(),'paygo-v1']))[0].d;
  await callAs(db,'service_role',null,"SELECT hocalist.paygo_setup_bind($1,'cus_Paygo','cs_test_Collection','https://checkout.stripe.com/c/paygo')",[setup.setup_id]);
  await callAs(db,'service_role',null,"SELECT hocalist.paygo_setup_finish($1,'cus_Paygo','cs_test_Collection','pm_Paygo',false)",[setup.setup_id]);
  const target=(await authorize()).rows[0].d.target_id;
  assert.equal((await authorize()).rows[0].d.target_id,target);
  const jobs=async()=>(await db.query('SELECT * FROM hocalist.paygo_charges WHERE target_id=$1 ORDER BY phase',[target])).rows;
  assert.equal((await jobs()).length,0,'sending an offer does not queue a card charge');
  const targetRow=async()=>(await db.query('SELECT * FROM hocalist.credit_targets WHERE id=$1',[target])).rows[0];
  assert.equal((await targetRow()).batch_id,null);
  const send=(user,key,text)=>callAs(db,'authenticated',user,'SELECT hocalist.chat_deal_send($1,$2,$3,$4)',[conversation,offer,key,text]);
  await send(IDS.seller,'seller-opening','Hello, I can help with this request.');assert.equal((await jobs()).length,0);
  await send(IDS.buyer,'buyer-reply','Hello');await send(IDS.buyer,'buyer-reply','Hello');
  const initial=(await jobs())[0];assert.equal(Number(initial.amount_minor),200);assert.equal((await jobs()).length,1);
  const context=id=>callAs(db,'service_role',null,'SELECT hocalist.paygo_charge_context($1) AS d',[id]).then(r=>r[0].d);
  await assert.rejects(callAs(db,'authenticated',IDS.seller,'SELECT hocalist.paygo_charge_context($1)',[initial.id]),/permission denied/);
  await callAs(db,'service_role',null,"SELECT hocalist.paygo_charge_bind($1,'pi_Initial')",[initial.id]);
  const finish=(job,intent,amount,state,customer='cus_Paygo')=>callAs(db,'service_role',null,'SELECT hocalist.paygo_charge_finish($1,$2,$3,$4,$5)',[job,intent,customer,amount,state]);
  await assert.rejects(finish(initial.id,'pi_Initial',201,'succeeded'),/payment_identity_mismatch/);
  await assert.rejects(finish(initial.id,'pi_Initial',200,'succeeded','cus_Foreign'),/payment_identity_mismatch/);
  await finish(initial.id,'pi_Initial',200,'requires_action');
  assert.equal(Number((await targetRow()).charged_minor),0);
  assert.equal((await db.query('SELECT count(*) AS n FROM hocalist.credit_batches')).rows[0].n,0,'an incomplete payment creates no funded batch');
  await finish(initial.id,'pi_Initial',200,'requires_payment_method');
  await db.query("UPDATE hocalist.paygo_payment_methods SET payment_method_id='pm_Replacement' WHERE user_id=$1",[IDS.seller]);
  await assert.rejects(callAs(db,'service_role',null,'SELECT hocalist.paygo_charge_retry($1,$2)',[IDS.seller2,initial.id]),/billing_access_denied/);
  await callAs(db,'service_role',null,'SELECT hocalist.paygo_charge_retry($1,$2)',[IDS.seller,initial.id]);
  await assert.rejects(callAs(db,'service_role',null,'SELECT hocalist.paygo_charge_retry($1,$2)',[IDS.seller,initial.id]),/payment_not_retryable/);
  const retry=(await context(initial.id));assert.equal(retry.retry_generation,1);assert.equal(retry.payment_intent_id,'pi_Initial');assert.equal(retry.payment_method_id,'pm_Replacement');
  await assert.rejects(db.query("SELECT hocalist.credit_settle_internal($1,'win')",[target]),/purchase_confirmation_required/);
  const meeting=crypto.randomUUID();
  await db.query("INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status,meeting_expires_at) VALUES($1,$2,$3,$4,$5,$6,'accepted',now()+interval '1 day')",[meeting,conversation,request,offer,IDS.buyer,IDS.seller]);
  await db.query('INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id) VALUES($1,$2,$3,gen_random_uuid(),$4,$5)',[request,meeting,offer,IDS.buyer,IDS.seller]);
  await db.query("SELECT hocalist.credit_settle_internal($1,'win')",[target]);
  const win=(await jobs()).find(j=>j.phase==='win');assert.equal(Number(win.amount_minor),300);
  assert.equal((await context(win.id)).state,'waiting_for_initial');
  await finish(initial.id,'pi_Initial',200,'succeeded');await finish(initial.id,'pi_Initial',200,'succeeded');
  assert.equal(Number((await targetRow()).charged_minor),200);
  assert.equal((await context(win.id)).state,'queued');
  await callAs(db,'service_role',null,"SELECT hocalist.paygo_charge_bind($1,'pi_Winning')",[win.id]);
  await finish(win.id,'pi_Winning',300,'succeeded');await finish(win.id,'pi_Winning',300,'succeeded');
  assert.equal((await targetRow()).status,'won');assert.equal(Number((await targetRow()).charged_minor),500);
  const ledger=(await db.query('SELECT sum(amount_minor) AS net FROM hocalist.credit_entries')).rows[0];assert.equal(Number(ledger.net),0);
  const batch=(await db.query('SELECT * FROM hocalist.credit_batches')).rows[0];assert.equal(Number(batch.original_minor),500);assert.equal(Number(batch.balance_minor),0);
  const wallet=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.commercial_credit_wallet() AS d'))[0].d;
  assert.equal(wallet.paygo.initial_minor,200);assert.equal(wallet.paygo.winning_minor,500);assert.equal(wallet.paygo.enabled,true);assert.equal(wallet.batches[0].funding_kind,'paygo');
 }finally{await db.close();}
});
test('returned HC is reusable without another card charge and reserved credits are released on cancellation',async()=>{
 const db=await collectionDb();
 try{
  await db.exec('UPDATE hocalist.paygo_collection_policy SET enabled=true');
  const setup=crypto.randomUUID();
  await db.query("INSERT INTO hocalist.paygo_payment_setups(id,user_id,membership_id,request_key,customer_id,state,consent_version) VALUES($1,$2,$3,gen_random_uuid(),'cus_Pool','complete','paygo-v1')",[setup,IDS.seller,IDS.sellerMembership]);
  await db.query("INSERT INTO hocalist.paygo_payment_methods(user_id,setup_id,customer_id,payment_method_id,consent_version) VALUES($1,$2,'cus_Pool','pm_Pool','paygo-v1')",[IDS.seller,setup]);
  async function offer(){
   const r=crypto.randomUUID(),o=crypto.randomUUID();
   await db.query("INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status) VALUES($1,$2,$3,'product','Returned credit test','used','active')",[r,IDS.buyer,IDS.buyerMembership]);
   await db.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES($1,$2,$3,$4,$5,'submitted')",[o,r,IDS.buyer,IDS.seller,IDS.sellerMembership]);
   const t=(await db.query('SELECT hocalist.credit_authorize_target($1,$2,$3) AS d',[IDS.seller,r,o])).rows[0].d.target_id;
   await db.query('UPDATE hocalist.credit_targets SET qualified_at=now() WHERE id=$1',[t]);
   await db.query("SELECT hocalist.credit_settle_internal($1,'initial')",[t]);
   return {target:t,job:(await db.query('SELECT * FROM hocalist.paygo_charges WHERE target_id=$1',[t])).rows[0]};
  }
  const finish=(id,intent,amount,state='succeeded')=>callAs(db,'service_role',null,'SELECT hocalist.paygo_charge_finish($1,$2,$3,$4,$5)',[id,intent,'cus_Pool',amount,state]);
  const first=await offer();
  await callAs(db,'service_role',null,"SELECT hocalist.paygo_charge_bind($1,'pi_Pool')",[first.job.id]);
  await finish(first.job.id,'pi_Pool',200);
  await db.query("SELECT hocalist.credit_settle_internal($1,'refund')",[first.target]);
  await db.query("SELECT hocalist.credit_settle_internal($1,'refund')",[first.target]);
  assert.equal(Number((await db.query('SELECT sum(balance_minor) AS n FROM hocalist.credit_batches')).rows[0].n),200);
  const second=await offer();assert.equal(Number(second.job.amount_minor),0);assert.equal(Number(second.job.fee_minor),200);
  assert.equal(Number((await db.query('SELECT sum(reserved_minor) AS n FROM hocalist.credit_batches')).rows[0].n),200);
  await finish(second.job.id,null,0);await finish(second.job.id,null,0);
  assert.equal(Number((await db.query('SELECT charged_minor FROM hocalist.credit_targets WHERE id=$1',[second.target])).rows[0].charged_minor),200);
  const totals=(await db.query('SELECT sum(balance_minor) AS balance,sum(reserved_minor) AS reserved,sum(external_funded_minor) AS cash FROM hocalist.credit_batches')).rows[0];
  assert.equal(Number(totals.balance),0);assert.equal(Number(totals.reserved),0);assert.equal(Number(totals.cash),200,'reused credits are not another cash deposit');
  assert.equal((await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.commercial_credit_wallet() AS d'))[0].d.deposited_minor,200);
  const pool=(await db.query("SELECT hocalist.credit_deposit_internal($1,'synthetic-return-boundary',199,0,0,'test') AS id",[IDS.seller])).rows[0].id;
  await db.query("UPDATE hocalist.credit_batches SET funding_kind='paygo',external_funded_minor=199 WHERE id=$1",[pool]);
  const third=await offer();assert.equal(Number(third.job.amount_minor),50,'card portion respects provider minimum');
  assert.equal(Number((await db.query('SELECT reserved_minor FROM hocalist.credit_batches WHERE id=$1',[pool])).rows[0].reserved_minor),150);
  await callAs(db,'service_role',null,"SELECT hocalist.paygo_charge_bind($1,'pi_Cancelled')",[third.job.id]);
  const receipt=(account='acct_1Le6hqDmHEV44E5Y',type='payment_intent.processing')=>callAs(db,'service_role',null,'SELECT hocalist.receive_stripe_test_paygo_event($1,$2,$3,$4,$5,false) AS inserted',[account,'evt_PaygoReceipt',type,'pi_Cancelled',12345]);
  await assert.rejects(receipt('acct_Other'),/invalid_provider_account/);
  assert.equal((await receipt())[0].inserted,true);assert.equal((await receipt())[0].inserted,false);
  await assert.rejects(receipt('acct_1Le6hqDmHEV44E5Y','payment_intent.succeeded'),/event_identity_conflict/);
  await assert.rejects(callAs(db,'authenticated',IDS.seller,'SELECT hocalist.paygo_next_charge()'),/permission denied/);
  const selected=(await callAs(db,'service_role',null,'SELECT hocalist.paygo_next_charge() AS d'))[0].d;
  assert.equal(selected.id,third.job.id);
  assert.equal((await callAs(db,'service_role',null,'SELECT hocalist.paygo_next_charge() AS d'))[0].d,null,'a selected job is not immediately selected again');
  await finish(third.job.id,'pi_Cancelled',50,'canceled');
  assert.ok((await db.query("SELECT processed_at FROM hocalist.paygo_provider_events WHERE event_id='evt_PaygoReceipt'")).rows[0].processed_at);
  const released=(await db.query('SELECT balance_minor,reserved_minor FROM hocalist.credit_batches WHERE id=$1',[pool])).rows[0];
  assert.equal(Number(released.balance_minor),199);assert.equal(Number(released.reserved_minor),0);
 }finally{await db.close();}
});

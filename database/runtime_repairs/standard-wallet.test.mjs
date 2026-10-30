import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,IDS,callAs} from '../commercial_completion/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('standard deposits are provider-fenced, immutable, pooled without revenue duplication and card-independent',async()=>{
 const db=await createCommercialDb();
 try{
  for(const p of ['../commercial/094_deposit_checkout.sql','../website_completion/172_website_purchase_status.sql','./194_credit_subscription.sql','./206_credit_access.sql','./226_checkout_recovery.sql','./227_plan_deposit_rates.sql','./235_paygo_payment_setup.sql','./236_paygo_collection.sql','./240_standard_wallet.sql'])await db.exec(await read(p));
  const begin=(amount,key)=>callAs(db,'service_role',null,'SELECT hocalist.stripe_test_standard_deposit_begin($1,$2,$3) AS d',[IDS.seller,amount,key]).then(r=>r[0].d);
  await assert.rejects(begin(100,crypto.randomUUID()),/standard_deposit_unavailable/);
  await db.exec('UPDATE hocalist.standard_wallet_policy SET enabled=true');
  for(const amount of [0,49,2000,4000])await assert.rejects(begin(amount,crypto.randomUUID()),/standard_deposit_unavailable/);
  await assert.rejects(callAs(db,'authenticated',IDS.seller,'SELECT hocalist.stripe_test_standard_deposit_begin($1,100,$2)',[IDS.seller,crypto.randomUUID()]),/permission denied/);
  for(const [i,amount] of [100,200,200].entries()){
   const key=crypto.randomUUID(),checkout=await begin(amount,key);
   assert.equal(checkout.standard_deposit,true);assert.equal(Number(checkout.initial_fee_minor),200);assert.equal(Number(checkout.winning_total_minor),500);
   await assert.rejects(begin(amount+1,key),/idempotency_conflict/);
   const finish=(paid)=>callAs(db,'service_role',null,"SELECT hocalist.stripe_test_deposit_finish($1,'cus_Standard',$2,$3,NULL) AS d",[checkout.checkout_id,paid,`pi_Standard${i}`]);
   // The trusted completion retains customer and paid-amount binding.
   await db.query("INSERT INTO hocalist.stripe_test_customers(membership_id,customer_id) VALUES($1,'cus_Standard') ON CONFLICT DO NOTHING",[IDS.sellerMembership]);
   await assert.rejects(finish(amount+1),/amount_mismatch/);
   await finish(amount);await finish(amount);
  }
  assert.equal(Number((await db.query('SELECT sum(balance_minor) AS n FROM hocalist.credit_batches')).rows[0].n),500);
  await db.query('SELECT hocalist.standard_wallet_pool($1)',[IDS.seller]);
  const batches=(await db.query('SELECT * FROM hocalist.credit_batches WHERE user_id=$1',[IDS.seller])).rows;
  assert.equal(batches.length,4);assert.equal(batches.filter(b=>Number(b.balance_minor)===500).length,1);
  assert.equal(batches.reduce((sum,b)=>sum+Number(b.external_funded_minor??b.original_minor),0),500);
  assert.equal(batches.reduce((sum,b)=>sum+Number(b.balance_minor),0),500);
  assert.equal((await db.query('SELECT * FROM hocalist.paygo_payment_methods')).rows.length,0);
  const request=crypto.randomUUID(),offer=crypto.randomUUID();
  await db.query("INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status) VALUES($1,$2,$3,'product','Standard wallet request','used','active')",[request,IDS.buyer,IDS.buyerMembership]);
  await db.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES($1,$2,$3,$4,$5,'submitted')",[offer,request,IDS.buyer,IDS.seller,IDS.sellerMembership]);
  const target=(await db.query("SELECT hocalist.credit_reserve_internal($1,$2,$3,current_date,10) AS id",[IDS.seller,request,offer])).rows[0].id;
  const totals=async()=>(await db.query('SELECT sum(balance_minor) AS balance,sum(reserved_minor) AS reserved FROM hocalist.credit_batches WHERE user_id=$1',[IDS.seller])).rows[0];
  assert.equal(Number((await totals()).balance),500);assert.equal(Number((await totals()).reserved),500);
  await db.query("SELECT hocalist.credit_settle_internal($1,'initial')",[target]);
  assert.equal(Number((await totals()).balance),300);assert.equal(Number((await totals()).reserved),300);
  await db.query("SELECT hocalist.credit_settle_internal($1,'initial')",[target]);
  assert.equal(Number((await totals()).balance),300);
  await db.query("SELECT hocalist.credit_settle_internal($1,'refund')",[target]);
  assert.equal(Number((await totals()).balance),500);assert.equal(Number((await totals()).reserved),0);
  assert.equal((await db.query('SELECT * FROM hocalist.paygo_charges')).rows.length,0);
  await db.exec(await read('./241_billing_plan_fee_comparison.sql'));
  await db.exec("INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version) VALUES(2000,195,475,'test'),(4000,185,450,'test')");
  const status=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.website_purchase_status(NULL) AS d'))[0].d;
  assert.equal(status.plan_fee_rates.length,3);
  const elite=status.plan_fee_rates.find(row=>row.plan_code==='elite');
  assert.deepEqual(elite.deposits.map(row=>[Number(row.initial_fee_minor),Number(row.winning_total_minor)]),[[155,375],[145,325]]);
  assert.equal(Number(elite.initial_minor),180);
 }finally{await db.close();}
});

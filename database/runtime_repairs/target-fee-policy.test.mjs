import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,callAs,schedule} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const command=async(db,u,op,key,input)=>(await callAs(db,'authenticated',u,'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS d',[op,key,JSON.stringify(input)]))[0].d;
test('new offer policy snapshots fees, refunds and competitor forfeiture without historical repricing',async()=>{
 const db=await setup(false);
 try {
  for(const p of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql','../outcomes/080_sale_confirmation.sql','../commercial/090_credit_batches.sql','../commercial/091_buyer_rewards.sql','../commercial/092_credit_settlement.sql','../chat/012_credit_qualification.sql','./207_offer_submission_fee.sql','./228_target_fee_policy.sql']) await db.exec(await read(p));
  await db.query("SELECT hocalist.credit_deposit_internal($1,'policy-test',4000,145,325,'old-batch')",[B]);
  const request=key=>command(db,A,'request.create',key,{kind:'product',title:'Synthetic policy check',description:'Synthetic item',condition:'used',quantity:1,budget_minimum_minor:1000,budget_maximum_minor:50000,currency_code:'USD',accepts_higher_offers:false,use_home_address:true,category_id:'20000000-0000-4000-8000-000000000001'});
  const offer=r=>command(db,B,'offer.submit',crypto.randomUUID(),{request_id:r.id,price_minor:20000,currency_code:'USD',message:'Test offer',image_media_ids:[],...schedule()});
  const target=async o=>(await db.query('SELECT * FROM hocalist.credit_targets WHERE offer_id=$1',[o.id])).rows[0];
  for(const plan of ['free','pro','elite']) {
   await db.query("INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source) VALUES($1,$2,'admin') ON CONFLICT(user_id) DO UPDATE SET plan_code=excluded.plan_code",[B,plan]);
   const r=await request(crypto.randomUUID()),o=await offer(r),t=await target(o);
   assert.equal(t.policy_plan,plan);
   await db.query("UPDATE hocalist.offers SET status='withdrawn' WHERE id=$1",[o.id]);
   await db.query('SELECT hocalist.credit_policy_release($1)',[t.id]);
   await db.query('SELECT hocalist.credit_policy_release($1)',[t.id]);
   assert.equal((await target(o)).status,plan==='free'?'released':'refunded');
  }
  const r=await request('late-window');
  await db.query("UPDATE hocalist.requests SET first_accepted_at=now()-interval '6 days',acceptance_expires_at=now()+interval '6 hours' WHERE id=$1",[r.id]);
  const o=await offer(r),t=await target(o);
  assert.deepEqual([Number(t.initial_minor),Number(t.winning_minor),Number(t.charged_minor),Number(t.reserved_minor)],[200,200,200,0]);
  await db.query("SELECT hocalist.credit_settle_internal($1,'win')",[t.id]);
  assert.equal(Number((await target(o)).charged_minor),200);
  const pending=await request('elite-no-purchase'),declined=await offer(pending),d=await target(declined);
  await db.query("UPDATE hocalist.offers SET status='declined' WHERE id=$1",[declined.id]);
  await db.query('SELECT hocalist.credit_policy_release($1)',[d.id]);
  assert.equal((await target(declined)).status,'released');
  await db.query("UPDATE hocalist.requests SET status='closed' WHERE id=$1",[pending.id]);
  await db.query('SELECT hocalist.credit_reconcile_internal($1)',[B]);
  assert.equal((await target(declined)).status,'refunded');
  await assert.rejects(callAs(db,'authenticated',B,'SELECT hocalist.credit_view_competing_offers($1)',[pending.id]),/offer_access_denied/);
  const viewedRequest=await request('viewed-request'),viewedOffer=await offer(viewedRequest);
  await command(db,A,'offer.select','select-for-view',{offer_id:viewedOffer.id,revision_id:viewedOffer.revisions[0].id,expected_offer_revision:viewedOffer.revision});
  const viewed=(await callAs(db,'authenticated',B,'SELECT hocalist.credit_view_competing_offers($1) AS d',[viewedRequest.id]))[0].d;
  assert.equal(viewed.refund_eligible,false);
  assert.deepEqual(viewed.offers,[]);
  const stamp=(await target(viewedOffer)).competitors_viewed_at;
  await callAs(db,'authenticated',B,'SELECT hocalist.credit_view_competing_offers($1)',[viewedRequest.id]);
  assert.equal((await target(viewedOffer)).competitors_viewed_at.getTime(),stamp.getTime());
  await db.query("UPDATE hocalist.requests SET status='closed' WHERE id=$1",[viewedRequest.id]);
  await db.query('SELECT hocalist.credit_reconcile_internal($1)',[B]);
  assert.equal((await target(viewedOffer)).status,'released');
 }finally{await db.close();}
});

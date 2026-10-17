import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,B,MB} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('free seller can buy credits; subscription status does not set deposit rates; safety remains',async()=>{
 const db=await setup(false);
 try{
  for(const path of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql','../outcomes/080_sale_confirmation.sql','../commercial/090_credit_batches.sql','../commercial/091_buyer_rewards.sql','../commercial/092_credit_settlement.sql','../commercial/094_deposit_checkout.sql','../website_completion/172_website_purchase_status.sql','./194_credit_subscription.sql','./credit-access-preflight.sql','./206_credit_access.sql','./credit-access-verify.sql'])await db.exec(await read(path));
  const option=(await db.query("INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version) VALUES(2000,155,375,'test') RETURNING id")).rows[0].id;
  const begin=()=>db.query('SELECT hocalist.stripe_test_deposit_begin($1,$2,$3) AS d',[B,option,'00000000-0000-4000-8000-000000000077']);
  const first=(await begin()).rows[0].d;
  assert.equal(first.initial_fee_minor,155); assert.equal(first.winning_total_minor,375);
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[B]);
  assert.equal((await db.query('SELECT hocalist.website_purchase_status() AS d')).rows[0].d.credit_purchase_allowed,true);
  await db.query("INSERT INTO hocalist.stripe_test_subscriptions(membership_id,subscription_id,plan_code,provider_status,paid_until,cancel_at_period_end) VALUES($1,'sub_test','pro','past_due',now()-interval '1 day',false)",[MB]);
  assert.deepEqual((await begin()).rows[0].d,first);
  for(const status of ['restricted','disabled']){
   await db.query('UPDATE hocalist.memberships SET status=$1 WHERE id=$2',[status,MB]);
   await assert.rejects(begin(),/billing_access_denied/);
   await assert.rejects(db.query('SELECT hocalist.website_purchase_status()'),/billing_access_denied/);
  }
  await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1",[MB]);
  await db.query("INSERT INTO hocalist.stripe_test_customers(membership_id,customer_id,requires_review) VALUES($1,'cus_test',true)",[MB]);
  assert.equal((await db.query('SELECT hocalist.website_purchase_status() AS d')).rows[0].d.credit_purchase_allowed,false);
  await db.exec('DELETE FROM hocalist.stripe_test_checkouts');
  await assert.rejects(begin(),/billing_review_required/);
  await assert.rejects(db.exec(await read('./206_credit_access.sql')),/definition drift/);
 }finally{await db.close();}
});

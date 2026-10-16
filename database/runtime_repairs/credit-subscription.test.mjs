import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup, B, MB} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('credit checkout requires verified paid subscription and refuses drift',async()=>{
 const db=await setup(false);
 try {
 for(const path of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql','../outcomes/080_sale_confirmation.sql','../commercial/090_credit_batches.sql','../commercial/091_buyer_rewards.sql','../commercial/092_credit_settlement.sql','../commercial/094_deposit_checkout.sql','../website_completion/172_website_purchase_status.sql'])await db.exec(await read(path));
 await db.exec(await read('./credit-subscription-preflight.sql'));
 await db.exec(await read('./194_credit_subscription.sql'));
 await db.exec(await read('./credit-subscription-verify.sql'));
 const option=(await db.query("INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version) VALUES(2000,155,375,'test') RETURNING id")).rows[0].id;
 const begin=()=>db.query('SELECT hocalist.stripe_test_deposit_begin($1,$2,$3)',[B,option,'00000000-0000-4000-8000-000000000077']);
 await assert.rejects(begin(),/subscription_required/);
 await db.query("INSERT INTO hocalist.stripe_test_subscriptions(membership_id,subscription_id,plan_code,provider_status,paid_until,cancel_at_period_end) VALUES($1,'sub_test','pro','active',now()+interval '1 day',false)",[MB]);
 await begin();
 await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[B]);
 assert.equal((await db.query('SELECT hocalist.website_purchase_status() AS d')).rows[0].d.credit_purchase_allowed,true);
 for(const status of ['trialing','past_due','canceled','unpaid']){
  await db.query('UPDATE hocalist.stripe_test_subscriptions SET provider_status=$1',[status]);
  await assert.rejects(begin(),/subscription_required/);
  assert.equal((await db.query('SELECT hocalist.website_purchase_status() AS d')).rows[0].d.credit_purchase_allowed,false);
 }
 await db.exec("UPDATE hocalist.stripe_test_subscriptions SET provider_status='active',paid_until=now()-interval '1 minute'");
 await assert.rejects(begin(),/subscription_required/);
 await db.exec("UPDATE hocalist.stripe_test_subscriptions SET paid_until=now()+interval '1 day',requires_review=true");
 await assert.rejects(begin(),/subscription_required/);
 await assert.rejects(db.exec(await read('./194_credit_subscription.sql')),/definition drift/);
 }finally{await db.close();}
});

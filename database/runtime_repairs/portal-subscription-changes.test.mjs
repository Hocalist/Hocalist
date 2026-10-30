import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,callAs,IDS} from '../commercial_completion/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('portal pricing stays server-owned and original checkout ownership is retained',async()=>{
 const db=await createCommercialDb();
 try {
  for(const p of ['../commercial/094_deposit_checkout.sql','../website_completion/172_website_purchase_status.sql','../website_completion/173_website_checkout_context.sql','./194_credit_subscription.sql','./206_credit_access.sql','./226_checkout_recovery.sql','./227_plan_deposit_rates.sql','./229_earned_pro_policy.sql','./230_subscription_periods.sql','./239_billing_design_read_model.sql','../../supabase/migrations/20261028154717_verified_portal_subscription_changes.sql']) await db.exec(await read(p));
  await db.exec("UPDATE hocalist.subscription_price_options SET enabled=true,price_id='price_PortalPro' WHERE code='pro' AND billing_interval='month'; UPDATE hocalist.subscription_price_options SET enabled=true,price_id='price_PortalElite' WHERE code='elite' AND billing_interval='month';");
  await db.query("INSERT INTO hocalist.stripe_test_customers(membership_id,customer_id) VALUES($1,'cus_PortalTest')",[IDS.sellerMembership]);
  const begin=(await callAs(db,'service_role',null,'SELECT hocalist.stripe_test_subscription_begin($1,$2,$3,$4) AS d',[IDS.seller,'pro',crypto.randomUUID(),'month']))[0].d;
  const checkout=begin.checkout_id;
  await db.query("INSERT INTO hocalist.stripe_test_subscriptions(membership_id,subscription_id,plan_code,provider_status,paid_until,cancel_at_period_end) VALUES($1,'sub_PortalTest','pro','active',now()+interval '30 days',false)",[IDS.sellerMembership]);
  const context=(await callAs(db,'service_role',null,"SELECT hocalist.website_checkout_context('cus_PortalTest') AS d"))[0].d;
  assert.equal(context.subscription.subscription_id,'sub_PortalTest');
  assert.ok(context.price_options.some(p=>p.code==='elite'));
  const price=(await db.query("SELECT * FROM hocalist.subscription_price_options WHERE code='elite' AND billing_interval='month'")).rows[0];
  const finish=async(snapshot,event)=>{
   await callAs(db,'service_role',null,"SELECT hocalist.receive_stripe_test_event('acct_1Le6hqDmHEV44E5Y',$1,'customer.subscription.updated','sub_PortalTest',12345,false)",[event]);
   const claim=(await callAs(db,'service_role',null,'SELECT hocalist.stripe_test_claim() AS d'))[0].d;
   return callAs(db,'service_role',null,'SELECT hocalist.stripe_test_finish($1,$2,$3,$4::jsonb,NULL)',[claim.token,event,'cus_PortalTest',JSON.stringify(snapshot)]);
  };
  const snapshot={subscription_id:'sub_PortalTest',checkout_id:checkout,plan_code:'elite',status:'active',paid_until:new Date(Date.now()+30*86400000).toISOString(),cancel_at_period_end:false,requires_review:false,price_id:price.price_id,amount_minor:price.amount_minor,billing_interval:'month'};
  await finish(snapshot,'evt_PortalGood');
  const status=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.website_purchase_status() AS d'))[0].d;
  assert.equal(status.effective_plan,'elite');
  assert.equal(status.subscription_price.amount_minor,price.amount_minor);
  const original=(await db.query('SELECT plan_code FROM hocalist.stripe_test_checkouts WHERE id=$1',[checkout])).rows[0];
  assert.equal(original.plan_code,'pro','historical checkout is never repriced');
  await assert.rejects(finish({...snapshot,price_id:'price_Unknown'},'evt_PortalUnknown'),/invalid_subscription_snapshot/);
  await assert.rejects(callAs(db,'authenticated',IDS.seller,"SELECT hocalist.website_checkout_context('cus_PortalTest')"),/permission denied/);
 }finally{await db.close();}
});

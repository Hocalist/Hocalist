import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,IDS,callAs} from '../commercial_completion/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('commercial changes install together with payment gates disabled and verified fee reads',async()=>{
 const db=await createCommercialDb();
 try{
  const paths=[
   '../commercial/094_deposit_checkout.sql','../website_completion/172_website_purchase_status.sql','../website_completion/173_website_checkout_context.sql',
   '../support/070_support_cases.sql','../trust/120_review_workflow.sql','../admin_completion/160_admin_commercial_config.sql',
   './194_credit_subscription.sql','./206_credit_access.sql','../chat/012_credit_qualification.sql','./207_offer_submission_fee.sql','./226_checkout_recovery.sql',
   './227_plan_deposit_rates.sql','./228_target_fee_policy.sql','./229_earned_pro_policy.sql','./230_subscription_periods.sql',
   './231_deal_chat_threads.sql','./232_deal_read_markers.sql','./233_reviewed_credit_returns.sql','./234_deposit_bands.sql',
   './235_paygo_payment_setup.sql','./236_paygo_collection.sql','./237_paygo_event_reconciliation.sql','./238_paygo_admin_rates.sql',
   './239_billing_design_read_model.sql','./240_standard_wallet.sql','./241_billing_plan_fee_comparison.sql','./242_paygo_chat_payment_gate.sql','./243_managed_paygo_card.sql',
  ];
  for(const path of paths){try{await db.exec(await read(path));}catch(error){throw new Error(`${path}: ${error.message}`);}}
  await db.exec(await read('../../supabase/migrations/20261027065137_elite_deferred_initial_fee.sql'));
  assert.equal((await db.query('SELECT enabled FROM hocalist.paygo_collection_policy')).rows[0].enabled,false);
  assert.equal((await db.query('SELECT enabled FROM hocalist.standard_wallet_policy')).rows[0].enabled,false);
  await db.exec("INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version) VALUES(2000,195,475,'test'),(4000,185,450,'test')");
  const status=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.website_purchase_status() AS d'))[0].d;
  assert.equal(status.plan_fee_rates.length,3);assert.equal(status.standard_deposits_enabled,false);
  assert.equal(status.subscription_price,null);
  assert.equal(status.entitlement.plans.find(p=>p.plan_code==='free').weekly_target_limit,10);
  assert.equal(status.plan_fee_rates.find(p=>p.plan_code==='pro').deposits[0].initial_fee_minor,175);
  assert.equal(status.plans.filter(p=>p.billing_interval==='year'&&p.enabled).length,0);
 }finally{await db.close();}
});

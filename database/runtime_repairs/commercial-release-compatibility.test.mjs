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
  await db.exec(await read('../../supabase/migrations/20261125190045_free_weekly_unique_buyers.sql'));
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

test('Free quota counts distinct buyers across funding methods and resets the next UTC week', async () => {
 const db = await createCommercialDb();
 try {
  for (const path of [
   '../chat/012_credit_qualification.sql', './207_offer_submission_fee.sql',
   './228_target_fee_policy.sql', './229_earned_pro_policy.sql', './231_deal_chat_threads.sql',
   './235_paygo_payment_setup.sql', './236_paygo_collection.sql',
   '../../supabase/migrations/20261027065137_elite_deferred_initial_fee.sql',
   '../../supabase/migrations/20261125190045_free_weekly_unique_buyers.sql',
  ]) await db.exec(await read(path));

  const seller = IDS.seller;
  const buyers = [{ user: IDS.buyer, membership: IDS.buyerMembership }];
  for (let index = 1; index < 11; index++) {
   const buyer = { user: crypto.randomUUID(), membership: crypto.randomUUID() };
   await db.query("INSERT INTO auth.users(id, raw_user_meta_data) VALUES($1,'{}')", [buyer.user]);
   await db.query("INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES($1,$2,'buyer','active')",
    [buyer.membership, buyer.user]);
   buyers.push(buyer);
  }

  const [week] = (await db.query("SELECT date_trunc('week',now() AT TIME ZONE 'UTC')::date::text AS start")).rows;
  const batch = (await db.query(
   "SELECT hocalist.credit_deposit_internal($1,'unique-buyer-test',10000,200,500,'test') AS id", [seller],
  )).rows[0].id;
  const newOffer = async (buyer) => {
   const request = crypto.randomUUID();
   const offer = crypto.randomUUID();
   await db.query(`INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
     VALUES($1,$2,$3,'product','Synthetic request','used','active')`, [request, buyer.user, buyer.membership]);
   await db.query(`INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
     VALUES($1,$2,$3,$4,$5,'submitted')`, [offer, request, buyer.user, seller, IDS.sellerMembership]);
   return {request, offer};
  };
  const reserve = async (routine, {request, offer}, date = week.start) => (
   await db.query(`SELECT hocalist.${routine}($1,$2,$3,$4,10) AS target`, [seller, request, offer, date])
  ).rows[0].target;
  const prepaid = 'credit_reserve_internal';
  const paygo = 'paygo_reserve_target';
  const wallet = async (routine) => (
   await callAs(db, 'authenticated', seller, `SELECT hocalist.${routine}() AS wallet`)
  )[0].wallet.weekly;
  const target = await newOffer(buyers[0]);
  const first = await reserve(prepaid, target);
  assert.equal(await reserve(prepaid, target), first, 'retry keeps the same payment record');
  const repeat = await reserve(prepaid, await newOffer(buyers[0]));
  assert.notEqual(repeat, first, 'a separate offer keeps its own payment record');
  assert.equal((await wallet('commercial_credit_wallet')).used, 1);
  for (const buyer of buyers.slice(1, 10)) await reserve(prepaid, await newOffer(buyer));

  const eleventh = await newOffer(buyers[10]);
  const balance = async () => (await db.query(
   'SELECT balance_minor,reserved_minor FROM hocalist.credit_batches WHERE id=$1', [batch],
  )).rows[0];
  const before = await balance();
  await assert.rejects(reserve(prepaid, eleventh), /weekly_target_limit/);
  assert.deepEqual(await balance(), before, 'quota denial keeps credits untouched');
  await reserve(prepaid, await newOffer(buyers[0]));

  await db.exec('UPDATE hocalist.paygo_collection_policy SET enabled=true');
  const setup = crypto.randomUUID();
  await db.query(`INSERT INTO hocalist.paygo_payment_setups
     (id,user_id,membership_id,request_key,customer_id,state,consent_version)
     VALUES($1,$2,$3,gen_random_uuid(),'cus_Quota','complete','paygo-v1')`, [setup, seller, IDS.sellerMembership]);
  await db.query(`INSERT INTO hocalist.paygo_payment_methods
     (user_id,setup_id,customer_id,payment_method_id,consent_version)
     VALUES($1,$2,'cus_Quota','pm_Quota','paygo-v1')`, [seller, setup]);
  await assert.rejects(reserve(paygo, eleventh), /weekly_target_limit/);
  await reserve(paygo, await newOffer(buyers[1]));
  for (const routine of ['credit_wallet', 'commercial_credit_wallet']) {
   const weekly = await wallet(routine);
   assert.equal(weekly.limit, 10);
   assert.equal(weekly.used, 10);
  }
  const nextWeek = (await db.query('SELECT ($1::date + 7)::text AS start', [week.start])).rows[0].start;
  await reserve(prepaid, eleventh, nextWeek);
  assert.equal((await wallet('commercial_credit_wallet')).used, 10);
  assert.equal((await db.query('SELECT hocalist.weekly_target_usage($1,$2) AS used', [seller, nextWeek])).rows[0].used, 1);

  await callAs(db, 'authenticated', IDS.admin, 'SELECT hocalist.entitlement_admin_command($1,$2,$3::jsonb)',
   ['grant.set', 'paid-quota-regression', JSON.stringify({user_id: seller, plan_code: 'pro', active: true})]);
  assert.equal((await wallet('commercial_credit_wallet')).used, 13, 'paid plans still count each request');
 } finally {
  await db.close();
 }
});

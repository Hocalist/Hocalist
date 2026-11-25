import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,IDS,callAs} from '../commercial_completion/tests/fixture.mjs';
import {schedule} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const freeQuotaMigration='../../supabase/migrations/20261125190045_free_weekly_unique_buyers.sql';
const pullOutMigration='../../supabase/migrations/20261125192441_pro_buyer_quota_and_offer_pull_out.sql';

async function configureCardFunding(db, seller, membership, label) {
 const setup = crypto.randomUUID();
 await db.query(`INSERT INTO hocalist.paygo_payment_setups
    (id,user_id,membership_id,request_key,customer_id,state,consent_version)
    VALUES($1,$2,$3,gen_random_uuid(),$4,'complete','paygo-v1')`, [setup, seller, membership, `cus_${label}`]);
 await db.query(`INSERT INTO hocalist.paygo_payment_methods
    (user_id,setup_id,customer_id,payment_method_id,consent_version)
    VALUES($1,$2,$3,$4,'paygo-v1')`, [seller, setup, `cus_${label}`, `pm_${label}`]);
}

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
  await db.exec(await read(freeQuotaMigration));
  await db.exec(await read(pullOutMigration));
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

test('Free and Pro count distinct weekly buyers across funding methods', async () => {
 const db = await createCommercialDb();
 try {
  for (const path of [
   '../chat/012_credit_qualification.sql', './207_offer_submission_fee.sql',
   './228_target_fee_policy.sql', './229_earned_pro_policy.sql', './231_deal_chat_threads.sql',
   './235_paygo_payment_setup.sql', './236_paygo_collection.sql',
   '../../supabase/migrations/20261027065137_elite_deferred_initial_fee.sql',
   freeQuotaMigration, pullOutMigration,
  ]) await db.exec(await read(path));

  const seller = IDS.seller;
  const buyers = [{ user: IDS.buyer, membership: IDS.buyerMembership }];
  for (let index = 1; index < 51; index++) {
   const buyer = { user: crypto.randomUUID(), membership: crypto.randomUUID() };
   await db.query("INSERT INTO auth.users(id, raw_user_meta_data) VALUES($1,'{}')", [buyer.user]);
   await db.query("INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES($1,$2,'buyer','active')",
    [buyer.membership, buyer.user]);
   buyers.push(buyer);
  }

  const [week] = (await db.query("SELECT date_trunc('week',now() AT TIME ZONE 'UTC')::date::text AS start")).rows;
  const batch = (await db.query(
   "SELECT hocalist.credit_deposit_internal($1,'unique-buyer-test',40000,200,500,'test') AS id", [seller],
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
   await db.query(`SELECT hocalist.${routine}($1,$2,$3,$4,hocalist.marketplace_weekly_target_limit($1)) AS target`,
    [seller, request, offer, date])
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
  await configureCardFunding(db, seller, IDS.sellerMembership, 'Quota');
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

  const setPlan = (plan) => callAs(db, 'authenticated', IDS.admin,
   'SELECT hocalist.entitlement_admin_command($1,$2,$3::jsonb)',
   ['grant.set', `quota-${plan}`, JSON.stringify({user_id: seller, plan_code: plan, active: true})]);
  await setPlan('elite');
  assert.equal((await wallet('commercial_credit_wallet')).used, 13, 'Elite counts requests');
  await setPlan('pro');
  assert.equal((await wallet('commercial_credit_wallet')).used, 10, 'Pro counts distinct buyers');
  for (const buyer of buyers.slice(10, 50)) await reserve(prepaid, await newOffer(buyer));
  const fiftyFirst = await newOffer(buyers[50]);
  await assert.rejects(reserve(prepaid, fiftyFirst), /weekly_target_limit/);
  await assert.rejects(reserve(paygo, fiftyFirst), /weekly_target_limit/);
  await reserve(prepaid, await newOffer(buyers[0]));
  await reserve(paygo, await newOffer(buyers[1]));
  for (const routine of ['credit_wallet', 'commercial_credit_wallet']) {
   const weekly = await wallet(routine);
   assert.equal(weekly.limit, 50);
   assert.equal(weekly.used, 50);
  }
 } finally {
  await db.close();
 }
});

test('Pro can withdraw and resend for one request with credits or a card', async t => {
 const db = await createCommercialDb();
 try {
  for (const path of [
   '../chat/012_credit_qualification.sql', './207_offer_submission_fee.sql',
   './228_target_fee_policy.sql', './231_deal_chat_threads.sql',
   './235_paygo_payment_setup.sql', './236_paygo_collection.sql',
   '../../supabase/migrations/20261027065137_elite_deferred_initial_fee.sql',
   freeQuotaMigration, pullOutMigration,
  ]) await db.exec(await read(path));

  const {buyer, buyerMembership, seller, sellerMembership, seller2, seller2Membership} = IDS;
  const command = async (user, operation, key, input) => (await callAs(db, 'authenticated', user,
   'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS offer', [operation,key,JSON.stringify(input)]))[0].offer;
  const submit = (user, request, key, price = 22000) => command(user, 'offer.submit', key, {
   request_id: request, price_minor: price, currency_code: 'USD', message: 'Available for pickup.',
   image_media_ids: [], ...schedule({schedule_date: new Date(Date.now()+86400000).toISOString().slice(0,10)}),
  });
  const withdraw = (user, offer, key) => command(user, 'offer.withdraw', key,
   {offer_id:offer.id, expected_offer_revision:offer.revision});
  const createRequest = async () => {
   const id = crypto.randomUUID();
   await db.query(`INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
     VALUES($1,$2,$3,'product','Synthetic request','used','active')`, [id,buyer,buyerMembership]);
   return id;
  };
  const deposit = () => db.query("SELECT hocalist.credit_deposit_internal($1,'pull-out-test',5000,190,475,'test') AS id",[seller]);
  const targetFor = async (offer) => (await db.query(
   'SELECT * FROM hocalist.credit_targets WHERE offer_id=$1', [offer.id],
  )).rows[0];
  const jobsFor = async (target) => (await db.query(
   'SELECT * FROM hocalist.paygo_charges WHERE target_id=$1', [target.id],
  )).rows;

  await deposit();
  const freeOffer = await submit(seller, await createRequest(), 'free-offer');
  await assert.rejects(withdraw(seller, freeOffer, 'free-withdraw'), /offer_withdraw_plan_required/);
  assert.equal((await targetFor(freeOffer)).status, 'reserved');
  await db.query("INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source) VALUES($1,'pro','admin'),($2,'pro','admin')", [seller,seller2]);
  await db.exec('UPDATE hocalist.paygo_collection_policy SET enabled=true');
  await configureCardFunding(db,seller2,seller2Membership,'PullOut');

  for (const [funding, owner, membership] of [['prepaid',seller,sellerMembership],['paygo',seller2,seller2Membership]]) {
   await t.test(funding, async () => {
    const request = await createRequest();
    const original = await submit(owner, request, `${funding}-send`);
    const originalTarget = await targetFor(original);
    assert.equal(originalTarget.funding_kind,funding);
    assert.equal(Number(originalTarget.charged_minor),0);
    assert.equal(Number(originalTarget.reserved_minor),funding === 'prepaid' ? 475 : 0);
    const canceled = await withdraw(owner,original,`${funding}-withdraw`);
    assert.equal(canceled.status,'withdrawn');
    assert.deepEqual(await withdraw(owner,original,`${funding}-withdraw`),canceled);
    const returned = await targetFor(original);
    assert.equal(returned.status,'refunded');
    assert.equal(Number(returned.reserved_minor),0);

    const replacement = await submit(owner,request,`${funding}-resend`,24000);
    const fresh = await targetFor(replacement);
    assert.notEqual(fresh.id,originalTarget.id);
    assert.equal(fresh.request_id,request);
    assert.equal(fresh.funding_kind,funding);
    assert.equal(fresh.status,'reserved');
    assert.deepEqual(await submit(owner,request,`${funding}-resend`,24000),replacement);
    assert.equal((await targetFor(replacement)).id,fresh.id);

    // Keep this fixture submitted to exercise the reply-specific guard, in
    // addition to the normal selected-offer path which already blocks pull out.
    const chat = crypto.randomUUID();
    await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)", [chat,request,replacement.id]);
    await db.query('UPDATE hocalist.offers SET conversation_id=$1 WHERE id=$2', [chat,replacement.id]);
    await db.query("INSERT INTO hocalist.conversation_members(conversation_id,user_id,profile_id,role) VALUES($1,$2,$3,'buyer'),($1,$4,$5,'seller')", [chat,buyer,buyerMembership,owner,membership]);
    await callAs(db,'authenticated',buyer,'SELECT hocalist.chat_deal_send($1,$2,$3,$4)', [chat,replacement.id,`${funding}-reply`,'I am interested.']);
    await assert.rejects(withdraw(owner,replacement,`${funding}-too-late`), /offer_withdraw_buyer_responded/);
    assert.equal((await targetFor(original)).status,'refunded');
    assert.equal((await jobsFor(originalTarget)).length,0);
    if (funding === 'prepaid') {
     assert.equal(Number((await targetFor(replacement)).charged_minor),190);
    } else {
     const jobs = await jobsFor(fresh);
     assert.deepEqual(jobs.map(job=>[job.phase,Number(job.fee_minor)]), [['initial',190]]);
     await callAs(db,'service_role',null,'SELECT hocalist.paygo_charge_bind($1,$2)', [jobs[0].id,'pi_PullOutReplacement']);
     for (let replay = 0; replay < 2; replay++) {
      await callAs(db,'service_role',null,'SELECT hocalist.paygo_charge_finish($1,$2,$3,$4,$5)',
       [jobs[0].id,'pi_PullOutReplacement','cus_PullOut',190,'succeeded']);
     }
     assert.equal(Number((await targetFor(replacement)).charged_minor),190);
     assert.equal(Number((await targetFor(original)).charged_minor),0);
    }
    const wallet = (await callAs(db,'authenticated',owner,'SELECT hocalist.commercial_credit_wallet() AS data'))[0].data;
    assert.equal(wallet.weekly.used,1,'withdrawal and resend use one buyer slot');
   });
  }
 } finally {
  await db.close();
 }
});

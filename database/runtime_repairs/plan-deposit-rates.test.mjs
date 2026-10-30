import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('verified plan prices new deposits, retries preserve snapshot, private rates cannot be changed by clients',async()=>{
 const db=await setup(false);
 try {
  for(const p of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql','../outcomes/080_sale_confirmation.sql','../commercial/090_credit_batches.sql','../commercial/091_buyer_rewards.sql','../commercial/092_credit_settlement.sql','../commercial/094_deposit_checkout.sql','../website_completion/172_website_purchase_status.sql','./194_credit_subscription.sql','./206_credit_access.sql','./226_checkout_recovery.sql','../admin_completion/160_admin_commercial_config.sql','./227_plan_deposit_rates.sql']) await db.exec(await read(p));
  const options=(await db.query("INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version) VALUES(2000,155,375,'legacy'),(4000,145,325,'legacy') RETURNING id,amount_minor")).rows;
  for(const [plan,expected] of [['free',[[195,475],[185,450]]],['pro',[[175,460],[165,450]]],['elite',[[155,375],[145,325]]]]) {
   await db.query("INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source) VALUES($1,$2,'admin') ON CONFLICT(user_id) DO UPDATE SET plan_code=excluded.plan_code",[B,plan]);
   const wallet=(await callAs(db,'authenticated',B,'SELECT hocalist.credit_wallet() AS d'))[0].d;
   assert.deepEqual(wallet.deposit_options.map(o=>[o.initial_fee_minor,o.winning_total_minor]),expected);
   for(let i=0;i<2;i++) {
    const key=crypto.randomUUID();
    const result=(await callAs(db,'service_role',null,'SELECT hocalist.stripe_test_deposit_begin($1,$2,$3) AS d',[B,options[i].id,key]))[0].d;
    assert.deepEqual([result.initial_fee_minor,result.winning_total_minor],expected[i]);
    await db.query("UPDATE hocalist.credit_plan_deposit_rates SET initial_fee_minor=initial_fee_minor+1 WHERE plan_code=$1 AND amount_minor=$2",[plan,options[i].amount_minor]);
    const retry=(await callAs(db,'service_role',null,'SELECT hocalist.stripe_test_deposit_begin($1,$2,$3) AS d',[B,options[i].id,key]))[0].d;
    assert.deepEqual([retry.initial_fee_minor,retry.winning_total_minor],expected[i]);
    await db.query("UPDATE hocalist.stripe_test_checkouts SET state='expired' WHERE id=$1",[result.checkout_id]);
   }
  }
  await assert.rejects(callAs(db,'authenticated',B,"UPDATE hocalist.credit_plan_deposit_rates SET initial_fee_minor=0"),/permission denied/);
  await assert.rejects(callAs(db,'anon',null,'SELECT * FROM hocalist.credit_deposit_options_for_user($1)',[B]),/permission denied/);
  await assert.rejects(callAs(db,'authenticated',B,'SELECT hocalist.credit_admin_command($1,$2,$3)',[
   'plan_deposit_rate.set','denied',JSON.stringify({plan_code:'free',amount_minor:2000,initial_fee_minor:190,winning_total_minor:470,rate_version:'edited',expected_revision:1})]),/admin/);
  await db.query('INSERT INTO hocalist.platform_admins(user_id) VALUES($1) ON CONFLICT DO NOTHING',[A]);
  const config=(await callAs(db,'authenticated',A,'SELECT hocalist.admin_commercial_config() AS d'))[0].d;
  assert.equal(config.plan_deposit_rates.length,6);
  const input={plan_code:'free',amount_minor:2000,initial_fee_minor:190,winning_total_minor:470,rate_version:'edited',expected_revision:1};
  const save=key=>callAs(db,'authenticated',A,'SELECT hocalist.credit_admin_command($1,$2,$3) AS d',['plan_deposit_rate.set',key,JSON.stringify(input)]);
  const first=await save('rate-edit');
  assert.deepEqual(await save('rate-edit'),first);
  await assert.rejects(save('stale-edit'),/revision_conflict/);
  const receipt=await db.query("SELECT count(*)::int AS n FROM hocalist.marketplace_receipts WHERE operation='credit_admin.plan_deposit_rate.set'");
  assert.equal(receipt.rows[0].n,1);
  await db.exec(await read('./234_deposit_bands.sql'));
  await db.query("INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version) VALUES(1999,155,375,'legacy'),(3999,155,375,'legacy'),(4001,145,325,'legacy')");
  const banded=(await callAs(db,'authenticated',B,'SELECT hocalist.website_purchase_status() AS d'))[0].d.options;
  assert.equal(banded.some(o=>o.amount_minor===1999),false);
  assert.deepEqual(banded.filter(o=>[3999,4001].includes(o.amount_minor)).map(o=>[Number(o.amount_minor),Number(o.initial_fee_minor),Number(o.winning_total_minor)]),[[3999,156,375],[4001,146,325]]);
  for(const p of ['../chat/012_credit_qualification.sql','./207_offer_submission_fee.sql','./228_target_fee_policy.sql','./231_deal_chat_threads.sql','./235_paygo_payment_setup.sql','./236_paygo_collection.sql','./238_paygo_admin_rates.sql'])await db.exec(await read(p));
  const standard={plan_code:'free',initial_minor:205,winning_minor:505,expected_revision:1};
  const standardSave=(user,key)=>callAs(db,'authenticated',user,'SELECT hocalist.credit_admin_command($1,$2,$3) AS d',['paygo_plan_rate.set',key,JSON.stringify(standard)]);
  await assert.rejects(standardSave(B,'denied-standard'),/admin/);
  const standardFirst=await standardSave(A,'standard-edit');
  assert.deepEqual(await standardSave(A,'standard-edit'),standardFirst);
  await assert.rejects(standardSave(A,'stale-standard'),/revision_conflict/);
  const updated=(await callAs(db,'authenticated',A,'SELECT hocalist.admin_commercial_config() AS d'))[0].d;
  assert.equal(updated.paygo_plan_rates.length,3);
  assert.equal(updated.paygo_plan_rates.find(r=>r.plan_code==='free').initial_minor,205);
  assert.equal((await db.query("SELECT count(*)::int AS n FROM hocalist.marketplace_receipts WHERE operation='credit_admin.paygo_plan_rate.set'")).rows[0].n,1);
  assert.equal((await db.query('SELECT enabled FROM hocalist.paygo_collection_policy')).rows[0].enabled,false,'editing a fee cannot activate collection');
 } finally {await db.close();}
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,callAs,schedule} from '../outcomes/tests/fixture.mjs';
const read = path => readFile(new URL(path,import.meta.url),'utf8');
const command = async(db,user,op,key,input) =>
 (await callAs(db,'authenticated',user,'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS d',[op,key,JSON.stringify(input)]))[0].d;

test('offer submission charges initial once; chat never charges; winning total stays batch-bound',async t=>{
 const db=await setup(false);
 try {
  for(const path of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql',
   '../outcomes/080_sale_confirmation.sql','../commercial/090_credit_batches.sql','../commercial/091_buyer_rewards.sql',
   '../commercial/092_credit_settlement.sql','../chat/012_credit_qualification.sql']) await db.exec(await read(path));
  const request=async(key)=>command(db,A,'request.create',key,{
   kind:'product',title:'Synthetic desk',description:'A test desk',condition:'used',quantity:1,
   budget_minimum_minor:1000,budget_maximum_minor:50000,currency_code:'USD',accepts_higher_offers:false,
   use_home_address:true,category_id:'20000000-0000-4000-8000-000000000001',
  });
  const payload=id=>({request_id:id,price_minor:20000,currency_code:'USD',message:'Test offer',image_media_ids:[],...schedule()});
  const batch=(await db.query("SELECT hocalist.credit_deposit_internal($1,'offer-fee-test',2000,155,375,'test') AS id",[B])).rows[0].id;
  const before=await request('legacy-request');
  const legacy=await command(db,B,'offer.submit','legacy-offer',payload(before.id));
  await db.exec(await read('./offer-fee-preflight.sql'));
  await db.exec(await read('./207_offer_submission_fee.sql'));
  const target=async(id)=>(await db.query('SELECT * FROM hocalist.credit_targets WHERE offer_id=$1',[id])).rows[0];
  await t.test('migration does not charge historical offers or rewrite balances',async()=>{
   assert.equal(Number((await target(legacy.id)).charged_minor),0);
   assert.equal(Number((await db.query('SELECT balance_minor FROM hocalist.credit_batches WHERE id=$1',[batch])).rows[0].balance_minor),2000);
  });
  const r=await request('new-request');
  let offer;
  await t.test('successful submit debits 155 with no selection or chat',async()=>{
   offer=await command(db,B,'offer.submit','new-offer',payload(r.id));
   const row=await target(offer.id);
   assert.equal(row.status,'initial_charged');
   assert.equal(Number(row.charged_minor),155);
   assert.equal(Number(row.reserved_minor),220);
   assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.conversation_messages')).rows[0].n),0);
  });
  await t.test('same-key replay and internal authorization replay do not debit twice',async()=>{
   assert.deepEqual(await command(db,B,'offer.submit','new-offer',payload(r.id)),offer);
   await db.query('SELECT hocalist.credit_authorize_target($1,$2,$3)',[B,r.id,offer.id]);
   assert.equal(Number((await db.query("SELECT count(*) AS n FROM hocalist.credit_entries e JOIN hocalist.credit_targets t ON t.id=e.target_id WHERE t.offer_id=$1 AND e.kind='initial'",[offer.id])).rows[0].n),1);
  });
  await t.test('chat cannot charge either a new or legacy target',async()=>{
   await command(db,A,'offer.select','select-new',{offer_id:offer.id,revision_id:offer.revisions[0].id,expected_offer_revision:offer.revision});
   const opened=await command(db,A,'conversation.open_offer','open-new',{offer_id:offer.id});
   for(const [user,key] of [[A,'buyer-text'],[B,'seller-text']]) {
    await callAs(db,'authenticated',user,'SELECT hocalist.chat_send($1,$2,$3)',[opened.conversation_id,'Test message',key]);
   }
   assert.equal(Number((await target(offer.id)).charged_minor),155);
   await db.query('SELECT hocalist.credit_qualify_conversation($1)',[opened.conversation_id]);
   assert.equal(Number((await target(legacy.id)).charged_minor),0);
  });
  await t.test('winning settlement charges only the remaining 220 and replays once',async()=>{
   const row=await target(offer.id);
   await db.query("SELECT hocalist.credit_settle_internal($1,'win')",[row.id]);
   await db.query("SELECT hocalist.credit_settle_internal($1,'win')",[row.id]);
   assert.equal(Number((await target(offer.id)).charged_minor),375);
   assert.equal(Number((await target(offer.id)).reserved_minor),0);
  });
  await t.test('each separate deal charges its own initial fee and losing releases only the remainder',async()=>{
   const secondRequest=await request('second-deal');
   const second=await command(db,B,'offer.submit','second-offer',payload(secondRequest.id));
   const row=await target(second.id);
   assert.equal(Number(row.charged_minor),155);
   assert.equal(Number(row.reserved_minor),220);
   await db.query("SELECT hocalist.credit_settle_internal($1,'release')",[row.id]);
   assert.equal(Number((await target(second.id)).charged_minor),155);
   assert.equal(Number((await target(second.id)).reserved_minor),0);
  });
  await t.test('a receipt failure after the debit rolls the whole submission back; retry succeeds once',async()=>{
   const next=await request('receipt-failure-request');
   const balance=(await db.query('SELECT balance_minor,reserved_minor FROM hocalist.credit_batches WHERE id=$1',[batch])).rows[0];
   await db.exec(`CREATE FUNCTION hocalist.test_reject_offer_receipt() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
    IF NEW.idempotency_key='receipt-failure' THEN RAISE EXCEPTION 'synthetic_receipt_failure'; END IF; RETURN NEW; END $$;
    CREATE TRIGGER test_reject_offer_receipt BEFORE INSERT ON hocalist.marketplace_receipts
    FOR EACH ROW EXECUTE FUNCTION hocalist.test_reject_offer_receipt();`);
   await assert.rejects(command(db,B,'offer.submit','receipt-failure',payload(next.id)),/synthetic_receipt_failure/);
   assert.deepEqual((await db.query('SELECT balance_minor,reserved_minor FROM hocalist.credit_batches WHERE id=$1',[batch])).rows[0],balance);
   assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.offers WHERE request_id=$1',[next.id])).rows[0].n),0);
   await db.exec('DROP TRIGGER test_reject_offer_receipt ON hocalist.marketplace_receipts; DROP FUNCTION hocalist.test_reject_offer_receipt();');
   const retried=await command(db,B,'offer.submit','receipt-failure',payload(next.id));
   assert.equal(Number((await target(retried.id)).charged_minor),155);
   await command(db,B,'offer.submit','receipt-failure',payload(next.id));
   assert.equal(Number((await target(retried.id)).charged_minor),155);
  });
  await t.test('exhausted contact allowance blocks offer submission without a charge',async()=>{
   const next=await request('quota-request');
   const limits=(await db.query('SELECT plan_code,weekly_target_limit FROM hocalist.marketplace_plan_limits')).rows;
   const entries=Number((await db.query('SELECT count(*) AS n FROM hocalist.credit_entries')).rows[0].n);
   const balance=(await db.query('SELECT balance_minor,reserved_minor FROM hocalist.credit_batches WHERE id=$1',[batch])).rows[0];
   try {
    await db.exec('UPDATE hocalist.marketplace_plan_limits SET weekly_target_limit=1');
    await assert.rejects(command(db,B,'offer.submit','quota-offer',payload(next.id)),/weekly_target_limit/);
    assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.offers WHERE request_id=$1',[next.id])).rows[0].n),0);
    assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.credit_entries')).rows[0].n),entries);
    assert.deepEqual((await db.query('SELECT balance_minor,reserved_minor FROM hocalist.credit_batches WHERE id=$1',[batch])).rows[0],balance);
   } finally {
    for(const row of limits) await db.query('UPDATE hocalist.marketplace_plan_limits SET weekly_target_limit=$1 WHERE plan_code=$2',[row.weekly_target_limit,row.plan_code]);
   }
  });
  await t.test('a new UTC week restores capacity without deleting past usage',async()=>{
   const history=(await db.query('SELECT id,week_start FROM hocalist.credit_targets WHERE user_id=$1',[B])).rows;
   const count=history.length;
   assert.ok(count>0);
   try {
    await db.query("UPDATE hocalist.credit_targets SET week_start=date_trunc('week',now() AT TIME ZONE 'UTC')::date-7 WHERE user_id=$1",[B]);
    const wallet=async()=>(await callAs(db,'authenticated',B,'SELECT hocalist.credit_wallet() AS d'))[0].d;
    assert.equal(Number((await wallet()).weekly.used),0);
    const next=await request('new-week-request');
    await command(db,B,'offer.submit','new-week-offer',payload(next.id));
    assert.equal(Number((await wallet()).weekly.used),1);
    assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.credit_targets WHERE user_id=$1',[B])).rows[0].n),count+1);
   } finally {
    for(const row of history) await db.query('UPDATE hocalist.credit_targets SET week_start=$1 WHERE id=$2',[row.week_start,row.id]);
   }
  });
  await t.test('failed submission rolls back offer, receipt and any debit',async()=>{
   const next=await request('insufficient-request');
   await db.query('UPDATE hocalist.credit_batches SET balance_minor=reserved_minor WHERE id=$1',[batch]);
   const entries=Number((await db.query('SELECT count(*) AS n FROM hocalist.credit_entries')).rows[0].n);
   await assert.rejects(command(db,B,'offer.submit','insufficient-offer',payload(next.id)),/insufficient_single_batch|targeting_fee_unconfigured/);
   assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.offers WHERE request_id=$1',[next.id])).rows[0].n),0);
   assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.credit_entries')).rows[0].n),entries);
  });
  await t.test('double apply is safe, helpers remain internal, and drift is rejected',async()=>{
   await db.exec(await read('./207_offer_submission_fee.sql'));
   await db.exec(await read('./offer-fee-verify.sql'));
   await assert.rejects(callAs(db,'authenticated',B,'SELECT hocalist.credit_authorize_target($1,$2,$3)',[B,r.id,offer.id]),/permission denied/);
   await db.exec("CREATE OR REPLACE FUNCTION hocalist.credit_qualify_conversation(p_conversation uuid) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ SELECT '{}'::jsonb $$");
   await assert.rejects(db.exec(await read('./offer-fee-preflight.sql')),/definition drift/);
  });
 } finally { await db.close(); }
});

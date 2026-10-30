import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,C,callAs,schedule} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const cmd=async(db,u,op,input)=>(await callAs(db,'authenticated',u,'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS d',[op,crypto.randomUUID(),JSON.stringify(input)]))[0].d;
test('read receipts follow each deal and only signal advances',async()=>{
 const db=await setup(false);
 try {
  for(const p of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql','../outcomes/080_sale_confirmation.sql','../commercial/090_credit_batches.sql','../commercial/091_buyer_rewards.sql','../commercial/092_credit_settlement.sql','../chat/012_credit_qualification.sql','./207_offer_submission_fee.sql','./228_target_fee_policy.sql','./231_deal_chat_threads.sql']) await db.exec(await read(p));
  await db.query("SELECT hocalist.credit_deposit_internal($1,'deal-threads-test',4000,145,325,'test')",[B]);
  const deals=[];
  for(let i=0;i<2;i++){
   const r=await cmd(db,A,'request.create',{kind:'product',title:'Thread test '+i,description:'Synthetic item',condition:'used',quantity:1,budget_minimum_minor:1000,budget_maximum_minor:50000,currency_code:'USD',accepts_higher_offers:false,use_home_address:true,category_id:'20000000-0000-4000-8000-000000000001'});
   const o=await cmd(db,B,'offer.submit',{request_id:r.id,price_minor:20000,currency_code:'USD',message:'Seller opening message',image_media_ids:[],...schedule()});
   await cmd(db,A,'offer.select',{offer_id:o.id,revision_id:o.revisions[0].id,expected_offer_revision:o.revision});
   const c=await cmd(db,A,'conversation.open_offer',{offer_id:o.id});
   deals.push({offer:o.id,conversation:c.conversation_id});
  }
  const conversation=deals[0].conversation;
  await db.query('UPDATE hocalist.offers SET conversation_id=$1 WHERE id=$2',[conversation,deals[1].offer]);
  const target=async offer=>(await db.query('SELECT * FROM hocalist.credit_targets WHERE offer_id=$1',[offer])).rows[0];
  assert.equal(Number((await target(deals[0].offer)).charged_minor),0);
  const send=(u,offer,key,text)=>callAs(db,'authenticated',u,'SELECT hocalist.chat_deal_send($1,$2,$3,$4) AS d',[conversation,offer,key,text]);
  await send(B,deals[0].offer,'seller-a','First deal message');
  await send(A,deals[0].offer,'reply-a','Hello');
  await send(A,deals[0].offer,'reply-a','Hello');
  assert.equal(Number((await target(deals[0].offer)).charged_minor),145);
  assert.equal(Number((await target(deals[1].offer)).charged_minor),0);
  await assert.rejects(send(A,deals[1].offer,'reply-a','Hello'),/idempotency_conflict/);
  assert.equal(Number((await target(deals[1].offer)).charged_minor),0);
  await send(A,deals[1].offer,'reply-b','Hello about the second deal');
  assert.equal(Number((await target(deals[1].offer)).charged_minor),145);
  const messages=(await callAs(db,'authenticated',A,'SELECT hocalist.chat_deal_messages($1,$2,100,NULL) AS d',[conversation,deals[0].offer]))[0].d.items;
  assert.equal(messages.length,2);assert.ok(messages.every(m=>m.offer_id===deals[0].offer));
  const second=(await callAs(db,'authenticated',B,'SELECT hocalist.chat_deal_messages($1,$2,100,NULL) AS d',[conversation,deals[1].offer]))[0].d.items;
  assert.equal(second.length,1);
  await db.exec(await read('./232_deal_read_markers.sql'));
  await db.exec('CREATE TABLE hocalist.chat_change_signals(id bigint GENERATED ALWAYS AS IDENTITY, conversation_id uuid, created_at timestamptz DEFAULT now())');
  const repair=await read('../../supabase/migrations/20261026085605_chat_read_receipts.sql');
  await db.exec(repair);
  const page=async(u,offer)=>(await callAs(db,'authenticated',u,'SELECT hocalist.chat_deal_messages($1,$2,100,NULL) AS d',[conversation,offer]))[0].d.items;
  assert.equal((await page(A,deals[0].offer)).at(-1).read_by_counterpart,false);
  const mark=()=>callAs(db,'authenticated',B,'SELECT hocalist.chat_deal_mark_read($1,$2,$3) AS d',[conversation,deals[0].offer,messages.at(-1).id]);
  assert.equal((await mark())[0].d.unread_count,1);
  assert.equal((await page(A,deals[0].offer)).at(-1).read_by_counterpart,true);
  assert.equal((await page(A,deals[1].offer)).at(-1).read_by_counterpart,false);
  assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.chat_change_signals')).rows[0].n),1);
  await mark();
  assert.equal(Number((await db.query('SELECT count(*) AS n FROM hocalist.chat_change_signals')).rows[0].n),1);
  await assert.rejects(page(C,deals[0].offer),/access_denied/);
  await db.exec(repair);
  assert.equal((await page(A,deals[0].offer)).at(-1).read_by_counterpart,true);
 } finally {await db.close();}
});

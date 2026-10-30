import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,C,callAs,schedule} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('one participant thread retains independent confirmed deals and meeting decisions',async t=>{
 const db=await setup(false);
 const command=async(user,op,key,input)=>(await callAs(db,'authenticated',user,'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS d',[op,key,JSON.stringify(input)]))[0].d;
 const rpc=async(user,fn,args)=>(await callAs(db,'authenticated',user,fn,args))[0].d;
 try {
  for(const p of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql','../outcomes/080_sale_confirmation.sql','./192_confirmed_meeting_coordinates.sql']) await db.exec(await read(p));
  await db.exec(await read('./pair-chat-preflight.sql'));
  await db.exec(await read('./209_pair_conversations.sql'));
  const create=async(label,seller=B)=>{
   const request=await command(A,'request.create',`request-${label}`,{kind:'product',title:`Test ${label}`,description:'Test',condition:'used',quantity:1,budget_minimum_minor:1000,budget_maximum_minor:2000,currency_code:'USD',use_home_address:true});
   const offer=await command(seller,'offer.submit',`offer-${label}`,{request_id:request.id,price_minor:1500,currency_code:'USD',message:'Test',image_media_ids:[],...schedule()});
   const selected=await command(A,'offer.select',`select-${label}`,{offer_id:offer.id,revision_id:offer.revisions[0].id,expected_offer_revision:offer.revision});
   const opened=await command(A,'conversation.open_offer',`open-${label}`,{offer_id:offer.id});
   return {...selected,conversation_id:opened.conversation_id};
  };
  const a=await create('A');const b=await create('B');const outsider=await create('C',C);
  await t.test('two deals share one thread, a different seller stays isolated',async()=>{
   assert.equal(a.conversation_id,b.conversation_id);assert.notEqual(a.conversation_id,outsider.conversation_id);
   const deals=await rpc(A,'SELECT hocalist.chat_deals($1) AS d',[a.conversation_id]);
   assert.deepEqual(new Set(deals.items.map(x=>x.id)),new Set([a.id,b.id]));
   await assert.rejects(rpc(C,'SELECT hocalist.chat_deals($1) AS d',[a.conversation_id]),/meeting_access_denied/);
  });
  const proposal=(offer,key)=>rpc(B,'SELECT hocalist.meeting_propose($1,$2::jsonb,$3) AS d',[a.conversation_id,JSON.stringify({...schedule(),offer_id:offer.id}),key]);
  await t.test('seller confirmation must precede either participant proposing a meeting',async()=>{
   await assert.rejects(proposal(a,'too-early'),/confirm_seller_before_meeting/);
   for(const offer of [a,b]) await command(A,'purchase.select',`confirm-${offer.id}`,{offer_id:offer.id,expected_offer_revision:offer.revision});
   await assert.rejects(rpc(B,'SELECT hocalist.meeting_propose($1,$2::jsonb,$3) AS d',[a.conversation_id,JSON.stringify(schedule()),'ambiguous']),/meeting_offer_not_selected/);
  });
  const first=await proposal(a,'meeting-a');const second=await proposal(b,'meeting-b');
  await t.test('both meetings remain separate and only the other participant accepts',async()=>{
   assert.notEqual(first.id,second.id);assert.equal(first.offer_id,a.id);assert.equal(second.offer_id,b.id);
   await assert.rejects(rpc(B,'SELECT hocalist.meeting_respond($1,true,$2,$3) AS d',[first.id,first.revision,'self']),/meeting_self_accept/);
   const accepted=await rpc(A,'SELECT hocalist.meeting_respond($1,true,$2,$3) AS d',[first.id,first.revision,'accept-a']);
   assert.equal(accepted.status,'accepted');
   assert.equal((await db.query('SELECT status FROM hocalist.meetings WHERE id=$1',[second.id])).rows[0].status,'proposed');
   assert.deepEqual(await proposal(a,'meeting-a'),first);
  });
  await t.test('double apply preserves messages and client cannot call opening helper',async()=>{
   await db.exec(await read('./209_pair_conversations.sql'));
   await db.exec(await read('./pair-chat-verify.sql'));
   assert.equal((await db.query("SELECT has_function_privilege('authenticated','hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)','EXECUTE') AS allowed")).rows[0].allowed,false);
  });
 }finally{await db.close();}
});

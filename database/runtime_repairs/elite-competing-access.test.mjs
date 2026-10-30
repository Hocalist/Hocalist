import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,IDS,callAs} from '../commercial_completion/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('qualified deferred Elite can compare prices without early debit; private and role gates stay enforced',async()=>{
 const db=await createCommercialDb();try{
 for(const p of ['../chat/012_credit_qualification.sql','./207_offer_submission_fee.sql','./228_target_fee_policy.sql','./231_deal_chat_threads.sql','./235_paygo_payment_setup.sql','./236_paygo_collection.sql'])await db.exec(await read(p));
 await db.exec(await read('../../supabase/migrations/20261027065137_elite_deferred_initial_fee.sql'));
 await db.exec(await read('../../supabase/migrations/20261030144543_elite_competing_offer_access.sql'));
 await db.query("INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source) VALUES($1,'elite','admin') ON CONFLICT(user_id) DO UPDATE SET plan_code='elite'",[IDS.seller]);
 const req=crypto.randomUUID(),off=crypto.randomUUID(),target=crypto.randomUUID();
 await db.query("INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status,first_accepted_at,acceptance_expires_at) VALUES($1,$2,$3,'product','Synthetic competitor gate','used','active',now(),now()+interval '7 days')",[req,IDS.buyer,IDS.buyerMembership]);
 await db.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status,accepted_revision_id) VALUES($1,$2,$3,$4,$5,'selected',gen_random_uuid())",[off,req,IDS.buyer,IDS.seller,IDS.sellerMembership]);
 const batch=(await db.query("SELECT hocalist.credit_deposit_internal($1,$2,2000,155,375,'test') id",[IDS.seller,crypto.randomUUID()])).rows[0].id;
 await db.query("INSERT INTO hocalist.credit_targets(id,user_id,request_id,offer_id,batch_id,initial_minor,winning_minor,reserved_minor,week_start,rate_version) VALUES($1,$2,$3,$4,$5,155,375,375,current_date,'test')",[target,IDS.seller,req,off,batch]);
 const view=()=>callAs(db,'authenticated',IDS.seller,'SELECT hocalist.credit_view_competing_offers($1) d',[req]);
 await assert.rejects(view(),/offer_access_denied/);
 await db.query('UPDATE hocalist.credit_targets SET qualified_at=now() WHERE id=$1',[target]);
 assert.deepEqual((await view())[0].d,{offers:[],refund_eligible:false});
 const row=async()=>(await db.query('SELECT * FROM hocalist.credit_targets WHERE id=$1',[target])).rows[0];
 const stamp=(await row()).competitors_viewed_at;await view();assert.equal((await row()).competitors_viewed_at.getTime(),stamp.getTime());assert.equal(Number((await row()).charged_minor),0);
 await assert.rejects(callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.credit_view_competing_offers($1)',[req]),/offer_access_denied/);
 await db.query("UPDATE hocalist.seller_entitlements SET plan_code='pro' WHERE user_id=$1",[IDS.seller]);await assert.rejects(view(),/offer_access_denied/);
 }finally{await db.close();}
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,callAs,expectRejected,IDS} from '../commercial_completion/tests/fixture.mjs';

test('customer tools enforce sale ownership and plans; history is factual and notes private',async()=>{
 const db=await createCommercialDb({completion:false});
 try {
  await db.exec(await readFile(new URL('./248_seller_customer_tools.sql',import.meta.url),'utf8'));
  const req='30000000-0000-4000-8000-000000000001';
  const offer='40000000-0000-4000-8000-000000000001';
  const chat='60000000-0000-4000-8000-000000000001';
  const meeting='50000000-0000-4000-8000-000000000001';
  await db.exec(`INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status,address_line1)
    VALUES('${req}','${IDS.buyer}','${IDS.buyerMembership}','product','Customer test','used','closed','PRIVATE ADDRESS');
    INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
    VALUES('${offer}','${req}','${IDS.buyer}','${IDS.seller}','${IDS.sellerMembership}','completed');
    INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES('${chat}','targeted_request','${req}','${offer}');
    INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status)
    VALUES('${meeting}','${chat}','${req}','${offer}','${IDS.buyer}','${IDS.seller}','accepted');
    INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id)
    VALUES('${req}','${meeting}','${offer}',gen_random_uuid(),'${IDS.buyer}','${IDS.seller}');
    INSERT INTO hocalist.requests(buyer_user_id,buyer_profile_id,kind,title,condition,status)
    VALUES('${IDS.buyer}','${IDS.buyerMembership}','product','No purchase','used','cancelled'),
      ('${IDS.buyer}','${IDS.buyerMembership}','product','Still open','used','active');`);
  const list=user=>callAs(db,'authenticated',user,'SELECT hocalist.seller_customers() AS d');
  const save=(user,buyer,saved,note)=>callAs(db,'authenticated',user,'SELECT hocalist.seller_customer_save($1,$2,$3) AS d',[buyer,saved,note]);
  const insights=(user,buyer)=>callAs(db,'authenticated',user,'SELECT hocalist.seller_customer_insights($1) AS d',[buyer]);
  await expectRejected(list(IDS.seller),'contacts_plan_required');
  await db.query("INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source) VALUES($1,'pro','admin'),($2,'elite','admin')",[IDS.seller,IDS.seller2]);
  let data=(await list(IDS.seller))[0].d;
  assert.equal(data.items.length,1);assert.equal(data.insights_available,false);assert.equal(data.items[0].saved,false);
  assert.doesNotMatch(JSON.stringify(data),/PRIVATE ADDRESS|email|phone|coordinates/);
  await save(IDS.seller,IDS.buyer,true,'PRIVATE SELLER NOTE');
  await save(IDS.seller,IDS.buyer,true,'PRIVATE SELLER NOTE');
  assert.equal((await list(IDS.seller))[0].d.items[0].note,'PRIVATE SELLER NOTE');
  assert.equal((await list(IDS.seller2))[0].d.items.length,0);
  await expectRejected(save(IDS.seller2,IDS.buyer,true,'foreign'),'confirmed_customer_required');
  await expectRejected(insights(IDS.seller,IDS.buyer),'insights_plan_required');
  await expectRejected(insights(IDS.seller2,IDS.buyer),'customer_access_denied');
  await db.query("UPDATE hocalist.seller_entitlements SET plan_code='elite' WHERE user_id=$1",[IDS.seller]);
  data=(await insights(IDS.seller,IDS.buyer))[0].d;
  assert.deepEqual(data,{buyer_id:IDS.buyer,concluded_requests:2,confirmed_purchases:1,ongoing_requests:1,completion_percent:50});
  await save(IDS.seller,IDS.buyer,false,'');
  assert.equal((await list(IDS.seller))[0].d.items[0].saved,false);
  await assert.rejects(callAs(db,'authenticated',IDS.seller,'SELECT * FROM hocalist.seller_saved_customers'),{code:'42501'});
  await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE user_id=$1",[IDS.seller]);
  await assert.rejects(list(IDS.seller));
 }finally{await db.close();}
});

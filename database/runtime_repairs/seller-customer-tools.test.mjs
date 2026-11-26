import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,callAs,expectRejected,IDS} from '../commercial_completion/tests/fixture.mjs';

test('customer tools enforce sale ownership and plans; history is factual and notes private',async()=>{
 const db=await createCommercialDb({completion:false});
 try {
  await db.exec(await readFile(new URL('./248_seller_customer_tools.sql',import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../../supabase/migrations/20261125193543_elite_buyer_quota_and_lead_insights.sql',import.meta.url),'utf8'));
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
  const lead = (await db.query("SELECT id FROM hocalist.requests WHERE title='Still open'")).rows[0].id;
  const leadInsights = (user, request) => callAs(db,'authenticated',user,
   'SELECT hocalist.seller_lead_insights($1) AS d',[request]);
  await expectRejected(leadInsights(IDS.seller,lead),'insights_plan_required');
  await expectRejected(leadInsights(IDS.seller2,req),'request_access_denied');
  assert.deepEqual((await leadInsights(IDS.seller2,lead))[0].d,{request_id:lead,history:null});
  const expired = (await db.query(`INSERT INTO hocalist.requests
    (buyer_user_id,buyer_profile_id,kind,title,condition,status,first_accepted_at,acceptance_expires_at)
    SELECT $1,$2,'product','Expired by time','used','active',now()-interval '8 days',now()-interval '1 day'
    FROM generate_series(1,3) RETURNING id`,[IDS.buyer,IDS.buyerMembership])).rows;
  await expectRejected(leadInsights(IDS.seller2,expired[0].id),'request_access_denied');
  assert.deepEqual((await leadInsights(IDS.seller2,lead))[0].d,{request_id:lead,history:{
   concluded_requests:5,confirmed_purchases:1,ongoing_requests:1,completion_percent:20,
  }});
  const stillMeeting = expired[1].id;
  const meetingOffer = crypto.randomUUID();
  const meetingChat = crypto.randomUUID();
  await db.query(`INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
   VALUES($1,$2,$3,$4,$5,'selected')`,[meetingOffer,stillMeeting,IDS.buyer,IDS.seller,IDS.sellerMembership]);
  await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)",
   [meetingChat,stillMeeting,meetingOffer]);
  await db.query(`INSERT INTO hocalist.meetings(conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status,meeting_expires_at)
   VALUES($1,$2,$3,$4,$5,'accepted',now()+interval '1 day')`,[meetingChat,stillMeeting,meetingOffer,IDS.buyer,IDS.seller]);
  assert.equal((await leadInsights(IDS.seller2,lead))[0].d.history,null,
   'a still-valid meetup keeps the expired request ongoing and the sample below five');
  await db.query("UPDATE hocalist.meetings SET meeting_expires_at=now()-interval '1 minute' WHERE request_id=$1", [stillMeeting]);
  assert.equal((await leadInsights(IDS.seller2,lead))[0].d.history.concluded_requests,5);
  await expectRejected(callAs(db,'authenticated',IDS.seller2,'SELECT hocalist.seller_buyer_history_internal($1)',[IDS.buyer]),'permission denied');
  await db.query("UPDATE hocalist.seller_entitlements SET plan_code='elite' WHERE user_id=$1",[IDS.seller]);
  data=(await insights(IDS.seller,IDS.buyer))[0].d;
  assert.deepEqual(data,{buyer_id:IDS.buyer,concluded_requests:5,confirmed_purchases:1,ongoing_requests:1,completion_percent:20});
  await save(IDS.seller,IDS.buyer,false,'');
  assert.equal((await list(IDS.seller))[0].d.items[0].saved,false);
  await assert.rejects(callAs(db,'authenticated',IDS.seller,'SELECT * FROM hocalist.seller_saved_customers'),{code:'42501'});
  await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE user_id=$1",[IDS.seller]);
  await assert.rejects(list(IDS.seller));
 }finally{await db.close();}
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,callAs,expectRejected,IDS} from '../../commercial_completion/tests/fixture.mjs';
const sql=await readFile(new URL('../200_audit_reads.sql',import.meta.url),'utf8');
const verify=await readFile(new URL('../verify.sql',import.meta.url),'utf8');
const request='30000000-0000-4000-8000-000000000001',offer='40000000-0000-4000-8000-000000000001',conversation='60000000-0000-4000-8000-000000000001',meeting='50000000-0000-4000-8000-000000000001';
async function fixture(){
 const db=await createCommercialDb();
 await db.exec(`INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status) VALUES('${request}','${IDS.buyer}','${IDS.buyerMembership}','product','Audit sold lamp','used','closed');
 INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES('${offer}','${request}','${IDS.buyer}','${IDS.seller}','${IDS.sellerMembership}','completed');
 INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES('${conversation}','targeted_request','${request}','${offer}');
 INSERT INTO hocalist.conversation_members(conversation_id,user_id,profile_id,role) VALUES('${conversation}','${IDS.buyer}','${IDS.buyerMembership}','buyer'),('${conversation}','${IDS.seller}','${IDS.sellerMembership}','seller');
 INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status) VALUES('${meeting}','${conversation}','${request}','${offer}','${IDS.buyer}','${IDS.seller}','accepted');
 INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id) VALUES('${request}','${meeting}','${offer}',gen_random_uuid(),'${IDS.buyer}','${IDS.seller}');`);
 await db.exec(sql);return db;
}
test('retained request is participant-only, redacted, revoked/restricted fenced',async()=>{
 const db=await fixture();try{
 const row=(await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.marketplace_request($1) AS data',[request]))[0].data;
 assert.equal(row.title,'Audit sold lamp');assert.equal(row.verified_purchase_count,1);assert.equal('address_line1' in row,false);assert.equal('coordinates' in row,false);
 assert.equal((await db.query('SELECT hocalist.marketplace_offer_json($1) AS data',[offer])).rows[0].data.request_title,'Audit sold lamp');
 await expectRejected(callAs(db,'authenticated',IDS.seller2,'SELECT hocalist.marketplace_request($1)',[request]),'request_access_denied');
 await db.exec(`UPDATE hocalist.conversation_members SET revoked_at=now() WHERE user_id='${IDS.seller}';`);
 await expectRejected(callAs(db,'authenticated',IDS.seller,'SELECT hocalist.marketplace_request($1)',[request]),'request_access_denied');
 await db.exec(`UPDATE hocalist.memberships SET status='restricted' WHERE id='${IDS.buyerMembership}';`);
 await expectRejected(callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.marketplace_request($1)',[request]),'account_restricted');
 }finally{await db.close();}
});
test('full-history summary excludes completed meetings from active and denies outsiders',async()=>{
 const db=await fixture();try{
 assert.deepEqual((await callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.commercial_deal_summary() AS data'))[0].data,{completed:1,active:0,attention:0});
 await expectRejected(callAs(db,'authenticated',IDS.outsider,'SELECT hocalist.commercial_deal_summary()'),'role');
 await expectRejected(callAs(db,'anon','','SELECT hocalist.commercial_deal_summary()'),'permission denied');
 }finally{await db.close();}
});
test('canonical public store excludes all private and unapproved catalogue content',async()=>{
 const db=await fixture();try{
 await db.exec(`INSERT INTO hocalist.store_listings(seller_user_id,seller_profile_id,kind,title,description,price_label,status,moderation_status) VALUES
 ('${IDS.seller}','${IDS.sellerMembership}','product','Public lamp','Public description','$30','active','approved'),
 ('${IDS.seller}','${IDS.sellerMembership}','product','PRIVATE DRAFT','not public','$40','draft','approved'),
 ('${IDS.seller}','${IDS.sellerMembership}','service','PENDING','not public','$50','active','pending_review');`);
 const data=(await callAs(db,'anon','','SELECT hocalist.public_store($1) AS data',[IDS.sellerMembership]))[0].data;
 assert.equal(data.available,true);assert.deepEqual(data.items.map(i=>i.title),['Public lamp']);assert.equal('seller_user_id' in data.items[0],false);assert.equal('image_media_ids' in data.items[0],false);
 await db.exec(`UPDATE hocalist.memberships SET status='restricted' WHERE id='${IDS.sellerMembership}';`);
 assert.deepEqual((await callAs(db,'anon','','SELECT hocalist.public_store($1) AS data',[IDS.sellerMembership]))[0].data,{available:false});
 }finally{await db.close();}
});
test('baseline drift and repeated apply stop before mutation',async()=>{
 const db=await fixture();try{
 await db.exec(verify);
 await assert.rejects(()=>db.exec(sql),/Audit prerequisite drift/);await db.exec('ROLLBACK');
 assert.equal((await callAs(db,'authenticated',IDS.buyer,'SELECT hocalist.commercial_deal_summary() AS data'))[0].data.completed,1);
 await db.exec('GRANT EXECUTE ON FUNCTION hocalist.commercial_deal_summary() TO anon');
 await assert.rejects(()=>db.exec(verify),/Audit repair grant drift/);
 await db.exec('REVOKE EXECUTE ON FUNCTION hocalist.commercial_deal_summary() FROM anon');
 await db.exec("CREATE OR REPLACE FUNCTION hocalist.public_store(p_seller uuid) RETURNS jsonb LANGUAGE sql AS 'SELECT null::jsonb'");
 await assert.rejects(()=>db.exec(verify),/Audit repair verification drift/);
 }finally{await db.close();}
});

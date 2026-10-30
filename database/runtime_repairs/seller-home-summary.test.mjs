import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,callAs,IDS} from '../commercial_completion/tests/fixture.mjs';
test('seller homepage totals are private, monthly and independent of client pagination',async()=>{
 const db=await createCommercialDb();
 try {
  await db.exec(await readFile(new URL('./245_seller_home_summary.sql',import.meta.url),'utf8'));
  const summary=user=>callAs(db,'authenticated',user,'SELECT hocalist.seller_home_summary() AS d').then(rows=>rows[0].d);
  assert.equal((await summary(IDS.seller)).timezone,'UTC');
  assert.equal((await db.query('SELECT calendar_timezone FROM hocalist.entitlement_policy')).rows[0].calendar_timezone,null);
  await db.exec("UPDATE hocalist.entitlement_policy SET calendar_timezone='America/Chicago'");
  await assert.rejects(summary(IDS.buyer),/role_not_active/);
  await assert.rejects(summary(IDS.outsider),/role_not_active/);
  await assert.rejects(callAs(db,'anon',null,'SELECT hocalist.seller_home_summary()'),/permission denied/);
  const empty=await summary(IDS.seller); assert.equal(empty.leads_targeted,0);assert.equal(empty.deals_closed,0);
  const start=empty.month_start,end=empty.month_end;
  const batch=crypto.randomUUID();
  await db.query("INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,initial_fee_minor,winning_total_minor,rate_version) VALUES($1,$2,'summary-test',100000,100000,100,300,'test')",[batch,IDS.seller]);
  // 101 current-month records exceed the visible lists; boundary rows and
  // another seller must not inflate this caller's totals.
  for(let i=0;i<104;i++){
    const request=crypto.randomUUID(),offer=crypto.randomUUID(),conversation=crypto.randomUUID(),meeting=crypto.randomUUID();
    const seller=i===103?IDS.seller2:IDS.seller;
    const member=i===103?IDS.seller2Membership:IDS.sellerMembership;
    const timestamp=i===101?new Date(new Date(start).getTime()-1).toISOString():i===102?end:start;
    await db.query("INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status) VALUES($1,$2,$3,'product','Summary test','used','closed')",[request,IDS.buyer,IDS.buyerMembership]);
    await db.query("INSERT INTO hocalist.credit_targets(user_id,request_id,batch_id,initial_minor,winning_minor,reserved_minor,week_start,created_at) VALUES($1,$2,$3,100,300,0,current_date,$4)",[seller,request,batch,timestamp]);
    if(i>=4 && i<101)continue;
    await db.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES($1,$2,$3,$4,$5,'completed')",[offer,request,IDS.buyer,seller,member]);
    await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)",[conversation,request,offer]);
    await db.query("INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status) VALUES($1,$2,$3,$4,$5,$6,'accepted')",[meeting,conversation,request,offer,IDS.buyer,seller]);
    await db.query('INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id,confirmed_at) VALUES($1,$2,$3,$4,$5,$6,$7)',[request,meeting,offer,crypto.randomUUID(),IDS.buyer,seller,timestamp]);
  }
  const totals=await summary(IDS.seller); assert.equal(totals.leads_targeted,101);assert.equal(totals.deals_closed,4);
  assert.equal(totals.timezone,'America/Chicago');
  const other=await summary(IDS.seller2);assert.equal(other.leads_targeted,1);assert.equal(other.deals_closed,1);
  await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE user_id=$1",[IDS.seller]);
  await assert.rejects(summary(IDS.seller),/account_restricted/);
 } finally {await db.close();}
});

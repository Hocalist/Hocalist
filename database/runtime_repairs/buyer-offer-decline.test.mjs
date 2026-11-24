import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb, IDS, callAs} from '../commercial_completion/tests/fixture.mjs';

test('buyer decline is private, replayable, releases the hold and preserves the chat', async () => {
  const db = await createCommercialDb();
  try {
    const cancellation = await readFile(new URL('./281_home_and_meeting_actions.sql', import.meta.url),'utf8');
    await db.exec(cancellation.split('-- Preserve the installed')[0] + '\nCOMMIT;');
    await db.exec(await readFile(new URL('../../supabase/migrations/20261120111441_buyer_offer_decline.sql', import.meta.url),'utf8'));
    const request=crypto.randomUUID(), offer=crypto.randomUUID(), conversation=crypto.randomUUID();
    await db.query(`INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
      VALUES($1,$2,$3,'product','Desk','used','active')`,[request,IDS.buyer,IDS.buyerMembership]);
    await db.query(`INSERT INTO hocalist.conversations(id,origin,request_id) VALUES($1,'targeted_request',$2)`,[conversation,request]);
    await db.query(`INSERT INTO hocalist.conversation_members(conversation_id,user_id,profile_id,role)
      VALUES($1,$2,$3,'buyer'),($1,$4,$5,'seller')`,[conversation,IDS.buyer,IDS.buyerMembership,IDS.seller,IDS.sellerMembership]);
    await db.query(`INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status,conversation_id)
      VALUES($1,$2,$3,$4,$5,'selected',$6)`,[offer,request,IDS.buyer,IDS.seller,IDS.sellerMembership,conversation]);
    const revision=(await db.query(`INSERT INTO hocalist.offer_revisions(offer_id,sequence,price_minor,currency_code,
      schedule_date,schedule_time,schedule_timezone,schedule_offset_minutes,schedule_instant,place_choice,status,proposed_by_user_id)
      VALUES($1,1,65000,'USD',current_date,'15:00','America/Chicago',-360,now(),'seller_business','accepted',$2) RETURNING id`,[offer,IDS.seller])).rows[0].id;
    await db.query('UPDATE hocalist.offers SET accepted_revision_id=$1 WHERE id=$2',[revision,offer]);
    await db.query('UPDATE hocalist.requests SET purchase_offer_id=$1 WHERE id=$2',[offer,request]);
    const batch=(await db.query("SELECT hocalist.credit_deposit_internal($1,gen_random_uuid()::text,2000,200,450,'test') AS id",[IDS.seller])).rows[0].id;
    await db.query(`INSERT INTO hocalist.credit_targets(user_id,request_id,offer_id,batch_id,initial_minor,winning_minor,reserved_minor,week_start,status)
      VALUES($1,$2,$3,$4,200,450,450,current_date,'reserved')`,[IDS.seller,request,offer,batch]);
    await db.query('UPDATE hocalist.credit_batches SET reserved_minor=450 WHERE id=$1',[batch]);
    const decline=(user,key='decline',rev=1)=>callAs(db,'authenticated',user,
      'SELECT hocalist.buyer_decline_offer($1,$2,$3) AS result',[offer,rev,key]);
    await assert.rejects(decline(IDS.seller), /role|access/);
    await assert.rejects(decline(IDS.buyer,'stale',2), /revision_conflict/);
    const meeting=crypto.randomUUID();
    await db.query(`INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status)
      VALUES($1,$2,$3,$4,$5,$6,'accepted')`,[meeting,conversation,request,offer,IDS.buyer,IDS.seller]);
    await assert.rejects(decline(IDS.buyer,'confirmed'), /meeting_details_required/);
    assert.equal((await db.query('SELECT status FROM hocalist.offers WHERE id=$1',[offer])).rows[0].status,'selected');
    await db.query("UPDATE hocalist.meetings SET status='proposed' WHERE id=$1",[meeting]);
    const result=await decline(IDS.buyer);
    assert.equal(result[0].result.status,'declined');
    assert.deepEqual(await decline(IDS.buyer),result);
    await assert.rejects(decline(IDS.buyer,'decline',2),/idempotency_conflict/);
    const row=(await db.query('SELECT status,conversation_id,revision FROM hocalist.offers WHERE id=$1',[offer])).rows[0];
    assert.deepEqual(row,{status:'declined',conversation_id:conversation,revision:2});
    const req=(await db.query('SELECT status,purchase_offer_id FROM hocalist.requests WHERE id=$1',[request])).rows[0];
    assert.deepEqual(req,{status:'active',purchase_offer_id:null});
    const wallet=(await db.query('SELECT balance_minor,reserved_minor FROM hocalist.credit_batches WHERE id=$1',[batch])).rows[0];
    assert.equal(Number(wallet.reserved_minor),0);
    assert.equal(Number(wallet.balance_minor),2000);
    assert.equal((await db.query('SELECT status FROM hocalist.meetings WHERE id=$1',[meeting])).rows[0].status,'cancelled');
    assert.equal((await db.query('SELECT reason FROM hocalist.meeting_cancellation_reasons WHERE meeting_id=$1',[meeting])).rows[0].reason,'Buyer declined offer');
    assert.equal((await db.query('SELECT count(*) AS n FROM hocalist.conversations WHERE id=$1',[conversation])).rows[0].n,1);
  } finally { await db.close(); }
});

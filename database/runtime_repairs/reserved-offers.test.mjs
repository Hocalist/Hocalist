import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createCommercialDb, IDS, callAs } from '../commercial_completion/tests/fixture.mjs';

test('reserved credit details include older offers and are scoped to their seller', async () => {
  const db = await createCommercialDb();
  try {
    for (const path of [
      '../chat/012_credit_qualification.sql', './207_offer_submission_fee.sql',
      './228_target_fee_policy.sql', './231_deal_chat_threads.sql',
      './235_paygo_payment_setup.sql', './236_paygo_collection.sql', './237_paygo_event_reconciliation.sql',
      '../../supabase/migrations/20261027065137_elite_deferred_initial_fee.sql',
      './283_wallet_reserved_offers.sql',
    ]) {
      await db.exec(await readFile(new URL(path, import.meta.url), 'utf8'));
    }
    const batch = (await db.query(
      "SELECT hocalist.credit_deposit_internal($1, gen_random_uuid()::text, 2000, 155, 375, 'test') AS id",
      [IDS.seller])).rows[0].id;
    let heldOffer;
    for (let index = 0; index <= 50; index++) {
      const request = crypto.randomUUID(), offer = crypto.randomUUID();
      const active = index === 0;
      await db.query(`INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
        VALUES ($1,$2,$3,'product',$4,'used','active')`, [request, IDS.buyer, IDS.buyerMembership, 'Desk ' + index]);
      await db.query(`INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
        VALUES ($1,$2,$3,$4,$5,'submitted')`, [offer,request,IDS.buyer,IDS.seller,IDS.sellerMembership]);
      await db.query(`INSERT INTO hocalist.credit_targets(user_id,request_id,offer_id,batch_id,initial_minor,
        winning_minor,reserved_minor,week_start,status,created_at) VALUES
        ($1,$2,$3,$4,155,375,$5,current_date,$6,now() - $7::interval)`,
        [IDS.seller,request,offer,batch,active ? 375 : 0,active ? 'reserved' : 'released',
         active ? '1 hour' : '1 second']);
      if (active) heldOffer = offer;
    }
    await db.query('UPDATE hocalist.credit_batches SET reserved_minor=375 WHERE id=$1', [batch]);
    const wallet = async (id) => (await callAs(db,'authenticated',id,
      'SELECT hocalist.commercial_credit_wallet() AS wallet'))[0].wallet;
    const mine = await wallet(IDS.seller);
    assert.equal(mine.targets.length, 50);
    assert.ok(!mine.targets.some(target => target.offer_id === heldOffer));
    assert.deepEqual(mine.reserved_offers.map(o => [o.offer_id,o.held_minor,o.next_step]),
      [[heldOffer,375,'buyer_response']]);
    assert.equal(mine.reserved_minor, 375);
    assert.deepEqual((await wallet(IDS.seller2)).reserved_offers, []);
  } finally {
    await db.close();
  }
});

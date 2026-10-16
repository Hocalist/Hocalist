// Commercial reads proof (migration 184).
//
// Authoritative credit/reward wallet projections, per-batch breakdown, weekly
// quota separation, held/available reward split with reversal holds, role-aware
// sale history and participant-only drill-down. PGlite deterministic proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createCommercialDb, callAs, expectRejected, IDS } from './fixture.mjs';

const { buyer, seller, seller2, outsider, admin } = IDS;

const B1 = '80000000-0000-4000-8004-000000000001';
const B2 = '80000000-0000-4000-8004-000000000002';
const T1 = '81000000-0000-4000-8004-000000000001';
const T2 = '81000000-0000-4000-8004-000000000002';
const T3 = '81000000-0000-4000-8004-000000000003';
const O1 = '70000000-0000-4000-8004-000000000001';
const O2 = '70000000-0000-4000-8004-000000000002';
const R1 = '82000000-0000-4000-8004-000000000001';
const R2 = '82000000-0000-4000-8004-000000000002';

async function seedWallet(db) {
  await db.exec(`
    INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
    VALUES('30000000-0000-4000-8004-000000000001','${buyer}','${IDS.buyerMembership}',
        'product','Sold laptop','used','closed'),
          ('30000000-0000-4000-8004-000000000002','${buyer}','${IDS.buyerMembership}',
        'product','Sold camera','used','closed');
    INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status,
      accepted_revision_id)
    VALUES('40000000-0000-4000-8004-000000000001','30000000-0000-4000-8004-000000000001',
        '${buyer}','${seller}','${IDS.sellerMembership}','completed',
        '41000000-0000-4000-8004-000000000001'),
          ('40000000-0000-4000-8004-000000000002','30000000-0000-4000-8004-000000000002',
        '${buyer}','${seller2}','${IDS.seller2Membership}','selected',
        '41000000-0000-4000-8004-000000000002');
    INSERT INTO hocalist.offer_revisions(id,offer_id,sequence,price_minor,currency_code,message,
      schedule_date,schedule_time,schedule_timezone,schedule_offset_minutes,schedule_instant,
      place_choice,place_label,status,proposed_by_user_id)
    VALUES('41000000-0000-4000-8004-000000000001','40000000-0000-4000-8004-000000000001',1,42000,'USD','',
        '2026-11-05','18:30','America/New_York',-240,'2026-11-05T22:30:00Z','specific_place','Place A','accepted','${seller}'),
          ('41000000-0000-4000-8004-000000000002','40000000-0000-4000-8004-000000000002',1,15000,'USD','',
        '2026-11-06','18:30','America/New_York',-240,'2026-11-06T22:30:00Z','specific_place','Place B','accepted','${seller2}');
    INSERT INTO hocalist.conversations(id,origin,request_id,offer_id)
    VALUES('60000000-0000-4000-8004-000000000001','targeted_request',
        '30000000-0000-4000-8004-000000000001','40000000-0000-4000-8004-000000000001'),
          ('60000000-0000-4000-8004-000000000002','targeted_request',
        '30000000-0000-4000-8004-000000000002','40000000-0000-4000-8004-000000000002');
    INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,
      status,meeting_expires_at)
    VALUES('50000000-0000-4000-8004-000000000001','60000000-0000-4000-8004-000000000001',
        '30000000-0000-4000-8004-000000000001','40000000-0000-4000-8004-000000000001',
        '${buyer}','${seller}','accepted',now()+interval '1 day'),
          ('50000000-0000-4000-8004-000000000002','60000000-0000-4000-8004-000000000002',
        '30000000-0000-4000-8004-000000000002','40000000-0000-4000-8004-000000000002',
        '${buyer}','${seller2}','accepted',now()+interval '1 day');
    INSERT INTO hocalist.sale_confirmations(id,request_id,meeting_id,offer_id,schedule_revision_id,
      buyer_user_id,seller_user_id,confirmed_at)
    VALUES('${O1}','30000000-0000-4000-8004-000000000001','50000000-0000-4000-8004-000000000001',
        '40000000-0000-4000-8004-000000000001',gen_random_uuid(),'${buyer}','${seller}',
        now()-interval '2 days'),
          ('${O2}','30000000-0000-4000-8004-000000000002','50000000-0000-4000-8004-000000000002',
        '40000000-0000-4000-8004-000000000002',gen_random_uuid(),'${buyer}','${seller2}',
        now()-interval '1 day');
    INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,
      reserved_minor,initial_fee_minor,winning_total_minor,rate_version,created_at)
    VALUES('${B1}','${seller}','dep-w1',4000,3625,0,155,375,'v40',now()-interval '10 days'),
          ('${B2}','${seller}','dep-w2',2000,1845,220,155,375,'v20',now()-interval '5 days');
    INSERT INTO hocalist.credit_targets(id,user_id,request_id,batch_id,offer_id,initial_minor,winning_minor,
      charged_minor,reserved_minor,status,week_start,rate_version)
    VALUES('${T1}','${seller}','30000000-0000-4000-8004-000000000001','${B1}',
        '40000000-0000-4000-8004-000000000001',155,375,375,0,'won',
        date_trunc('week',now() AT TIME ZONE 'UTC')::date,'v40'),
          ('${T2}','${seller}','30000000-0000-4000-8004-000000000002','${B2}',
        '40000000-0000-4000-8004-000000000002',155,375,155,220,'initial_charged',
        date_trunc('week',now() AT TIME ZONE 'UTC')::date,'v20');
    INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,
      reserved_minor,initial_fee_minor,winning_total_minor,rate_version)
    VALUES('83000000-0000-4000-8004-000000000001','${seller2}','dep-w3',500,500,200,100,200,'v1');
    INSERT INTO hocalist.credit_targets(id,user_id,request_id,batch_id,offer_id,initial_minor,winning_minor,
      charged_minor,reserved_minor,status,week_start,rate_version)
    VALUES('${T3}','${seller2}','30000000-0000-4000-8004-000000000002',
        '83000000-0000-4000-8004-000000000001',
        '40000000-0000-4000-8004-000000000002',100,200,0,200,'reserved',
        date_trunc('week',now() AT TIME ZONE 'UTC')::date,'v1');
    INSERT INTO hocalist.buyer_rewards(id,outcome_id,target_id,buyer_user_id,amount_minor,rule_version,created_at)
    VALUES('${R1}','${O1}','${T1}','${buyer}',15,'reward-v1',now()-interval '2 days'),
          ('${R2}','${O2}','${T3}','${buyer}',15,'reward-v1',now()-interval '1 day');
  `);
}

const creditWallet = (db, user) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.commercial_credit_wallet() AS data')
    .then((rows) => rows[0].data);

const rewardWallet = (db, user) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.commercial_reward_wallet() AS data')
    .then((rows) => rows[0].data);

test('the seller wallet matches the ledger and keeps quota separate', async () => {
  const db = await createCommercialDb();
  try {
    await seedWallet(db);
    const data = await creditWallet(db, seller);
    assert.equal(data.currency, 'HC');
    assert.equal(data.balance_minor, 5470);
    assert.equal(data.reserved_minor, 220);
    assert.equal(data.available_minor, 5250);
    assert.equal(data.charged_minor, 530);
    assert.equal(data.deposited_minor, 6000);
    assert.equal(data.weekly.used, 2);
    assert.equal(data.weekly.limit, 10);
    assert.equal(data.policy.deposit_options_configured, false);
    assert.equal(data.deposit_options.length, 0);

    const b1 = data.batches.find((b) => b.id === B1);
    const b2 = data.batches.find((b) => b.id === B2);
    assert.equal(b1.rate_version, 'v40');
    assert.equal(b1.winning_total_minor, 375);
    assert.equal(b1.charged_minor, 375);
    assert.equal(b1.available_minor, 3625);
    assert.equal(b2.rate_version, 'v20');
    assert.equal(b2.charged_minor, 155);
    assert.equal(b2.reserved_minor, 220);
    assert.equal(b2.available_minor, 1625);

    const t2 = data.targets.find((t) => t.id === T2);
    assert.equal(t2.request_title, 'Sold camera');
    assert.equal(t2.status, 'initial_charged');
    assert.equal(t2.charged_minor, 155);
    assert.equal(t2.reserved_minor, 220);
    assert.equal(t2.rate_version, 'v20');

    await db.exec(`
      INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version)
      VALUES(4000,145,325,'v40');
    `);
    const withOptions = await creditWallet(db, seller);
    assert.equal(withOptions.policy.deposit_options_configured, true);
    assert.equal(withOptions.deposit_options[0].amount_minor, 4000);
    assert.equal(withOptions.deposit_options[0].initial_fee_minor, 145);

    await expectRejected(creditWallet(db, buyer), 'wallet_access_denied', '42501');
    await expectRejected(creditWallet(db, outsider), 'wallet_access_denied', '42501');
  } finally {
    await db.close();
  }
});

test('the buyer reward wallet separates earned, held and available', async () => {
  const db = await createCommercialDb();
  try {
    await seedWallet(db);
    const data = await rewardWallet(db, buyer);
    assert.equal(data.currency, 'USD');
    assert.equal(data.earned_minor, 15);
    assert.equal(data.pending_minor, 15);
    assert.equal(data.held_minor, 15);
    assert.equal(data.available_minor, 15);
    assert.equal(data.withdrawal.configured, true);
    assert.equal(data.withdrawal.minimum_minor, 2000);
    assert.equal(data.withdrawal.fee_minor, 250);
    assert.equal(data.withdrawal.email_verified, false);
    assert.equal(data.payout.provider_configured, false);
    assert.equal(data.payout.execution_enabled, false);
    assert.equal(data.reversal_policy.reward_hold_configured, false);
    const earned = data.items.find((i) => i.id === R1);
    const held = data.items.find((i) => i.id === R2);
    assert.equal(earned.status, 'earned');
    assert.equal(earned.item_title, 'Sold laptop');
    assert.equal(held.status, 'held');

    // A configured reversal hold reduces the available amount.
    await db.exec(`
      UPDATE hocalist.reversal_policy SET reward_hold_enabled=true;
      INSERT INTO hocalist.payment_reversals(id,provider_key,provider_reference,kind,scope,amount_minor,
        causal_outcome_id,state)
      VALUES('90000000-0000-4000-8004-000000000001','test','ref-1','chargeback','buyer_reward',15,
        '${O1}','open');
      INSERT INTO hocalist.ledger_corrections(reversal_id,target_kind,target_id,entry_kind,
        amount_minor,actor)
      VALUES('90000000-0000-4000-8004-000000000001','buyer_reward','${R1}','reward_hold',15,'admin');
    `);
    const held2 = await rewardWallet(db, buyer);
    assert.equal(held2.earned_minor, 15);
    assert.equal(held2.held_minor, 30);
    assert.equal(held2.available_minor, 0);

    await expectRejected(rewardWallet(db, seller), 'wallet_access_denied', '42501');
    await expectRejected(rewardWallet(db, outsider), 'wallet_access_denied', '42501');
  } finally {
    await db.close();
  }
});

test('sale history is role-aware, paged and drill-down is participant-only', async () => {
  const db = await createCommercialDb();
  try {
    await seedWallet(db);
    const purchases = await callAs(db, 'authenticated', buyer,
      'SELECT hocalist.commercial_sale_history(NULL,NULL) AS data')
      .then((rows) => rows[0].data.items);
    assert.equal(purchases.length, 2);
    assert.ok(purchases.every((row) => row.side === 'purchase'));
    assert.equal(purchases[0].id, O2);
    assert.equal(purchases[0].title, 'Sold camera');
    assert.equal(purchases[0].reward.status, 'held');
    assert.equal(purchases[0].fee, null);
    assert.equal(purchases[1].reward.status, 'earned');

    // Cursor paging returns the older item.
    const page = await callAs(db, 'authenticated', buyer,
      'SELECT hocalist.commercial_sale_history($1,$2) AS data',
      [purchases[0].confirmed_at, purchases[0].id]).then((rows) => rows[0].data.items);
    assert.equal(page.length, 1);
    assert.equal(page[0].id, O1);

    const sales = await callAs(db, 'authenticated', seller,
      'SELECT hocalist.commercial_sale_history(NULL,NULL) AS data')
      .then((rows) => rows[0].data.items);
    assert.equal(sales.length, 1);
    assert.equal(sales[0].side, 'sale');
    assert.equal(sales[0].reward, null);
    assert.equal(sales[0].fee.status, 'won');
    assert.equal(sales[0].fee.charged_minor, 375);
    assert.equal(sales[0].fee.rate_version, 'v40');

    const detail = await callAs(db, 'authenticated', seller,
      'SELECT hocalist.commercial_sale_detail($1) AS data', [O1])
      .then((rows) => rows[0].data);
    assert.equal(detail.side, 'sale');
    assert.equal(detail.title, 'Sold laptop');
    assert.equal(detail.item_payment, 'offline');
    assert.equal(detail.fee.charged_minor, 375);
    assert.equal(detail.reward.amount_minor, 15);

    const buyerDetail = await callAs(db, 'authenticated', buyer,
      'SELECT hocalist.commercial_sale_detail($1) AS data', [O1])
      .then((rows) => rows[0].data);
    assert.equal(buyerDetail.side, 'purchase');
    assert.equal(buyerDetail.reward.status, 'earned');

    await expectRejected(
      callAs(db, 'authenticated', outsider,
        'SELECT hocalist.commercial_sale_detail($1)', [O1]),
      'sale_access_denied',
      '42501',
    );
    const outsiderHistory = await callAs(db, 'authenticated', outsider,
      'SELECT hocalist.commercial_sale_history(NULL,NULL) AS data')
      .then((rows) => rows[0].data.items);
    assert.equal(outsiderHistory.length, 0);
  } finally {
    await db.close();
  }
});

test('withdrawal admission shares the wallet holds rule', async () => {
  const db = await createCommercialDb();
  try {
    await seedWallet(db);
    await db.exec(`
      UPDATE auth.users SET email_confirmed_at=now(), phone_confirmed_at=now()
      WHERE id='${buyer}';
      UPDATE hocalist.buyer_rewards SET amount_minor=12000 WHERE id='${R1}';
      INSERT INTO hocalist.withdrawal_requests(user_id,client_key,amount_minor,fee_minor,net_minor,status,
        provider,provider_reference)
      VALUES('${buyer}','already-paid',3000,250,2750,'paid','fake_payout','transfer_paid');
    `);
    const adminCommand = (key, input) =>
      callAs(db, 'authenticated', admin,
        'SELECT hocalist.reversal_admin_command($1,$2,$3::jsonb) AS result',
        ['policy.set', key, JSON.stringify(input)]).then((rows) => rows[0].result);
    await adminCommand('policy-paid', { reward_hold_enabled: true });

    const open = await db.query(
      "INSERT INTO hocalist.payment_reversals(provider_key,provider_reference,kind,scope,amount_minor,causal_outcome_id,state) VALUES('t','held-4000','chargeback','buyer_reward',4000,$1,'open') RETURNING id",
      [O1]).then((r) => r.rows[0].id);
    await callAs(db, 'authenticated', admin,
      'SELECT hocalist.reversal_admin_command($1,$2,$3::jsonb) AS result',
      ['reversal.hold', 'hold-4000', JSON.stringify({ reversal_id: open })]);
    // The direct-policy helper mirrors the wallet's single deduction rule.
    const rule = await db.query(
      'SELECT hocalist.withdrawal_available_minor($1) AS available', [buyer]);
    assert.equal(rule.rows[0].available, 5000);

    const walletView = await rewardWallet(db, buyer);
    assert.equal(walletView.earned_minor, 12000);
    assert.equal(walletView.paid_minor, 3000);
    assert.equal(walletView.hold_minor, 4000);
    assert.equal(walletView.available_minor, 5000);
    const status = await callAs(db, 'authenticated', buyer,
      'SELECT hocalist.withdrawal_status() AS data').then((rows) => rows[0].data);
    assert.equal(status.available_minor, 5000);

    // The authenticated command must refuse held funds.
    await expectRejected(
      callAs(db, 'authenticated', buyer,
        "SELECT hocalist.withdrawal_request('held-money',6000)"),
      'insufficient_earned_balance',
      'P0001',
    );
    const ok = await callAs(db, 'authenticated', buyer,
      "SELECT hocalist.withdrawal_request('held-ok',2000) AS data").then((rows) => rows[0].data);
    assert.equal(ok.status, 'processing');
    // Held funds cannot be spent by a second sequential request either.
    await expectRejected(
      callAs(db, 'authenticated', buyer,
        "SELECT hocalist.withdrawal_request('held-more',4000)"),
      'insufficient_earned_balance',
      'P0001',
    );
    const after = await rewardWallet(db, buyer);
    assert.equal(after.available_minor, 3000);
  } finally {
    await db.close();
  }
});

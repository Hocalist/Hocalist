// Entitlement lifecycle proof (migration 180).
//
// Verified-source resolution, the settled seven-sale threshold, explicit
// unconfigured states for the unapproved calendar/overlap/annual/trial/
// downgrade rules, admin-only configuration, idempotency and grant fences.
// PGlite is single-connection deterministic proof, not live JWT proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  createCommercialDb,
  callAs,
  expectRejected,
  IDS,
} from './fixture.mjs';

const { buyer, seller, seller2, outsider, admin } = IDS;

const entitlement = (db, user) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.account_entitlement() AS data')
    .then((rows) => rows[0].data);

const adminCommand = (db, user, op, key, input) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.entitlement_admin_command($1,$2,$3::jsonb) AS result',
    [op, key, JSON.stringify(input)]).then((rows) => rows[0].result);

async function seedSevenPreviousMonthSales(db) {
  await db.exec(`
    INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
    SELECT ('30000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      '${buyer}','${IDS.buyerMembership}','product','Sold '||i,'used','closed'
    FROM generate_series(1,7) i;
    INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
    SELECT ('40000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      ('30000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      '${buyer}','${seller}','${IDS.sellerMembership}','completed'
    FROM generate_series(1,7) i;
    INSERT INTO hocalist.conversations(id,origin,request_id,offer_id)
    SELECT ('60000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'targeted_request',
      ('30000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      ('40000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid
    FROM generate_series(1,7) i;
    INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status,meeting_expires_at)
    SELECT ('50000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      ('60000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      ('30000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      ('40000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      '${buyer}','${seller}','accepted',now()
    FROM generate_series(1,7) i;
    INSERT INTO hocalist.sale_confirmations(id,request_id,meeting_id,offer_id,schedule_revision_id,
      buyer_user_id,seller_user_id,confirmed_at)
    SELECT ('70000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      ('30000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      ('50000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      ('40000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      gen_random_uuid(),'${buyer}','${seller}',
      date_trunc('month',now() AT TIME ZONE 'UTC') - interval '1 month' + make_interval(days => i)
    FROM generate_series(1,7) i;
  `);
}

test('unapproved entitlement rules stay explicitly unconfigured', async () => {
  const db = await createCommercialDb();
  try {
    const data = await entitlement(db, seller);
    assert.equal(data.effective_plan, 'free');
    assert.equal(data.effective_source, 'free');
    assert.equal(data.policy.earned_pro_threshold, 7);
    assert.equal(data.policy.calendar_configured, false);
    assert.equal(data.policy.paid_overlap_configured, false);
    assert.equal(data.policy.downgrade_visibility_configured, false);
    assert.equal(data.policy.annual_enabled, false);
    assert.equal(data.policy.trial_days, null);
    assert.equal(data.verified.earned.configured, false);
    assert.equal(data.verified.earned.unavailable_reason, 'calendar_unconfigured');
    assert.equal(data.verified.earned.progress, undefined);
    assert.equal(data.annual.available, false);
    assert.equal(data.trial.available, false);
    // Settled plan values are reported, not invented.
    const free = data.plans.find((p) => p.plan_code === 'free');
    const pro = data.plans.find((p) => p.plan_code === 'pro');
    const elite = data.plans.find((p) => p.plan_code === 'elite');
    assert.deepEqual(
      [free.store_listing_limit, pro.store_listing_limit, elite.store_listing_limit],
      [3, 15, 50],
    );
    assert.deepEqual(
      [free.weekly_target_limit, pro.weekly_target_limit, elite.weekly_target_limit],
      [10, 50, 100],
    );
    assert.equal(data.store_listing.limit, 3);
  } finally {
    await db.close();
  }
});

test('seven verified sales grant following-month Pro once configured', async () => {
  const db = await createCommercialDb();
  try {
    await seedSevenPreviousMonthSales(db);
    const before = await entitlement(db, seller);
    // The threshold is settled but counting is unavailable until configured.
    assert.equal(before.verified.earned.configured, false);
    assert.equal(before.effective_plan, 'free');

    await adminCommand(db, admin, 'policy.set', 'calendar-1', {
      calendar_timezone: 'UTC',
    });
    const after = await entitlement(db, seller);
    assert.equal(after.verified.earned.configured, true);
    assert.equal(after.verified.earned.unavailable_reason, null);
    assert.equal(after.verified.earned.qualifying_window.sales, 7);
    assert.equal(after.verified.earned.plan, 'pro');
    assert.equal(after.verified.earned.applied, true);
    assert.equal(after.effective_plan, 'pro');
    assert.equal(after.effective_source, 'earned');
    assert.equal(after.verified.earned.current_window.sales, 0);

    // Six sales are not enough.
    await db.exec(`
      DELETE FROM hocalist.sale_confirmations
      WHERE seller_user_id='${seller}'
        AND id='70000000-0000-4000-8000-000000000007';
    `);
    const six = await entitlement(db, seller);
    assert.equal(six.verified.earned.qualifying_window.sales, 6);
    assert.equal(six.verified.earned.plan, null);
    assert.equal(six.effective_plan, 'free');
  } finally {
    await db.close();
  }
});

test('paid and earned overlap follows only a configured rule', async () => {
  const db = await createCommercialDb();
  try {
    await seedSevenPreviousMonthSales(db);
    await adminCommand(db, admin, 'policy.set', 'calendar-1', {
      calendar_timezone: 'UTC',
    });
    await db.exec(`
      INSERT INTO hocalist.stripe_test_subscriptions(
        membership_id,subscription_id,plan_code,provider_status,paid_until,cancel_at_period_end)
      VALUES('${IDS.sellerMembership}','sub_test_1','pro','active',now()+interval '20 days',false);
    `);
    const unconfigured = await entitlement(db, seller);
    assert.equal(unconfigured.effective_plan, 'pro');
    assert.equal(unconfigured.effective_source, 'billing');
    assert.equal(unconfigured.verified.earned.applied, false);
    assert.equal(unconfigured.verified.earned.overlap_unconfigured, true);

    // elapsed/stale paid record never grants a plan
    await db.exec(`
      UPDATE hocalist.stripe_test_subscriptions SET paid_until=now()-interval '1 day';
    `);
    const stale = await entitlement(db, seller);
    assert.equal(stale.verified.billing.available, false);
    assert.equal(stale.effective_plan, 'pro');
    assert.equal(stale.effective_source, 'earned');
    assert.equal(stale.verified.earned.applied, true);

    await db.exec(`
      UPDATE hocalist.stripe_test_subscriptions
        SET paid_until=now()+interval '20 days', plan_code='elite';
    `);
    await adminCommand(db, admin, 'policy.set', 'overlap-1', {
      paid_overlap: 'earned_priority',
    });
    const elite = await entitlement(db, seller);
    // An earned Pro never silently downgrades an active Elite plan.
    assert.equal(elite.effective_plan, 'elite');
    assert.equal(elite.effective_source, 'billing');
    assert.equal(elite.verified.earned.plan, 'pro');
  } finally {
    await db.close();
  }
});

test('admin grants come from an explicit recorded decision only', async () => {
  const db = await createCommercialDb();
  try {
    await expectRejected(
      adminCommand(db, seller, 'grant.set', 'g1', {
        user_id: seller2, plan_code: 'pro', active: true,
      }),
      'admin_required',
      '42501',
    );
    const before = await entitlement(db, seller2);
    assert.equal(before.effective_source, 'free');

    const granted = await adminCommand(db, admin, 'grant.set', 'g1', {
      user_id: seller2, plan_code: 'pro', active: true,
    });
    assert.equal(granted.plan_code, 'pro');
    const after = await entitlement(db, seller2);
    assert.equal(after.effective_plan, 'pro');
    assert.equal(after.effective_source, 'admin');
    assert.equal(after.store_listing.limit, 15);

    // A non-admin-owned entitlement row is never overwritten by a grant.
    await db.exec(`
      INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source,active)
      VALUES('${seller}','pro','earned',true);
    `);
    await expectRejected(
      adminCommand(db, admin, 'grant.set', 'g2', {
        user_id: seller, plan_code: 'free', active: true,
      }),
      'grant_not_admin_owned',
      'P0001',
    );

    // A provider plan outranks an admin grant without deleting the grant.
    await db.exec(`
      INSERT INTO hocalist.stripe_test_subscriptions(
        membership_id,subscription_id,plan_code,provider_status,paid_until,cancel_at_period_end)
      VALUES('${IDS.seller2Membership}','sub_test_2','elite','active',now()+interval '5 days',false);
    `);
    const providerWins = await entitlement(db, seller2);
    assert.equal(providerWins.effective_plan, 'elite');
    assert.equal(providerWins.effective_source, 'billing');

    const cleared = await adminCommand(db, admin, 'grant.clear', 'g3', { user_id: seller2 });
    assert.equal(cleared.cleared, true);
    const providerOnly = await entitlement(db, seller2);
    assert.equal(providerOnly.effective_plan, 'elite');
    assert.equal(providerOnly.effective_source, 'billing');
    assert.equal(providerOnly.verified.admin.available, false);

    // Replays are answers; changed input or a stale revision is refused.
    const replay = await adminCommand(db, admin, 'grant.clear', 'g3', { user_id: seller2 });
    assert.equal(replay.cleared, true);
    await expectRejected(
      adminCommand(db, admin, 'grant.clear', 'g3', { user_id: seller }),
      'idempotency_conflict',
      'P0001',
    );
    await expectRejected(
      adminCommand(db, admin, 'policy.set', 'calendar-1', {
        calendar_timezone: 'America/New_York', expected_revision: 0,
      }),
      'revision_conflict',
      'P0001',
    );
  } finally {
    await db.close();
  }
});

test('preview shows downgrade/annual/trial only when configured', async () => {
  const db = await createCommercialDb();
  try {
    await db.exec(`
      INSERT INTO hocalist.store_listings(seller_user_id,seller_profile_id,kind,title,price_label,status)
      SELECT '${seller}','${IDS.sellerMembership}','product','Listing '||i,'$10','active'
      FROM generate_series(1,4) i;
    `);
    const preview = await callAs(db, 'authenticated', seller,
      'SELECT hocalist.entitlement_plan_preview($1) AS data', ['free'])
      .then((rows) => rows[0].data);
    assert.equal(preview.over_limit, true);
    assert.equal(preview.active_listings, 4);
    assert.equal(preview.downgrade.policy_configured, false);
    assert.equal(preview.downgrade.unavailable_reason, 'downgrade_policy_unconfigured');
    assert.equal(preview.downgrade.would_hide_existing, null);
    assert.equal(preview.downgrade.would_block_new_publishes, null);
    assert.equal(preview.annual.available, false);
    assert.equal(preview.trial.available, false);

    await adminCommand(db, admin, 'policy.set', 'downgrade-1', {
      downgrade_visibility: 'keep_existing_block_new',
      annual_enabled: true,
      trial_days: 14,
    });
    const configured = await callAs(db, 'authenticated', seller,
      'SELECT hocalist.entitlement_plan_preview($1) AS data', ['free'])
      .then((rows) => rows[0].data);
    assert.equal(configured.downgrade.policy_configured, true);
    assert.equal(configured.downgrade.would_block_new_publishes, true);
    assert.equal(configured.downgrade.would_hide_existing, null);
    assert.equal(configured.annual.available, true);
    assert.equal(configured.annual.amount_minor, null);
    assert.equal(configured.trial.available, true);
    assert.equal(configured.trial.days, 14);
  } finally {
    await db.close();
  }
});

test('access and grant fences hold for non-sellers and internals', async () => {
  const db = await createCommercialDb();
  try {
    await expectRejected(entitlement(db, buyer), 'entitlement_access_denied', '42501');
    await expectRejected(
      callAs(db, 'authenticated', buyer,
        'SELECT hocalist.entitlement_plan_preview($1)', ['pro']),
      'entitlement_access_denied',
      '42501',
    );
    await expectRejected(
      callAs(db, 'authenticated', seller,
        "SELECT hocalist.entitlement_readings_internal($1)", [seller]),
      'permission denied',
      '42501',
    );
    await expectRejected(
      callAs(db, 'authenticated', seller,
        "SELECT hocalist.entitlement_resolve_internal($1)", [seller]),
      'permission denied',
      '42501',
    );
    await expectRejected(
      callAs(db, 'anon', outsider,
        'SELECT hocalist.account_entitlement()'),
      'permission denied',
      '42501',
    );

    // A restricted membership removes every benefit and blocks the read.
    await db.exec(`
      UPDATE hocalist.memberships SET status='restricted'
      WHERE id='${IDS.sellerMembership}';
    `);
    await expectRejected(entitlement(db, seller), 'entitlement_access_denied', '42501');
  } finally {
    await db.close();
  }
});

test('timezone configuration is validated and patch-semantic', async () => {
  const db = await createCommercialDb();
  try {
    await expectRejected(
      adminCommand(db, admin, 'policy.set', 'tz-bad', { calendar_timezone: 'Not/AZone' }),
      'invalid_timezone',
      '22023',
    );
    await adminCommand(db, admin, 'policy.set', 'tz-ok', { calendar_timezone: 'UTC' });
    await adminCommand(db, admin, 'policy.set', 'overlap-ok', { paid_overlap: 'highest_priority' });
    const policy = await callAs(db, 'authenticated', seller,
      'SELECT hocalist.account_entitlement() AS data')
      .then((rows) => rows[0].data.policy);
    // The later partial patch does not clear the earlier calendar setting.
    assert.equal(policy.calendar_timezone, 'UTC');
    assert.equal(policy.paid_overlap, 'highest_priority');
    assert.equal(policy.revision, 3);
  } finally {
    await db.close();
  }
});

test('the authoritative plan governs Store and targeting admission', async () => {
  const db = await createCommercialDb();
  try {
    await seedSevenPreviousMonthSales(db);
    // Keep the settled pro/elite values; tighten only the Free weekly limit so
    // the admission difference is observable without 50 fixture deals.
    await db.exec(`
      UPDATE hocalist.marketplace_plan_limits SET weekly_target_limit=1 WHERE plan_code='free';
      INSERT INTO hocalist.credit_batches(user_id,deposit_reference,original_minor,balance_minor,
        reserved_minor,initial_fee_minor,winning_total_minor,rate_version)
      VALUES('${seller}','admission-batch',10000,10000,0,155,375,'v40');
    `);

    const limits = () => db.query(
      `SELECT hocalist.marketplace_seller_plan($1) AS plan,
              hocalist.marketplace_store_limit($1) AS store,
              hocalist.marketplace_weekly_target_limit($1) AS weekly`, [seller])
      .then((r) => r.rows[0]);

    // Unconfigured calendar: the earned month is invisible, so Free applies.
    let row = await limits();
    assert.deepEqual(row, { plan: 'free', store: 3, weekly: 1 });
    await db.query('SELECT hocalist.credit_authorize_target($1,$2,$3)',
      [seller, '30000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001']);
    await expectRejected(
      db.query('SELECT hocalist.credit_authorize_target($1,$2,$3)',
        [seller, '30000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002']),
      'weekly_target_limit',
      'P0001',
    );

    // A configured calendar applies the earned plan to actual admission.
    await adminCommand(db, admin, 'policy.set', 'calendar-admission', {
      calendar_timezone: 'UTC',
    });
    row = await limits();
    assert.deepEqual(row, { plan: 'pro', store: 15, weekly: 50 });
    await db.query('SELECT hocalist.credit_authorize_target($1,$2,$3)',
      [seller, '30000000-0000-4000-8000-000000000003', '40000000-0000-4000-8000-000000000003']);
    const quota = await db.query(
      "SELECT count(*)::int AS n FROM hocalist.credit_targets WHERE user_id=$1 AND week_start=date_trunc('week',now() AT TIME ZONE 'UTC')::date",
      [seller]).then((r) => r.rows[0].n);
    assert.equal(quota, 2);
    assert.equal((await entitlement(db, seller)).effective_plan, 'pro');

    // Plan changes never rewrite immutable deposit-batch pricing.
    const batch = await db.query(
      "SELECT initial_fee_minor, winning_total_minor, rate_version FROM hocalist.credit_batches WHERE deposit_reference='admission-batch'")
      .then((r) => r.rows[0]);
    assert.deepEqual(batch, { initial_fee_minor: 155, winning_total_minor: 375, rate_version: 'v40' });
  } finally {
    await db.close();
  }
});

test('verified, expired, reviewed, granted and restricted records resolve correctly', async () => {
  const db = await createCommercialDb();
  try {
    const limits = (user) => db.query(
      `SELECT hocalist.marketplace_seller_plan($1) AS plan,
              hocalist.marketplace_store_limit($1) AS store,
              hocalist.marketplace_weekly_target_limit($1) AS weekly`, [user])
      .then((r) => r.rows[0]);

    // Verified paid Pro subscription.
    await db.exec(`
      INSERT INTO hocalist.stripe_test_subscriptions(
        membership_id,subscription_id,plan_code,provider_status,paid_until,cancel_at_period_end)
      VALUES('${IDS.sellerMembership}','sub_admission_1','pro','active',now()+interval '10 days',false);
    `);
    assert.deepEqual(await limits(seller), { plan: 'pro', store: 15, weekly: 50 });

    // Expiry removes the benefit.
    await db.exec("UPDATE hocalist.stripe_test_subscriptions SET paid_until=now()-interval '1 day'");
    assert.deepEqual(await limits(seller), { plan: 'free', store: 3, weekly: 10 });

    // A review flag removes the benefit.
    await db.exec(`
      UPDATE hocalist.stripe_test_subscriptions SET paid_until=now()+interval '10 days';
      INSERT INTO hocalist.stripe_test_customers(membership_id,customer_id,requires_review)
      VALUES('${IDS.sellerMembership}','cus_review',true);
    `);
    assert.deepEqual(await limits(seller), { plan: 'free', store: 3, weekly: 10 });
    await db.exec(`DELETE FROM hocalist.stripe_test_customers WHERE membership_id='${IDS.sellerMembership}'`);
    assert.deepEqual(await limits(seller), { plan: 'pro', store: 15, weekly: 50 });

    // An explicit admin grant applies to the same enforcement path.
    await db.exec("DELETE FROM hocalist.stripe_test_subscriptions");
    await adminCommand(db, admin, 'grant.set', 'grant-admission', {
      user_id: seller2, plan_code: 'elite', active: true,
    });
    assert.deepEqual(await limits(seller2), { plan: 'elite', store: 50, weekly: 100 });

    // A restricted membership removes every benefit from enforcement.
    await db.exec(`
      UPDATE hocalist.memberships SET status='restricted' WHERE id='${IDS.sellerMembership}';
    `);
    assert.deepEqual(await limits(seller), { plan: 'free', store: 3, weekly: 10 });
  } finally {
    await db.close();
  }
});

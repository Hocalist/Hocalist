import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createDisposableDb, SYNTHETIC } from '../tests/fixture.mjs';

test('finance reads and monthly inputs are restricted and live payout totals exclude sandbox', async () => {
  const db = await createDisposableDb();
  const totals = { subscriptions: null, targeting: 0, confirmation: 2000,
    stripeFees: 500, refunds: null, rewardsEarned: 1730, overhead: 2300 };
  try {
    await db.exec(`
      GRANT USAGE ON SCHEMA hocalist TO authenticated;
      CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS
        $$ SELECT jsonb_build_object('aal', current_setting('test.aal', true)) $$;
      CREATE FUNCTION hocalist.marketplace_assert_admin(p_user uuid) RETURNS void
        LANGUAGE plpgsql AS $$ BEGIN
          IF p_user IS DISTINCT FROM '${SYNTHETIC.a}'::uuid THEN
            RAISE EXCEPTION 'admin_required' USING ERRCODE='42501';
          END IF;
        END $$;
      ALTER TABLE auth.users ADD COLUMN raw_app_meta_data jsonb;
      INSERT INTO auth.users VALUES
        ('${SYNTHETIC.a}', '{}', '{"hocalist_reporting_cohort":"real"}'),
        ('${SYNTHETIC.b}', '{}', '{"hocalist_reporting_cohort":"real"}'),
        ('${SYNTHETIC.outsider}', '{"hocalist_reporting_cohort":"real"}', '{}'),
        ('${SYNTHETIC.ma}', '{"hocalist_reporting_cohort":"real"}', '{}');
      CREATE TABLE hocalist.credit_batches(id integer PRIMARY KEY, user_id uuid, live_billing boolean);
      CREATE TABLE hocalist.stripe_live_credit_payments(wallet_batch_id integer, amount_minor bigint, verified_at timestamptz);
      CREATE TABLE hocalist.stripe_live_billing_pilot(user_id uuid);
      CREATE TABLE hocalist.sandbox_reward_credits(buyer_id uuid);
      CREATE TABLE hocalist.requests(created_at timestamptz, buyer_user_id uuid);
      CREATE TABLE hocalist.offers(created_at timestamptz, buyer_user_id uuid, seller_user_id uuid);
      CREATE TABLE hocalist.sale_confirmations(confirmed_at timestamptz, buyer_user_id uuid, seller_user_id uuid);
      CREATE TABLE hocalist.stripe_live_billing_receipts(stripe_account_id text, stripe_object_id text, stripe_created bigint, handling_state text, event_type text, user_id uuid);
      CREATE TABLE hocalist.withdrawal_requests(id integer PRIMARY KEY, user_id uuid, amount_minor bigint, net_minor bigint, fee_minor bigint, status text, provider text);
      CREATE TABLE hocalist.withdrawal_events(withdrawal_id integer, event text, created_at timestamptz);
      INSERT INTO hocalist.stripe_live_billing_pilot VALUES ('${SYNTHETIC.outsider}');
      INSERT INTO hocalist.credit_batches VALUES (1, '${SYNTHETIC.b}', true), (2, '${SYNTHETIC.b}', false), (3, '${SYNTHETIC.outsider}', true);
      INSERT INTO hocalist.stripe_live_credit_payments VALUES (1, 2000, now()), (2, 9999, now()), (3, 2500, now());
      INSERT INTO hocalist.requests VALUES (now(), '${SYNTHETIC.b}'), (now(), '${SYNTHETIC.outsider}'), (now(), '${SYNTHETIC.ma}');
      INSERT INTO hocalist.offers VALUES (now(), '${SYNTHETIC.b}', '${SYNTHETIC.a}'), (now(), '${SYNTHETIC.b}', '${SYNTHETIC.outsider}'), (now(), '${SYNTHETIC.b}', '${SYNTHETIC.ma}');
      INSERT INTO hocalist.sale_confirmations VALUES (now(), '${SYNTHETIC.b}', '${SYNTHETIC.outsider}');
      INSERT INTO hocalist.stripe_live_billing_receipts VALUES
        ('acct_example','in_verified',floor(extract(epoch FROM now())),'verified','invoice.paid','${SYNTHETIC.b}'),
        ('acct_example','in_verified',floor(extract(epoch FROM now())),'verified','invoice.paid','${SYNTHETIC.b}'),
        ('acct_example','in_pilot',floor(extract(epoch FROM now())),'verified','invoice.paid','${SYNTHETIC.outsider}');
      INSERT INTO hocalist.withdrawal_requests VALUES
        (1,'${SYNTHETIC.b}',2000,1750,250,'paid','stripe_global_live'),
        (2,'${SYNTHETIC.b}',2500,2250,250,'paid','stripe_global_live'),
        (3,'${SYNTHETIC.outsider}',2000,1750,250,'paid','stripe_global_sandbox'),
        (4,'${SYNTHETIC.b}',3000,2750,250,'processing','stripe_global_live');
      INSERT INTO hocalist.withdrawal_events VALUES
        (1,'paid',now()), (1,'paid',now()), (2,'paid',now()), (3,'paid',now()), (4,'requested',now());
    `);
    await db.exec(await readFile(new URL('./admin_finance_reports.sql', import.meta.url), 'utf8'));
    await db.exec(`
      INSERT INTO hocalist.admin_finance_stripe_invoices
        (account_id, invoice_id, paid_month, customer_revenue_minor)
      VALUES ('acct_example', 'in_verified', date_trunc('month', now() AT TIME ZONE 'America/New_York')::date, 5900),
        ('acct_example', 'in_pilot', date_trunc('month', now() AT TIME ZONE 'America/New_York')::date, 2000);
    `);
    await db.exec('SET ROLE authenticated');
    await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [SYNTHETIC.b]);
    await assert.rejects(db.query('SELECT hocalist.admin_finance_overview()'), /admin_required/);
    await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [SYNTHETIC.a]);
    await assert.rejects(db.query('SELECT hocalist.admin_finance_overview()'), /admin_mfa_required/);
    await db.exec("SET test.aal = 'aal2'");
    const read = async () => (await db.query('SELECT hocalist.admin_finance_overview() AS data')).rows[0].data;
    const before = await read();
    const month = before.months.at(-1);
    assert.equal(month.deposits, 2000);
    assert.equal(month.excludedPilotDeposits, 2500);
    assert.equal(month.paidBuyers, 1);
    assert.equal(month.payoutCount, 2);
    assert.equal(month.paidNet, 4000);
    assert.equal(before.processingGross, 3000);
    assert.equal(month.totals.subscriptions, 5900);
    assert.equal(month.subscriptionReconciled, true);
    assert.equal(before.sandboxPaidPayouts, 1);
    assert.deepEqual(month.activity, {
      real: { requests: 1, offers: 1, confirmations: 0 },
      test: { requests: 1, offers: 1, confirmations: 1 },
      unclassified: { requests: 1, offers: 1, confirmations: 0 },
    });

    const save = (revision, amounts) => db.query(
      "SELECT hocalist.admin_finance_save_month($1, $2, $3::jsonb, 'Test statement')",
      [month.month + '-01', revision, JSON.stringify(amounts)],
    );
    await assert.rejects(save(0, { ...totals, refunds: -100 }), /invalid_finance_totals/);
    await assert.rejects(save(0, { ...totals, subscriptions: 100 }), /finance_subscriptions_require_stripe/);
    await save(0, totals);
    await assert.rejects(save(0, totals), /finance_month_changed/);
    assert.deepEqual((await read()).months.at(-1).totals, { ...totals, subscriptions: 5900 });
    await assert.rejects(db.query('SELECT * FROM hocalist.admin_finance_month_entries'), /permission denied/);
    await assert.rejects(db.query('SELECT * FROM hocalist.admin_finance_stripe_invoices'), /permission denied/);
    await db.exec(`RESET ROLE;
      INSERT INTO hocalist.stripe_live_billing_receipts VALUES
        ('acct_example','in_new',floor(extract(epoch FROM now())),'verified','invoice.paid','${SYNTHETIC.b}');
      SET ROLE authenticated;
    `);
    const updated = (await read()).months.at(-1);
    assert.equal(updated.subscriptionReconciled, false);
    assert.equal(updated.totals.subscriptions, null);
  } finally {
    await db.close();
  }
});

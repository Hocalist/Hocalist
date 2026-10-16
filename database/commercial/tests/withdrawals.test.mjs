// Disposable PostgreSQL checks for the provider-neutral withdrawal workflow:
// verification gate, $20/$2.50 terms, reserve/restore and double-payout
// reconciliation. No provider is called.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const OUT = '00000000-0000-4000-8000-00000000000c';
const ADM = '00000000-0000-4000-8000-00000000000e';
const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MADM = '10000000-0000-4000-8000-00000000000e';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

async function asRole(db, role, user, body) {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return await body();
  } finally {
    await db.exec('RESET ROLE');
  }
}

async function callAs(db, role, user, sql, params = []) {
  return asRole(db, role, user, async () => (await db.query(sql, params)).rows);
}

async function expectRejected(promise, messagePart, code = '42501') {
  try {
    await promise;
  } catch (error) {
    assert.equal(error.code, code, `${messagePart}: got ${error.code} ${error.message}`);
    if (messagePart) assert.match(error.message, new RegExp(messagePart));
    return error;
  }
  assert.fail(`expected SQLSTATE ${code} for ${messagePart}`);
}

test('withdrawal workflow reserves, restores and never double-pays', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    for (const path of [
      '../../provider-rollout/apply.sql',
      '../../chat/010_chat_foundation.sql',
      '../../marketplace/020_marketplace_foundation.sql',
      '../../marketplace/021_request_coordinates.sql',
      '../../marketplace/023_multi_negotiation.sql',
      '../../meetings/040_meetings_foundation.sql',
      '../../outcomes/080_sale_confirmation.sql',
      '../../outcomes/081_purchase_seller.sql',
      '../090_credit_batches.sql',
      '../091_buyer_rewards.sql',
      '../092_credit_settlement.sql',
      '../093_withdrawals.sql',
    ]) {
      await db.exec(await read(path));
    }
    await db.exec(`
      ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz, ADD COLUMN phone_confirmed_at timestamptz;
      INSERT INTO auth.users(id, raw_user_meta_data) VALUES
        ('${A}','{}'),('${B}','{}'),('${OUT}','{}'),('${ADM}','{}');
      INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
        ('${MA}','${A}','buyer','active'),('${MB}','${B}','seller','active'),
        ('${MADM}','${ADM}','seller','active');
      INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
        ('${MA}','Buyer A'),('${MB}','Seller B'),('${MADM}','Admin');
      INSERT INTO hocalist.platform_admins(user_id) VALUES ('${ADM}');
    `);
    // Deterministic sold chain plus a won target and an earned reward.
    await db.exec(`
      INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
      VALUES ('30000000-0000-4000-8000-000000000001','${A}','${MA}','product','Sold item','used','closed');
      INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status,accepted_revision_id)
      VALUES ('40000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','${A}','${B}','${MB}','completed',
              '41000000-0000-4000-8000-000000000001');
      INSERT INTO hocalist.offer_revisions(id,offer_id,sequence,price_minor,currency_code,message,schedule_date,schedule_time,
        schedule_timezone,schedule_offset_minutes,schedule_instant,place_choice,place_label,status,proposed_by_user_id)
      VALUES ('41000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001',1,42000,'USD','','2026-11-05','18:30',
        'America/New_York',-240,'2026-11-05T22:30:00Z','specific_place','Synthetic place','accepted','${B}');
      INSERT INTO hocalist.conversations(id,origin,request_id,offer_id)
      VALUES ('60000000-0000-4000-8000-000000000001','targeted_request','30000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001');
      INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status,accepted_revision_id,meeting_expires_at)
      VALUES ('50000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',
        '40000000-0000-4000-8000-000000000001','${A}','${B}','accepted','44000000-0000-4000-8000-000000000001',now()+interval '1 day');
      INSERT INTO hocalist.sale_confirmations(id,request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id)
      VALUES ('70000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001',
        '40000000-0000-4000-8000-000000000001','44000000-0000-4000-8000-000000000001','${A}','${B}');
      INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,initial_fee_minor,winning_total_minor,rate_version)
      VALUES ('80000000-0000-4000-8000-000000000001','${B}','dep-1',900,800,100,200,'v1');
      INSERT INTO hocalist.credit_targets(id,user_id,request_id,batch_id,initial_minor,winning_minor,charged_minor,reserved_minor,status,week_start,rate_version)
      VALUES ('81000000-0000-4000-8000-000000000001','${B}','30000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001',
        100,200,200,0,'won',date_trunc('week',now())::date,'v1');
      INSERT INTO hocalist.buyer_rewards(outcome_id,target_id,buyer_user_id,amount_minor,rule_version)
      VALUES ('70000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','${A}',5000,'reward-v1');
    `);

    const status = () =>
      callAs(db, 'authenticated', A, 'SELECT hocalist.withdrawal_status() AS data').then(
        (rows) => rows[0].data,
      );
    const requestWithdrawal = (key, amount) =>
      callAs(db, 'authenticated', A,
        'SELECT hocalist.withdrawal_request($1,$2) AS data', [key, amount]).then(
        (rows) => rows[0].data,
      );

    await t.test('the settled terms and earned balance are authoritative', async () => {
      const data = await status();
      assert.equal(data.minimum_minor, 2000);
      assert.equal(data.fee_minor, 250);
      assert.equal(data.earned_minor, 5000);
      assert.equal(data.available_minor, 5000);
      assert.equal(data.email_verified, false);
      assert.equal(data.phone_verified, false);
    });

    await t.test('unverified email or phone blocks the request', async () => {
      await expectRejected(
        requestWithdrawal('wd-unverified', 3000),
        'contact_verification_required',
        'P0001',
      );
      await db.exec(`UPDATE auth.users SET email_confirmed_at=now() WHERE id='${A}'`);
      await expectRejected(
        requestWithdrawal('wd-unverified', 3000),
        'contact_verification_required',
        'P0001',
      );
      await db.exec(`UPDATE auth.users SET phone_confirmed_at=now() WHERE id='${A}'`);
      assert.equal((await status()).email_verified, true);
      assert.equal((await status()).phone_verified, true);
    });

    await t.test('below-minimum and insufficient amounts are refused', async () => {
      await expectRejected(requestWithdrawal('wd-small', 1999), 'below_minimum', 'P0001');
      await expectRejected(
        requestWithdrawal('wd-too-much', 6000),
        'insufficient_earned_balance',
        'P0001',
      );
    });

    let first;
    await t.test('a request reserves the amount and shows the net payout', async () => {
      first = await requestWithdrawal('wd-1', 3000);
      assert.equal(first.amount_minor, 3000);
      assert.equal(first.fee_minor, 250);
      assert.equal(first.net_minor, 2750);
      const data = await status();
      assert.equal(data.processing_minor, 3000);
      assert.equal(data.available_minor, 2000);
      assert.equal(data.requests[0].status, 'processing');
    });

    await t.test('an exact retry replays the original request', async () => {
      const replay = await requestWithdrawal('wd-1', 3000);
      assert.equal(replay.withdrawal_id, first.withdrawal_id);
      const count = await db.query(
        'SELECT count(*)::int AS n FROM hocalist.withdrawal_requests WHERE user_id=$1', [A]);
      assert.equal(count.rows[0].n, 1);
    });

    await t.test('a confirmed failure restores the reserved balance once', async () => {
      await db.query(
        "SELECT hocalist.withdrawal_settle_internal($1,'failed','stripe_global_payouts',NULL,'account closed')",
        [first.withdrawal_id],
      );
      const replay = await asRole(db, 'service_role', '', async () =>
        (await db.query(
          "SELECT hocalist.withdrawal_settle_internal($1,'failed','stripe_global_payouts',NULL,'account closed') AS data",
          [first.withdrawal_id],
        )).rows[0].data);
      assert.equal(replay.status, 'failed');
      const data = await status();
      assert.equal(data.processing_minor, 0);
      assert.equal(data.available_minor, 5000);
      assert.equal(data.requests[0].status, 'failed');
    });

    await t.test('a late success after failure is flagged, never paid again', async () => {
      const second = await requestWithdrawal('wd-2', 2000);
      await asRole(db, 'service_role', '', async () => {
        await db.query(
          "SELECT hocalist.withdrawal_settle_internal($1,'failed','stripe_global_payouts',NULL,'network')",
          [second.withdrawal_id],
        );
      });
      const late = await asRole(db, 'service_role', '', async () =>
        (await db.query(
          "SELECT hocalist.withdrawal_settle_internal($1,'paid','stripe_global_payouts','po-late') AS data",
          [second.withdrawal_id],
        )).rows[0].data);
      assert.equal(late.status, 'reconciliation_required');
      const row = await db.query(
        'SELECT status, provider_reference FROM hocalist.withdrawal_requests WHERE id=$1',
        [second.withdrawal_id],
      );
      assert.equal(row.rows[0].status, 'failed');
      assert.equal(row.rows[0].provider_reference, 'po-late');
      const events = await db.query(
        'SELECT event FROM hocalist.withdrawal_events WHERE withdrawal_id=$1 ORDER BY revision',
        [second.withdrawal_id],
      );
      assert.deepEqual(events.rows.map((e) => e.event), ['requested', 'failed', 'reconciliation']);
    });

    await t.test('a paid withdrawal is final', async () => {
      const third = await requestWithdrawal('wd-3', 3000);
      const paid = await asRole(db, 'service_role', '', async () =>
        (await db.query(
          "SELECT hocalist.withdrawal_settle_internal($1,'paid','stripe_global_payouts','po-1') AS data",
          [third.withdrawal_id],
        )).rows[0].data);
      assert.equal(paid.status, 'paid');
      const data = await status();
      assert.equal(data.requests[0].status, 'paid');
      await expectRejected(
        asRole(db, 'service_role', '', () =>
          db.query(
            "SELECT hocalist.withdrawal_settle_internal($1,'failed','stripe_global_payouts',NULL,'reversed')",
            [third.withdrawal_id],
          )),
        'late_failure_after_payout',
        'P0001',
      );
    });

    await t.test('the admin queue is admin-only and read-only', async () => {
      await expectRejected(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.admin_withdrawal_queue(50,NULL)'),
        'admin_required',
      );
      const queue = (await callAs(db, 'authenticated', ADM,
        'SELECT hocalist.admin_withdrawal_queue(50,NULL) AS data'))[0].data;
      assert.equal(queue.items.length, 3);
      assert.equal(queue.processing_minor, 0);
    });

    await t.test('tables and the settlement helper stay closed to clients', async () => {
      await expectRejected(
        callAs(db, 'authenticated', A, 'SELECT * FROM hocalist.withdrawal_requests'),
        'permission denied',
      );
      await expectRejected(
        callAs(db, 'authenticated', A,
          "SELECT hocalist.withdrawal_settle_internal('70000000-0000-4000-8000-000000000001','paid','x','y')"),
        'permission denied',
      );
      await expectRejected(
        callAs(db, 'authenticated', OUT, 'SELECT hocalist.withdrawal_status()'),
        'withdrawal_access_denied',
      );
    });
  } finally {
    await db.close();
  }
});

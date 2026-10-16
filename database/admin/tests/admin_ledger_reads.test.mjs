// Disposable PostgreSQL checks for the administrator commercial ledger reads
// (draft database/admin/061_admin_ledger_reads.sql).
//
// PGlite is single-connection: deterministic SQL proof for admin-only access,
// aggregation, keyset paging and projection limits. It is NOT live JWT or
// reconciliation proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const ADMIN = '00000000-0000-4000-8000-000000000001';
const BUYER = '00000000-0000-4000-8000-000000000002';
const SELLER = '00000000-0000-4000-8000-000000000003';
const OUTSIDER = '00000000-0000-4000-8000-000000000004';
const M_BUYER = '10000000-0000-4000-8000-000000000002';
const M_SELLER = '10000000-0000-4000-8000-000000000003';
const BATCH_A = '70000000-0000-4000-8000-00000000000a';
const BATCH_B = '70000000-0000-4000-8000-00000000000b';
const TARGET_WON = '71000000-0000-4000-8000-00000000000a';
const TARGET_RELEASED = '71000000-0000-4000-8000-00000000000b';
const OUTCOME = '72000000-0000-4000-8000-00000000000a';
const OUTCOME_2 = '72000000-0000-4000-8000-00000000000b';
const REQUEST = '73000000-0000-4000-8000-00000000000a';
const REQUEST_2 = '73000000-0000-4000-8000-00000000000b';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

async function as(db, role, user, query, params = []) {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return (await db.query(query, params)).rows;
  } finally {
    await db.exec('RESET ROLE');
  }
}

test('admin commercial ledger reads on disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    for (const path of [
      '../../provider-rollout/apply.sql',
      '../../chat/010_chat_foundation.sql',
      '../../marketplace/020_marketplace_foundation.sql',
      '../../meetings/040_meetings_foundation.sql',
      '../../outcomes/080_sale_confirmation.sql',
      '../../commercial/090_credit_batches.sql',
      '../../commercial/091_buyer_rewards.sql',
    ]) {
      await db.exec(await read(path));
    }
    await db.exec(await read('../060_admin_reads.sql'));
    await db.exec(await read('../061_admin_ledger_reads.sql'));

    await db.exec(`
      INSERT INTO auth.users(id, raw_user_meta_data) VALUES
        ('${ADMIN}','{}'),('${BUYER}','{}'),('${SELLER}','{}'),('${OUTSIDER}','{}');
      INSERT INTO hocalist.profiles(id) VALUES
        ('${ADMIN}'),('${BUYER}'),('${SELLER}'),('${OUTSIDER}') ON CONFLICT DO NOTHING;
      INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
        ('${M_BUYER}','${BUYER}','buyer','active'),
        ('${M_SELLER}','${SELLER}','seller','active');
      INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
        ('${M_BUYER}','Ledger Buyer'),('${M_SELLER}','Ledger Seller');
      INSERT INTO hocalist.platform_admins(user_id) VALUES ('${ADMIN}');
      INSERT INTO hocalist.credit_batches(
        id,user_id,deposit_reference,original_minor,balance_minor,reserved_minor,
        initial_fee_minor,winning_total_minor,rate_version)
      VALUES
        ('${BATCH_A}','${SELLER}','deposit-a',2000,1550,375,155,375,'elite-v1'),
        ('${BATCH_B}','${SELLER}','deposit-b',4000,4000,0,145,325,'elite-v1');
      -- The target/reward rows normally reference a full request/outcome chain;
      -- this test only exercises the admin aggregate, so referential
      -- enforcement is relaxed for the synthetic rows.
      SET session_replication_role = replica;
      INSERT INTO hocalist.credit_targets(
        id,user_id,request_id,batch_id,initial_minor,winning_minor,charged_minor,
        reserved_minor,status,week_start)
      VALUES
        ('${TARGET_WON}','${SELLER}','${REQUEST}','${BATCH_A}',155,375,375,0,'won',date '2026-09-21'),
        ('${TARGET_RELEASED}','${SELLER}','${REQUEST_2}','${BATCH_A}',155,375,0,0,'released',date '2026-09-21');
      INSERT INTO hocalist.buyer_rewards(
        id,outcome_id,target_id,buyer_user_id,amount_minor,rule_version)
      VALUES
        ('74000000-0000-4000-8000-00000000000a','${OUTCOME}','${TARGET_WON}','${BUYER}',150,'reward-v1'),
        ('74000000-0000-4000-8000-00000000000b','${OUTCOME_2}','${TARGET_RELEASED}','${BUYER}',30,'reward-v1');
      SET session_replication_role = origin;
    `);

    const credits = (user, params = [50, null]) =>
      as(
        db,
        'authenticated',
        user,
        'SELECT hocalist.admin_credit_summary($1,$2) AS data',
        params,
      );
    const rewards = (user, params = [50, null]) =>
      as(
        db,
        'authenticated',
        user,
        'SELECT hocalist.admin_reward_summary($1,$2) AS data',
        params,
      );

    await t.test('only an explicitly provisioned admin can read the ledgers', async () => {
      await assert.rejects(credits(OUTSIDER), { code: '42501' });
      await assert.rejects(rewards(OUTSIDER), { code: '42501' });
      await assert.rejects(credits(ADMIN, [0, null]), { code: '22023' });
      await assert.rejects(credits(ADMIN, [101, null]), { code: '22023' });
      assert.equal((await credits(ADMIN))[0].data.items.length, 1);
      assert.equal((await rewards(ADMIN))[0].data.items.length, 1);
    });

    await t.test('credit totals aggregate batches, targets and availability', async () => {
      const item = (await credits(ADMIN))[0].data.items[0];
      assert.equal(item.user_id, SELLER);
      assert.equal(item.batch_count, 2);
      assert.equal(item.original_minor, 6000);
      assert.equal(item.remaining_minor, 5550);
      assert.equal(item.reserved_minor, 375);
      assert.equal(item.available_minor, 5175);
      assert.equal(item.spent_percent, 8);
      assert.equal(item.target_count, 2);
      assert.equal(item.won_count, 1);
      assert.equal(item.released_count, 1);
    });

    await t.test('reward totals stay separate from seller credits', async () => {
      const item = (await rewards(ADMIN))[0].data.items[0];
      assert.equal(item.buyer_user_id, BUYER);
      assert.equal(item.reward_count, 2);
      assert.equal(item.total_minor, 180);
      const payload = JSON.stringify((await rewards(ADMIN))[0].data);
      assert.doesNotMatch(payload, /deposit-a|deposit-b|rate_version/);
    });

    await t.test('credit detail drills into one seller without contacts', async () => {
      const detail = (
        await as(
          db,
          'authenticated',
          ADMIN,
          'SELECT hocalist.admin_credit_detail($1) AS data',
          [SELLER],
        )
      )[0].data;
      assert.equal(detail.user_id, SELLER);
      assert.equal(detail.batches.length, 2);
      assert.equal(detail.targets.length, 2);
      assert.equal(detail.available_minor, 5175);
      const payload = JSON.stringify(detail);
      assert.doesNotMatch(payload, /Ledger Seller|private/i);

      await assert.rejects(
        as(
          db,
          'authenticated',
          ADMIN,
          'SELECT hocalist.admin_credit_detail($1)',
          ['00000000-0000-4000-8000-0000000000ff'],
        ),
        { code: '22023' },
      );
      await assert.rejects(
        as(
          db,
          'authenticated',
          OUTSIDER,
          'SELECT hocalist.admin_credit_detail($1)',
          [SELLER],
        ),
        { code: '42501' },
      );
    });

    await t.test('keyset paging returns no repeated rows', async () => {
      await db.exec(`
        INSERT INTO hocalist.credit_batches(
          user_id,deposit_reference,original_minor,balance_minor,reserved_minor,
          initial_fee_minor,winning_total_minor,rate_version)
        VALUES ('${BUYER}','deposit-c',1000,1000,0,155,375,'elite-v1');
      `);
      const first = (await credits(ADMIN, [1, null]))[0].data;
      assert.equal(first.items.length, 1);
      assert.ok(first.next_cursor);
      const second = (await credits(ADMIN, [1, first.next_cursor]))[0].data;
      assert.equal(second.items.length, 1);
      assert.notEqual(second.items[0].user_id, first.items[0].user_id);
      assert.equal(second.next_cursor, null);
    });

    await t.test('anon and service roles cannot execute or read the tables', async () => {
      await assert.rejects(
        as(db, 'anon', ADMIN, 'SELECT hocalist.admin_credit_summary(50,null)'),
        { code: '42501' },
      );
      await assert.rejects(
        as(db, 'service_role', ADMIN, 'SELECT hocalist.admin_reward_summary(50,null)'),
        { code: '42501' },
      );
      await assert.rejects(
        as(db, 'authenticated', ADMIN, 'SELECT count(*) FROM hocalist.credit_batches'),
        { code: '42501' },
      );
    });
  } finally {
    await db.close();
  }
});

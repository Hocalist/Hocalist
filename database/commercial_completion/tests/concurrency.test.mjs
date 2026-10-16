import { loadPostgres } from '../../tests/postgres.mjs';
// Opt-in real multi-connection concurrency harness for the commercial
// completion package: credit reservation, qualification, PIN winning
// difference, withdrawal, reversal and payout claim races.
//
//   $env:HOCALIST_TEST_DATABASE_URL = 'postgres://postgres:postgres@127.0.0.1:5432/hocalist_test'
//   $env:HOCALIST_ALLOW_DISPOSABLE_DB = '1'
//   node --test database/commercial_completion/tests/concurrency.test.mjs
//
// PGlite is single-connection and is never concurrency proof. This harness
// needs a genuine disposable PostgreSQL instance with superuser rights to
// create the synthetic auth fixture and roles. Safety guards: the shared
// Supabase project and reserved databases are refused, the database name must
// contain test/disposable/scratch/tmp even on localhost, and the target must be
// empty of auth/hocalist/public business objects before any mutation. The run
// creates only its own schemas and removes only those schemas at the end.
// Without the environment variables the suite reports NOT RUN.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import {
  assertConcurrencyTarget,
  assertEmptyTargetContents,
  concurrencySkipReason,
} from '../../tests/harness_guard.mjs';
import { loadSql } from '../../tests/fixture.mjs';

const databaseUrl = process.env.HOCALIST_TEST_DATABASE_URL ?? '';
const acknowledged = process.env.HOCALIST_ALLOW_DISPOSABLE_DB === '1';
const skipReason = concurrencySkipReason({ databaseUrl });
let guardError = null;
if (!skipReason) {
  try {
    assertConcurrencyTarget({ databaseUrl, acknowledged });
  } catch (error) {
    guardError = error;
  }
}

const BASE_SQL = [
  '../drafts/003_membership_private_profiles.sql',
  '../drafts/004_account_commands.sql',
  '../drafts/005_stripe_test_inbox.sql',
  '../provider-rollout/apply.sql',
  '../chat/010_chat_foundation.sql',
  '../marketplace/020_marketplace_foundation.sql',
  '../marketplace/021_request_coordinates.sql',
  '../marketplace/023_multi_negotiation.sql',
  '../meetings/040_meetings_foundation.sql',
  '../outcomes/080_sale_confirmation.sql',
  '../outcomes/081_purchase_seller.sql',
  '../commercial/090_credit_batches.sql',
  '../commercial/091_buyer_rewards.sql',
  '../commercial/092_credit_settlement.sql',
  '../commercial/093_withdrawals.sql',
  '../commercial_completion/180_entitlement_lifecycle.sql',
  '../commercial_completion/181_reconciliation_orchestration.sql',
  '../commercial_completion/182_reversals.sql',
  '../commercial_completion/183_payout_execution.sql',
  '../commercial_completion/184_commercial_reads.sql',
];

const IDS = Object.freeze({
  buyer: '00000000-0000-4000-8000-00000000000a',
  seller: '00000000-0000-4000-8000-00000000000b',
  outsider: '00000000-0000-4000-8000-00000000000c',
  admin: '00000000-0000-4000-8000-00000000000e',
  buyerMembership: '10000000-0000-4000-8000-00000000000a',
  sellerMembership: '10000000-0000-4000-8000-00000000000b',
  outsiderMembership: '10000000-0000-4000-8000-00000000000c',
  adminMembership: '10000000-0000-4000-8000-00000000000e',
});

const runHarness = async (t) => {
  const pg = await loadPostgres();
  const { Client } = pg;
  const admin = new Client({ connectionString: databaseUrl });
  await admin.connect();
  let created = false;

  const connectAs = async (user) => {
    const client = new Client({ connectionString: databaseUrl });
    await client.connect();
    await client.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
    await client.query('SET ROLE authenticated');
    return client;
  };
  const connect = async () => {
    const client = new Client({ connectionString: databaseUrl });
    await client.connect();
    return client;
  };
  const count = async (sql, params = []) =>
    Number((await admin.query(sql, params)).rows[0].n);
  const expectRejected = async (promise, message, code = 'P0001') => {
    try {
      await promise;
    } catch (error) {
      assert.equal(error.code, code, `${message}: got ${error.code} ${error.message}`);
      assert.match(error.message, new RegExp(message));
      return error;
    }
    throw new Error(`expected ${code} for ${message}`);
  };

  let seq = 0;
  const nextId = (prefix) => {
    seq += 1;
    return `${prefix}${String(seq).padStart(12, '0')}`;
  };
  // Seeds one accepted deal with a batch/target and optional conversation.
  const seedDeal = async ({
    targetStatus = 'reserved',
    charged = 0,
    initial = 100,
    winning = 375,
    original = 400,
    withConversation = false,
    withSale = false,
    withBatch = true,
    withTarget = true,
    requestStatus = 'closed',
  }) => {
    const n = ++seq;
    const request = nextId('30000000-0000-4000-8010-');
    const offer = nextId('40000000-0000-4000-8010-');
    const conversation = nextId('60000000-0000-4000-8010-');
    const meeting = nextId('50000000-0000-4000-8010-');
    const batch = nextId('80000000-0000-4000-8010-');
    const target = nextId('81000000-0000-4000-8010-');
    const reserved = withTarget ? winning - charged : 0;
    await admin.query(`
      INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
      VALUES('${request}','${IDS.buyer}','${IDS.buyerMembership}','product','Deal ${n}','used','${requestStatus}');
      INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
      VALUES('${offer}','${request}','${IDS.buyer}','${IDS.seller}','${IDS.sellerMembership}','selected');
      INSERT INTO hocalist.conversations(id,origin,request_id,offer_id)
      VALUES('${conversation}','targeted_request','${request}','${offer}');
      INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,
        status,meeting_expires_at)
      VALUES('${meeting}','${conversation}','${request}','${offer}','${IDS.buyer}','${IDS.seller}',
        'accepted',now()+interval '1 day');
      ${withBatch ? `
      INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,
        reserved_minor,initial_fee_minor,winning_total_minor,rate_version)
      VALUES('${batch}','${IDS.seller}','dep-${n}',${original},${original - charged},${reserved},
        ${initial},${winning},'v1');` : ''}
      ${withTarget ? `
      INSERT INTO hocalist.credit_targets(id,user_id,request_id,batch_id,offer_id,initial_minor,
        winning_minor,charged_minor,reserved_minor,status,week_start,rate_version)
      VALUES('${target}','${IDS.seller}','${request}','${batch}','${offer}',${initial},${winning},
        ${charged},${reserved},'${targetStatus}',date_trunc('week',now() AT TIME ZONE 'UTC')::date,'v1');` : ''}
      ${withConversation ? `
        INSERT INTO hocalist.conversation_messages(conversation_id,sender_user_id,sender_profile_id,kind,text,client_message_id,request_hash)
        VALUES('${conversation}','${IDS.buyer}','${IDS.buyerMembership}','text','hi','m-a-${n}',md5('hi')),
              ('${conversation}','${IDS.seller}','${IDS.sellerMembership}','text','hello','m-b-${n}',md5('hello'));` : ''}
      ${withSale ? `
        INSERT INTO hocalist.sale_confirmations(id,request_id,meeting_id,offer_id,schedule_revision_id,
          buyer_user_id,seller_user_id)
        VALUES('${nextId('70000000-0000-4000-8010-')}','${request}','${meeting}','${offer}',
          gen_random_uuid(),'${IDS.buyer}','${IDS.seller}');` : ''}
    `);
    return { request, offer, conversation, meeting, batch, target };
  };

  try {
    const content = await admin.query(`
      SELECT
        (SELECT coalesce(array_agg(nspname), ARRAY[]::name[]) FROM pg_namespace
          WHERE nspname IN ('auth', 'hocalist')) AS schemas,
        (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','S','f')) AS public_relations,
        (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public') AS public_functions`);
    assertEmptyTargetContents({
      schemas: content.rows[0].schemas,
      publicRelations: content.rows[0].public_relations,
      publicFunctions: content.rows[0].public_functions,
    });

    await admin.query(`
      DO $roles$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
          EXECUTE 'CREATE ROLE anon NOLOGIN';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
          EXECUTE 'CREATE ROLE authenticated NOLOGIN';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
          EXECUTE 'CREATE ROLE service_role NOLOGIN BYPASSRLS';
        END IF;
      END
      $roles$;
      CREATE SCHEMA auth;
      CREATE TABLE auth.users(id uuid PRIMARY KEY, raw_user_meta_data jsonb,
        email_confirmed_at timestamptz, phone_confirmed_at timestamptz);
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
      $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
      GRANT USAGE ON SCHEMA auth TO authenticated;
      GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
      CREATE SCHEMA hocalist;
      REVOKE ALL ON SCHEMA hocalist FROM PUBLIC, anon, authenticated;
    `);
    created = true;
    const bootstrap = await loadSql('../bootstrap/002_hocalist_signup_routing.sql');
    await admin.query(
      bootstrap.slice(
        bootstrap.indexOf('CREATE TABLE hocalist.profiles'),
        bootstrap.indexOf('COMMIT;'),
      ),
    );
    for (const path of BASE_SQL) {
      await admin.query(await loadSql(path));
    }
    await admin.query(`
      INSERT INTO auth.users(id, raw_user_meta_data, email_confirmed_at, phone_confirmed_at) VALUES
        ('${IDS.buyer}','{}',now(),now()),
        ('${IDS.seller}','{}',NULL,NULL),
        ('${IDS.outsider}','{}',NULL,NULL),
        ('${IDS.admin}','{}',NULL,NULL);
      INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
        ('${IDS.buyerMembership}','${IDS.buyer}','buyer','active'),
        ('${IDS.sellerMembership}','${IDS.seller}','seller','active'),
        ('${IDS.outsiderMembership}','${IDS.outsider}','seller','active'),
        ('${IDS.adminMembership}','${IDS.admin}','seller','active');
      INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
        ('${IDS.buyerMembership}','Buyer'),('${IDS.sellerMembership}','Seller'),
        ('${IDS.outsiderMembership}','Outsider'),('${IDS.adminMembership}','Admin');
      INSERT INTO hocalist.platform_admins(user_id) VALUES ('${IDS.admin}');
    `);

    await t.test('concurrent reservations against one batch never overspend', async () => {
      await admin.query("INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version) VALUES(400,100,375,'race-v1')" );
      const funded = await seedDeal({ original: 400, winning: 375, withTarget: false });
      const other = await seedDeal({
        original: 400, winning: 375, withBatch: false, withTarget: false,
        requestStatus: 'active',
      });
      const c1 = await connect();
      const c2 = await connect();
      try {
        const week = "date_trunc('week',now() AT TIME ZONE 'UTC')::date";
        const call = (client, request, offer) =>
          client.query(
            `SELECT hocalist.credit_reserve_internal($1,$2,$3,${week},10) AS id`,
            [IDS.seller, request, offer]);
        const results = await Promise.allSettled([
          call(c1, funded.request, funded.offer),
          call(c2, other.request, other.offer),
        ]);
        const fulfilled = results.filter((r) => r.status === 'fulfilled');
        const rejected = results.filter((r) => r.status === 'rejected');
        // One 375 winning fee fits; the other reservation is refused.
        assert.equal(fulfilled.length, 1, JSON.stringify(rejected.map((r) => r.reason?.message)));
        assert.equal(rejected.length, 1);
        assert.match(rejected[0].reason.message, /insufficient_single_batch/);
        assert.equal(await count(
          'SELECT reserved_minor::int AS n FROM hocalist.credit_batches WHERE id=$1',
          [funded.batch]), 375);
        assert.equal(await count(
          "SELECT count(*)::int AS n FROM hocalist.credit_targets WHERE status IN ('reserved','initial_charged')"),
          1);
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('concurrent same-request reservations converge on one target', async () => {
      const deal = await seedDeal({ original: 4000, winning: 375, requestStatus: 'active' });
      const c1 = await connect();
      const c2 = await connect();
      try {
        const week = "date_trunc('week',now() AT TIME ZONE 'UTC')::date";
        const call = (client) =>
          client.query(
            `SELECT hocalist.credit_reserve_internal($1,$2,$3,${week},10) AS id`,
            [IDS.seller, deal.request, deal.offer]);
        const results = await Promise.all([call(c1), call(c2)]);
        assert.equal(results[0].rows[0].id, results[1].rows[0].id);
        assert.equal(await count(
          'SELECT count(*)::int AS n FROM hocalist.credit_targets WHERE request_id=$1',
          [deal.request]), 1);
        assert.equal(await count(
          'SELECT reserved_minor::int AS n FROM hocalist.credit_batches WHERE id=$1',
          [deal.batch]), 375);
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('qualification charges the initial fee exactly once', async () => {
      const deal = await seedDeal({ withConversation: true, requestStatus: 'active' });
      const c1 = await connect();
      const c2 = await connect();
      try {
        const call = (client) =>
          client.query('SELECT hocalist.credit_qualify_conversation($1) AS result',
            [deal.conversation]);
        const results = await Promise.allSettled([call(c1), call(c2)]);
        for (const result of results) {
          assert.equal(result.status, 'fulfilled', result.reason?.message);
        }
        assert.equal(await count(
          "SELECT count(*)::int AS n FROM hocalist.credit_entries WHERE target_id=$1 AND kind='initial'",
          [deal.target]), 1);
        const row = await admin.query(
          'SELECT charged_minor::int, status FROM hocalist.credit_targets WHERE id=$1', [deal.target]);
        assert.equal(row.rows[0].charged_minor, 100);
        assert.equal(row.rows[0].status, 'initial_charged');
        assert.equal(await count(
          'SELECT balance_minor::int AS n FROM hocalist.credit_batches WHERE id=$1', [deal.batch]), 300);
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('concurrent purchase settlement charges only the difference once', async () => {
      const deal = await seedDeal({
        targetStatus: 'initial_charged', charged: 100, withSale: true,
      });
      const c1 = await connect();
      const c2 = await connect();
      try {
        const call = (client) =>
          client.query('SELECT hocalist.credit_settle_purchase($1) AS result', [deal.request]);
        await Promise.all([call(c1), call(c2)]);
        assert.equal(await count(
          "SELECT count(*)::int AS n FROM hocalist.credit_entries WHERE target_id=$1 AND kind='win'",
          [deal.target]), 1);
        const row = await admin.query(
          'SELECT charged_minor::int, reserved_minor::int, status FROM hocalist.credit_targets WHERE id=$1',
          [deal.target]);
        assert.equal(row.rows[0].charged_minor, 375);
        assert.equal(row.rows[0].reserved_minor, 0);
        assert.equal(row.rows[0].status, 'won');
        assert.equal(await count(
          'SELECT balance_minor::int AS n FROM hocalist.credit_batches WHERE id=$1', [deal.batch]), 25);
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('concurrent withdrawals cannot reserve the same earnings twice', async () => {
      const outcome = nextId('70000000-0000-4000-8010-');
      const request = nextId('30000000-0000-4000-8010-');
      const offer = nextId('40000000-0000-4000-8010-');
      const conversation = nextId('60000000-0000-4000-8010-');
      const meeting = nextId('50000000-0000-4000-8010-');
      const batch = nextId('80000000-0000-4000-8010-');
      const target = nextId('81000000-0000-4000-8010-');
      await admin.query(`
        INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
        VALUES('${request}','${IDS.buyer}','${IDS.buyerMembership}','product','Paid','used','closed');
        INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
        VALUES('${offer}','${request}','${IDS.buyer}','${IDS.seller}','${IDS.sellerMembership}','completed');
        INSERT INTO hocalist.conversations(id,origin,request_id,offer_id)
        VALUES('${conversation}','targeted_request','${request}','${offer}');
        INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,
          status,meeting_expires_at)
        VALUES('${meeting}','${conversation}','${request}','${offer}','${IDS.buyer}','${IDS.seller}',
          'accepted',now()+interval '1 day');
        INSERT INTO hocalist.sale_confirmations(id,request_id,meeting_id,offer_id,schedule_revision_id,
          buyer_user_id,seller_user_id)
        VALUES('${outcome}','${request}','${meeting}','${offer}',gen_random_uuid(),
          '${IDS.buyer}','${IDS.seller}');
        INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,
          reserved_minor,initial_fee_minor,winning_total_minor,rate_version)
        VALUES('${batch}','${IDS.seller}','dep-wd',400,100,0,100,375,'v1');
        INSERT INTO hocalist.credit_targets(id,user_id,request_id,batch_id,offer_id,initial_minor,
          winning_minor,charged_minor,reserved_minor,status,week_start,rate_version)
        VALUES('${target}','${IDS.seller}','${request}','${batch}','${offer}',100,375,375,0,'won',
          date_trunc('week',now() AT TIME ZONE 'UTC')::date,'v1');
        INSERT INTO hocalist.buyer_rewards(outcome_id,target_id,buyer_user_id,amount_minor,rule_version)
        VALUES('${outcome}','${target}','${IDS.buyer}',5000,'reward-v1');
      `);
      const c1 = await connectAs(IDS.buyer);
      const c2 = await connectAs(IDS.buyer);
      try {
        const call = (client, key, amount) =>
          client.query('SELECT hocalist.withdrawal_request($1,$2) AS result', [key, amount]);
        const results = await Promise.allSettled([
          call(c1, `wd-a-${randomUUID()}`, 5000),
          call(c2, `wd-b-${randomUUID()}`, 5000),
        ]);
        const fulfilled = results.filter((r) => r.status === 'fulfilled');
        assert.equal(fulfilled.length, 1, JSON.stringify(results.map((r) => r.reason?.message)));
        assert.match(results.find((r) => r.status === 'rejected').reason.message,
          /insufficient_earned_balance/);
        assert.equal(await count(
          "SELECT count(*)::int AS n FROM hocalist.withdrawal_requests WHERE user_id=$1 AND status='processing'",
          [IDS.buyer]), 1);
        assert.equal(await count(
          "SELECT coalesce(sum(amount_minor),0)::int AS n FROM hocalist.withdrawal_requests WHERE user_id=$1 AND status='processing'",
          [IDS.buyer]), 5000);
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('concurrent payout claims produce one immutable intent', async () => {
      await admin.query(`
        UPDATE hocalist.payout_policy SET provider_key='fake_payout', execution_enabled=true;
      `);
      const w = await admin.query(`
        INSERT INTO hocalist.withdrawal_requests(user_id,client_key,amount_minor,fee_minor,net_minor)
        VALUES('${IDS.buyer}','claim-race',2000,250,1750) RETURNING id`);
      const withdrawalId = w.rows[0].id;
      const c1 = await connect();
      const c2 = await connect();
      try {
        const call = (client) =>
          client.query("SELECT hocalist.payout_claim_internal(10,'race') AS result");
        const results = await Promise.allSettled([call(c1), call(c2)]);
        for (const result of results) {
          assert.equal(result.status, 'fulfilled', result.reason?.message);
        }
        assert.equal(await count(
          'SELECT count(*)::int AS n FROM hocalist.payout_attempts WHERE withdrawal_id=$1',
          [withdrawalId]), 1);
        // The persisted intent identity never changes, so a lost response can
        // only be reconciled through the same key.
        assert.equal(await count(
          'SELECT count(*)::int AS n FROM hocalist.payout_attempts WHERE withdrawal_id=$1 AND request_key=$2::text',
          [withdrawalId, withdrawalId]), 1);
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('a hold and a withdrawal cannot both reserve the same reward', async () => {
      // A won sale with one 4000 reward for the buyer.
      const deal = await seedDeal({ targetStatus: 'won', charged: 375, withSale: true, original: 400 });
      const outcomeId = (await admin.query(
        'SELECT id FROM hocalist.sale_confirmations WHERE request_id=$1', [deal.request])).rows[0].id;
      const reward = nextId('82000000-0000-4000-8010-');
      await admin.query(`
        INSERT INTO hocalist.buyer_rewards(id,outcome_id,target_id,buyer_user_id,amount_minor,rule_version)
        VALUES('${reward}','${outcomeId}','${deal.target}','${IDS.buyer}',4000,'race-v1');
        UPDATE hocalist.reversal_policy SET reward_hold_enabled=true, clawback_mode='same_batch_only';
        SELECT hocalist.reversal_open_internal('test','race-hold-ref','chargeback','buyer_reward',4000,
          NULL,'${outcomeId}',NULL,NULL);
      `);
      const reversalId = (await admin.query(
        "SELECT id FROM hocalist.payment_reversals WHERE provider_reference='race-hold-ref'")).rows[0].id;
      const adminClient = await connectAs(IDS.admin);
      const buyerClient = await connectAs(IDS.buyer);
      try {
        const hold = () => adminClient.query(
          "SELECT hocalist.reversal_admin_command('reversal.hold','race-hold-key',$1::jsonb) AS result",
          [JSON.stringify({ reversal_id: reversalId })]);
        const withdraw = () => buyerClient.query(
          "SELECT hocalist.withdrawal_request('race-hold-withdraw',4000) AS result");
        const results = await Promise.allSettled([hold(), withdraw()]);
        for (const result of results) {
          if (result.status === 'rejected') {
            assert.match(result.reason.message,
              /insufficient_earned_balance|below_minimum/);
          }
        }
        const holdMinor = Number((await admin.query(
          'SELECT hold_minor AS n FROM hocalist.payment_reversals WHERE id=$1', [reversalId])).rows[0].n);
        const processingMinor = await count(
          "SELECT coalesce(sum(amount_minor),0)::int AS n FROM hocalist.withdrawal_requests WHERE user_id=$1 AND status='processing'",
          [IDS.buyer]);
        // Earlier subtests also earned rewards and created withdrawals for
        // this identity. Conserve its complete ledger, not just the new row.
        const totalEarned = await count(
          'SELECT coalesce(sum(amount_minor),0)::int AS n FROM hocalist.buyer_rewards WHERE buyer_user_id=$1',
          [IDS.buyer]);
        assert.ok(holdMinor + processingMinor <= totalEarned,
          `hold ${holdMinor} + processing ${processingMinor} exceeded the reward`);
      } finally {
        await adminClient.end();
        await buyerClient.end();
      }
    });

    await t.test('concurrent reversal compensation debits the batch once', async () => {
      // 375 already charged leaves 400 available for the 150 correction.
      const deal = await seedDeal({ targetStatus: 'won', charged: 375, withSale: true, original: 775 });
      const outcomeRow = await admin.query(
        'SELECT id FROM hocalist.sale_confirmations WHERE request_id=$1', [deal.request]);
      const outcomeId = outcomeRow.rows[0].id;
      await admin.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [IDS.admin]);
      await admin.query(`
        UPDATE hocalist.reversal_policy SET clawback_mode='same_batch_only', reward_hold_enabled=true;
        SELECT hocalist.reversal_open_internal('test','race-ref','chargeback','credit_batch',150,
          NULL,'${outcomeId}',NULL,NULL);
        SELECT hocalist.reversal_admin_command('reversal.hold','race-hold',
          jsonb_build_object('reversal_id',(SELECT id FROM hocalist.payment_reversals
            WHERE provider_reference='race-ref')));
      `);
      const reversalId = (await admin.query(
        "SELECT id FROM hocalist.payment_reversals WHERE provider_reference='race-ref'")).rows[0].id;
      const c1 = await connectAs(IDS.admin);
      const c2 = await connectAs(IDS.admin);
      try {
        const call = (client, key) =>
          client.query(
            "SELECT hocalist.reversal_admin_command('reversal.compensate',$1,$2::jsonb) AS result",
            [key, JSON.stringify({ reversal_id: reversalId })]);
        const results = await Promise.allSettled([
          call(c1, `comp-${randomUUID()}`),
          call(c2, `comp-${randomUUID()}`),
        ]);
        const fulfilled = results.filter((r) => r.status === 'fulfilled');
        const rejected = results.filter((r) => r.status === 'rejected');
        assert.equal(fulfilled.length, 1, JSON.stringify(rejected.map((r) => r.reason?.message)));
        assert.match(rejected[0].reason.message, /reversal_final|hold_required/);
        assert.equal(await count(
          "SELECT count(*)::int AS n FROM hocalist.ledger_corrections WHERE reversal_id=$1 AND entry_kind='compensate'",
          [reversalId]), 1);
        assert.equal(await count(
          'SELECT balance_minor::int AS n FROM hocalist.credit_batches WHERE id=$1', [deal.batch]), 250);
      } finally {
        await c1.end();
        await c2.end();
      }
    });
  } finally {
    if (created) {
      await admin.query('DROP SCHEMA IF EXISTS hocalist CASCADE').catch(() => {});
      await admin.query('DROP SCHEMA IF EXISTS auth CASCADE').catch(() => {});
    }
    await admin.end();
  }
};

if (guardError) {
  test('multi-connection commercial concurrency on a disposable database', () => {
    throw guardError;
  });
} else {
  test(
    'multi-connection commercial concurrency on a disposable database',
    { skip: skipReason || false },
    runHarness,
  );
}

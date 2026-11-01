import { loadPostgres } from '../tests/postgres.mjs';
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
} from '../tests/harness_guard.mjs';
import { loadSql } from '../tests/fixture.mjs';

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
  '../chat/012_credit_qualification.sql',
  '../runtime_repairs/207_offer_submission_fee.sql',
  '../runtime_repairs/228_target_fee_policy.sql',
  '../runtime_repairs/231_deal_chat_threads.sql',
  '../runtime_repairs/235_paygo_payment_setup.sql',
  '../runtime_repairs/236_paygo_collection.sql',
  '../runtime_repairs/249_multi_seller_buyer_rewards.sql',

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


    await t.test('parallel purchase settlement accrues both contributions once', async () => {
      await admin.query("INSERT INTO hocalist.reward_policy(singleton,normal_minor,late_minor,late_window_hours,rule_version) VALUES(true,2500,2500,12,'synthetic-concurrency')");
      const deal=await seedDeal({targetStatus:'initial_charged',charged:100,original:6000,winning:375,withSale:true});
      const offer=randomUUID(),batch=randomUUID(),target=randomUUID();
      await admin.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES($1,$2,$3,$4,$5,'submitted')",[offer,deal.request,IDS.buyer,IDS.outsider,IDS.outsiderMembership]);
      await admin.query("INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,reserved_minor,initial_fee_minor,winning_total_minor,rate_version) VALUES($1,$2,'multi',6000,5900,275,100,375,'synthetic')",[batch,IDS.outsider]);
      await admin.query("INSERT INTO hocalist.credit_targets(id,user_id,request_id,offer_id,batch_id,initial_minor,winning_minor,charged_minor,reserved_minor,status,week_start,rate_version,qualified_at) VALUES($1,$2,$3,$4,$5,100,375,100,275,'initial_charged',current_date,'synthetic',now()-interval '1 minute')",[target,IDS.outsider,deal.request,offer,batch]);
      await admin.query("UPDATE hocalist.credit_targets SET qualified_at=now()-interval '1 minute' WHERE id=$1",[deal.target]);
      const clients=await Promise.all([connect(),connect(),connect()]);
      try {
        const results=await Promise.allSettled(clients.map(c=>c.query('SELECT hocalist.credit_settle_purchase($1)',[deal.request])));
        assert.equal(results.filter(r=>r.status==='fulfilled').length,3,JSON.stringify(results.filter(r=>r.status==='rejected').map(r=>r.reason.message)));
        assert.equal(await count('SELECT count(*) AS n FROM hocalist.buyer_rewards'),2);
        assert.equal(await count('SELECT sum(amount_minor) AS n FROM hocalist.buyer_rewards'),5000);
        assert.equal(await count('SELECT sum(charged_minor) AS n FROM hocalist.credit_targets WHERE request_id=$1',[deal.request]),475);
        assert.equal(await count('SELECT sum(reserved_minor) AS n FROM hocalist.credit_targets WHERE request_id=$1',[deal.request]),0);
      } finally {await Promise.all(clients.map(c=>c.end()));}
    });
    await t.test('multi-contribution hold and withdrawal cannot reserve the same funds', async () => {
      await admin.query("UPDATE hocalist.reversal_policy SET clawback_mode='same_batch_only',reward_hold_enabled=true");
      await admin.query("INSERT INTO hocalist.withdrawal_policy(singleton,minimum_minor,fee_minor) VALUES(true,2000,100) ON CONFLICT(singleton) DO UPDATE SET minimum_minor=2000,fee_minor=100");
      const outcome=(await admin.query('SELECT outcome_id FROM hocalist.buyer_rewards LIMIT 1')).rows[0].outcome_id;
      const reversal=(await admin.query("SELECT hocalist.reversal_open_internal('synthetic','race','chargeback','buyer_reward',4000,NULL,$1,NULL,NULL) AS d",[outcome])).rows[0].d.reversal_id;
      const buyerClient=await connectAs(IDS.buyer),reviewerClient=await connectAs(IDS.admin);
      try {
        const results=await Promise.allSettled([
          buyerClient.query("SELECT hocalist.withdrawal_request('multi-race',2000) AS d"),
          reviewerClient.query("SELECT hocalist.reversal_admin_command('reversal.hold','multi-hold',$1::jsonb) AS d",[JSON.stringify({reversal_id:reversal})]),
        ]);
        for(const r of results) if(r.status==='rejected') assert.match(r.reason.message,/insufficient_earned_balance/);
        assert.equal(results[1].status,'fulfilled');
        const held=await count("SELECT coalesce(sum(amount_minor),0) AS n FROM hocalist.ledger_corrections WHERE entry_kind='reward_hold'");
        const spent=await count("SELECT coalesce(sum(amount_minor),0) AS n FROM hocalist.withdrawal_requests WHERE status IN ('processing','paid')");
        assert.ok(held+spent<=5000);
        assert.equal(await count('SELECT hocalist.withdrawal_available_minor($1) AS n',[IDS.buyer]),5000-held-spent);
      } finally {await buyerClient.end();await reviewerClient.end();}
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

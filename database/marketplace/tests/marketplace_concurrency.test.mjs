import { loadPostgres } from '../../tests/postgres.mjs';
// Opt-in real multi-connection concurrency harness for the marketplace
// foundation: request-scoped offer selection, seller Store capacity and
// idempotency-receipt races.
//
// PGlite is single-connection and is never concurrency proof. This harness
// needs a genuine disposable PostgreSQL instance with superuser rights:
//
//   $env:HOCALIST_TEST_DATABASE_URL = 'postgres://postgres:postgres@127.0.0.1:5432/hocalist_test'
//   $env:HOCALIST_ALLOW_DISPOSABLE_DB = '1'
//   npm run test:concurrency
//
// Safety mirrors database/tests/concurrency.test.mjs: reserved databases and
// the shared Supabase project are refused, the target must be empty of
// auth/hocalist/public business objects before mutation, and the run removes
// only the schemas it created. Without the environment variables the suite
// reports NOT RUN.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
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

const requestInput = (title) => ({
  kind: 'product',
  title,
  description: 'Synthetic concurrency probe.',
  condition: 'used',
  quantity: 1,
  budget_minimum_minor: 1000,
  budget_maximum_minor: 2000,
  currency_code: 'USD',
  accepts_higher_offers: false,
  use_home_address: true,
});

const offerInput = (requestId) => ({
  request_id: requestId,
  price_minor: 1500,
  currency_code: 'USD',
  message: 'Synthetic offer.',
  image_media_ids: [],
  schedule_date: '2026-10-01',
  schedule_time: '18:30',
  schedule_timezone: 'America/New_York',
  place_choice: 'specific_place',
  place_label: 'Synthetic Mall',
});

const listingInput = (title) => ({
  kind: 'product',
  title,
  description: 'Synthetic listing.',
  category_id: '',
  price_label: '$10',
  service_area: 'Synthetic area',
  availability: 'Today',
  image_media_ids: [],
  publish_intent: 'draft',
});

const runHarness = async (t) => {
  const pg = await loadPostgres();
  const { Client } = pg;
  const admin = new Client({ connectionString: databaseUrl });
  await admin.connect();

  const connectAs = async (user) => {
    const client = new Client({ connectionString: databaseUrl });
    await client.connect();
    await client.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
    await client.query('SET ROLE authenticated');
    return client;
  };

  const command = (client, op, key, input) =>
    client.query('SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS result', [
      op, key, JSON.stringify(input),
    ]);

  const identity = async () => {
    const id = randomUUID();
    await admin.query(
      'INSERT INTO auth.users(id, raw_user_meta_data) VALUES ($1, $2)',
      [id, { full_name: 'Marketplace Concurrency Probe' }],
    );
    return id;
  };

  const onboard = async (user, role) => {
    const client = await connectAs(user);
    try {
      const result = await client.query(
        'SELECT hocalist.account_command($1,$2,$3::jsonb) AS result',
        ['onboard', `onboard-${randomUUID()}`, JSON.stringify({ role, display_name: `${role} probe` })],
      );
      return result.rows[0].result.profile_id;
    } finally {
      await client.end();
    }
  };

  const count = async (sql, params = []) =>
    Number((await admin.query(sql, params)).rows[0].n);

  const waitForBlockedLock = async () => {
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      const waiting = await admin.query('SELECT count(*)::int AS n FROM pg_locks WHERE NOT granted');
      if (waiting.rows[0].n > 0) return;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    throw new Error('timed out waiting for the concurrent writer to block on the row lock');
  };

  const expectRejected = async (promise, pattern) => {
    let error = null;
    try {
      await promise;
    } catch (caught) {
      error = caught;
    }
    assert.ok(error, `expected rejection matching ${pattern}`);
    assert.match(error.message, pattern);
  };

  let created = false;
  try {
    const content = await admin.query(`
      SELECT
        (SELECT coalesce(array_agg(nspname), ARRAY[]::name[]) FROM pg_namespace
          WHERE nspname IN ('auth', 'hocalist')) AS schemas,
        (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')) AS public_relations,
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
    `);
    await admin.query(`
      CREATE SCHEMA auth;
      CREATE TABLE auth.users(id uuid PRIMARY KEY, raw_user_meta_data jsonb);
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
    await admin.query(await loadSql('../drafts/003_membership_private_profiles.sql'));
    await admin.query(await loadSql('../drafts/004_account_commands.sql'));
    await admin.query(
      await readFile(new URL('../../chat/010_chat_foundation.sql', import.meta.url), 'utf8'),
    );
    await admin.query(
      await readFile(new URL('../../marketplace/020_marketplace_foundation.sql', import.meta.url), 'utf8'),
    );
    const category = (await admin.query(
      "INSERT INTO hocalist.catalogue_categories(label, scope) VALUES ('Synthetic','both') RETURNING id",
    )).rows[0].id;

    await t.test('competing selections for one request leave exactly one accepted offer', async () => {
      const buyer = await identity();
      await onboard(buyer, 'buyer');
      const sellerB = await identity();
      await onboard(sellerB, 'seller');
      const sellerC = await identity();
      await onboard(sellerC, 'seller');

      const buyerClient = await connectAs(buyer);
      let requestId;
      try {
        requestId = (await command(buyerClient, 'request.create', `req-${randomUUID()}`, requestInput('Synthetic request'))).rows[0].result.id;
      } finally {
        await buyerClient.end();
      }

      const submitOffer = async (seller) => {
        const client = await connectAs(seller);
        try {
          return (await command(client, 'offer.submit', `offer-${randomUUID()}`, offerInput(requestId))).rows[0].result;
        } finally {
          await client.end();
        }
      };
      const offerB = await submitOffer(sellerB);
      const offerC = await submitOffer(sellerC);

      const c1 = await connectAs(buyer);
      const c2 = await connectAs(buyer);
      try {
        await c1.query('BEGIN');
        const selected = (await command(c1, 'offer.select', `select-${randomUUID()}`, {
          offer_id: offerB.id,
          revision_id: offerB.revisions[0].id,
          expected_offer_revision: 1,
        })).rows[0].result;
        assert.equal(selected.status, 'selected');

        const pending = command(c2, 'offer.select', `select-${randomUUID()}`, {
          offer_id: offerC.id,
          revision_id: offerC.revisions[0].id,
          expected_offer_revision: 1,
        });
        await waitForBlockedLock();
        await c1.query('COMMIT');
        await expectRejected(pending, /selection_policy_pending/);

        assert.equal(
          await count(
            "SELECT count(*)::int AS n FROM hocalist.offers WHERE request_id=$1 AND status='selected'",
            [requestId],
          ),
          1,
        );
      } finally {
        await c1.query('ROLLBACK').catch(() => {});
        await c1.end();
        await c2.end();
      }
    });

    await t.test('parallel Store creates cannot pass the last remaining slot', async () => {
      const seller = await identity();
      await onboard(seller, 'seller');
      const client = await connectAs(seller);
      try {
        for (const title of ['First listing', 'Second listing']) {
          await command(client, 'store.create', `seed-${randomUUID()}`, {
            ...listingInput(title),
            category_id: category,
          });
        }
      } finally {
        await client.end();
      }

      const c1 = await connectAs(seller);
      const c2 = await connectAs(seller);
      try {
        await c1.query('BEGIN');
        const third = (await command(c1, 'store.create', `cap-${randomUUID()}`, {
          ...listingInput('Third listing'),
          category_id: category,
        })).rows[0].result;
        assert.equal(third.status, 'draft');

        const pending = command(c2, 'store.create', `cap-${randomUUID()}`, {
          ...listingInput('Fourth listing'),
          category_id: category,
        });
        await waitForBlockedLock();
        await c1.query('COMMIT');
        await expectRejected(pending, /store_limit_exceeded/);

        assert.equal(
          await count(
            "SELECT count(*)::int AS n FROM hocalist.store_listings WHERE seller_user_id=$1 AND status <> 'archived'",
            [seller],
          ),
          3,
        );
      } finally {
        await c1.query('ROLLBACK').catch(() => {});
        await c1.end();
        await c2.end();
      }
    });

    await t.test('parallel same-key retries replay one committed result', async () => {
      const buyer = await identity();
      await onboard(buyer, 'buyer');
      const c1 = await connectAs(buyer);
      const c2 = await connectAs(buyer);
      try {
        const key = `same-${randomUUID()}`;
        const input = requestInput('Synthetic same-key request');
        const [r1, r2] = await Promise.all([
          command(c1, 'request.create', key, input),
          command(c2, 'request.create', key, input),
        ]);
        assert.deepEqual(r1.rows[0].result, r2.rows[0].result);
        assert.equal(
          await count('SELECT count(*)::int AS n FROM hocalist.requests WHERE buyer_user_id=$1', [buyer]),
          1,
        );
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('parallel same-key changed payloads leave one winner', async () => {
      const buyer = await identity();
      await onboard(buyer, 'buyer');
      const c1 = await connectAs(buyer);
      const c2 = await connectAs(buyer);
      try {
        const key = `changed-${randomUUID()}`;
        const results = await Promise.allSettled([
          command(c1, 'request.create', key, requestInput('Synthetic winner one')),
          command(c2, 'request.create', key, requestInput('Synthetic winner two')),
        ]);
        const fulfilled = results.filter((result) => result.status === 'fulfilled');
        const rejected = results.filter((result) => result.status === 'rejected');
        assert.equal(fulfilled.length, 1);
        assert.equal(rejected.length, 1);
        assert.match(rejected[0].reason.message, /idempotency_conflict/);
        assert.equal(
          await count('SELECT count(*)::int AS n FROM hocalist.requests WHERE buyer_user_id=$1', [buyer]),
          1,
        );
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
  test('multi-connection marketplace concurrency on a disposable database', () => {
    throw guardError;
  });
} else {
  test(
    'multi-connection marketplace concurrency on a disposable database',
    { skip: skipReason || false },
    runHarness,
  );
}

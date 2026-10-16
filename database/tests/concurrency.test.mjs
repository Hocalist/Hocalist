import { loadPostgres } from './postgres.mjs';
// Opt-in real multi-connection concurrency harness for the account commands.
//
// PGlite is single-connection and is never concurrency proof. This harness
// needs a genuine disposable PostgreSQL instance with superuser rights to
// create the synthetic auth fixture and roles:
//
//   $env:HOCALIST_TEST_DATABASE_URL = 'postgres://postgres:postgres@127.0.0.1:5432/hocalist_test'
//   $env:HOCALIST_ALLOW_DISPOSABLE_DB = '1'
//   npm run test:concurrency
//
// Safety: the database name must contain test/disposable/scratch/tmp even on
// localhost, reserved databases and the shared Supabase project are refused,
// and the target must be empty of auth/hocalist/public business objects before
// any mutation. The run creates only its own schemas and removes only those
// schemas at the end; it never drops pre-existing objects. Without the
// environment variables the suite reports NOT RUN.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import {
  assertConcurrencyTarget,
  assertEmptyTargetContents,
  concurrencySkipReason,
} from './harness_guard.mjs';
import { loadSql } from './fixture.mjs';

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

const runHarness = async (t) => {
  const pg = await loadPostgres();
  const { Client } = pg;
  const admin = new Client({ connectionString: databaseUrl });
  await admin.connect();

  const command = (client, op, key, input) =>
    client.query('SELECT hocalist.account_command($1,$2,$3::jsonb) AS result', [
      op, key, JSON.stringify(input),
    ]);

  const connectAs = async (user) => {
    const client = new Client({ connectionString: databaseUrl });
    await client.connect();
    await client.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
    await client.query('SET ROLE authenticated');
    return client;
  };

  const expectConflict = (settled, message) => {
    assert.equal(settled.status, 'rejected', `expected ${message}`);
    assert.match(settled.reason.message, new RegExp(message));
  };

  const identity = async () => {
    const id = randomUUID();
    await admin.query('INSERT INTO auth.users(id, raw_user_meta_data) VALUES ($1, $2)', [id, { full_name: 'Concurrency Probe' }]);
    return id;
  };

  const count = async (sql, params = []) => Number((await admin.query(sql, params)).rows[0].n);

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

    await t.test('simultaneous same-key retries converge on one result', async () => {
      const user = await identity();
      const c1 = await connectAs(user);
      const c2 = await connectAs(user);
      const key = `same-key-${randomUUID()}`;
      const input = { role: 'buyer', display_name: 'Same Key' };
      try {
        const [r1, r2] = await Promise.allSettled([
          command(c1, 'onboard', key, input),
          command(c2, 'onboard', key, input),
        ]);
        assert.equal(r1.status, 'fulfilled', r1.reason?.message);
        assert.equal(r2.status, 'fulfilled', r2.reason?.message);
        assert.deepEqual(r1.value.rows[0].result, r2.value.rows[0].result);
        assert.equal(await count('SELECT count(*)::int AS n FROM hocalist.memberships WHERE user_id=$1', [user]), 1);
        assert.equal(await count('SELECT count(*)::int AS n FROM hocalist.command_receipts WHERE user_id=$1', [user]), 1);
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('same key with different payloads has exactly one winner', async () => {
      const user = await identity();
      const c1 = await connectAs(user);
      const c2 = await connectAs(user);
      const key = `conflict-key-${randomUUID()}`;
      const first = { role: 'buyer', display_name: 'Winner One' };
      const second = { role: 'buyer', display_name: 'Winner Two' };
      try {
        const results = await Promise.allSettled([
          command(c1, 'onboard', key, first),
          command(c2, 'onboard', key, second),
        ]);
        const fulfilled = results.filter((result) => result.status === 'fulfilled');
        const rejected = results.filter((result) => result.status === 'rejected');
        assert.equal(fulfilled.length, 1);
        assert.equal(rejected.length, 1);
        assert.match(rejected[0].reason.message, /idempotency_conflict/);
        const row = await admin.query(
          'SELECT p.display_name FROM hocalist.role_profiles p JOIN hocalist.memberships m ON m.id=p.membership_id WHERE m.user_id=$1',
          [user],
        );
        const winnerInput = results[0].status === 'fulfilled' ? first : second;
        assert.equal(row.rows[0].display_name, winnerInput.display_name);
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('competing expected revisions leave one consistent winner', async () => {
      const user = await identity();
      const setup = await connectAs(user);
      let profileId;
      try {
        const onboarded = await command(setup, 'onboard', `rev-seed-${randomUUID()}`, {
          role: 'buyer', display_name: 'Revision Base',
        });
        profileId = onboarded.rows[0].result.profile_id;
      } finally {
        await setup.end();
      }
      const c1 = await connectAs(user);
      const c2 = await connectAs(user);
      try {
        const results = await Promise.allSettled([
          command(c1, 'profile.update', `rev-a-${randomUUID()}`, {
            profile_id: profileId, expected_revision: 1, display_name: 'Revision A',
          }),
          command(c2, 'profile.update', `rev-b-${randomUUID()}`, {
            profile_id: profileId, expected_revision: 1, display_name: 'Revision B',
          }),
        ]);
        const fulfilled = results.filter((result) => result.status === 'fulfilled');
        const rejected = results.filter((result) => result.status === 'rejected');
        assert.equal(fulfilled.length, 1);
        assert.equal(rejected.length, 1);
        expectConflict(rejected[0], 'revision_conflict');
        assert.equal(fulfilled[0].value.rows[0].result.revision, 2);
        const row = await admin.query(
          'SELECT display_name, revision FROM hocalist.role_profiles WHERE membership_id=$1',
          [profileId],
        );
        assert.equal(row.rows[0].revision, '2');
        const winnerName = results[0].status === 'fulfilled' ? 'Revision A' : 'Revision B';
        assert.equal(row.rows[0].display_name, winnerName);
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('buyer and seller onboarding for one identity both commit', async () => {
      const user = await identity();
      const c1 = await connectAs(user);
      const c2 = await connectAs(user);
      try {
        const results = await Promise.allSettled([
          command(c1, 'onboard', `buyer-${randomUUID()}`, { role: 'buyer', display_name: 'Both Buyer' }),
          command(c2, 'onboard', `seller-${randomUUID()}`, { role: 'seller', display_name: 'Both Seller' }),
        ]);
        for (const result of results) {
          assert.equal(result.status, 'fulfilled', result.reason?.message);
        }
        assert.equal(await count("SELECT count(*)::int AS n FROM hocalist.memberships WHERE user_id=$1", [user]), 2);
        assert.equal(await count("SELECT count(*)::int AS n FROM hocalist.role_profiles p JOIN hocalist.memberships m ON m.id=p.membership_id WHERE m.user_id=$1", [user]), 2);
        assert.equal(await count('SELECT count(*)::int AS n FROM hocalist.profile_contacts WHERE user_id=$1', [user]), 1);
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('competing contact revisions leave one consistent winner', async () => {
      const user = await identity();
      const setup = await connectAs(user);
      try {
        await command(setup, 'onboard', `contact-seed-${randomUUID()}`, { role: 'buyer', display_name: 'Contact Base' });
      } finally {
        await setup.end();
      }
      const c1 = await connectAs(user);
      const c2 = await connectAs(user);
      try {
        const results = await Promise.allSettled([
          command(c1, 'contact.update', `contact-a-${randomUUID()}`, { expected_revision: 1, city: 'City A' }),
          command(c2, 'contact.update', `contact-b-${randomUUID()}`, { expected_revision: 1, city: 'City B' }),
        ]);
        const fulfilled = results.filter((result) => result.status === 'fulfilled');
        const rejected = results.filter((result) => result.status === 'rejected');
        assert.equal(fulfilled.length, 1);
        assert.equal(rejected.length, 1);
        expectConflict(rejected[0], 'revision_conflict');
        const row = await admin.query('SELECT city, revision FROM hocalist.profile_contacts WHERE user_id=$1', [user]);
        assert.equal(row.rows[0].revision, '2');
        assert.ok(['City A', 'City B'].includes(row.rows[0].city));
      } finally {
        await c1.end();
        await c2.end();
      }
    });

    await t.test('parallel replay of a committed key returns the stored result', async () => {
      const user = await identity();
      const seed = await connectAs(user);
      const key = `replay-${randomUUID()}`;
      const input = { role: 'buyer', display_name: 'Replay Base' };
      let stored;
      try {
        stored = (await command(seed, 'onboard', key, input)).rows[0].result;
      } finally {
        await seed.end();
      }
      const c1 = await connectAs(user);
      const c2 = await connectAs(user);
      try {
        const results = await Promise.allSettled([
          command(c1, 'onboard', key, input),
          command(c2, 'onboard', key, input),
        ]);
        for (const result of results) {
          assert.equal(result.status, 'fulfilled', result.reason?.message);
          assert.deepEqual(result.value.rows[0].result, stored);
        }
        assert.equal(await count('SELECT count(*)::int AS n FROM hocalist.memberships WHERE user_id=$1', [user]), 1);
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
  test('multi-connection account command concurrency on a disposable database', () => {
    throw guardError;
  });
} else {
  test(
    'multi-connection account command concurrency on a disposable database',
    { skip: skipReason || false },
    runHarness,
  );
}

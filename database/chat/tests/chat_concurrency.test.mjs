import { loadPostgres } from '../../tests/postgres.mjs';
// Opt-in real multi-connection concurrency harness for the chat read marker.
//
// PGlite is single-connection and is never concurrency proof. This harness
// needs a genuine disposable PostgreSQL instance with superuser rights to
// create the synthetic auth fixture and roles:
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
    client.query('SELECT hocalist.account_command($1,$2,$3::jsonb) AS result', [
      op, key, JSON.stringify(input),
    ]);

  const identity = async () => {
    const id = randomUUID();
    await admin.query(
      'INSERT INTO auth.users(id, raw_user_meta_data) VALUES ($1, $2)',
      [id, { full_name: 'Chat Concurrency Probe' }],
    );
    return id;
  };

  const onboard = async (user, role) => {
    const client = await connectAs(user);
    try {
      const result = await command(client, 'onboard', `onboard-${randomUUID()}`, {
        role,
        display_name: `${role} probe`,
      });
      return result.rows[0].result.profile_id;
    } finally {
      await client.end();
    }
  };

  const waitForBlockedLock = async () => {
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      const waiting = await admin.query('SELECT count(*)::int AS n FROM pg_locks WHERE NOT granted');
      if (waiting.rows[0].n > 0) return;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    throw new Error('timed out waiting for the concurrent mark-read to block on the row lock');
  };

  const readMarker = async (conversation, user) =>
    (await admin.query(
      'SELECT last_read_seq::int, last_read_message_id FROM hocalist.conversation_members WHERE conversation_id=$1 AND user_id=$2',
      [conversation, user],
    )).rows[0];

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

    await t.test('an older mark-read cannot overwrite a newer committed position', async () => {
      const buyer = await identity();
      const seller = await identity();
      const buyerProfile = await onboard(buyer, 'buyer');
      const sellerProfile = await onboard(seller, 'seller');

      const opened = await admin.query(
        `SELECT hocalist.chat_open_internal('targeted_request',$1,NULL,NULL,NULL,$2::jsonb) AS id`,
        [
          randomUUID(),
          JSON.stringify([
            { user_id: buyer, profile_id: buyerProfile, role: 'buyer' },
            { user_id: seller, profile_id: sellerProfile, role: 'seller' },
          ]),
        ],
      );
      const conversation = opened.rows[0].id;

      const sender = await connectAs(buyer);
      let first;
      let second;
      try {
        first = (await sender.query(
          "SELECT hocalist.chat_send($1,'race-key-1','first message') AS message",
          [conversation],
        )).rows[0].message;
        second = (await sender.query(
          "SELECT hocalist.chat_send($1,'race-key-2','second message') AS message",
          [conversation],
        )).rows[0].message;
      } finally {
        await sender.end();
      }
      assert.ok(second.seq > first.seq, 'sequence must advance');

      const newer = await connectAs(buyer);
      const older = await connectAs(buyer);
      try {
        await newer.query('BEGIN');
        const advanced = (await newer.query(
          'SELECT hocalist.chat_mark_read($1,$2) AS member',
          [conversation, second.id],
        )).rows[0].member;
        assert.equal(advanced.last_read_message_id, second.id);
        assert.equal(advanced.last_read_seq, second.seq);

        // The older session has already read the pre-commit member row and now
        // waits on the row lock the newer session holds.
        const pending = older.query(
          'SELECT hocalist.chat_mark_read($1,$2) AS member',
          [conversation, first.id],
        );
        await waitForBlockedLock();
        await newer.query('COMMIT');

        const stale = (await pending).rows[0].member;
        assert.equal(stale.last_read_message_id, second.id, 'older session returns the newer marker');
        assert.equal(stale.last_read_seq, second.seq);

        const stored = await readMarker(conversation, buyer);
        assert.equal(stored.last_read_message_id, second.id, 'committed marker is not rolled back');
        assert.equal(stored.last_read_seq, second.seq);

        const noop = (await older.query(
          'SELECT hocalist.chat_mark_read($1,$2) AS member',
          [conversation, first.id],
        )).rows[0].member;
        assert.equal(noop.last_read_message_id, second.id, 'no-op returns the authoritative marker');
        assert.equal(noop.last_read_seq, second.seq);
      } finally {
        await newer.query('ROLLBACK').catch(() => {});
        await newer.end();
        await older.end();
      }
    });

    await t.test('concurrent advancing mark-reads keep the highest position', async () => {
      const buyer = await identity();
      const seller = await identity();
      const buyerProfile = await onboard(buyer, 'buyer');
      const sellerProfile = await onboard(seller, 'seller');

      const opened = await admin.query(
        `SELECT hocalist.chat_open_internal('store_listing',NULL,NULL,$1,NULL,$2::jsonb) AS id`,
        [
          randomUUID(),
          JSON.stringify([
            { user_id: seller, profile_id: sellerProfile, role: 'seller' },
            { user_id: buyer, profile_id: buyerProfile, role: 'buyer' },
          ]),
        ],
      );
      const conversation = opened.rows[0].id;

      const sender = await connectAs(buyer);
      let first;
      let second;
      try {
        first = (await sender.query(
          "SELECT hocalist.chat_send($1,'advance-key-1','one') AS message",
          [conversation],
        )).rows[0].message;
        second = (await sender.query(
          "SELECT hocalist.chat_send($1,'advance-key-2','two') AS message",
          [conversation],
        )).rows[0].message;
      } finally {
        await sender.end();
      }

      const c1 = await connectAs(buyer);
      const c2 = await connectAs(buyer);
      try {
        await c1.query('BEGIN');
        const firstMark = (await c1.query(
          'SELECT hocalist.chat_mark_read($1,$2) AS member',
          [conversation, first.id],
        )).rows[0].member;
        assert.equal(firstMark.last_read_seq, first.seq);

        const pending = c2.query(
          'SELECT hocalist.chat_mark_read($1,$2) AS member',
          [conversation, second.id],
        );
        await waitForBlockedLock();
        await c1.query('COMMIT');

        const secondMark = (await pending).rows[0].member;
        assert.equal(secondMark.last_read_message_id, second.id);
        assert.equal(secondMark.last_read_seq, second.seq);

        const stored = await readMarker(conversation, buyer);
        assert.equal(stored.last_read_message_id, second.id);
        assert.equal(stored.last_read_seq, second.seq);
      } finally {
        await c1.query('ROLLBACK').catch(() => {});
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
  test('multi-connection chat mark-read concurrency on a disposable database', () => {
    throw guardError;
  });
} else {
  test(
    'multi-connection chat mark-read concurrency on a disposable database',
    { skip: skipReason || false },
    runHarness,
  );
}

// Disposable PostgreSQL checks for the secured Places gateway.
//
// PGlite is single-connection: this is deterministic SQL proof for membership
// gating, identity-bound sessions, suggestion validation, request ceilings and
// storage privacy. It is NOT real JWT, PostgREST, multi-instance concurrency or
// provider-call proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const C = '00000000-0000-4000-8000-00000000000c';
const E = '00000000-0000-4000-8000-00000000000e';
const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MC = '10000000-0000-4000-8000-00000000000c';
const S1 = '30000000-0000-4000-8000-000000000001';
const S2 = '30000000-0000-4000-8000-000000000002';
const S3 = '30000000-0000-4000-8000-000000000003';
const PLACE_A = 'ChIJ_places_gateway_a';
const PLACE_B = 'ChIJ_places_gateway_b';

async function asService(db, sql, params = []) {
  await db.exec('SET ROLE service_role');
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('RESET ROLE');
  }
}

async function asAuthenticated(db, sql, params = []) {
  await db.exec('SET ROLE authenticated');
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('RESET ROLE');
  }
}

const gate = async (db, user, operation, session, input = null, placeId = null) =>
  (await asService(
    db,
    'SELECT hocalist.places_gate($1,$2,$3,$4,$5) AS decision',
    [user, operation, session, input, placeId],
  ))[0].decision;

const record = async (db, session, user, ids) =>
  (await asService(
    db,
    'SELECT hocalist.places_record_suggestions($1,$2,$3::text[]) AS result',
    [session, user, ids],
  ))[0].result;

const resolve = async (db, session, user) =>
  (await asService(
    db,
    'SELECT hocalist.places_resolve_session($1,$2) AS result',
    [session, user],
  ))[0].result;

const release = async (db, session, user) =>
  (await asService(
    db,
    'SELECT hocalist.places_release_session($1,$2) AS result',
    [session, user],
  ))[0].result;

// Pins the current and next minute/day buckets so a clock rollover during a
// test cannot silently reset the counter under test.
async function seedCounter(db, scope, operation, windowKind, count) {
  const unit = windowKind === 'minute' ? 'minute' : 'day';
  await db.query(
    `INSERT INTO hocalist.places_rate_counters(scope, operation, window_kind, bucket, count)
     SELECT $1, $2, $3, date_trunc($4, now()) + make_interval(mins => off), $5
     FROM generate_series(0, 1) AS off
     ON CONFLICT (scope, operation, window_kind, bucket) DO UPDATE SET count = excluded.count`,
    [scope, operation, windowKind, unit, count],
  );
}

async function seed(db) {
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${A}','{}'),('${B}','{}'),('${C}','{}'),('${E}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${MA}','${A}','buyer','active'),
      ('${MB}','${B}','seller','active'),
      ('${MC}','${C}','seller','restricted');
    INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
      ('${MA}','Buyer A'),('${MB}','Seller B'),('${MC}','Seller C');
  `);
}

test('secured Places gateway in disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyAccountDrafts(db);
    await db.exec(
      await readFile(new URL('../050_places_gateway.sql', import.meta.url), 'utf8'),
    );
    await seed(db);

    await t.test('client roles cannot execute the service RPCs', async () => {
      for (
        const call of [
          `SELECT hocalist.places_gate('${A}','autocomplete','${S1}','x',null)`,
          `SELECT hocalist.places_record_suggestions('${S1}','${A}',ARRAY['x'])`,
          `SELECT hocalist.places_resolve_session('${S1}','${A}')`,
          `SELECT hocalist.places_release_session('${S1}','${A}')`,
        ]
      ) {
        await assert.rejects(
          () => asAuthenticated(db, call),
          (error) => error.code === '42501',
          `authenticated must not execute ${call}`,
        );
      }
    });

    await t.test('a member without active membership is refused', async () => {
      const outsider = await gate(db, E, 'autocomplete', S1, 'coffee');
      assert.equal(outsider.decision, 'membership_required');
      const restricted = await gate(db, C, 'autocomplete', S2, 'coffee');
      assert.equal(restricted.decision, 'membership_required');
      const rows = await db.query(
        'SELECT count(*)::int AS n FROM hocalist.places_search_sessions',
      );
      assert.equal(rows.rows[0].n, 0, 'refused calls must not create sessions');
    });

    await t.test('invalid input is rejected before any session work', async () => {
      assert.equal(
        (await gate(db, A, 'geocode', S1, 'coffee')).decision,
        'invalid_input',
      );
      assert.equal(
        (await gate(db, A, 'autocomplete', S1, '   ')).decision,
        'invalid_input',
      );
      assert.equal(
        (await gate(db, A, 'autocomplete', S1, 'x'.repeat(201))).decision,
        'invalid_input',
      );
      assert.equal(
        (await gate(db, A, 'details', S1, null, '../secret')).decision,
        'invalid_input',
      );
      assert.equal(
        (await gate(db, A, 'details', S1, null, null)).decision,
        'invalid_input',
      );
    });

    await t.test('autocomplete binds a session to the member and counts operations', async () => {
      const first = await gate(db, A, 'autocomplete', S1, 'public library');
      assert.equal(first.decision, 'allowed');
      assert.equal(first.user_id, A);
      const stored = await db.query(
        'SELECT user_id, operation_count, resolved_at FROM hocalist.places_search_sessions WHERE token=$1',
        [S1],
      );
      assert.equal(stored.rows[0].user_id, A);
      assert.equal(stored.rows[0].operation_count, 1);
      assert.equal(stored.rows[0].resolved_at, null);

      const second = await gate(db, A, 'autocomplete', S1, 'public librar');
      assert.equal(second.decision, 'allowed');
      const after = await db.query(
        'SELECT operation_count FROM hocalist.places_search_sessions WHERE token=$1',
        [S1],
      );
      assert.equal(after.rows[0].operation_count, 2);

      const other = await gate(db, B, 'autocomplete', S1, 'public library');
      assert.equal(other.decision, 'session_invalid');
    });

    await t.test('suggestion recording is bounded and owner-scoped', async () => {
      const foreign = await record(db, S1, B, [PLACE_A]);
      assert.equal(foreign.recorded, false);
      assert.equal(foreign.reason, 'session_invalid');

      const oversized = await record(db, S1, A, Array(6).fill(PLACE_A));
      assert.equal(oversized.recorded, false);
      assert.equal(oversized.reason, 'invalid_input');

      const injected = await record(db, S1, A, ['../secret']);
      assert.equal(injected.recorded, false);
      assert.equal(injected.reason, 'invalid_input');

      const accepted = await record(db, S1, A, [PLACE_A, PLACE_B]);
      assert.equal(accepted.recorded, true);
      const stored = await db.query(
        'SELECT place_id FROM hocalist.places_search_suggestions WHERE session_token=$1 ORDER BY place_id',
        [S1],
      );
      assert.deepEqual(stored.rows.map((row) => row.place_id), [PLACE_A, PLACE_B]);
    });

    await t.test('details requires a suggestion from the same session', async () => {
      const unselected = await gate(db, A, 'details', S1, null, 'ChIJ_never_seen');
      assert.equal(unselected.decision, 'suggestion_required');

      const foreign = await gate(db, B, 'details', S1, null, PLACE_A);
      assert.equal(foreign.decision, 'session_invalid');

      const allowed = await gate(db, A, 'details', S1, null, PLACE_A);
      assert.equal(allowed.decision, 'allowed');
      const reserved = await db.query(
        'SELECT resolving_at FROM hocalist.places_search_sessions WHERE token=$1',
        [S1],
      );
      assert.notEqual(reserved.rows[0].resolving_at, null);
    });

    await t.test('a concurrent details call is refused until the reservation clears', async () => {
      const busy = await gate(db, A, 'details', S1, null, PLACE_A);
      assert.equal(busy.decision, 'session_busy');

      const released = await release(db, S1, A);
      assert.equal(released.released, true);
      const retry = await gate(db, A, 'details', S1, null, PLACE_A);
      assert.equal(retry.decision, 'allowed');

      const foreignRelease = await release(db, S1, B);
      assert.equal(foreignRelease.released, false);
    });

    await t.test('resolving closes the session and is idempotent', async () => {
      const foreign = await resolve(db, S1, B);
      assert.equal(foreign.resolved, false);
      const done = await resolve(db, S1, A);
      assert.equal(done.resolved, true);
      const again = await resolve(db, S1, A);
      assert.equal(again.resolved, false);
      assert.equal(
        (await gate(db, A, 'details', S1, null, PLACE_A)).decision,
        'session_expired',
      );
      assert.equal(
        (await gate(db, A, 'autocomplete', S1, 'library')).decision,
        'session_expired',
      );
    });

    await t.test('expired and exhausted sessions are refused', async () => {
      const expired = await gate(db, A, 'autocomplete', S2, 'coffee');
      assert.equal(expired.decision, 'allowed');
      await db.query(
        "UPDATE hocalist.places_search_sessions SET expires_at = now() - interval '1 minute' WHERE token=$1",
        [S2],
      );
      assert.equal(
        (await gate(db, A, 'autocomplete', S2, 'coffee')).decision,
        'session_expired',
      );
      assert.equal((await record(db, S2, A, [PLACE_A])).reason, 'session_invalid');

      const exhausted = await gate(db, A, 'autocomplete', S3, 'tea');
      assert.equal(exhausted.decision, 'allowed');
      await db.query(
        'UPDATE hocalist.places_search_sessions SET operation_count = 10 WHERE token=$1',
        [S3],
      );
      assert.equal(
        (await gate(db, A, 'autocomplete', S3, 'tea')).decision,
        'session_exhausted',
      );
    });

    await t.test('per-user and shared request ceilings are enforced', async () => {
      const fresh = '30000000-0000-4000-8000-000000000010';
      const freshUser = '00000000-0000-4000-8000-00000000000d';
      await db.exec(`
        INSERT INTO auth.users(id, raw_user_meta_data) VALUES ('${freshUser}','{}');
        INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
          ('10000000-0000-4000-8000-00000000000d','${freshUser}','buyer','active');
        INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
          ('10000000-0000-4000-8000-00000000000d','Buyer D');
      `);
      assert.equal(
        (await gate(db, freshUser, 'autocomplete', fresh, 'coffee')).decision,
        'allowed',
      );

      await seedCounter(db, `u:${freshUser}`, 'autocomplete', 'minute', 20);
      assert.equal(
        (await gate(db, freshUser, 'autocomplete', fresh, 'coffee')).decision,
        'rate_limited',
      );
      await db.query(
        "DELETE FROM hocalist.places_rate_counters WHERE scope = $1 AND window_kind = 'minute'",
        [`u:${freshUser}`],
      );

      await seedCounter(db, `u:${freshUser}`, 'autocomplete', 'day', 200);
      assert.equal(
        (await gate(db, freshUser, 'autocomplete', fresh, 'coffee')).decision,
        'rate_limited',
      );
      await db.query(
        "DELETE FROM hocalist.places_rate_counters WHERE scope = $1 AND window_kind = 'day'",
        [`u:${freshUser}`],
      );

      await seedCounter(db, 'g', 'autocomplete', 'minute', 50);
      assert.equal(
        (await gate(db, freshUser, 'autocomplete', fresh, 'coffee')).decision,
        'rate_limited',
      );
      await db.query(
        "DELETE FROM hocalist.places_rate_counters WHERE scope = 'g' AND operation = 'autocomplete' AND window_kind = 'minute'",
      );

      await record(db, fresh, freshUser, [PLACE_A]);
      await seedCounter(db, `u:${freshUser}`, 'details', 'minute', 10);
      assert.equal(
        (await gate(db, freshUser, 'details', fresh, null, PLACE_A)).decision,
        'rate_limited',
      );
      await db.query(
        "DELETE FROM hocalist.places_rate_counters WHERE scope = $1 AND operation = 'details' AND window_kind = 'minute'",
        [`u:${freshUser}`],
      );

      await seedCounter(db, 'g', 'details', 'day', 180);
      assert.equal(
        (await gate(db, freshUser, 'details', fresh, null, PLACE_A)).decision,
        'rate_limited',
      );
      await db.query(
        "DELETE FROM hocalist.places_rate_counters WHERE scope = 'g' AND operation = 'details' AND window_kind = 'day'",
      );

      assert.equal(
        (await gate(db, freshUser, 'details', fresh, null, PLACE_A)).decision,
        'allowed',
      );
    });

    await t.test('gateway stores only place ids, never queries or addresses', async () => {
      const columns = await db.query(`
        SELECT table_name, column_name FROM information_schema.columns
        WHERE table_schema='hocalist'
          AND table_name IN ('places_search_sessions','places_search_suggestions','places_rate_counters')
      `);
      const forbidden = /(query|label|address|input|display|formatted|latitude|longitude)/i;
      assert.deepEqual(
        columns.rows.filter((row) => forbidden.test(row.column_name)),
        [],
      );
      const stored = await db.query(`
        SELECT string_agg(place_id, ',') AS ids FROM hocalist.places_search_suggestions
      `);
      for (const id of stored.rows[0].ids.split(',')) {
        assert.match(id, /^[A-Za-z0-9_-]{1,256}$/);
      }
      const grants = await db.query(`
        SELECT count(*)::int AS n FROM information_schema.role_table_grants
        WHERE table_schema='hocalist'
          AND table_name IN ('places_search_sessions','places_search_suggestions','places_rate_counters')
          AND grantee IN ('anon','authenticated')
      `);
      assert.equal(grants.rows[0].n, 0);
    });

    await t.test('bounded cleanup removes stale counters and sessions', async () => {
      await db.query(
        `INSERT INTO hocalist.places_rate_counters(scope, operation, window_kind, bucket, count)
         VALUES ('g','autocomplete','day', now() - interval '3 days', 1)`,
      );
      await db.query(
        `INSERT INTO hocalist.places_search_sessions(token, user_id, expires_at)
         VALUES ('30000000-0000-4000-8000-0000000000ff', $1, now() - interval '2 days')`,
        [A],
      );
      const probe = '30000000-0000-4000-8000-000000000011';
      assert.equal(
        (await gate(db, A, 'autocomplete', probe, 'park')).decision,
        'allowed',
      );
      const stale = await db.query(`
        SELECT
          (SELECT count(*)::int FROM hocalist.places_rate_counters
            WHERE bucket < now() - interval '2 days') AS counters,
          (SELECT count(*)::int FROM hocalist.places_search_sessions
            WHERE token = '30000000-0000-4000-8000-0000000000ff') AS sessions
      `);
      assert.deepEqual(stale.rows[0], { counters: 0, sessions: 0 });
    });
  } finally {
    await db.close();
  }
});

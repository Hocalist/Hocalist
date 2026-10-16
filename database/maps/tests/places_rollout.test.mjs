// Validates the guarded Places gateway rollout bundle against a disposable
// copy of the account 003/004 baseline. PGlite is single-connection: not
// concurrency, JWT or live proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const sql = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const preflightSql = await sql('../rollout/preflight.sql');
const applySql = await sql('../rollout/apply.sql');
const verifySql = await sql('../rollout/verify.sql');
const containmentSql = await sql('../rollout/containment.sql');
const draftSql = await sql('../050_places_gateway.sql');

const block = (text, tag) => {
  const marker = `DO $${tag}$`;
  const start = text.indexOf(marker);
  const endMarker = '$' + tag + '$;';
  const end = text.indexOf(endMarker, start) + endMarker.length;
  assert.ok(start >= 0 && end > start, `missing ${tag} block`);
  return text.slice(start, end);
};

async function runScript(db, script) {
  try {
    await db.exec(script);
    return { ok: true };
  } catch (error) {
    await db.exec('ROLLBACK').catch(() => {});
    return { ok: false, error };
  }
}

async function knownBaseline() {
  const db = await createDisposableDb();
  await applySignupSeed(db);
  await applyAccountDrafts(db);
  return db;
}

test('guarded Places gateway rollout bundle on a disposable baseline', async (t) => {
  await t.test('guard and post-apply blocks are identical across files', () => {
    assert.equal(
      block(draftSql, 'places_guard'),
      block(preflightSql, 'places_guard'),
    );
    assert.equal(
      block(draftSql, 'hocalist_places_postapply'),
      block(verifySql, 'hocalist_places_postapply'),
    );
    assert.ok(applySql.includes(draftSql), 'apply.sql must embed the reviewed draft verbatim');
  });

  await t.test('preflight passes read-only with gateway objects absent', async () => {
    const db = await knownBaseline();
    try {
      const preflight = await runScript(db, preflightSql);
      assert.equal(preflight.ok, true, preflight.error?.message);
      const checks = await db.query(`
        SELECT
          to_regclass('hocalist.places_search_sessions') AS sessions,
          to_regclass('hocalist.places_search_suggestions') AS suggestions,
          to_regclass('hocalist.places_rate_counters') AS counters
      `);
      assert.deepEqual(checks.rows[0], {
        sessions: null,
        suggestions: null,
        counters: null,
      });
    } finally {
      await db.close();
    }
  });

  await t.test('apply succeeds, verify passes and repeated apply aborts', async () => {
    const db = await knownBaseline();
    try {
      const applied = await runScript(db, applySql);
      assert.equal(applied.ok, true, applied.error?.message);
      assert.equal((await runScript(db, verifySql)).ok, true);
      const repeated = await runScript(db, applySql);
      assert.equal(repeated.ok, false, 'repeated apply must abort');
      assert.match(repeated.error.message, /already exist/);
      assert.equal((await runScript(db, verifySql)).ok, true);
    } finally {
      await db.close();
    }
  });

  await t.test('containment revokes service access and preserves state', async () => {
    const db = await knownBaseline();
    try {
      assert.equal((await runScript(db, applySql)).ok, true);
      const first = await runScript(db, containmentSql);
      assert.equal(first.ok, true, first.error?.message);
      const second = await runScript(db, containmentSql);
      assert.equal(second.ok, true, second.error?.message);

      const checks = await db.query(`
        SELECT
          has_function_privilege('service_role','hocalist.places_gate(uuid,text,uuid,text,text)','EXECUTE') AS gate,
          has_function_privilege('service_role','hocalist.places_record_suggestions(uuid,uuid,text[])','EXECUTE') AS record,
          has_function_privilege('service_role','hocalist.places_resolve_session(uuid,uuid)','EXECUTE') AS resolve,
          has_function_privilege('service_role','hocalist.places_release_session(uuid,uuid)','EXECUTE') AS release,
          has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') AS account_ok,
          (SELECT count(*)::int FROM hocalist.places_search_sessions) AS sessions
      `);
      assert.deepEqual(checks.rows[0], {
        gate: false,
        record: false,
        resolve: false,
        release: false,
        account_ok: true,
        sessions: 0,
      });
      const verifyAfter = await runScript(db, verifySql);
      assert.equal(verifyAfter.ok, false, 'verify describes the applied, not contained, state');
      assert.match(verifyAfter.error.message, /places function grants are wrong/);
    } finally {
      await db.close();
    }
  });

  const driftCases = [
    {
      name: 'pre-existing sessions table',
      message: /already exist/,
      setup: (db) =>
        db.exec('CREATE TABLE hocalist.places_search_sessions(token uuid PRIMARY KEY)'),
    },
    {
      name: 'pre-existing gate function',
      message: /already exist/,
      setup: (db) =>
        db.exec("CREATE FUNCTION hocalist.places_gate(p_user uuid, p_operation text, p_session_token uuid, p_input text, p_place_id text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$"),
    },
    {
      name: 'missing account baseline',
      message: /Account foundation is missing/,
      setup: (db) => db.exec('DROP FUNCTION hocalist.account_command(text,text,jsonb) CASCADE'),
    },
  ];

  for (const drift of driftCases) {
    await t.test(`drift aborts: ${drift.name}`, async () => {
      const db = await knownBaseline();
      try {
        await drift.setup(db);
        const preflight = await runScript(db, preflightSql);
        assert.equal(preflight.ok, false, 'preflight must abort on drift');
        assert.match(preflight.error.message, drift.message);
        const apply = await runScript(db, applySql);
        assert.equal(apply.ok, false, 'apply must abort on drift');
        assert.match(apply.error.message, drift.message);
      } finally {
        await db.close();
      }
    });
  }
});

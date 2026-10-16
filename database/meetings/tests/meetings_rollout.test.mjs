// Validates the guarded meeting rollout bundle against a disposable copy of
// the account + chat + marketplace baseline. PGlite is single-connection: not
// concurrency or live proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const sql = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const preflightSql = await sql('../rollout/preflight.sql');
const applySql = await sql('../rollout/apply.sql');
const verifySql = await sql('../rollout/verify.sql');
const containmentSql = await sql('../rollout/containment.sql');
const draftSql = await sql('../040_meetings_foundation.sql');
const chatSql = await sql('../../chat/010_chat_foundation.sql');
const marketplaceSql = await sql('../../marketplace/020_marketplace_foundation.sql');
const providerApplySql = await sql('../../provider-rollout/apply.sql');
const accountApplySql = await sql('../../rollout/account_apply.sql');

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
  await applyStripeInbox(db);
  assert.equal((await runScript(db, accountApplySql)).ok, true, 'account baseline');
  assert.equal((await runScript(db, providerApplySql)).ok, true, 'provider baseline');
  assert.equal((await runScript(db, chatSql)).ok, true, 'chat baseline');
  assert.equal((await runScript(db, marketplaceSql)).ok, true, 'marketplace baseline');
  return db;
}

test('guarded meeting rollout bundle on a disposable baseline', async (t) => {
  await t.test('guard and post-apply blocks are identical across files', () => {
    assert.equal(
      block(draftSql, 'meeting_guard'),
      block(preflightSql, 'meeting_guard'),
    );
    assert.equal(
      block(draftSql, 'hocalist_meeting_postapply'),
      block(verifySql, 'hocalist_meeting_postapply'),
    );
    assert.ok(applySql.includes(draftSql), 'apply.sql must embed the reviewed draft verbatim');
  });

  await t.test('preflight passes read-only with meeting objects absent', async () => {
    const db = await knownBaseline();
    try {
      const preflight = await runScript(db, preflightSql);
      assert.equal(preflight.ok, true, preflight.error?.message);
      assert.equal(
        (await db.query("SELECT to_regclass('hocalist.meetings') AS target")).rows[0].target,
        null,
      );
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

  await t.test('containment revokes client meeting access and preserves state', async () => {
    const db = await knownBaseline();
    try {
      assert.equal((await runScript(db, applySql)).ok, true);
      const first = await runScript(db, containmentSql);
      assert.equal(first.ok, true, first.error?.message);
      const second = await runScript(db, containmentSql);
      assert.equal(second.ok, true, second.error?.message);

      const checks = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.meeting_propose(uuid,jsonb,text)','EXECUTE') AS propose,
          has_function_privilege('anon','hocalist.meeting_list(text,integer,text)','EXECUTE') AS anon_list,
          has_function_privilege('service_role','hocalist.meeting_respond(uuid,boolean,bigint,text)','EXECUTE') AS svc_respond,
          has_function_privilege('authenticated','hocalist.marketplace_timezones()','EXECUTE') AS marketplace_ok,
          (SELECT count(*)::int FROM hocalist.meetings) AS meetings
      `);
      assert.deepEqual(checks.rows[0], {
        propose: false,
        anon_list: false,
        svc_respond: false,
        marketplace_ok: true,
        meetings: 0,
      });
      const verifyAfter = await runScript(db, verifySql);
      assert.equal(verifyAfter.ok, false, 'verify describes the applied, not contained, state');
      assert.match(verifyAfter.error.message, /meeting function grants are wrong/);
    } finally {
      await db.close();
    }
  });

  const driftCases = [
    {
      name: 'pre-existing meetings table',
      message: /already exist/,
      setup: (db) => db.exec('CREATE TABLE hocalist.meetings(id uuid PRIMARY KEY)'),
    },
    {
      name: 'pre-existing propose function',
      message: /already exist/,
      setup: (db) =>
        db.exec("CREATE FUNCTION hocalist.meeting_propose(p_conversation uuid, p_input jsonb, p_key text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$"),
    },
    {
      name: 'missing marketplace baseline',
      message: /foundation is missing/,
      setup: (db) => db.exec('DROP FUNCTION hocalist.marketplace_next_local_day_start(date,text) CASCADE'),
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

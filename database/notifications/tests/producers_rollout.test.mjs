// Validates the guarded notification producer rollout bundle against a
// disposable account + push + chat + marketplace + meetings + inbox baseline.
// PGlite is single-connection: not concurrency, JWT or live proof.
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
const preflightSql = await sql('../producers-rollout/preflight.sql');
const applySql = await sql('../producers-rollout/apply.sql');
const verifySql = await sql('../producers-rollout/verify.sql');
const containmentSql = await sql('../producers-rollout/containment.sql');
const draftSql = await sql('../031_notification_producers.sql');
const providerApplySql = await sql('../../provider-rollout/apply.sql');
const chatSql = await sql('../../chat/010_chat_foundation.sql');
const marketplaceSql = await sql('../../marketplace/020_marketplace_foundation.sql');
const meetingsSql = await sql('../../meetings/040_meetings_foundation.sql');
const inboxSql = await sql('../030_notification_inbox.sql');

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
  await applyAccountDrafts(db);
  assert.equal((await runScript(db, providerApplySql)).ok, true, 'push baseline');
  assert.equal((await runScript(db, chatSql)).ok, true, 'chat baseline');
  assert.equal((await runScript(db, marketplaceSql)).ok, true, 'marketplace baseline');
  assert.equal((await runScript(db, meetingsSql)).ok, true, 'meetings baseline');
  assert.equal((await runScript(db, inboxSql)).ok, true, 'inbox baseline');
  return db;
}

test('guarded notification producer rollout bundle on a disposable baseline', async (t) => {
  await t.test('guard and post-apply blocks are identical across files', () => {
    assert.equal(
      block(draftSql, 'notification_producer_guard'),
      block(preflightSql, 'notification_producer_guard'),
    );
    assert.equal(
      block(draftSql, 'hocalist_notification_producer_postapply'),
      block(verifySql, 'hocalist_notification_producer_postapply'),
    );
    assert.ok(applySql.includes(draftSql), 'apply.sql must embed the reviewed draft verbatim');
  });

  await t.test('preflight passes read-only with producers absent', async () => {
    const db = await knownBaseline();
    try {
      const preflight = await runScript(db, preflightSql);
      assert.equal(preflight.ok, true, preflight.error?.message);
      const triggers = await db.query(`
        SELECT count(*)::int AS n FROM pg_trigger
        WHERE tgname IN ('notification_offer_insert','notification_message_insert',
                         'notification_meeting_proposal','notification_meeting_status')
      `);
      assert.equal(triggers.rows[0].n, 0);
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

  await t.test('containment drops the triggers and keeps the functions', async () => {
    const db = await knownBaseline();
    try {
      assert.equal((await runScript(db, applySql)).ok, true);
      const first = await runScript(db, containmentSql);
      assert.equal(first.ok, true, first.error?.message);
      const second = await runScript(db, containmentSql);
      assert.equal(second.ok, true, second.error?.message);

      const checks = await db.query(`
        SELECT
          (SELECT count(*)::int FROM pg_trigger
            WHERE tgname IN ('notification_offer_insert','notification_message_insert',
                             'notification_meeting_proposal','notification_meeting_status')) AS triggers,
          to_regprocedure('hocalist.notification_on_offer_insert()') IS NOT NULL AS function_kept
      `);
      assert.deepEqual(checks.rows[0], { triggers: 0, function_kept: true });
      const verifyAfter = await runScript(db, verifySql);
      assert.equal(verifyAfter.ok, false, 'verify describes the applied, not contained, state');
      assert.match(verifyAfter.error.message, /missing producer trigger/);
    } finally {
      await db.close();
    }
  });

  const driftCases = [
    {
      name: 'pre-existing producer function',
      message: /already exist/,
      setup: (db) =>
        db.exec("CREATE FUNCTION hocalist.notification_on_offer_insert() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$"),
    },
    {
      name: 'missing inbox baseline',
      message: /foundation is missing/,
      setup: (db) =>
        db.exec('DROP FUNCTION hocalist.notification_emit(uuid,uuid,text,uuid,text,text,text,jsonb) CASCADE'),
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

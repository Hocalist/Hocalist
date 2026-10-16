// Validates the guarded notification inbox rollout bundle against a disposable
// copy of the account 003/004 + push 007 baseline. PGlite is single-connection:
// not concurrency or live proof.
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
const draftSql = await sql('../030_notification_inbox.sql');
const providerApplySql = await sql('../../provider-rollout/apply.sql');
const accountApplySql = await sql('../../rollout/account_apply.sql');

const block = (text, tag) => {
  const marker = `\nDO $${tag}$\n`;
  const start = text.indexOf(marker) + 1;
  const end = text.indexOf(`$${tag}$;`, start) + `$${tag}$;`.length;
  assert.ok(start > 0 && end > start, `missing ${tag} block`);
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
  const provider = await runScript(db, providerApplySql);
  assert.equal(provider.ok, true, provider.error?.message);
  return db;
}

test('guarded notification inbox rollout bundle on a disposable baseline', async (t) => {
  await t.test('guard and post-apply blocks are identical across files', () => {
    assert.equal(
      block(draftSql, 'notification_guard'),
      block(preflightSql, 'notification_guard'),
    );
    assert.equal(
      block(draftSql, 'hocalist_notification_postapply'),
      block(verifySql, 'hocalist_notification_postapply'),
    );
    assert.ok(applySql.includes(draftSql), 'apply.sql must embed the reviewed draft verbatim');
  });

  await t.test('preflight passes read-only with inbox objects absent', async () => {
    const db = await knownBaseline();
    try {
      const preflight = await runScript(db, preflightSql);
      assert.equal(preflight.ok, true, preflight.error?.message);
      assert.equal(
        (await db.query("SELECT to_regclass('hocalist.notification_preferences') AS target")).rows[0].target,
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

  await t.test('containment revokes client inbox access and preserves state', async () => {
    const db = await knownBaseline();
    try {
      assert.equal((await runScript(db, applySql)).ok, true);
      const first = await runScript(db, containmentSql);
      assert.equal(first.ok, true, first.error?.message);
      const second = await runScript(db, containmentSql);
      assert.equal(second.ok, true, second.error?.message);

      const checks = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.notification_inbox(integer,text)','EXECUTE') AS inbox,
          has_function_privilege('anon','hocalist.notification_preferences()','EXECUTE') AS anon_prefs,
          has_function_privilege('service_role','hocalist.notification_mark_read(uuid)','EXECUTE') AS svc_read,
          has_function_privilege('authenticated','hocalist.push_device_register(uuid,text,text,boolean)','EXECUTE') AS push_register,
          (SELECT count(*)::int FROM pg_attribute
           WHERE attrelid='hocalist.notifications'::regclass AND attname IN ('title','body','deep_link','payload')
             AND NOT attisdropped) AS new_columns
      `);
      assert.deepEqual(checks.rows[0], {
        inbox: false,
        anon_prefs: false,
        svc_read: false,
        push_register: true,
        new_columns: 4,
      });
      const verifyAfter = await runScript(db, verifySql);
      assert.equal(verifyAfter.ok, false, 'verify describes the applied, not contained, state');
      assert.match(verifyAfter.error.message, /notification function grants are wrong/);
    } finally {
      await db.close();
    }
  });

  const driftCases = [
    {
      name: 'pre-existing preferences table',
      message: /already exist/,
      setup: (db) => db.exec('CREATE TABLE hocalist.notification_preferences(id int PRIMARY KEY)'),
    },
    {
      name: 'pre-existing inbox function',
      message: /already exist/,
      setup: (db) =>
        db.exec("CREATE FUNCTION hocalist.notification_inbox(p_limit integer, p_cursor text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$"),
    },
    {
      name: 'missing push baseline',
      message: /push foundation 003\/004\/007 is missing/,
      setup: (db) => db.exec('DROP FUNCTION hocalist.notification_enqueue(uuid,uuid,text,uuid) CASCADE'),
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

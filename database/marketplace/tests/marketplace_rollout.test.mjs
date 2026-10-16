// Validates the guarded marketplace rollout bundle against a disposable copy
// of the account 003/004 + chat 010 baseline. PGlite is single-connection:
// not concurrency or live proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const sql = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const preflightSql = await sql('../rollout/preflight.sql');
const applySql = await sql('../rollout/apply.sql');
const verifySql = await sql('../rollout/verify.sql');
const containmentSql = await sql('../rollout/containment.sql');
const draftSql = await sql('../020_marketplace_foundation.sql');
const chatSql = await sql('../../chat/010_chat_foundation.sql');
const accountApplySql = await sql('../../rollout/account_apply.sql');
const providerApplySql = await sql('../../provider-rollout/apply.sql');

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
  const chat = await runScript(db, chatSql);
  assert.equal(chat.ok, true, chat.error?.message);
  return db;
}

async function catalogInventory(db) {
  const query = async (statement) => (await db.query(statement)).rows;
  return {
    relations: await query(`
      SELECT c.relname, c.relkind, c.relrowsecurity, pg_get_userbyid(c.relowner) AS owner,
             c.relacl::text AS acl
      FROM pg_class c WHERE c.relnamespace='hocalist'::regnamespace
        AND c.relkind IN ('r','p','v','m','S','f','i') ORDER BY c.relname, c.relkind`),
    columns: await query(`
      SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod) AS type,
             a.attnotnull, pg_get_expr(d.adbin, d.adrelid) AS default_expr
      FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
      LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE c.relnamespace='hocalist'::regnamespace AND a.attnum>0 AND NOT a.attisdropped
      ORDER BY c.relname, a.attnum`),
    constraints: await query(`
      SELECT conrelid::regclass::text AS relation, conname, contype,
             pg_get_constraintdef(oid) AS definition
      FROM pg_constraint WHERE connamespace='hocalist'::regnamespace
      ORDER BY conrelid::regclass::text, conname`),
    policies: await query(`
      SELECT tablename, policyname, roles::text, cmd, qual, with_check
      FROM pg_policies WHERE schemaname='hocalist' ORDER BY tablename, policyname`),
    functions: await query(`
      SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
             p.prosecdef, p.proconfig::text AS config, p.proacl::text AS acl,
             md5(pg_get_functiondef(p.oid)) AS definition_hash
      FROM pg_proc p WHERE p.pronamespace='hocalist'::regnamespace
      ORDER BY p.proname, arguments`),
  };
}

test('guarded marketplace rollout bundle on a disposable baseline', async (t) => {
  await t.test('guard and post-apply blocks are identical across files', () => {
    assert.equal(block(draftSql, 'marketplace_guard'), block(preflightSql, 'marketplace_guard'));
    assert.equal(
      block(draftSql, 'hocalist_marketplace_postapply'),
      block(verifySql, 'hocalist_marketplace_postapply'),
    );
    assert.ok(applySql.includes(draftSql), 'apply.sql must embed the reviewed draft verbatim');
    assert.ok(applySql.indexOf(draftSql) > 0, 'apply.sql keeps a header before the draft');
  });

  await t.test('preflight passes read-only with marketplace objects absent', async () => {
    const db = await knownBaseline();
    try {
      const preflight = await runScript(db, preflightSql);
      assert.equal(preflight.ok, true, preflight.error?.message);
      assert.equal(
        (await db.query("SELECT to_regclass('hocalist.requests') AS target")).rows[0].target,
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
      const before = await catalogInventory(db);
      const repeated = await runScript(db, applySql);
      assert.equal(repeated.ok, false, 'repeated apply must abort');
      assert.match(repeated.error.message, /Marketplace objects already exist/);
      assert.deepEqual(await catalogInventory(db), before);
      assert.equal((await runScript(db, verifySql)).ok, true);
    } finally {
      await db.close();
    }
  });

  await t.test('containment revokes client marketplace access and preserves state', async () => {
    const db = await knownBaseline();
    try {
      assert.equal((await runScript(db, applySql)).ok, true);
      const first = await runScript(db, containmentSql);
      assert.equal(first.ok, true, first.error?.message);
      const second = await runScript(db, containmentSql);
      assert.equal(second.ok, true, second.error?.message);

      const checks = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.marketplace_command(text,text,jsonb)','EXECUTE') AS command,
          has_function_privilege('anon','hocalist.marketplace_catalogue(text,boolean)','EXECUTE') AS anon_catalogue,
          has_function_privilege('authenticated','hocalist.chat_send(uuid,text,text)','EXECUTE') AS chat_send,
          has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') AS account_command,
          (SELECT count(*)::int FROM hocalist.marketplace_plan_limits) AS plan_limits
      `);
      assert.deepEqual(checks.rows[0], {
        command: false,
        anon_catalogue: false,
        chat_send: true,
        account_command: true,
        plan_limits: 3,
      });
      const verifyAfter = await runScript(db, verifySql);
      assert.equal(verifyAfter.ok, false, 'verify describes the applied, not contained, state');
      assert.match(verifyAfter.error.message, /marketplace function grants are wrong/);
    } finally {
      await db.close();
    }
  });

  const driftCases = [
    {
      name: 'pre-existing marketplace relation',
      message: /Marketplace objects already exist/,
      setup: (db) => db.exec('CREATE TABLE hocalist.requests(id uuid PRIMARY KEY)'),
    },
    {
      name: 'pre-existing marketplace function',
      message: /Marketplace objects already exist/,
      setup: (db) =>
        db.exec("CREATE FUNCTION hocalist.marketplace_command(p_operation text, p_key text, p_input jsonb) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$"),
    },
    {
      name: 'missing account baseline',
      message: /Account foundation 002\/003\/004 is missing/,
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
        assert.equal(
          (await db.query("SELECT to_regclass('hocalist.store_listings') AS target")).rows[0].target,
          null,
        );
      } finally {
        await db.close();
      }
    });
  }
});

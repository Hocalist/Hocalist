// Validates the guarded chat rollout bundle against a disposable copy of the
// known deployed baseline (account 003/004, Stripe receipt 005, billing 006,
// push 007). PGlite is single-connection: not concurrency or live proof.
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
const draftSql = await sql('../010_chat_foundation.sql');
const accountApplySql = await sql('../../rollout/account_apply.sql');
const providerApplySql = await sql('../../provider-rollout/apply.sql');
const placesApplySql = await sql('../../maps/rollout/apply.sql');
const placesVerifySql = await sql('../../maps/rollout/verify.sql');

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
    schema: await query(`
      SELECT nspname, pg_get_userbyid(nspowner) AS owner, nspacl::text AS acl
      FROM pg_namespace WHERE nspname='hocalist'`),
    trigger: await query(`
      SELECT tgname, tgenabled, pg_get_triggerdef(oid) AS definition
      FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND NOT tgisinternal`),
  };
}

test('guarded chat rollout bundle on a disposable baseline', async (t) => {
  await t.test('accepts complete private Places module and preserves it through chat apply', async () => {
    const db = await knownBaseline();
    try {
      await db.exec(placesApplySql);
      const before = (await catalogInventory(db)).functions.filter(x => x.proname.startsWith('places_'));
      const preflight = await runScript(db, preflightSql);
      assert.equal(preflight.ok, true, preflight.error?.message);
      const applied = await runScript(db, applySql);
      assert.equal(applied.ok, true, applied.error?.message);
      assert.equal((await runScript(db, placesVerifySql)).ok, true);
      assert.deepEqual((await catalogInventory(db)).functions.filter(x => x.proname.startsWith('places_')), before);
    } finally { await db.close(); }
  });

  await t.test('optional Places cannot hide incomplete objects or client access drift', async () => {
    const db = await knownBaseline();
    try {
      await db.exec('CREATE TABLE hocalist.places_search_sessions (id uuid)');
      assert.equal((await runScript(db, preflightSql)).ok, false);
      await db.exec('DROP TABLE hocalist.places_search_sessions');
      await db.exec(placesApplySql);
      await db.exec('GRANT SELECT ON hocalist.places_search_sessions TO authenticated');
      assert.equal((await runScript(db, preflightSql)).ok, false);
      assert.equal((await runScript(db, applySql)).ok, false);
      assert.equal((await db.query("SELECT to_regclass('hocalist.conversations') AS target")).rows[0].target, null);
    } finally { await db.close(); }
  });

  await t.test('guard and post-apply blocks are identical across files', () => {
    assert.equal(block(preflightSql, 'hocalist_chat_guard'), block(applySql, 'hocalist_chat_guard'));
    assert.equal(block(applySql, 'hocalist_chat_postapply'), block(verifySql, 'hocalist_chat_postapply'));
  });

  await t.test('preflight passes read-only with chat objects absent', async () => {
    const db = await knownBaseline();
    try {
      const preflight = await runScript(db, preflightSql);
      assert.equal(preflight.ok, true, preflight.error?.message);
      assert.equal(
        (await db.query("SELECT to_regclass('hocalist.conversations') AS target")).rows[0].target,
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
      assert.match(repeated.error.message, /chat (relation|function) already exists/);
      assert.deepEqual(await catalogInventory(db), before);
      assert.equal((await runScript(db, verifySql)).ok, true);
    } finally {
      await db.close();
    }
  });

  await t.test('containment revokes client chat access and preserves state', async () => {
    const db = await knownBaseline();
    try {
      assert.equal((await runScript(db, applySql)).ok, true);
      await db.query('INSERT INTO auth.users(id, raw_user_meta_data) VALUES ($1,$3::jsonb),($2,$3::jsonb)', [
        '00000000-0000-4000-8000-0000000000aa',
        '00000000-0000-4000-8000-0000000000bb',
        '{}',
      ]);
      await db.query("INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES ($1,$2,'buyer','active'),($3,$4,'seller','active')", [
        '10000000-0000-4000-8000-0000000000aa',
        '00000000-0000-4000-8000-0000000000aa',
        '10000000-0000-4000-8000-0000000000bb',
        '00000000-0000-4000-8000-0000000000bb',
      ]);
      const opened = await db.query(
        `SELECT hocalist.chat_open_internal('targeted_request',$1,NULL,NULL,NULL,$2::jsonb) AS id`,
        [
          '20000000-0000-4000-8000-0000000000aa',
          JSON.stringify([
            { user_id: '00000000-0000-4000-8000-0000000000aa', profile_id: '10000000-0000-4000-8000-0000000000aa', role: 'buyer' },
            { user_id: '00000000-0000-4000-8000-0000000000bb', profile_id: '10000000-0000-4000-8000-0000000000bb', role: 'seller' },
          ]),
        ],
      );
      const conversation = opened.rows[0].id;
      await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)", [
        '00000000-0000-4000-8000-0000000000aa',
      ]);
      await db.exec('SET ROLE authenticated');
      try {
        await db.query("SELECT hocalist.chat_send($1,'seed-key','Synthetic message')", [conversation]);
      } finally {
        await db.exec('RESET ROLE');
      }

      const first = await runScript(db, containmentSql);
      assert.equal(first.ok, true, first.error?.message);
      const second = await runScript(db, containmentSql);
      assert.equal(second.ok, true, second.error?.message);

      const checks = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.chat_send(uuid,text,text)','EXECUTE') AS auth_send,
          has_function_privilege('anon','hocalist.chat_inbox(integer,text)','EXECUTE') AS anon_inbox,
          (SELECT count(*)::int FROM hocalist.conversation_messages) AS messages,
          (SELECT count(*)::int FROM hocalist.conversation_members) AS members,
          has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') AS account_command,
          has_table_privilege('authenticated','hocalist.notifications','SELECT') AS notifications,
          has_function_privilege('service_role','hocalist.push_claim()','EXECUTE') AS push_claim
      `);
      assert.deepEqual(checks.rows[0], {
        auth_send: false,
        anon_inbox: false,
        messages: 1,
        members: 2,
        account_command: true,
        notifications: true,
        push_claim: true,
      });
      const verifyAfter = await runScript(db, verifySql);
      assert.equal(verifyAfter.ok, false, 'verify describes the applied, not contained, state');
      assert.match(verifyAfter.error.message, /chat function grants are wrong/);
    } finally {
      await db.close();
    }
  });

  await t.test('rollout DDL produces the same catalog as the draft', async () => {
    const draftDb = await knownBaseline();
    const rolloutDb = await knownBaseline();
    try {
      await draftDb.exec(draftSql);
      const applied = await runScript(rolloutDb, applySql);
      assert.equal(applied.ok, true, applied.error?.message);
      assert.deepEqual(await catalogInventory(rolloutDb), await catalogInventory(draftDb));
    } finally {
      await draftDb.close();
      await rolloutDb.close();
    }
  });

  const driftCases = [
    {
      name: 'pre-existing chat relation',
      message: /chat relation already exists: conversations/,
      setup: (db) => db.exec('CREATE TABLE hocalist.conversations(id uuid PRIMARY KEY)'),
    },
    {
      name: 'pre-existing chat function',
      message: /chat function already exists: chat_inbox/,
      setup: (db) =>
        db.exec("CREATE FUNCTION hocalist.chat_inbox(p_size integer DEFAULT 50, p_cursor text DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$"),
    },
    {
      name: 'unexpected relation',
      message: /unexpected relation in hocalist: mystery_chat/,
      setup: (db) => db.exec('CREATE TABLE hocalist.mystery_chat(id int)'),
    },
    {
      name: 'missing baseline relation',
      message: /missing baseline relation: hocalist.push_devices/,
      setup: (db) => db.exec('DROP TABLE hocalist.push_devices CASCADE'),
    },
    {
      name: 'baseline ACL drift',
      message: /account table grants differ/,
      setup: (db) => db.exec('GRANT INSERT ON hocalist.memberships TO authenticated'),
    },
    {
      name: 'missing baseline function',
      message: /missing baseline function: push_claim\(\)/,
      setup: (db) => db.exec('DROP FUNCTION hocalist.push_claim()'),
    },
    {
      name: 'default privileges leak client access',
      message: /default privileges would grant client/,
      setup: (db) =>
        db.exec('ALTER DEFAULT PRIVILEGES IN SCHEMA hocalist GRANT SELECT ON TABLES TO authenticated'),
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
          (await db.query("SELECT to_regclass('hocalist.conversation_members') AS target")).rows[0].target,
          null,
        );
      } finally {
        await db.close();
      }
    });
  }
});

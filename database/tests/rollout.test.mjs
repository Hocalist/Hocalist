// Validates the guarded rollout bundle against a disposable copy of the known
// baseline: success path, repeated application, containment, drift aborts and
// catalog equivalence with the hardened drafts. PGlite is single-connection;
// this is not concurrency or live proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
  loadSql,
} from './fixture.mjs';

const preflightSql = await loadSql('../rollout/preflight.sql');
const applySql = await loadSql('../rollout/account_apply.sql');
const verifySql = await loadSql('../rollout/verify.sql');
const containmentSql = await loadSql('../rollout/containment.sql');

const block = (text, tag) => {
  const marker = `\nDO $${tag}$\n`;
  const start = text.indexOf(marker) + 1;
  const end = text.indexOf(`$${tag}$;`, start) + `$${tag}$;`.length;
  assert.ok(start > 0 && end > start, `missing ${tag} block`);
  return text.slice(start, end);
};

async function runScript(db, sql) {
  try {
    await db.exec(sql);
    return { ok: true };
  } catch (error) {
    await db.exec('ROLLBACK').catch(() => {});
    return { ok: false, error };
  }
}

async function knownBaseline({ stripe = true } = {}) {
  const db = await createDisposableDb();
  await applySignupSeed(db);
  if (stripe) await applyStripeInbox(db);
  return db;
}

async function catalogInventory(db) {
  const query = async (sql) => (await db.query(sql)).rows;
  return {
    relations: await query(`
      SELECT c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity,
             pg_get_userbyid(c.relowner) AS owner, c.relacl::text AS acl
      FROM pg_class c
      WHERE c.relnamespace = 'hocalist'::regnamespace
        AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f', 'i')
      ORDER BY c.relname, c.relkind`),
    columns: await query(`
      SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod) AS type,
             a.attnotnull, pg_get_expr(d.adbin, d.adrelid) AS default_expr
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
      WHERE c.relnamespace = 'hocalist'::regnamespace
        AND a.attnum > 0 AND NOT a.attisdropped
      ORDER BY c.relname, a.attnum`),
    constraints: await query(`
      SELECT conrelid::regclass::text AS relation, conname, contype,
             pg_get_constraintdef(oid) AS definition
      FROM pg_constraint
      WHERE connamespace = 'hocalist'::regnamespace
      ORDER BY conrelid::regclass::text, conname`),
    policies: await query(`
      SELECT tablename, policyname, roles::text, cmd, qual, with_check
      FROM pg_policies WHERE schemaname = 'hocalist'
      ORDER BY tablename, policyname`),
    functions: await query(`
      SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
             pg_get_function_result(p.oid) AS result, p.prosecdef,
             p.proconfig::text AS config, p.provolatile, p.proacl::text AS acl,
             md5(pg_get_functiondef(p.oid)) AS definition_hash
      FROM pg_proc p
      WHERE p.pronamespace = 'hocalist'::regnamespace
      ORDER BY p.proname, arguments`),
    schema: await query(`
      SELECT nspname, pg_get_userbyid(nspowner) AS owner, nspacl::text AS acl
      FROM pg_namespace WHERE nspname = 'hocalist'`),
    comments: await query(`
      SELECT c.relname, obj_description(c.oid, 'pg_class') AS comment
      FROM pg_class c
      WHERE c.relnamespace = 'hocalist'::regnamespace AND c.relkind = 'r'
      ORDER BY c.relname`),
    trigger: await query(`
      SELECT tgname, tgenabled, pg_get_triggerdef(oid) AS definition
      FROM pg_trigger
      WHERE tgrelid = 'auth.users'::regclass AND NOT tgisinternal`),
  };
}

test('guarded account rollout bundle on a disposable baseline', async (t) => {
  await t.test('guard and post-apply blocks are textually identical across files', () => {
    assert.equal(
      block(preflightSql, 'hocalist_guard'),
      block(applySql, 'hocalist_guard'),
      'preflight and apply guards must stay identical',
    );
    assert.equal(
      block(applySql, 'hocalist_postapply'),
      block(verifySql, 'hocalist_postapply'),
      'apply and verify post-apply assertions must stay identical',
    );
  });

  await t.test('preflight passes read-only on the reviewed baseline', async () => {
    const db = await knownBaseline();
    try {
      const preflight = await runScript(db, preflightSql);
      assert.equal(preflight.ok, true, preflight.error?.message);
      const target = await db.query("SELECT to_regclass('hocalist.memberships') AS target");
      assert.equal(target.rows[0].target, null, 'preflight must not create target objects');
      const marker = await db.query(
        "SELECT count(*)::int AS n FROM pg_class WHERE relnamespace='hocalist'::regnamespace AND relname IN ('memberships','role_profiles','profile_contacts','command_receipts')",
      );
      assert.equal(marker.rows[0].n, 0);
    } finally {
      await db.close();
    }
  });

  await t.test('apply succeeds, verify passes and repeated apply aborts unchanged', async () => {
    const db = await knownBaseline();
    try {
      const applied = await runScript(db, applySql);
      assert.equal(applied.ok, true, applied.error?.message);
      const verified = await runScript(db, verifySql);
      assert.equal(verified.ok, true, verified.error?.message);

      const before = await catalogInventory(db);
      const repeated = await runScript(db, applySql);
      assert.equal(repeated.ok, false, 'repeated apply must abort, not overwrite');
      assert.match(repeated.error.message, /target (relation|function) already exists/);
      const after = await catalogInventory(db);
      assert.deepEqual(after, before, 'aborted repeat must not change the catalog');
      assert.equal((await runScript(db, verifySql)).ok, true);
    } finally {
      await db.close();
    }
  });

  await t.test('containment revokes client access, preserves rows and is repeatable', async () => {
    const db = await knownBaseline();
    try {
      assert.equal((await runScript(db, applySql)).ok, true);
      const user = '00000000-0000-0000-0000-00000000c001';
      await db.query('INSERT INTO auth.users(id) VALUES ($1)', [user]);
      await db.query(
        "INSERT INTO hocalist.memberships(user_id,role,status) VALUES ($1,'buyer','active')",
        [user],
      );
      await db.query('INSERT INTO hocalist.profile_contacts(user_id,phone) VALUES ($1,$2)', [user, 'SYNTHETIC']);
      // Containment must also withdraw column-level drift, not just table grants.
      await db.query('GRANT SELECT (phone) ON hocalist.profile_contacts TO authenticated');

      const first = await runScript(db, containmentSql);
      assert.equal(first.ok, true, first.error?.message);
      const second = await runScript(db, containmentSql);
      assert.equal(second.ok, true, second.error?.message);

      const checks = await db.query(`
        SELECT
          has_schema_privilege('authenticated','hocalist','USAGE') AS auth_usage,
          has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') AS auth_exec,
          has_table_privilege('authenticated','hocalist.memberships','SELECT') AS auth_select,
          has_table_privilege('authenticated','hocalist.memberships','TRUNCATE') AS auth_truncate,
          has_schema_privilege('service_role','hocalist','USAGE') AS service_usage,
          has_function_privilege('service_role','hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)','EXECUTE') AS service_exec,
          (SELECT count(*)::int FROM hocalist.memberships) AS memberships,
          (SELECT count(*)::int FROM hocalist.profile_contacts) AS contacts,
          (SELECT count(*)::int FROM pg_attribute att, aclexplode(att.attacl) a
            WHERE att.attrelid='hocalist.profile_contacts'::regclass
              AND att.attnum>0 AND NOT att.attisdropped
              AND pg_get_userbyid(a.grantee) IN ('anon','authenticated')) AS contact_column_grants
      `);
      assert.deepEqual(checks.rows[0], {
        auth_usage: false,
        auth_exec: false,
        auth_select: false,
        auth_truncate: false,
        service_usage: true,
        service_exec: true,
        memberships: 1,
        contacts: 1,
        contact_column_grants: 0,
      });
      const policies = await db.query(
        "SELECT count(*)::int AS n FROM pg_policies WHERE schemaname='hocalist'",
      );
      assert.equal(policies.rows[0].n, 3, 'containment must not drop policies');
      const verifyAfter = await runScript(db, verifySql);
      assert.equal(verifyAfter.ok, false, 'verify describes the applied, not contained, state');
      assert.match(verifyAfter.error.message, /authenticated is missing SELECT|schema privileges/);
    } finally {
      await db.close();
    }
  });

  await t.test('pre-apply privilege drift aborts preflight and apply', async () => {
    const db = await knownBaseline();
    try {
      const drifts = [
        {
          grant: 'GRANT TRUNCATE ON hocalist.profiles TO authenticated',
          revoke: 'REVOKE TRUNCATE ON hocalist.profiles FROM authenticated',
          message: /unexpected TRUNCATE for authenticated on hocalist\.profiles/,
        },
        {
          grant: 'GRANT SELECT (full_name) ON hocalist.profiles TO authenticated',
          revoke: 'REVOKE SELECT (full_name) ON hocalist.profiles FROM authenticated',
          message: /hocalist\.profiles has unexpected column grants/,
        },
        {
          grant: 'GRANT EXECUTE ON FUNCTION hocalist.handle_new_user() TO authenticated',
          revoke: 'REVOKE EXECUTE ON FUNCTION hocalist.handle_new_user() FROM authenticated',
          message: /unexpected EXECUTE for authenticated on handle_new_user/,
        },
        {
          grant: 'GRANT INSERT ON hocalist.stripe_test_inbox TO service_role',
          revoke: 'REVOKE INSERT ON hocalist.stripe_test_inbox FROM service_role',
          message: /unexpected INSERT for service_role on hocalist\.stripe_test_inbox/,
        },
        {
          grant: 'GRANT CREATE ON SCHEMA hocalist TO service_role',
          revoke: 'REVOKE CREATE ON SCHEMA hocalist FROM service_role',
          message: /unexpected client\/service schema access/,
        },
        {
          grant: 'GRANT USAGE ON SCHEMA hocalist TO PUBLIC',
          revoke: 'REVOKE USAGE ON SCHEMA hocalist FROM PUBLIC',
          message: /hocalist schema ACL differs/,
        },
        {
          grant: `CREATE ROLE hocalist_legacy_reader NOLOGIN;
                  GRANT SELECT ON hocalist.profiles TO hocalist_legacy_reader;
                  GRANT hocalist_legacy_reader TO authenticated`,
          revoke: `REVOKE hocalist_legacy_reader FROM authenticated;
                   REVOKE SELECT ON hocalist.profiles FROM hocalist_legacy_reader;
                   DROP ROLE hocalist_legacy_reader`,
          message: /hocalist\.profiles has unexpected non-owner grants/,
        },
      ];
      for (const drift of drifts) {
        await db.exec(drift.grant);
        const preflight = await runScript(db, preflightSql);
        assert.equal(preflight.ok, false, `preflight must abort: ${drift.grant}`);
        assert.match(preflight.error.message, drift.message);
        const apply = await runScript(db, applySql);
        assert.equal(apply.ok, false, `apply must abort: ${drift.grant}`);
        assert.match(apply.error.message, drift.message);
        await db.exec(drift.revoke);
        const clean = await runScript(db, preflightSql);
        assert.equal(clean.ok, true, `preflight must pass after cleanup: ${clean.error?.message}`);
      }
    } finally {
      await db.close();
    }
  });

  await t.test('post-apply privilege drift fails verification', async () => {
    const db = await knownBaseline();
    try {
      assert.equal((await runScript(db, applySql)).ok, true);
      const drifts = [
        {
          grant: 'GRANT INSERT ON hocalist.memberships TO authenticated',
          revoke: 'REVOKE INSERT ON hocalist.memberships FROM authenticated',
          message: /ACL differs from the reviewed authenticated SELECT grant|unexpected INSERT for authenticated/,
        },
        {
          grant: 'GRANT UPDATE (display_name) ON hocalist.role_profiles TO authenticated',
          revoke: 'REVOKE UPDATE (display_name) ON hocalist.role_profiles FROM authenticated',
          message: /hocalist\.role_profiles has unexpected column grants/,
        },
        {
          grant: 'GRANT TRUNCATE ON hocalist.profile_contacts TO authenticated',
          revoke: 'REVOKE TRUNCATE ON hocalist.profile_contacts FROM authenticated',
          message: /ACL differs from the reviewed authenticated SELECT grant|unexpected TRUNCATE for authenticated/,
        },
        {
          grant: 'GRANT EXECUTE ON FUNCTION hocalist.account_command(text,text,jsonb) TO service_role',
          revoke: 'REVOKE EXECUTE ON FUNCTION hocalist.account_command(text,text,jsonb) FROM service_role',
          message: /account_command ACL differs|unexpected EXECUTE for service_role/,
        },
        {
          grant: 'GRANT CREATE ON SCHEMA hocalist TO authenticated',
          revoke: 'REVOKE CREATE ON SCHEMA hocalist FROM authenticated',
          message: /hocalist schema ACL differs|schema privileges are wrong/,
        },
        {
          grant: 'GRANT SELECT ON hocalist.command_receipts TO PUBLIC',
          revoke: 'REVOKE SELECT ON hocalist.command_receipts FROM PUBLIC',
          message: /command_receipts has unexpected non-owner grants|unexpected SELECT for/,
        },
        {
          grant: 'GRANT SELECT ON hocalist.memberships TO authenticated WITH GRANT OPTION',
          revoke: 'REVOKE GRANT OPTION FOR SELECT ON hocalist.memberships FROM authenticated',
          message: /ACL differs from the reviewed authenticated SELECT grant/,
        },
        {
          grant: 'GRANT EXECUTE ON FUNCTION hocalist.account_command(text,text,jsonb) TO authenticated WITH GRANT OPTION',
          revoke: 'REVOKE GRANT OPTION FOR EXECUTE ON FUNCTION hocalist.account_command(text,text,jsonb) FROM authenticated',
          message: /account_command ACL differs/,
        },
        {
          grant: `CREATE ROLE hocalist_legacy_writer NOLOGIN;
                  GRANT INSERT ON hocalist.memberships TO hocalist_legacy_writer;
                  GRANT hocalist_legacy_writer TO authenticated`,
          revoke: `REVOKE hocalist_legacy_writer FROM authenticated;
                   REVOKE INSERT ON hocalist.memberships FROM hocalist_legacy_writer;
                   DROP ROLE hocalist_legacy_writer`,
          message: /ACL differs from the reviewed authenticated SELECT grant|unexpected INSERT for authenticated/,
        },
      ];
      for (const drift of drifts) {
        await db.exec(drift.grant);
        const failed = await runScript(db, verifySql);
        assert.equal(failed.ok, false, `verify must fail: ${drift.grant}`);
        assert.match(failed.error.message, drift.message);
        await db.exec(drift.revoke);
        const restored = await runScript(db, verifySql);
        assert.equal(restored.ok, true, `verify must pass after cleanup: ${restored.error?.message}`);
      }
    } finally {
      await db.close();
    }
  });

  await t.test('post-apply policy drift fails verification', async () => {
    const db = await knownBaseline();
    try {
      assert.equal((await runScript(db, applySql)).ok, true);
      const verifyFails = async (message) => {
        const failed = await runScript(db, verifySql);
        assert.equal(failed.ok, false);
        assert.match(failed.error.message, message);
      };
      const verifyPasses = async () => {
        const ok = await runScript(db, verifySql);
        assert.equal(ok.ok, true, ok.error?.message);
      };
      const restoreMembershipPolicy = () => db.exec(`
        DROP POLICY membership_owner_read ON hocalist.memberships;
        CREATE POLICY membership_owner_read ON hocalist.memberships FOR SELECT
          TO authenticated USING (user_id = (SELECT auth.uid()))`);

      // Finding 2: a same-name USING (true) alteration must not pass.
      await db.exec('ALTER POLICY membership_owner_read ON hocalist.memberships USING (true)');
      await verifyFails(/policy predicate changed: membership_owner_read/);
      await db.exec('ALTER POLICY membership_owner_read ON hocalist.memberships USING (user_id = (SELECT auth.uid()))');
      await verifyPasses();

      // Altered ownership join (caller check removed) must fail.
      await db.exec(`ALTER POLICY active_owner_profile_read ON hocalist.role_profiles USING (EXISTS (
        SELECT 1 FROM hocalist.memberships m
        WHERE m.id = membership_id AND m.status = 'active'))`);
      await verifyFails(/policy predicate changed: active_owner_profile_read/);
      await db.exec(`ALTER POLICY active_owner_profile_read ON hocalist.role_profiles USING (EXISTS (
        SELECT 1 FROM hocalist.memberships m
        WHERE m.id = membership_id AND m.user_id = (SELECT auth.uid()) AND m.status = 'active'))`);
      await verifyPasses();

      // Policy mode drift must fail.
      await db.exec(`
        DROP POLICY membership_owner_read ON hocalist.memberships;
        CREATE POLICY membership_owner_read ON hocalist.memberships AS RESTRICTIVE FOR SELECT
          TO authenticated USING (user_id = (SELECT auth.uid()))`);
      await verifyFails(/policy attributes changed: membership_owner_read/);
      await restoreMembershipPolicy();
      await verifyPasses();

      // Role drift on the policy must fail.
      await db.exec('ALTER POLICY membership_owner_read ON hocalist.memberships TO anon');
      await verifyFails(/policy attributes changed: membership_owner_read/);
      await db.exec('ALTER POLICY membership_owner_read ON hocalist.memberships TO authenticated');
      await verifyPasses();

      // A new policy on a preserved baseline object must fail.
      await db.exec("CREATE POLICY legacy_read ON hocalist.profiles FOR SELECT TO authenticated USING (true)");
      await verifyFails(/preserved baseline object gained a policy/);
      await db.exec('DROP POLICY legacy_read ON hocalist.profiles');
      await verifyPasses();
    } finally {
      await db.close();
    }
  });

  await t.test('rollout DDL produces the same catalog as drafts 003 + 004', async () => {
    const draftsDb = await knownBaseline();
    const rolloutDb = await knownBaseline();
    try {
      await applyAccountDrafts(draftsDb);
      const applied = await runScript(rolloutDb, applySql);
      assert.equal(applied.ok, true, applied.error?.message);
      assert.deepEqual(await catalogInventory(rolloutDb), await catalogInventory(draftsDb));
    } finally {
      await draftsDb.close();
      await rolloutDb.close();
    }
  });

  const driftCases = [
    {
      name: 'pre-existing target relation',
      message: /target relation already exists: memberships/,
      setup: (db) => db.exec('CREATE TABLE hocalist.memberships(id int)'),
      verify: async (db) => {
        const shape = await db.query(
          "SELECT count(*)::int AS n FROM pg_attribute WHERE attrelid='hocalist.memberships'::regclass AND attname='user_id'",
        );
        assert.equal(shape.rows[0].n, 0, 'pre-existing object must be left untouched');
      },
    },
    {
      name: 'pre-existing target function',
      message: /target function already exists: account_command/,
      setup: (db) => db.exec(`
        CREATE FUNCTION hocalist.account_command(p_operation text, p_key text, p_input jsonb)
        RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$`),
    },
    {
      name: 'unexpected relation',
      message: /unexpected relation in hocalist: mystery_table/,
      setup: (db) => db.exec('CREATE TABLE hocalist.mystery_table(id int)'),
    },
    {
      name: 'unexpected function',
      message: /unexpected function in hocalist: mystery_fn\(\)/,
      setup: (db) => db.exec("CREATE FUNCTION hocalist.mystery_fn() RETURNS int LANGUAGE sql AS $$ SELECT 1 $$"),
    },
    {
      name: 'deployed 005 objects missing',
      message: /stripe_test_inbox is missing/,
      stripe: false,
    },
    {
      name: 'signup trigger disabled',
      message: /signup routing trigger/,
      setup: (db) => db.exec('ALTER TABLE auth.users DISABLE TRIGGER on_auth_user_created'),
    },
    {
      name: 'client schema access pre-granted',
      message: /unexpected client\/service schema access/,
      setup: (db) => db.exec('GRANT USAGE ON SCHEMA hocalist TO authenticated'),
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
      const db = await knownBaseline({ stripe: drift.stripe !== false });
      try {
        if (drift.setup) await drift.setup(db);
        const preflight = await runScript(db, preflightSql);
        assert.equal(preflight.ok, false, 'preflight must abort on drift');
        assert.match(preflight.error.message, drift.message);
        const apply = await runScript(db, applySql);
        assert.equal(apply.ok, false, 'apply must abort on drift');
        assert.match(apply.error.message, drift.message);
        const target = await db.query("SELECT to_regclass('hocalist.role_profiles') AS target");
        assert.equal(target.rows[0].target, null, 'aborted apply must not create target objects');
        if (drift.verify) await drift.verify(db);
      } finally {
        await db.close();
      }
    });
  }
});

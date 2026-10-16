// Shared disposable-PostgreSQL fixture for the Hocalist account suites.
//
// PGlite is an in-memory single-connection PostgreSQL used for fast
// deterministic checks. It is not concurrency proof; see concurrency.test.mjs.
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

export const SYNTHETIC = Object.freeze({
  a: '00000000-0000-0000-0000-000000000001',
  b: '00000000-0000-0000-0000-000000000002',
  outsider: '00000000-0000-0000-0000-000000000003',
  ma: '10000000-0000-0000-0000-000000000001',
  mb: '10000000-0000-0000-0000-000000000002',
  pending: '10000000-0000-0000-0000-000000000003',
});

export async function loadSql(relativePath) {
  return readFile(new URL(relativePath, import.meta.url), 'utf8');
}

export async function createDisposableDb() {
  const db = new PGlite();
  await ensureRoles(db);
  await createAuthFixture(db);
  await createHocalistSchema(db);
  await createPublicPostaneurFixture(db);
  return db;
}

export async function ensureRoles(db) {
  await db.exec(`
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
}

export async function createAuthFixture(db) {
  await db.exec(`
    DROP SCHEMA IF EXISTS auth CASCADE;
    CREATE SCHEMA auth;
    CREATE TABLE auth.users(id uuid PRIMARY KEY, raw_user_meta_data jsonb);
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
    $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    GRANT USAGE ON SCHEMA auth TO authenticated;
    GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
  `);
}

export async function createHocalistSchema(db) {
  await db.exec(`
    DROP SCHEMA IF EXISTS hocalist CASCADE;
    CREATE SCHEMA hocalist;
    REVOKE ALL ON SCHEMA hocalist FROM PUBLIC, anon, authenticated;
  `);
}

// Synthetic stand-in for the shared project's Postaneur installation. The
// live function hash guard cannot be reproduced locally; rollout tests use
// this only as an unrelated baseline object that must never be modified.
export async function createPublicPostaneurFixture(db) {
  await db.exec(`
    DROP TABLE IF EXISTS public.unrelated_business;
    CREATE TABLE public.unrelated_business(id int PRIMARY KEY, confidential text);
    INSERT INTO public.unrelated_business VALUES (1, 'synthetic unrelated record');
    REVOKE ALL ON public.unrelated_business FROM PUBLIC, anon, authenticated;
    DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
    CREATE FUNCTION public.handle_new_user() RETURNS trigger LANGUAGE plpgsql AS
    $$ BEGIN RETURN NEW; END $$;
  `);
}

// Reuse the actual signup seed DDL/function/trigger, omitting only the
// historical legacy-function hash guard: this database has no live Postaneur
// installation to match.
export async function applySignupSeed(db) {
  const bootstrap = await loadSql('../bootstrap/002_hocalist_signup_routing.sql');
  await db.exec(
    bootstrap.slice(
      bootstrap.indexOf('CREATE TABLE hocalist.profiles'),
      bootstrap.indexOf('COMMIT;'),
    ),
  );
}

export async function applyAccountDrafts(db) {
  await db.exec(await loadSql('../drafts/003_membership_private_profiles.sql'));
  await db.exec(await loadSql('../drafts/004_account_commands.sql'));
}

export async function applyStripeInbox(db) {
  await db.exec(await loadSql('../drafts/005_stripe_test_inbox.sql'));
}

export async function seedSyntheticIdentities(db) {
  const { a, b, outsider, ma, mb, pending } = SYNTHETIC;
  await db.exec(`
    INSERT INTO auth.users VALUES
    ('${a}', '{"full_name":"Synthetic A","role":"admin","verified":true}'),
    ('${b}', '{"full_name":"Synthetic B"}'), ('${outsider}', '{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
    ('${ma}','${a}','buyer','active'), ('${mb}','${b}','seller','active'),
    ('${pending}','${a}','seller','pending');
    INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
    ('${ma}','A Buyer'), ('${mb}','B Seller'), ('${pending}','A Pending Seller');
    INSERT INTO hocalist.profile_contacts(user_id,phone,address_line1) VALUES
    ('${a}','SYNTHETIC-A','PRIVATE-A'), ('${b}','SYNTHETIC-B','PRIVATE-B');
  `);
}

// Runs `body` as an authenticated (or named) role inside a rolled-back
// transaction with a simulated JWT subject.
export async function asRole(db, role, user, body) {
  await db.exec('BEGIN');
  try {
    await db.query("SELECT set_config('request.jwt.claim.sub', $1, true)", [user]);
    await db.exec(`SET LOCAL ROLE ${role}`);
    await body();
  } finally {
    await db.exec('ROLLBACK').catch(() => {});
  }
}

export async function expectDenied(db, sql, role = 'authenticated', user = SYNTHETIC.a) {
  await asRole(db, role, user, async () => {
    await assertRejectsCode(db.exec(sql), '42501');
  });
}

export async function assertRejectsCode(promise, code) {
  try {
    await promise;
  } catch (error) {
    if (error.code !== code) {
      throw new Error(`expected SQLSTATE ${code}, got ${error.code}: ${error.message}`);
    }
    return error;
  }
  throw new Error(`expected SQLSTATE ${code}, but the statement succeeded`);
}

// Real route → real disposable-SQL admission regression.
//
// The compiled Next waitlist route runs with its RPC transport bridged to the
// real `website_waitlist_join` function in disposable PGlite, so full public
// response sequences can be compared across equal starting admission states.
// The route holds only a synthetic intake secret; no remote provider is
// called. PGlite is single-connection; cross-instance concurrency requires
// separate multi-connection PostgreSQL proof.
import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const SECRET = 'waitlist-intake-secret-0123456789abcdefghijk';
const originalFetch = globalThis.fetch;
const originalEnv = {
  url: process.env.HOCALIST_SUPABASE_URL,
  key: process.env.HOCALIST_SUPABASE_ANON_KEY,
  secret: process.env.HOCALIST_WAITLIST_INTAKE_SECRET,
};

// npm test runs from public-web, so the shared database fixtures resolve from
// the repository root.
async function readSql(relative: string): Promise<string> {
  return await readFile(resolve(process.cwd(), relative), 'utf8');
}

async function bootstrap(seed?: { email: string }): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(`
    DO $roles$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
    END $roles$;
    DROP SCHEMA IF EXISTS auth CASCADE;
    CREATE SCHEMA auth;
    CREATE TABLE auth.users(id uuid PRIMARY KEY, raw_user_meta_data jsonb);
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
      $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    DROP SCHEMA IF EXISTS hocalist CASCADE;
    CREATE SCHEMA hocalist;
    REVOKE ALL ON SCHEMA hocalist FROM PUBLIC, anon, authenticated;
  `);
  const signup = await readSql('../database/bootstrap/002_hocalist_signup_routing.sql');
  await db.exec(signup.slice(
    signup.indexOf('CREATE TABLE hocalist.profiles'),
    signup.indexOf('COMMIT;'),
  ));
  await db.exec(await readSql('../database/website_completion/170_website_waitlist.sql'));
  await db.exec('SET ROLE service_role');
  try {
    await db.query('SELECT hocalist.website_waitlist_configure($1)', [SECRET]);
  } finally {
    await db.exec('RESET ROLE');
  }
  if (seed) {
    // A pre-existing consent row stored under a different fingerprint. It
    // consumes no admission budget, exactly like an earlier registration.
    await db.query(
      `INSERT INTO hocalist.website_waitlist_signups(email,email_normalized,consent_version,source,client_hash)
       VALUES ($1,$1,'launch-updates-v1','fixture',$2) ON CONFLICT DO NOTHING`,
      [seed.email, 'f'.repeat(64)],
    );
  }
  return db;
}

// Minimal PostgREST bridge: POST /rest/v1/rpc/<fn> executes the real SQL
// function as `anon` and returns the PostgREST-shaped success or error body.
function bridgeFetch(db: PGlite) {
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (!/\/rest\/v1\/rpc\/website_waitlist_join$/.test(url)) {
      throw new Error(`unexpected fetch ${url}`);
    }
    const body = JSON.parse(String(init?.body ?? '{}')) as Record<string, unknown>;
    await db.exec('SET ROLE anon');
    try {
      const result = await db.query<{ data: unknown }>(
        'SELECT hocalist.website_waitlist_join($1,$2,$3,$4,$5) AS data',
        [body.p_email, body.p_consent_version, body.p_source, body.p_client_hash, body.p_intake_token],
      );
      return new Response(JSON.stringify(result.rows[0].data), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    } catch (error) {
      const failure = error as { code?: string; message?: string };
      return new Response(JSON.stringify({ code: failure.code, message: failure.message }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    } finally {
      await db.exec('RESET ROLE');
    }
  }) as typeof fetch;
}

function request(email: string, address: string): Request {
  return new Request('http://localhost/api/waitlist', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      origin: 'http://localhost',
      'sec-fetch-site': 'same-origin',
      'x-forwarded-for': address,
    },
    body: JSON.stringify({ email, consent: true, source: 'download-page' }),
  });
}

type Route = { POST: (request: Request) => Promise<Response> };

async function submit(route: Route, email: string, address: string) {
  const response = await route.POST(request(email, address));
  return { status: response.status, body: (await response.json()) as Record<string, unknown> };
}

test.beforeEach(() => {
  process.env.HOCALIST_SUPABASE_URL = 'https://example.supabase.co';
  process.env.HOCALIST_SUPABASE_ANON_KEY = 'synthetic-anon-key';
  process.env.HOCALIST_WAITLIST_INTAKE_SECRET = SECRET;
});

test.afterEach(() => {
  globalThis.fetch = originalFetch;
  for (const [name, value] of [
    ['HOCALIST_SUPABASE_URL', originalEnv.url],
    ['HOCALIST_SUPABASE_ANON_KEY', originalEnv.key],
    ['HOCALIST_WAITLIST_INTAKE_SECRET', originalEnv.secret],
  ] as const) {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
});

test('public admission does not reveal whether an address is already registered', async () => {
  const db = await bootstrap();
  try {
    bridgeFetch(db);
    const route = await import('../app/api/waitlist/route') as Route;

    // Below both caps: known and unknown addresses get the same acknowledgement.
    const first = await submit(route, 'known@example.com', '203.0.113.11');
    assert.equal(first.status, 200);
    assert.equal(first.body.status, 'accepted');
    const known = await submit(route, 'known@example.com', '203.0.113.11');
    const unknown = await submit(route, 'fresh@example.com', '203.0.113.11');
    assert.deepEqual(known.body, unknown.body, 'known/unknown are indistinguishable below the cap');

    // Another fingerprint is independently admitted below the caps.
    assert.equal((await submit(route, 'elsewhere@example.com', '203.0.113.19')).status, 200);

    // At the per-fingerprint cap: a registered address and a brand new one
    // produce the same 429 response. Five admitted submissions exhaust the
    // five-slot budget first.
    for (const email of ['cap1@example.com', 'cap2@example.com', 'cap3@example.com', 'cap4@example.com', 'cap5@example.com']) {
      assert.equal((await submit(route, email, '203.0.113.12')).status, 200);
    }
    const knownAtCap = await submit(route, 'cap1@example.com', '203.0.113.12');
    const unknownAtCap = await submit(route, 'cap-new@example.com', '203.0.113.12');    assert.equal(knownAtCap.status, 429);
    assert.equal(unknownAtCap.status, 429);
    assert.deepEqual(knownAtCap.body, unknownAtCap.body, 'known/unknown are indistinguishable at the cap');

    // At the global cap, a fresh fingerprint sees the same 429 for both.
    const total = (await db.query<{ n: number }>(
      'SELECT coalesce(sum(admitted),0)::int AS n FROM hocalist.website_waitlist_admissions')).rows[0].n;
    await db.query('SELECT hocalist.website_waitlist_set_caps(50, $1)', [total]);
    const knownGlobal = await submit(route, 'known@example.com', '203.0.113.13');
    const unknownGlobal = await submit(route, 'unknown-global@example.com', '203.0.113.14');
    assert.equal(knownGlobal.status, 429);
    assert.equal(unknownGlobal.status, 429);
    assert.deepEqual(knownGlobal.body, unknownGlobal.body, 'known/unknown are indistinguishable at the global cap');
    await db.query('SELECT hocalist.website_waitlist_set_caps(5, 240)');

    // A wrong intake secret never distinguishes the address either.
    process.env.HOCALIST_WAITLIST_INTAKE_SECRET = SECRET.replace(/.$/, 'x');
    const wrongSecretKnown = await submit(route, 'known@example.com', '203.0.113.15');
    const wrongSecretUnknown = await submit(route, 'never-seen@example.com', '203.0.113.16');
    assert.equal(wrongSecretKnown.status, 503);
    assert.deepEqual(wrongSecretKnown.body, wrongSecretUnknown.body);
  } finally {
    await db.close();
  }
});

test('equal starting admission states produce identical full public sequences', async () => {
  // Two baseline databases of equal size differ only in whether the target
  // address was already stored. Each sequence then runs against a fresh
  // caller fingerprint: four fresh addresses, the target, and one more fresh
  // address. The complete public sequences must be identical.
  const run = async (options: { targetRegistered: boolean; address: string; globalCap?: number }) => {
    const targetEmail = options.targetRegistered ? 'sequence-target@example.com' : 'sequence-other@example.com';
    const db = await bootstrap(options.targetRegistered
      ? { email: 'sequence-target@example.com' }
      : { email: 'sequence-unrelated@example.com' });
    try {
      if (options.globalCap !== undefined) {
        await db.query('SELECT hocalist.website_waitlist_set_caps(50, $1)', [options.globalCap]);
      }
      bridgeFetch(db);
      const route = await import('../app/api/waitlist/route') as Route;
      const sequence = [];
      for (let index = 0; index < 4; index++) {
        sequence.push(await submit(route, `sequence-${index}@example.com`, options.address));
      }
      sequence.push(await submit(route, targetEmail, options.address));
      sequence.push(await submit(route, 'sequence-after@example.com', options.address));
      return sequence;
    } finally {
      await db.close();
    }
  };

  const registered = await run({ targetRegistered: true, address: '198.51.100.21' });
  const unknown = await run({ targetRegistered: false, address: '198.51.100.22' });
  assert.deepEqual(registered, unknown, 'the full sequence is membership-independent');
  assert.deepEqual(registered.map((entry) => entry.status), [200, 200, 200, 200, 200, 429],
    'the sequence is limited only by the shared admission budget');

  // Near the global cap: the same comparison with the boundary crossed in the
  // middle of the sequence.
  const registeredGlobal = await run({ targetRegistered: true, address: '198.51.100.23', globalCap: 3 });
  const unknownGlobal = await run({ targetRegistered: false, address: '198.51.100.24', globalCap: 3 });
  assert.deepEqual(registeredGlobal, unknownGlobal, 'the near-global-cap sequence is membership-independent');
  assert.deepEqual(registeredGlobal.map((entry) => entry.status), [200, 200, 200, 429, 429, 429]);
});

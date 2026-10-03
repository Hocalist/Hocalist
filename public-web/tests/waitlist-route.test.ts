// Waitlist route contract: same-origin public intake, a required deployment
// secret, generic public acknowledgement for new and existing addresses, and
// the honest not-configured fallback. The RPC transport is stubbed.
import { strict as assert } from 'node:assert';
import { test, beforeEach, afterEach } from 'node:test';

const originalFetch = globalThis.fetch;
const originalEnv = {
  url: process.env.HOCALIST_SUPABASE_URL,
  key: process.env.HOCALIST_SUPABASE_ANON_KEY,
  secret: process.env.HOCALIST_WAITLIST_INTAKE_SECRET,
};
const SECRET = 'waitlist-intake-secret-0123456789abcdefghijk';

type Call = { url: string; body: Record<string, unknown> };

function stubFetch(handler: (url: string, body: Record<string, unknown>) => Response) {
  const calls: Call[] = [];
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const body = init?.body ? JSON.parse(String(init.body)) : {};
    calls.push({ url, body });
    return handler(url, body);
  }) as typeof fetch;
  return calls;
}

function request(
  body: unknown,
  headers: Record<string, string> = {
    'content-type': 'application/json',
    origin: 'http://localhost',
    'sec-fetch-site': 'same-origin',
    'x-forwarded-for': '203.0.113.10',
  },
): Request {
  return new Request('http://localhost/api/waitlist', {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
}

beforeEach(() => {
  process.env.HOCALIST_SUPABASE_URL = 'https://example.supabase.co';
  process.env.HOCALIST_SUPABASE_ANON_KEY = 'synthetic-anon-key';
  process.env.HOCALIST_WAITLIST_INTAKE_SECRET = SECRET;
});

afterEach(() => {
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

async function route() {
  return import('../app/api/waitlist/route');
}

test('configured waitlist sends the deployment secret and a salted fingerprint', async () => {
  const calls = stubFetch(() =>
    new Response(JSON.stringify({ status: 'joined' }), { status: 200 }));
  const { POST } = await route();
  const response = await POST(request({
    email: 'buyer@example.com', consent: true, source: 'download-page',
  }));
  assert.equal(response.status, 200);
  const payload = (await response.json()) as { status?: string; message?: string };
  assert.equal(payload.status, 'accepted');
  assert.match(String(payload.message), /launch update list/);
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /\/rest\/v1\/rpc\/website_waitlist_join$/);
  assert.equal(calls[0].body.p_email, 'buyer@example.com');
  assert.equal(calls[0].body.p_consent_version, 'launch-updates-v1');
  assert.equal(calls[0].body.p_source, 'download-page');
  assert.equal(calls[0].body.p_intake_token, SECRET);
  assert.match(String(calls[0].body.p_client_hash), /^[0-9a-f]{64}$/);
  assert.notEqual(calls[0].body.p_client_hash, '203.0.113.10');
});

test('new and existing addresses receive the same public acknowledgement', async () => {
  stubFetch(() => new Response(JSON.stringify({ status: 'already_joined' }), { status: 200 }));
  const { POST } = await route();
  const response = await POST(request({ email: 'existing@example.com', consent: true }));
  assert.equal(response.status, 200);
  const payload = (await response.json()) as { status?: string; message?: string };
  assert.equal(payload.status, 'accepted');
  assert.doesNotMatch(JSON.stringify(payload), /consented_at|already/);
});

test('forged forwarded metadata changes only the opaque fingerprint', async () => {
  const calls = stubFetch(() => new Response(JSON.stringify({ status: 'joined' }), { status: 200 }));
  const { POST } = await route();
  await POST(request({ email: 'a@example.com', consent: true }, {
    'content-type': 'application/json',
    origin: 'http://localhost',
    'sec-fetch-site': 'same-origin',
    'x-forwarded-for': '198.51.100.1',
  }));
  await POST(request({ email: 'b@example.com', consent: true }, {
    'content-type': 'application/json',
    origin: 'http://localhost',
    'sec-fetch-site': 'same-origin',
    'x-forwarded-for': '198.51.100.2',
  }));
  assert.equal(calls.length, 2);
  assert.notEqual(calls[0].body.p_client_hash, calls[1].body.p_client_hash);
});

test('cross-site, wrong content type and missing secret never reach the provider', async () => {
  const calls = stubFetch(() => new Response('{}', { status: 200 }));
  const { POST } = await route();
  const crossSite = await POST(request({ email: 'a@example.com', consent: true }, {
    'content-type': 'application/json',
    origin: 'https://evil.example',
    'sec-fetch-site': 'cross-site',
  }));
  assert.equal(crossSite.status, 403);
  const plainText = await POST(request({ email: 'a@example.com', consent: true }, {
    'content-type': 'text/plain',
    origin: 'http://localhost',
  }));
  assert.equal(plainText.status, 415);
  delete process.env.HOCALIST_WAITLIST_INTAKE_SECRET;
  const missingSecret = await POST(request({ email: 'a@example.com', consent: true }));
  assert.equal(missingSecret.status, 503);
  const payload = (await missingSecret.json()) as { error?: string };
  assert.equal(payload.error, 'waitlist_not_configured');
  assert.equal(calls.length, 0);
});

test('missing consent or invalid email is refused before any RPC call', async () => {
  const calls = stubFetch(() => new Response('{}', { status: 200 }));
  const { POST } = await route();
  assert.equal((await POST(request({ email: 'buyer@example.com', consent: false }))).status, 400);
  assert.equal((await POST(request({ email: 'nope', consent: true }))).status, 400);
  assert.equal(calls.length, 0);
});

test('a server rate limit is reported and storage failures stay generic', async () => {
  stubFetch(() => new Response(JSON.stringify({ code: 'P0001', message: 'rate_limited' }), { status: 400 }));
  let { POST } = await route();
  const limited = await POST(request({ email: 'other@example.com', consent: true }));
  assert.equal(limited.status, 429);

  stubFetch(() => new Response(JSON.stringify({ code: '42501', message: 'invalid_intake' }), { status: 403 }));
  ({ POST } = await route());
  const misconfigured = await POST(request({ email: 'other@example.com', consent: true }));
  assert.equal(misconfigured.status, 503);
  const payload = (await misconfigured.json()) as { error?: string };
  assert.equal(payload.error, 'waitlist_not_configured');
});

test('unconfigured backend keeps the honest not-configured contract', async () => {
  delete process.env.HOCALIST_SUPABASE_URL;
  delete process.env.HOCALIST_SUPABASE_ANON_KEY;
  const calls = stubFetch(() => new Response('{}', { status: 200 }));
  const { POST } = await route();
  const response = await POST(request({ email: 'buyer@example.com', consent: true }));
  assert.equal(response.status, 503);
  const payload = (await response.json()) as { error?: string };
  assert.equal(payload.error, 'waitlist_not_configured');
  assert.equal(calls.length, 0);
});

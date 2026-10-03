// Route-level mutation guard regression: the exact reproduction from the
// review (foreign Origin + Sec-Fetch-Site: cross-site + text/plain JSON) is
// rejected before authentication, and every cookie-authenticated mutation
// shares the guard. Provider transport is stubbed; no live call is made.
import { strict as assert } from 'node:assert';
import { test, beforeEach, afterEach } from 'node:test';

const originalFetch = globalThis.fetch;
const originalEnv = {
  url: process.env.HOCALIST_SUPABASE_URL,
  key: process.env.HOCALIST_SUPABASE_ANON_KEY,
};

beforeEach(() => {
  process.env.HOCALIST_SUPABASE_URL = 'https://example.supabase.co';
  process.env.HOCALIST_SUPABASE_ANON_KEY = 'synthetic-anon-key';
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  if (originalEnv.url === undefined) delete process.env.HOCALIST_SUPABASE_URL;
  else process.env.HOCALIST_SUPABASE_URL = originalEnv.url;
  if (originalEnv.key === undefined) delete process.env.HOCALIST_SUPABASE_ANON_KEY;
  else process.env.HOCALIST_SUPABASE_ANON_KEY = originalEnv.key;
});

function stubFetch(routes: Array<{ match: RegExp; response: () => Response }>) {
  const calls: string[] = [];
  globalThis.fetch = (async (input: string | URL | Request) => {
    const url = String(input);
    calls.push(url);
    for (const route of routes) {
      if (route.match.test(url)) return route.response();
    }
    throw new Error(`unexpected fetch ${url}`);
  }) as typeof fetch;
  return calls;
}

function request(
  path: string,
  headers: Record<string, string>,
  body: string,
): Request {
  return new Request(`http://localhost${path}`, { method: 'POST', headers, body });
}

const loginRoutes = () => [
  {
    match: /\/auth\/v1\/token\?grant_type=password/,
    response: () => new Response(JSON.stringify({
      access_token: 'access-token', refresh_token: 'refresh-token', expires_in: 3600,
    }), { status: 200 }),
  },
  {
    match: /website_purchase_status/,
    response: () => new Response(JSON.stringify({ account: { membership_id: 'm1' } }), { status: 200 }),
  },
];

test('the reproduced cross-site login is rejected before authentication', async () => {
  const calls = stubFetch(loginRoutes());
  const { POST } = await import('../app/api/session/login/route');
  const response = await POST(request('/api/session/login', {
    origin: 'https://evil.example',
    'sec-fetch-site': 'cross-site',
    'content-type': 'text/plain',
  }, JSON.stringify({ email: 'buyer@example.com', password: 'secret' })));
  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { state: 'rejected', error: 'cross_origin_rejected' });
  assert.equal(calls.length, 0, 'no provider call before the origin check');
});

test('same-site sibling and missing origin metadata are rejected', async () => {
  const calls = stubFetch(loginRoutes());
  const { POST } = await import('../app/api/session/login/route');
  const variants: Array<Record<string, string>> = [
    { origin: 'https://hocalist.com', 'sec-fetch-site': 'same-site', 'content-type': 'application/json' },
    { 'sec-fetch-site': 'same-origin', 'content-type': 'application/json' },
  ];
  for (const headers of variants) {
    const response = await POST(request('/api/session/login', headers, JSON.stringify({ email: 'a@b.com', password: 'x' })));
    assert.equal(response.status, 403, JSON.stringify(headers));
  }
  assert.equal(calls.length, 0);
});

test('same-origin non-JSON is rejected and same-origin JSON succeeds', async () => {
  const calls = stubFetch(loginRoutes());
  const { POST } = await import('../app/api/session/login/route');
  const wrongType = await POST(request('/api/session/login', {
    origin: 'http://localhost',
    'sec-fetch-site': 'same-origin',
    'content-type': 'text/plain',
  }, JSON.stringify({ email: 'a@b.com', password: 'x' })));
  assert.equal(wrongType.status, 415);
  assert.equal(calls.length, 0);

  const ok = await POST(request('/api/session/login', {
    origin: 'http://localhost',
    'sec-fetch-site': 'same-origin',
    'content-type': 'application/json',
  }, JSON.stringify({ email: 'seller@example.com', password: 'secret', returnTo: '/billing' })));
  assert.equal(ok.status, 200);
  const payload = (await ok.json()) as { ok?: boolean; returnTo?: string };
  assert.equal(payload.ok, true);
  assert.equal(payload.returnTo, '/billing');
  const cookies = ok.headers.getSetCookie?.() ?? [ok.headers.get('set-cookie') ?? ''];
  assert.equal(cookies.some((cookie) => /hocalist_site_session=/.test(cookie)), true);
  assert.equal(cookies.some((cookie) => /HttpOnly/i.test(cookie)), true);
});

test('a buyer or restricted account is refused after authentication', async () => {
  stubFetch([
    loginRoutes()[0],
    {
      match: /website_purchase_status/,
      response: () => new Response(JSON.stringify({
        code: '42501', message: 'billing_access_denied',
      }), { status: 403 }),
    },
  ]);
  const { POST } = await import('../app/api/session/login/route');
  const response = await POST(request('/api/session/login', {
    origin: 'http://localhost',
    'sec-fetch-site': 'same-origin',
    'content-type': 'application/json',
  }, JSON.stringify({ email: 'buyer@example.com', password: 'secret' })));
  assert.equal(response.status, 403);
});

test('logout, checkout and portal share the same guard', async () => {
  const calls = stubFetch([]);
  const { POST: logout } = await import('../app/api/session/logout/route');
  const { POST: checkout } = await import('../app/api/billing/checkout/route');
  const { POST: portal } = await import('../app/api/billing/portal/route');
  const hostile = {
    origin: 'https://evil.example',
    'sec-fetch-site': 'cross-site',
    'content-type': 'application/json',
  };
  assert.equal((await logout(request('/api/session/logout', hostile, '{}'))).status, 403);
  assert.equal((await checkout(request('/api/billing/checkout', hostile, JSON.stringify({
    kind: 'subscription', plan: 'pro', idempotencyKey: '2f0c9d1a-0000-4000-8000-000000000001',
  })))).status, 403);
  assert.equal((await portal(request('/api/billing/portal', hostile, JSON.stringify({
    returnPath: '/billing',
  })))).status, 403);
  assert.equal(calls.length, 0);

  const sameOriginLogout = await logout(request('/api/session/logout', {
    origin: 'http://localhost',
    'sec-fetch-site': 'same-origin',
  }, ''));
  assert.equal(sameOriginLogout.status, 200);
  const clearing = sameOriginLogout.headers.getSetCookie?.() ?? [sameOriginLogout.headers.get('set-cookie') ?? ''];
  assert.equal(clearing.some((cookie) => /Max-Age=0/i.test(cookie)), true);
});

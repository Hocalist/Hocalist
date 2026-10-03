// Same-origin mutation guard: cross-site and sibling-origin requests are
// rejected before any authentication or dispatch, Content-Type and body size
// are enforced, and reverse-proxy origin headers are handled.
import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { guardMutation, readBoundedJson, requestOrigin } from '../app/lib/website-guard';

function request(
  url: string,
  headers: Record<string, string> = {},
  body = '',
  method = 'POST',
): Request {
  return new Request(url, { method, headers, body: method === 'POST' ? body : undefined });
}

test('same-origin browser mutations pass with JSON', () => {
  const result = guardMutation(request('https://www.hocalist.com/api/session/login', {
    origin: 'https://www.hocalist.com',
    'sec-fetch-site': 'same-origin',
    'content-type': 'application/json',
  }), { policy: 'session' }, true);
  assert.equal(result.ok, true);
});

test('cross-site and sibling-origin mutations are rejected', () => {
  for (const origin of ['https://evil.example', 'https://hocalist.com', 'null']) {
    const result = guardMutation(request('https://www.hocalist.com/api/session/login', {
      origin,
      'sec-fetch-site': 'cross-site',
      'content-type': 'application/json',
    }), { policy: 'session' }, true);
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.equal(result.status, 403);
      assert.equal(result.error, 'cross_origin_rejected');
    }
  }
  // A same-site sibling request without the Origin header is still rejected.
  const missing = guardMutation(request('https://www.hocalist.com/api/session/logout', {
    'sec-fetch-site': 'same-site',
  }), { policy: 'session', json: false }, true);
  assert.equal(missing.ok, false);
});

test('missing or malformed origin metadata never authenticates', () => {
  const noHeaders = guardMutation(
    request('https://hocalist.com/api/session/login'),
    { policy: 'session' },
    true,
  );
  assert.equal(noHeaders.ok, false);
  const sameSiteOnly = guardMutation(request('https://hocalist.com/api/session/login', {
    origin: 'https://hocalist.com',
    'sec-fetch-site': 'same-site',
    'content-type': 'application/json',
  }), { policy: 'session' }, true);
  assert.equal(sameSiteOnly.ok, false);
});

test('content-type and size limits are enforced before anything else', () => {
  const plain = guardMutation(request('https://hocalist.com/api/session/login', {
    origin: 'https://hocalist.com',
    'sec-fetch-site': 'same-origin',
    'content-type': 'text/plain',
  }, JSON.stringify({ email: 'a@b.com', password: 'x' })), { policy: 'session' }, true);
  assert.equal(plain.ok, false);
  if (!plain.ok) assert.equal(plain.status, 415);

  const form = guardMutation(request('https://hocalist.com/api/session/login', {
    origin: 'https://hocalist.com',
    'sec-fetch-site': 'same-origin',
    'content-type': 'application/x-www-form-urlencoded',
  }, 'email=a%40b.com'), { policy: 'session' }, true);
  assert.equal(form.ok, false);

  const oversized = guardMutation(request('https://hocalist.com/api/waitlist', {
    origin: 'https://hocalist.com',
    'sec-fetch-site': 'same-origin',
    'content-type': 'application/json',
    'content-length': '9000',
  }), { policy: 'public-intake', maxBytes: 2048 }, true);
  assert.equal(oversized.ok, false);
  if (!oversized.ok) assert.equal(oversized.status, 413);

  const logoutNoBody = guardMutation(request('https://hocalist.com/api/session/logout', {
    origin: 'https://hocalist.com',
    'sec-fetch-site': 'same-origin',
  }), { policy: 'session', json: false }, true);
  assert.equal(logoutNoBody.ok, true);
});

test('reverse-proxy origin configuration is honoured', () => {
  const proxied = request('http://internal:3000/api/billing/checkout', {
    origin: 'https://shop.hocalist.com',
    'x-forwarded-host': 'shop.hocalist.com',
    'x-forwarded-proto': 'https',
    'sec-fetch-site': 'same-origin',
    'content-type': 'application/json',
  });
  assert.equal(requestOrigin(proxied, true), 'https://shop.hocalist.com');
  assert.equal(guardMutation(proxied, { policy: 'session' }, true).ok, true);

  const configured = process.env.HOCALIST_WEBSITE_ORIGIN;
  process.env.HOCALIST_WEBSITE_ORIGIN = 'https://billing.hocalist.com';
  try {
    const viaConfig = guardMutation(request('http://internal:3000/api/billing/portal', {
      origin: 'https://billing.hocalist.com',
      'content-type': 'application/json',
    }), { policy: 'session' }, true);
    assert.equal(viaConfig.ok, true);
  } finally {
    if (configured === undefined) delete process.env.HOCALIST_WEBSITE_ORIGIN;
    else process.env.HOCALIST_WEBSITE_ORIGIN = configured;
  }
});

test('local development origins are allowed without opening production', () => {
  const local = request('http://localhost:3013/api/session/login', {
    origin: 'http://localhost:3013',
    'sec-fetch-site': 'same-origin',
    'content-type': 'application/json',
  });
  assert.equal(guardMutation(local, { policy: 'session' }, false).ok, true);
  assert.equal(guardMutation(local, { policy: 'session' }, true).ok, false);
});

test('bounded JSON rejects oversized and malformed bodies', async () => {
  const ok = await readBoundedJson(request('https://hocalist.com/x', {
    'content-type': 'application/json',
  }, JSON.stringify({ a: 1 })), 64);
  assert.deepEqual(ok, { ok: true, body: { a: 1 } });

  const tooLarge = await readBoundedJson(request('https://hocalist.com/x', {
    'content-type': 'application/json',
  }, JSON.stringify({ a: 'x'.repeat(200) })), 64);
  assert.equal(tooLarge.ok, false);
  if (!tooLarge.ok) assert.equal(tooLarge.status, 413);

  const malformed = await readBoundedJson(request('https://hocalist.com/x', {
    'content-type': 'application/json',
  }, 'not json'), 64);
  assert.equal(malformed.ok, false);
  if (!malformed.ok) assert.equal(malformed.status, 400);
});

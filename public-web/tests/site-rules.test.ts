// Pure rules for the website purchase journey: sign-in validation, redirect
// allowlists, cookie options, provider URL checks and failure classification.
import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  classifySiteFailure,
  parseCheckoutBody,
  parseLoginBody,
  parsePortalBody,
  providerRedirect,
  refreshCookieOptions,
  safeReturnPath,
  sessionCookieOptions,
} from '../app/lib/website-rules';

const KEY = '2f0c9d1a-0000-4000-8000-000000000001';
const OPTION = '2f0c9d1a-0000-4000-8000-000000000002';
const CHECKOUT = '2f0c9d1a-0000-4000-8000-000000000003';

test('return continuity only allows reviewed same-site paths', () => {
  assert.equal(safeReturnPath('/billing'), '/billing');
  assert.equal(safeReturnPath('/billing/return'), '/billing/return');
  assert.equal(safeReturnPath('/pricing'), '/pricing');
  assert.equal(
    safeReturnPath(`/billing/return?checkout=${CHECKOUT}`),
    `/billing/return?checkout=${CHECKOUT}`,
  );
  assert.equal(
    safeReturnPath(`/billing/return?checkout=${CHECKOUT}&next=https://evil.example`),
    `/billing/return?checkout=${CHECKOUT}`,
  );
  assert.equal(safeReturnPath('/billing/return?checkout=not-a-uuid'), '/billing/return');
  for (const hostile of [
    'https://evil.example/billing',
    '//evil.example/billing',
    '/billing/../../etc/passwd',
    '/admin',
    '/billing?next=https://evil.example',
    'javascript:alert(1)',
    '',
    null,
    undefined,
    'x'.repeat(300),
  ]) {
    assert.equal(safeReturnPath(hostile), '/billing');
  }
});

test('login body is validated before any provider call', () => {
  const parsed = parseLoginBody({ email: ' seller@example.com ', password: 'secret', returnTo: '/billing/return' });
  assert.equal(parsed.ok, true);
  if (parsed.ok) {
    assert.deepEqual(parsed.value, {
      email: 'seller@example.com',
      password: 'secret',
      returnTo: '/billing/return',
    });
  }
  for (const body of [
    null,
    {},
    { email: 'not-an-email', password: 'x' },
    { email: 'a@b.com' },
    { email: 'a@b.com', password: 'x'.repeat(201) },
    { email: `${'a'.repeat(250)}@b.com`, password: 'x' },
  ]) {
    assert.equal(parseLoginBody(body).ok, false);
  }
});

test('checkout body accepts only a plan or catalogue option with a retry key', () => {
  assert.deepEqual(parseCheckoutBody({ kind: 'subscription', plan: 'pro', idempotencyKey: KEY }), {
    ok: true,
    value: { kind: 'subscription', plan: 'pro', idempotencyKey: KEY },
  });
  assert.deepEqual(parseCheckoutBody({ kind: 'credit_deposit', optionId: OPTION, idempotencyKey: KEY }), {
    ok: true,
    value: { kind: 'credit_deposit', optionId: OPTION, idempotencyKey: KEY },
  });
  for (const body of [
    { kind: 'subscription', plan: 'free', idempotencyKey: KEY },
    { kind: 'subscription', plan: 'pro', idempotencyKey: 'nope' },
    { kind: 'credit_deposit', optionId: 'nope', idempotencyKey: KEY },
    { kind: 'credit_deposit', idempotencyKey: KEY },
    { idempotencyKey: KEY },
    {},
  ]) {
    assert.equal(parseCheckoutBody(body).ok, false);
  }
});

test('portal body only allows approved return pages', () => {
  assert.deepEqual(parsePortalBody(null), { ok: true, value: { returnPath: '/billing' } });
  assert.deepEqual(parsePortalBody({ returnPath: '/billing/return' }), {
    ok: true,
    value: { returnPath: '/billing/return' },
  });
  for (const body of [{ returnPath: '/admin' }, { returnPath: 'https://evil.example' }, 'text', []]) {
    assert.equal(parsePortalBody(body).ok, false);
  }
});

test('provider redirects must be the exact hosted host over https', () => {
  assert.equal(
    providerRedirect('https://checkout.stripe.com/c/pay/test', 'checkout.stripe.com'),
    'https://checkout.stripe.com/c/pay/test',
  );
  assert.equal(
    providerRedirect('https://billing.stripe.com/p/session/test', 'billing.stripe.com'),
    'https://billing.stripe.com/p/session/test',
  );
  for (const bad of [
    'http://checkout.stripe.com/c/pay/test',
    'https://evil.example/checkout.stripe.com',
    'https://checkout.stripe.com.evil.example/x',
    'https://user:pass@checkout.stripe.com/x',
    'https://checkout.stripe.com:8443/x',
    'https://billing.stripe.com/p/session/test',
    null,
    42,
  ]) {
    assert.equal(providerRedirect(bad, 'checkout.stripe.com'), null);
  }
});

test('failure classification and cookie options stay conservative', () => {
  assert.equal(classifySiteFailure(401, null), 'signed_out');
  assert.equal(classifySiteFailure(403, '42501'), 'forbidden');
  assert.equal(classifySiteFailure(403, 'billing_review_required'), 'review');
  assert.equal(classifySiteFailure(503, null), 'error');

  const session = sessionCookieOptions({ expiresIn: 3600, isProduction: true });
  assert.deepEqual(session, { httpOnly: true, sameSite: 'lax', secure: true, path: '/', maxAge: 3600 });
  assert.equal(sessionCookieOptions({ expiresIn: 999999, isProduction: false }).maxAge, 86400);
  assert.equal(sessionCookieOptions({ expiresIn: 1, isProduction: false }).maxAge, 120);
  assert.equal(refreshCookieOptions({ isProduction: true }).maxAge, 60 * 60 * 24 * 30);
  assert.equal(refreshCookieOptions({ isProduction: true }).httpOnly, true);
});

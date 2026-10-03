// Waitlist intake rules: server-side consent/email validation and the exact
// RPC parameters sent to the database function.
import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { validateWaitlistSubmission, waitlistRpcParams } from '../app/api/waitlist/waitlist';
import { WAITLIST_CONSENT_VERSION } from '../app/lib/website-rules';

const HASH = 'a'.repeat(64);

test('waitlist validation requires an address and explicit consent', () => {
  assert.deepEqual(validateWaitlistSubmission({ email: ' buyer@example.com ', consent: true }), {
    ok: true,
    submission: { email: 'buyer@example.com', consent: true, market: undefined, source: undefined },
  });
  assert.equal(validateWaitlistSubmission({ email: 'buyer@example.com', consent: false }).ok, false);
  assert.equal(validateWaitlistSubmission({ email: 'nope', consent: true }).ok, false);
  assert.equal(validateWaitlistSubmission(null).ok, false);
  assert.equal(validateWaitlistSubmission('text').ok, false);
  const long = validateWaitlistSubmission({
    email: 'buyer@example.com',
    consent: true,
    source: 'x'.repeat(200),
  });
  assert.equal(long.ok, true);
  if (long.ok) assert.equal(long.submission.source?.length, 80);
});

test('RPC parameters use the server consent version, fingerprint and secret', () => {
  const params = waitlistRpcParams(
    { email: 'buyer@example.com', consent: true, source: 'download-page' },
    HASH,
    'intake-secret',
  );
  assert.deepEqual(params, {
    p_email: 'buyer@example.com',
    p_consent_version: WAITLIST_CONSENT_VERSION,
    p_source: 'download-page',
    p_client_hash: HASH,
    p_intake_token: 'intake-secret',
  });
  const fallback = waitlistRpcParams({ email: 'buyer@example.com', consent: true }, HASH, 'intake-secret');
  assert.equal(fallback.p_source, 'website');
});

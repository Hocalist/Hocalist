import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openNativeBillingTicket, sealNativeBillingTicket } from '../app/lib/native-billing-ticket';

test('native billing ticket hides credentials, rejects tampering/expiry and requires server configuration', () => {
  const saved = process.env.HOCALIST_NATIVE_BILLING_KEY;
  try {
    process.env.HOCALIST_NATIVE_BILLING_KEY = 'ab'.repeat(32);
    const now = Date.now();
    const issued = sealNativeBillingTicket('private-access-token', 'seller-test', now);
    assert(!issued.ticket.includes('private-access-token'));
    assert.equal(openNativeBillingTicket(issued.ticket, now).user, 'seller-test');
    assert.equal(openNativeBillingTicket(issued.ticket, now).token, 'private-access-token');
    assert.throws(() => openNativeBillingTicket(issued.ticket, now + 90_000));
    const data = Buffer.from(issued.ticket, 'base64url'); data[30] ^= 1;
    assert.throws(() => openNativeBillingTicket(data.toString('base64url'), now));
    assert.throws(() => openNativeBillingTicket('untrusted', now));
    delete process.env.HOCALIST_NATIVE_BILLING_KEY;
    assert.throws(() => sealNativeBillingTicket('token', 'seller'));
  } finally {
    if (saved === undefined) delete process.env.HOCALIST_NATIVE_BILLING_KEY;
    else process.env.HOCALIST_NATIVE_BILLING_KEY = saved;
  }
});

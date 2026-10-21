import { test } from 'node:test';
import assert from 'node:assert/strict';
import { subscribeNativeBillingReentry } from '../app/lib/native-billing-reentry';

test('a new native ticket on an already-mounted admission page reloads once', () => {
  const target = new EventTarget();
  let hash = '', reloads = 0;
  const stop = subscribeNativeBillingReentry(target, () => hash, () => reloads++);
  target.dispatchEvent(new Event('hashchange'));
  assert.equal(reloads, 0);
  hash = '#ticket=' + 'a'.repeat(80);
  target.dispatchEvent(new Event('hashchange'));
  target.dispatchEvent(new Event('hashchange'));
  assert.equal(reloads, 1);
  stop();
});

test('cleanup and effect replay do not leave duplicate listeners', () => {
  const target = new EventTarget();
  let hash = '', reloads = 0;
  const subscribe = () => subscribeNativeBillingReentry(target, () => hash, () => reloads++);
  subscribe()();
  const stop = subscribe();
  hash = '#ticket=' + 'b'.repeat(80);
  target.dispatchEvent(new Event('hashchange'));
  assert.equal(reloads, 1);
  stop();
  hash = '#ticket=' + 'c'.repeat(80);
  target.dispatchEvent(new Event('hashchange'));
  assert.equal(reloads, 1);
});

test('unrelated, malformed and oversized fragments never trigger reentry', () => {
  const target = new EventTarget();
  let hash = '', reloads = 0;
  const stop = subscribeNativeBillingReentry(target, () => hash, () => reloads++);
  for (const value of ['#help', '#ticket=short', '#ticket=' + 'a'.repeat(8193), '#ticket=%3Cscript%3E']) {
    hash = value;
    target.dispatchEvent(new Event('hashchange'));
  }
  assert.equal(reloads, 0);
  stop();
});

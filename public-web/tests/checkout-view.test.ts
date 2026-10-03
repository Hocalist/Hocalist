// Return-page selection rules: the exact hinted checkout wins, an older
// completed purchase never substitutes for a newer pending or cancelled one,
// subscription and deposit completion are distinct, and an unknown/foreign
// hint resolves to "missing" rather than to an unrelated success.
import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  intentMatches,
  readIntent,
  resolveCheckoutView,
  shouldClearIntent,
  writeIntent,
  type CheckoutIntent,
  type CheckoutRow,
  type IntentStorage,
} from '../app/lib/website-checkout';

const OLD_COMPLETE: CheckoutRow = {
  id: '91000000-0000-4000-8000-000000000001',
  kind: 'credit_deposit',
  state: 'complete',
  amount_minor: 2000,
  credited_at: '2026-09-26T14:04:00.000Z',
};
const NEW_OPEN: CheckoutRow = {
  id: '91000000-0000-4000-8000-000000000002',
  kind: 'credit_deposit',
  state: 'open',
  amount_minor: 2000,
  credited_at: null,
};
const SUBSCRIPTION_COMPLETE: CheckoutRow = {
  id: '91000000-0000-4000-8000-000000000003',
  kind: 'subscription',
  state: 'complete',
  amount_minor: 1500,
  plan_code: 'pro',
};

function memoryStorage(initial: Record<string, string> = {}): IntentStorage & { data: Record<string, string> } {
  const data = { ...initial };
  return {
    data,
    getItem: (key) => data[key] ?? null,
    setItem: (key, value) => {
      data[key] = value;
    },
    removeItem: (key) => {
      delete data[key];
    },
  };
}

test('a newer pending checkout is never masked by an older completion', () => {
  const view = resolveCheckoutView(
    { selected: NEW_OPEN, deposits: [NEW_OPEN, OLD_COMPLETE] },
    { hintProvided: true },
  );
  assert.equal(view.mode, 'pending');
  assert.equal(view.checkout?.id, NEW_OPEN.id);

  // Even without a hint, pending is preferred over an older completion.
  const withoutHint = resolveCheckoutView({ deposits: [NEW_OPEN, OLD_COMPLETE] }, {});
  assert.equal(withoutHint.mode, 'pending');
});

test('a cancelled current checkout does not fall back to an older completion', () => {
  const view = resolveCheckoutView(
    { selected: null, deposits: [OLD_COMPLETE] },
    { cancelled: true, hintProvided: true },
  );
  assert.equal(view.mode, 'missing');
  const noHint = resolveCheckoutView({ deposits: [OLD_COMPLETE] }, { cancelled: true });
  assert.equal(noHint.mode, 'unconfirmed');
});

test('subscription and deposit completion are distinguished', () => {
  assert.equal(
    resolveCheckoutView({ selected: SUBSCRIPTION_COMPLETE }, { hintProvided: true }).mode,
    'verified-subscription',
  );
  assert.equal(
    resolveCheckoutView({ selected: OLD_COMPLETE }, { hintProvided: true }).mode,
    'verified-deposit',
  );
  // A subscription checkout is not in the deposit history, but the exact
  // hinted row still resolves.
  const subscriptionOnly = resolveCheckoutView(
    { selected: SUBSCRIPTION_COMPLETE, deposits: [] },
    { hintProvided: true },
  );
  assert.equal(subscriptionOnly.mode, 'verified-subscription');
});

test('an unknown, foreign or expired hint is reported honestly', () => {
  assert.equal(
    resolveCheckoutView({ selected: null, deposits: [OLD_COMPLETE] }, { hintProvided: true }).mode,
    'missing',
  );
  assert.equal(
    resolveCheckoutView(
      { selected: { ...NEW_OPEN, state: 'expired' }, deposits: [OLD_COMPLETE] },
      { hintProvided: true },
    ).mode,
    'expired',
  );
  assert.equal(resolveCheckoutView({ selected: null, deposits: [] }, {}).mode, 'idle');
});

test('delayed webhook keeps the exact checkout pending', () => {
  const view = resolveCheckoutView(
    { selected: { ...NEW_OPEN, state: 'creating' }, deposits: [NEW_OPEN] },
    { hintProvided: true },
  );
  assert.equal(view.mode, 'pending');
});

test('retained intent is account-scoped and survives reloads, tabs and re-login', () => {
  const storage = memoryStorage();
  const intent: CheckoutIntent = {
    kind: 'subscription',
    value: 'pro',
    key: '2f0c9d1a-0000-4000-8000-00000000000a',
    checkoutId: null,
  };
  assert.equal(readIntent(storage, null), null, 'no account means no intent');
  writeIntent(storage, 'membership-a', intent);
  assert.deepEqual(readIntent(storage, 'membership-a'), intent);
  assert.equal(readIntent(storage, 'membership-b'), null, 'another account never sees it');
  writeIntent(storage, 'membership-b', null);
  assert.deepEqual(readIntent(storage, 'membership-a'), intent, 'clearing B leaves A intact');
  assert.equal(intentMatches(readIntent(storage, 'membership-a'), 'subscription', 'pro'), true);
  assert.equal(intentMatches(readIntent(storage, 'membership-a'), 'credit_deposit', 'x'), false);
});

test('the retry key is discarded only for the exact terminal checkout', () => {
  const intent: CheckoutIntent = {
    kind: 'credit_deposit',
    value: 'option-a',
    key: 'key-a',
    checkoutId: NEW_OPEN.id,
  };
  assert.equal(shouldClearIntent(intent, null), false, 'a lost response keeps the key');
  assert.equal(shouldClearIntent(intent, OLD_COMPLETE), false, 'an unrelated completion keeps the key');
  assert.equal(shouldClearIntent(intent, NEW_OPEN), false, 'an open exact checkout keeps the key');
  assert.equal(shouldClearIntent(intent, { ...NEW_OPEN, state: 'complete' }), true);
  assert.equal(shouldClearIntent(intent, { ...NEW_OPEN, state: 'expired' }), true);
  assert.equal(shouldClearIntent({ ...intent, checkoutId: null }, OLD_COMPLETE), false);
});

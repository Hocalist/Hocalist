import {test} from 'node:test';
import assert from 'node:assert/strict';
import {confirmationDelay, confirmationCopy} from '../app/lib/checkout-confirmation';

test('pending confirmation keeps polling beyond six checks and stops for terminal states', () => {
  for(let attempt=0;attempt<50;attempt++) assert.equal(confirmationDelay(true,false),5000);
  assert.equal(confirmationDelay(true,true),30000);
  assert.equal(confirmationDelay(false,false),null);
  assert.equal(confirmationDelay(false,true),null);
});
test('pending copy explains confirmation without inventing webhook delivery status', () => {
  assert.equal(confirmationCopy.title,'Confirming your payment');
  assert.match(confirmationCopy.delayed,/don’t pay again/);
  assert.doesNotMatch(Object.values(confirmationCopy).join(' '),/Stripe|event|webhook/);
});

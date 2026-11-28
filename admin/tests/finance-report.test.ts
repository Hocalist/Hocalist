import { test } from 'node:test';
import assert from 'node:assert/strict';
import { financePreview } from '../app/lib/finance-preview';
import { parseFinanceReport, parseMoneyInput, profitFor } from '../app/lib/finance-report';

test('profit counts earned fees and rewards once and excludes credit deposits and payout principal', () => {
  const month = financePreview.months[0];
  const result = profitFor(month);
  assert.deepEqual(result, { revenue: 53000, directCosts: 17300, contribution: 35700, profit: 22500 });
  assert.deepEqual(profitFor({ ...month, deposits: 999999, paidNet: 99999 }), result);
});

test('unknown costs leave profit incomplete and verified zero is accepted', () => {
  const month = financePreview.months[0];
  const totals = { ...month.totals!, overhead: null };
  assert.equal(profitFor({ ...month, totals }).profit, null);
  assert.equal(profitFor({ ...month, totals: { ...totals, overhead: 0 } }).profit, 35700);
  assert.equal(parseMoneyInput(''), null);
  assert.equal(parseMoneyInput('0.00'), 0);
  assert.equal(parseMoneyInput('20.05'), 2005);
  assert.equal(parseMoneyInput('20.001'), undefined);
  assert.equal(parseMoneyInput('-20.00'), undefined);
});

test('the server report requires sorted months and valid integer accounting data', () => {
  assert.ok(parseFinanceReport(financePreview));
  assert.equal(parseFinanceReport({ ...financePreview, months: [...financePreview.months].reverse() }), null);
  assert.equal(parseFinanceReport({
    ...financePreview,
    months: [{ ...financePreview.months[0], paidNet: -1 }, ...financePreview.months.slice(1)],
  }), null);
});

export const financeFields = {
  subscriptions: 'Paid subscriptions',
  targeting: 'Earned targeting fees',
  confirmation: 'Additional PIN-confirmation fees',
  stripeFees: 'Stripe fees',
  refunds: 'Refunds and disputes',
  rewardsEarned: 'Buyer rewards earned',
  overhead: 'Operating expenses',
} as const;

export type FinanceField = keyof typeof financeFields;
export const financeKeys = Object.keys(financeFields) as FinanceField[];
export type Totals = Record<FinanceField, number | null>;
export type Impact = {
  buyersWithOffers: number;
  confirmedPurchases: number;
  buyersRewarded: number;
  sellersReachingBuyers: number;
  sellersClosingDeals: number;
  creditsReturned: number;
  belowMinimum: number;
  readyToWithdraw: number;
};
export type Month = {
  month: string;
  deposits: number;
  excludedPilotDeposits?: number;
  subscriptionReconciled?: boolean;
  paidNet: number;
  paidBuyers: number;
  payoutCount: number;
  payoutDeductions: number;
  revision: number;
  totals: Totals | null;
  note: string | null;
  activity?: Record<'real' | 'test' | 'unclassified', Record<'requests' | 'offers' | 'confirmations', number>>;
  impact?: Impact;
  planContributions?: Record<'Free' | 'Pro' | 'Elite', number>;
};
export type FinanceReport = { months: Month[]; processingGross: number; capturedAt?: string; sandboxPaidPayouts?: number };
export type FinanceReview = { report: FinanceReport; capturedAt: string; sandboxPaidPayouts: number };

const formatUSD = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });
const formatMonth = new Intl.DateTimeFormat('en-US', { month: 'short', year: 'numeric', timeZone: 'UTC' });
export const money = (cents: number | null) => cents === null ? '—' : formatUSD.format(cents / 100);
export const monthLabel = (month: string) => formatMonth.format(new Date(month + '-01T00:00:00Z'));

function sumComplete(values: Array<number | null | undefined>) {
  return values.every((value): value is number => typeof value === 'number')
    ? values.reduce((sum, value) => sum + value, 0)
    : null;
}

export function profitFor(month: Month) {
  const { totals, payoutDeductions } = month;
  const revenue = sumComplete([totals?.subscriptions, totals?.targeting, totals?.confirmation, payoutDeductions]);
  const directCosts = sumComplete([totals?.stripeFees, totals?.refunds, totals?.rewardsEarned]);
  const contribution = revenue === null || directCosts === null ? null : revenue - directCosts;
  const profit = contribution === null || totals?.overhead == null ? null : contribution - totals.overhead;
  return { revenue, directCosts, contribution, profit };
}

export function parseMoneyInput(input: string) {
  if (input.trim() === '') return null;
  if (!/^\d{1,8}(\.\d{1,2})?$/.test(input.trim())) return undefined;
  const [whole, decimal = ''] = input.trim().split('.');
  return Number(whole) * 100 + Number(decimal.padEnd(2, '0'));
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function count(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

function validActivity(value: unknown) {
  return record(value) && ['real', 'test', 'unclassified'].every(key => {
    const cohort = value[key];
    return record(cohort) && [cohort.requests, cohort.offers, cohort.confirmations].every(count);
  });
}

function isMonth(value: unknown): value is Month {
  return record(value) && typeof value.month === 'string' && /^\d{4}-(0[1-9]|1[0-2])$/.test(value.month) &&
    [value.deposits, value.paidNet, value.paidBuyers, value.payoutCount, value.payoutDeductions, value.revision].every(count) &&
    (value.excludedPilotDeposits === undefined || count(value.excludedPilotDeposits)) &&
    (value.subscriptionReconciled === undefined || typeof value.subscriptionReconciled === 'boolean') &&
    (value.activity === undefined || validActivity(value.activity)) &&
    (value.note === null || typeof value.note === 'string') &&
    (value.totals === null || (record(value.totals) &&
      financeKeys.every(key => (value.totals as Record<string, unknown>)[key] === null ||
        count((value.totals as Record<string, unknown>)[key]))));
}

export function parseFinanceReport(value: unknown): FinanceReport | null {
  if (!record(value) || !Array.isArray(value.months) || value.months.length !== 6 ||
      !value.months.every(isMonth) || !count(value.processingGross) ||
      !value.months.every((month, i, rows) => i === 0 || rows[i - 1].month < month.month)) return null;
  const capturedAt = value.capturedAt;
  if (capturedAt !== undefined && (typeof capturedAt !== 'string' || !Number.isFinite(Date.parse(capturedAt)))) return null;
  const sandboxPaidPayouts = value.sandboxPaidPayouts;
  if (sandboxPaidPayouts !== undefined && !count(sandboxPaidPayouts)) return null;
  return { months: value.months, processingGross: value.processingGross,
    ...(typeof capturedAt === 'string' ? { capturedAt } : {}),
    ...(typeof sandboxPaidPayouts === 'number' ? { sandboxPaidPayouts } : {}) };
}

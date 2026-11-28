'use client';

import { useEffect, useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { Stat } from '../components';
import { adminRpc } from '../lib/admin-client';
import {
  financeFields, financeKeys, money, monthLabel, parseFinanceReport, parseMoneyInput,
  profitFor, type FinanceReport, type FinanceReview, type Month, type Totals,
} from '../lib/finance-report';
import './finance.css';

type View = 'profit' | 'impact';
const count = new Intl.NumberFormat('en-US');
const easternTime = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/New_York', dateStyle: 'medium', timeStyle: 'short',
});

function Chart({ report, view, month, select }: {
  report: FinanceReport; view: View; month: string; select: (month: string) => void;
}) {
  const values = report.months.map(row => view === 'profit' ? profitFor(row).profit : row.paidNet);
  const scale = Math.max(1, ...values.map(value => Math.abs(value ?? 0)));
  return <section className="section finance-chart">
    <h2>{view === 'profit' ? 'Monthly operating profit' : 'Monthly rewards paid'}</h2>
    <p>{view === 'profit' ? 'Choose a month to see the revenue and costs behind it.' : 'Choose a month to see who benefited and how much was paid.'}</p>
    <div className="finance-bars">
      {report.months.map((row, i) => {
        const value = values[i];
        return <button type="button" key={row.month} aria-pressed={month === row.month}
          onClick={() => select(row.month)}>
          <strong>{value === null ? 'Incomplete' : money(value)}</strong>
          <span className="finance-track" aria-hidden="true">
            <span data-state={value === null ? 'unknown' : value < 0 ? 'negative' : 'positive'}
              style={{ width: value === null ? '100%' : `${Math.abs(value) / scale * 100}%` }} />
          </span>
          <span>{monthLabel(row.month)}</span>
        </button>;
      })}
    </div>
  </section>;
}

function MonthlyInputs({ month, sample, onSaved }: {
  month: Month; sample: boolean; onSaved: (totals: Totals, note: string) => Promise<boolean>;
}) {
  const [message, setMessage] = useState('');
  const [saving, setSaving] = useState(false);
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const amounts = financeKeys.map(key => [key, parseMoneyInput(String(data.get(key) ?? ''))] as const);
    if (amounts.some(([, amount]) => amount === undefined)) {
      setMessage('Enter USD amounts with up to two decimal places.');
      return;
    }
    const note = String(data.get('note') ?? '').trim();
    if (!note) {
      setMessage('Add a short source note so the totals can be reconciled.');
      return;
    }
    setSaving(true);
    setMessage('');
    const saved = await onSaved(Object.fromEntries(amounts) as Totals, note);
    setSaving(false);
    setMessage(saved ? sample ? 'Example updated on this page.' : 'Monthly totals saved.' : 'Could not save. Reload to check for a newer revision.');
  }
  return <details className="section finance-inputs">
    <summary>{sample ? 'Try different monthly figures' : 'Record reconciled monthly figures'}</summary>
    <p>Use totals in USD for {monthLabel(month.month)}. Enter 0 only for a verified zero. Leave unknown amounts blank.</p>
    <p>Enter verified real customer activity and operating costs. Exclude sandbox, pilot testing, and unclassified amounts. Enter gross earned fees before refunds, and only the additional fee for PIN confirmation. Include payout provider fees under Stripe fees. Leave returned credits out of refunds if those credits were never counted as revenue.</p>
    <form onSubmit={save}>
      <div className="finance-form-grid">{financeKeys.filter(key => sample || key !== 'subscriptions').map(key => <label key={key}>
        {financeFields[key]}
        <input name={key} inputMode="decimal" placeholder="Unknown"
          defaultValue={month.totals?.[key] == null ? '' : (month.totals[key] / 100).toFixed(2)} />
      </label>)}</div>
      <label>Source note<input name="note" maxLength={240} required defaultValue={month.note ?? ''}
        placeholder="For example, Stripe statement and hosting invoice" /></label>
      <button className="primary" disabled={saving} type="submit">{sample ? 'Update example' : 'Save monthly figures'}</button>
      {message && <p role="status">{message}</p>}
    </form>
  </details>;
}

function Profit({ month, previous }: { month: Month; previous?: Month }) {
  const { revenue, directCosts, contribution, profit } = profitFor(month);
  const lines: [string, number | null][] = [
    ['Paid subscriptions', month.totals?.subscriptions ?? null],
    ['Earned targeting fees', month.totals?.targeting ?? null],
    ['Additional PIN-confirmation fees', month.totals?.confirmation ?? null],
    ['Withdrawal deductions retained', month.payoutDeductions],
    ['Stripe fees', month.totals?.stripeFees ?? null],
    ['Refunds and disputes', month.totals?.refunds ?? null],
    ['Buyer rewards earned', month.totals?.rewardsEarned ?? null],
    ['Operating expenses', month.totals?.overhead ?? null],
  ];
  const changes = [
    ['Stripe fees', 'stripeFees'], ['Refunds and disputes', 'refunds'],
    ['Buyer rewards', 'rewardsEarned'], ['Operating expenses', 'overhead'],
  ] as const;
  const changesByCost = changes.flatMap(([label, key]) => {
    const current = month.totals?.[key];
    const prior = previous?.totals?.[key];
    return current == null || prior == null ? [] : [{ label, change: current - prior }];
  }).sort((a, b) => b.change - a.change);
  const increase = changesByCost[0];
  return <>
    <div className="stats">
      <Stat label="Earned revenue" value={money(revenue)} note="Subscriptions and earned fees" />
      <Stat label="Direct costs" value={money(directCosts)} note="Stripe, refunds and buyer rewards" tone="gold" />
      <Stat label="After direct costs" value={money(contribution)} note="Before operating expenses" />
      <Stat label="Operating profit" value={money(profit)}
        note={profit === null ? 'More figures needed' : 'After listed operating expenses'} tone={profit !== null && profit < 0 ? 'red' : 'blue'} />
    </div>
    <section className="section finance-breakdown">
      <div>
        <h2>Revenue and cost breakdown</h2>
        <dl>{lines.map(([label, amount]) => <div key={label}><dt>{label}</dt><dd>{money(amount)}</dd></div>)}</dl>
      </div>
      <aside>
        <h2>What changed</h2>
        {increase?.change > 0
          ? <p>{increase.label} rose by {money(increase.change)} against the prior month. Review this line first to understand the increase.</p>
          : <p>{changesByCost.length ? 'No recorded cost line increased against the prior month.' : 'Enter comparable monthly totals to see what changed.'}</p>}
        <h3>Cash from HocaCredits</h3>
        <strong>{money(month.deposits)}</strong>
        <p>Credit purchases are cash collected. Earned fees enter revenue when those credits are spent on a qualifying fee.</p>
        {Boolean(month.excludedPilotDeposits) && <p>{money(month.excludedPilotDeposits ?? 0)} in real-money pilot deposits excluded.</p>}
      </aside>
    </section>
    <section className="section finance-breakdown">
      <div>
        <h2>After direct costs by seller plan</h2>
        <dl>{(['Free', 'Pro', 'Elite'] as const).map(plan =>
          <div key={plan}><dt>{plan}</dt><dd>{money(month.planContributions?.[plan] ?? null)}</dd></div>)}</dl>
      </div>
      <p>{month.planContributions
        ? 'Sample contributions show revenue less direct costs attributable to each plan. Shared costs stay in the overall report.'
        : 'Plan comparisons need live revenue and direct costs tied to the seller plan at the time of the transaction.'}</p>
    </section>
  </>;
}

function Rewards({ month, processingGross }: { month: Month; processingGross: number }) {
  const impact = month.impact;
  return <>
    <div className="stats">
      <Stat label="Rewards paid out" value={money(month.paidNet)} note={`${count.format(month.payoutCount)} completed payouts`} />
      <Stat label="Buyers who received a payout" value={count.format(month.paidBuyers)} note="Unique buyers in the selected month" />
      <Stat label="Buyers rewarded" value={impact ? count.format(impact.buyersRewarded) : '—'} note="Buyers who earned a reward" />
      <Stat label="PIN-confirmed purchases"
        value={month.activity ? count.format(month.activity.real.confirmations) : impact ? count.format(impact.confirmedPurchases) : '—'}
        note={month.activity ? 'Verified real activity' : 'Buyer-confirmed purchases'} />
    </div>
    <section className="section finance-breakdown">
      <div>
        <h2>Buyer rewards</h2>
        <dl>
          <div><dt>Average completed payout</dt><dd>{month.payoutCount ? money(Math.round(month.paidNet / month.payoutCount)) : '—'}</dd></div>
          <div><dt>Rewards earned this month</dt><dd>{money(month.totals?.rewardsEarned ?? null)}</dd></div>
          <div><dt>Pending withdrawal requests, all dates</dt><dd>{money(processingGross)}</dd></div>
          <div><dt>Balances below withdrawal minimum</dt><dd>{money(impact?.belowMinimum ?? null)}</dd></div>
          <div><dt>Balances ready to withdraw</dt><dd>{money(impact?.readyToWithdraw ?? null)}</dd></div>
        </dl>
        <p>Estimated rewards stay out of earned and paid totals. Item payments happen offline.</p>
      </div>
      <div>
        <h2>Marketplace outcomes</h2>
        <dl>
          <div><dt>Buyers who received offers</dt><dd>{impact ? count.format(impact.buyersWithOffers) : '—'}</dd></div>
          <div><dt>Sellers who reached buyers</dt><dd>{impact ? count.format(impact.sellersReachingBuyers) : '—'}</dd></div>
          <div><dt>Sellers with confirmed deals</dt><dd>{impact ? count.format(impact.sellersClosingDeals) : '—'}</dd></div>
          <div><dt>HocaCredit returned</dt><dd>{impact ? `${(impact.creditsReturned / 100).toFixed(2)} HC` : '—'}</dd></div>
        </dl>
        {!impact && <p>These figures are unavailable until real marketplace activity can be distinguished from test activity in the records.</p>}
      </div>
    </section>
  </>;
}

function MarketplaceActivity({ activity }: { activity: NonNullable<Month['activity']> }) {
  const cohorts = [['Verified real', 'real'], ['Test or pilot accounts', 'test'], ['Unclassified', 'unclassified']] as const;
  return <section className="section finance-breakdown">
    <div>
      <h2>Marketplace activity by group</h2>
      <table>
        <thead><tr><th scope="col">Activity</th><th scope="col">Requests</th><th scope="col">Offers</th><th scope="col">PIN-confirmed purchases</th></tr></thead>
        <tbody>{cohorts.map(([label, key]) => <tr key={key}>
          <th scope="row">{label}</th><td>{count.format(activity[key].requests)}</td>
          <td>{count.format(activity[key].offers)}</td><td>{count.format(activity[key].confirmations)}</td>
        </tr>)}</tbody>
      </table>
      <p>Records involving known test or pilot accounts stay in their own group. Activity requires verified real participants to count toward real usage. Records without enough evidence stay unclassified.</p>
    </div>
  </section>;
}

export function FinancePanel({ view, example, review }: { view: View; example: FinanceReport | null; review: FinanceReview | null }) {
  const router = useRouter();
  const [storedReport, setReport] = useState(example);
  const report = review?.report ?? storedReport;
  const [selected, select] = useState('');
  const [error, setError] = useState(false);
  const [reload, setReload] = useState(0);
  const reviewActive = review !== null;
  useEffect(() => {
    if (!reviewActive) return;
    const refresh = () => { if (document.visibilityState === 'visible') router.refresh(); };
    const interval = window.setInterval(refresh, 60_000);
    document.addEventListener('visibilitychange', refresh);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener('visibilitychange', refresh);
    };
  }, [reviewActive, router]);
  useEffect(() => {
    if (example || review) return;
    let active = true;
    let pending = false;
    async function refresh() {
      if (pending) return;
      pending = true;
      const result = await adminRpc('admin_finance_overview', {});
      pending = false;
      const parsed = result.ok ? parseFinanceReport(result.data) : null;
      if (!active) return;
      setReport(parsed);
      setError(parsed === null);
    }
    const refreshVisible = () => { if (document.visibilityState === 'visible') void refresh(); };
    void refresh();
    const interval = window.setInterval(refreshVisible, 60_000);
    document.addEventListener('visibilitychange', refreshVisible);
    return () => {
      active = false;
      window.clearInterval(interval);
      document.removeEventListener('visibilitychange', refreshVisible);
    };
  }, [example, review, reload]);

  if (error) return <section className="section" role="alert">
    <h2>Finance data is unavailable</h2>
    <p>Check that the reporting database is available and your administrator session is active.</p>
    <button onClick={() => { setError(false); setReload(value => value + 1); }}>Try again</button>
  </section>;
  if (!report) return <p role="status">Loading finance report…</p>;

  const month = report.months.find(row => row.month === selected) ?? report.months[report.months.length - 1];
  const previous = report.months[report.months.indexOf(month) - 1];
  async function onSaved(totals: Totals, note: string) {
    if (example) {
      setReport(current => current && { ...current, months: current.months.map(row =>
        row.month === month.month ? { ...row, totals, note } : row) });
      return true;
    }
    const saved = await adminRpc('admin_finance_save_month', {
      p_month: month.month + '-01', p_revision: month.revision, p_totals: totals, p_note: note,
    });
    if (saved.ok) setReload(value => value + 1);
    return saved.ok;
  }
  return <div className="finance-report">
    {example && <p className="demo-notice"><strong>Sample data.</strong> Figures and edits in this preview stay separate from your Hocalist records.</p>}
    {review && <p className="demo-notice"><strong>Read-only snapshot of real data.</strong> Captured {easternTime.format(new Date(review.capturedAt))} Eastern. {view === 'impact'
      ? `${count.format(review.sandboxPaidPayouts)} completed sandbox payouts excluded.`
      : 'Subscription figures appear for months reconciled against Stripe.'} This page checks for refreshed data every minute while open.</p>}
    {report.capturedAt && <p className="demo-notice">
      Last refreshed {easternTime.format(new Date(report.capturedAt))} Eastern. Refreshes every minute while open.
      {view === 'impact' && typeof report.sandboxPaidPayouts === 'number' &&
        ` ${count.format(report.sandboxPaidPayouts)} completed sandbox payouts excluded.`}
    </p>}
    <Chart report={report} view={view} month={month.month} select={select} />
    <h2 className="finance-period">{monthLabel(month.month)}</h2>
    {view === 'profit' ? <>
      <Profit month={month} previous={previous} />
      {!example && !review && <p className="demo-notice">{month.subscriptionReconciled
        ? 'Subscription payments for this month were reconciled against Stripe.'
        : 'Subscription revenue is unavailable until payments for this month are reconciled with Stripe.'}</p>}
      {review && month.note && <p className="demo-notice">{month.note}</p>}
      {!review && <MonthlyInputs key={month.month + '-' + month.revision} month={month} sample={Boolean(example)} onSaved={onSaved} />}
    </> : <>
      {month.activity && <MarketplaceActivity activity={month.activity} />}
      <Rewards month={month} processingGross={report.processingGross} />
    </>}
  </div>;
}

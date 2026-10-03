'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { formatUsdMinor, parsePortalBody, safeReturnPath } from '../lib/website-rules';
import {
  intentMatches,
  readIntent,
  shouldClearIntent,
  writeIntent,
  type CheckoutIntent,
  type CheckoutRow
} from '../lib/website-checkout';

type PlanRow = { code: string; amount_minor: number; currency?: string; enabled: boolean };
type BillingOption = {
  id: string;
  amount_minor: number;
  initial_fee_minor: number;
  winning_total_minor: number;
  rate_version: string;
  sort_order?: number;
};
type BillingSubscription = {
  plan?: string;
  provider_status?: string | null;
  paid_until?: string | null;
  cancel_at_period_end?: boolean;
  requires_review?: boolean;
};

type StatusPayload = {
  state: 'ready';
  preview?: boolean;
  account: { membership_id?: string } | null;
  plans: PlanRow[];
  options: BillingOption[];
  subscription: BillingSubscription | null;
  deposits: CheckoutRow[];
  selected: CheckoutRow | null;
};

type ViewState =
  | { kind: 'loading' }
  | { kind: 'signed_out'; message?: string }
  | { kind: 'forbidden'; message: string; review?: boolean }
  | { kind: 'error'; message: string }
  | { kind: 'ready'; data: StatusPayload };

const PLAN_COPY: Record<string, { name: string; summary: string }> = {
  pro: { name: 'Pro Seller', summary: '50 weekly customer targets and up to 15 Store listings.' },
  elite: { name: 'Elite Seller', summary: '100 weekly customer targets and up to 50 Store listings.' }
};

function browserStorage() {
  return window.localStorage;
}

function newKey(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  const bytes = new Uint8Array(16);
  if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
    crypto.getRandomValues(bytes);
  } else {
    for (let index = 0; index < bytes.length; index++) bytes[index] = Math.floor(Math.random() * 256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export default function BillingPortal({
  previewKind = null,
  returnTo: requestedReturnTo = null
}: {
  previewKind?: string | null;
  returnTo?: string | null;
}) {
  const returnTo = safeReturnPath(requestedReturnTo);
  const [view, setView] = useState<ViewState>({ kind: 'loading' });
  const [action, setAction] = useState<{ busy: string | null; message: string | null; tone: 'info' | 'error' }>({
    busy: null,
    message: null,
    tone: 'info'
  });
  const membershipRef = useRef<string | null>(null);

  const applyPayload = useCallback((body: Record<string, unknown>, membershipId: string | null) => {
    const payload: StatusPayload = {
      state: 'ready',
      preview: body.preview === true,
      account: (body.account as StatusPayload['account']) ?? null,
      plans: Array.isArray(body.plans) ? (body.plans as PlanRow[]) : [],
      options: Array.isArray(body.options) ? (body.options as BillingOption[]) : [],
      subscription: (body.subscription as BillingSubscription) ?? null,
      deposits: Array.isArray(body.deposits) ? (body.deposits as CheckoutRow[]) : [],
      selected: (body.selected as CheckoutRow) ?? null
    };
    setView({ kind: 'ready', data: payload });
    if (membershipId) {
      const intent = readIntent(browserStorage(), membershipId);
      if (shouldClearIntent(intent, payload.selected)) {
        writeIntent(browserStorage(), membershipId, null);
      }
    }
  }, []);

  const load = useCallback(async () => {
    setView((current) => (current.kind === 'ready' ? current : { kind: 'loading' }));
    const query = new URLSearchParams();
    if (previewKind) query.set('preview', previewKind);
    const membershipId = membershipRef.current;
    if (membershipId) {
      const intent = readIntent(browserStorage(), membershipId);
      if (intent?.checkoutId) query.set('checkout', intent.checkoutId);
    }
    const suffix = query.size > 0 ? `?${query.toString()}` : '';
    try {
      const response = await fetch(`/api/billing/status${suffix}`, { cache: 'no-store' });
      const body = await response.json().catch(() => null);
      if (response.ok && body?.state === 'ready') {
        const resolved = (body.account?.membership_id as string | undefined) ?? membershipId;
        membershipRef.current = resolved ?? null;
        applyPayload(body, resolved ?? null);
        // The first response resolves the account, so an intent that only
        // existed locally can now be checked for a terminal exact checkout.
        // An intent without a recorded checkout id stays retained: it is the
        // lost-response recovery path and is retried with the same key.
        if (!membershipId && resolved) {
          const intent = readIntent(browserStorage(), resolved);
          if (intent?.checkoutId) {
            const hinted = new URLSearchParams({ checkout: intent.checkoutId });
            if (previewKind) hinted.set('preview', previewKind);
            const second = await fetch(`/api/billing/status?${hinted.toString()}`, { cache: 'no-store' });
            const secondBody = await second.json().catch(() => null);
            if (second.ok && secondBody?.state === 'ready') {
              applyPayload(secondBody, resolved);
            }
          }
        }
        return;
      }
      if (response.status === 401) {
        setView({ kind: 'signed_out', message: body?.message });
        return;
      }
      if (response.status === 403) {
        setView({
          kind: 'forbidden',
          message: body?.message ?? 'This account cannot purchase seller plans or credits.',
          review: body?.state === 'review'
        });
        return;
      }
      setView({
        kind: 'error',
        message: body?.message ?? 'Billing status is unavailable right now. Try again shortly.'
      });
    } catch {
      setView({ kind: 'error', message: 'Billing status is unavailable right now. Try again shortly.' });
    }
  }, [previewKind, applyPayload]);

  useEffect(() => {
    void load();
  }, [load]);

  async function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (action.busy) return;
    const form = new FormData(event.currentTarget);
    setAction({ busy: 'signin', message: null, tone: 'info' });
    try {
      const response = await fetch('/api/session/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: String(form.get('email') ?? ''),
          password: String(form.get('password') ?? ''),
          returnTo
        })
      });
      const body = await response.json().catch(() => null);
      if (!response.ok) {
        setAction({
          busy: null,
          message: body?.message ?? 'Sign-in failed. Check the email and password.',
          tone: 'error'
        });
        return;
      }
      setAction({ busy: null, message: null, tone: 'info' });
      membershipRef.current = null;
      await load();
    } catch {
      setAction({ busy: null, message: 'Sign-in could not reach the server.', tone: 'error' });
    }
  }

  async function signOut() {
    setAction({ busy: 'signout', message: null, tone: 'info' });
    try {
      await fetch('/api/session/logout', { method: 'POST' });
    } finally {
      membershipRef.current = null;
      setAction({ busy: null, message: null, tone: 'info' });
      setView({ kind: 'signed_out' });
    }
  }

  async function startCheckout(kind: CheckoutIntent['kind'], value: string) {
    if (view.kind !== 'ready' || action.busy) return;
    if (view.data.preview) {
      setAction({
        busy: null,
        message: 'Local preview mode: hosted checkout is not contacted and nothing was charged.',
        tone: 'info'
      });
      return;
    }
    const membershipId = membershipRef.current;
    const existing = readIntent(browserStorage(), membershipId);
    if (existing && !intentMatches(existing, kind, value)) {
      setAction({
        busy: null,
        message: 'A different checkout is already retained for this account. Finish it or wait for it to expire before choosing another.',
        tone: 'error'
      });
      return;
    }
    const intent: CheckoutIntent = existing ?? { kind, value, key: newKey(), checkoutId: null };
    writeIntent(browserStorage(), membershipId, intent);
    setAction({ busy: `${kind}:${value}`, message: null, tone: 'info' });
    try {
      const response = await fetch('/api/billing/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(
          kind === 'subscription'
            ? { kind, plan: value, idempotencyKey: intent.key }
            : { kind, optionId: value, idempotencyKey: intent.key }
        )
      });
      const body = await response.json().catch(() => null);
      if (response.ok && typeof body?.url === 'string') {
        writeIntent(browserStorage(), membershipId, {
          ...intent,
          checkoutId: typeof body.checkoutId === 'string' ? body.checkoutId : intent.checkoutId
        });
        window.location.assign(body.url);
        return;
      }
      if (response.status === 401) {
        setView({ kind: 'signed_out', message: body?.message });
        return;
      }
      setAction({
        busy: null,
        message: body?.message ?? 'Checkout could not be started. Try again shortly.',
        tone: 'error'
      });
      await load();
    } catch {
      setAction({ busy: null, message: 'Checkout could not reach the server. Try again.', tone: 'error' });
    }
  }

  async function openPortal() {
    if (view.kind !== 'ready' || action.busy) return;
    if (view.data.preview) {
      setAction({
        busy: null,
        message: 'Local preview mode: the hosted portal is not contacted.',
        tone: 'info'
      });
      return;
    }
    const parsed = parsePortalBody({ returnPath: '/billing' });
    if (!parsed.ok) return;
    setAction({ busy: 'portal', message: null, tone: 'info' });
    try {
      const response = await fetch('/api/billing/portal', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ returnPath: parsed.value.returnPath })
      });
      const body = await response.json().catch(() => null);
      if (response.ok && typeof body?.url === 'string') {
        window.location.assign(body.url);
        return;
      }
      if (response.status === 401) {
        setView({ kind: 'signed_out', message: body?.message });
        return;
      }
      setAction({
        busy: null,
        message: body?.message ?? 'The billing portal is unavailable right now.',
        tone: 'error'
      });
    } catch {
      setAction({ busy: null, message: 'The billing portal could not reach the server.', tone: 'error' });
    }
  }

  if (view.kind === 'loading') {
    return (
      <section className="billing-section" aria-busy="true">
        <div className="billing-card billing-loading">
          <span className="status-chip">Checking billing status</span>
          <p>Loading your seller plan and credit pack options…</p>
        </div>
      </section>
    );
  }

  if (view.kind === 'signed_out') {
    return (
      <section className="billing-section">
        <div className="billing-card billing-signin">
          <p className="eyebrow">Seller account</p>
          <h1>Sign in to manage your seller plan and credits</h1>
          <p>
            Purchases happen on this website through Stripe TEST checkout while billing is in
            testing. Sign in with the same Hocalist account you use in the app. Buyers never pay
            Hocalist here; item payment stays between buyer and seller.
          </p>
          <form className="billing-form" onSubmit={signIn} noValidate>
            <label className="request-field wide">
              <span>Account email</span>
              <input type="email" name="email" autoComplete="email" required />
            </label>
            <label className="request-field wide">
              <span>Password</span>
              <input type="password" name="password" autoComplete="current-password" required />
            </label>
            <button className="button primary" type="submit" disabled={action.busy === 'signin'}>
              {action.busy === 'signin' ? 'Signing in…' : 'Sign in'}
            </button>
          </form>
          {action.message ? (
            <p className="billing-message error" role="alert">{action.message}</p>
          ) : null}
          <p className="billing-note">
            Need help with your account? <a href="/support">Contact support</a>.
          </p>
        </div>
      </section>
    );
  }

  if (view.kind === 'forbidden') {
    return (
      <section className="billing-section">
        <div className="billing-card">
          <span className={`status-chip ${view.review ? 'gold' : ''}`}>
            {view.review ? 'Billing review needed' : 'Seller access required'}
          </span>
          <h1>{view.review ? 'Purchases are paused for this account' : 'This account cannot purchase here'}</h1>
          <p>{view.message}</p>
          <div className="billing-actions">
            <a className="button secondary" href="/support">Get help</a>
            <button className="button secondary" type="button" onClick={signOut}>Sign out</button>
          </div>
        </div>
      </section>
    );
  }

  if (view.kind === 'error') {
    return (
      <section className="billing-section">
        <div className="billing-card">
          <span className="status-chip gold">Billing unavailable</span>
          <h1>Billing status could not be loaded</h1>
          <p>{view.message}</p>
          <div className="billing-actions">
            <button className="button primary" type="button" onClick={() => void load()}>Retry</button>
            <button className="button secondary" type="button" onClick={signOut}>Sign out</button>
          </div>
        </div>
      </section>
    );
  }

  const { subscription, options, deposits, plans, preview } = view.data;
  const plan = subscription?.plan ?? 'free';
  const activePaid = plan === 'pro' || plan === 'elite';
  const openCheckout = deposits.find((checkout) => checkout.state === 'creating' || checkout.state === 'open');

  return (
    <section className="billing-section">
      {preview ? (
        <p className="billing-preview-banner" role="note">
          Local preview mode: every value on this page is synthetic and no provider is contacted.
        </p>
      ) : null}
      <div className="billing-card">
        <div className="billing-card-head">
          <div>
            <p className="eyebrow">Seller billing</p>
            <h1>Your plan, credits, and payment method</h1>
          </div>
          <button className="button secondary small" type="button" onClick={signOut} disabled={action.busy === 'signout'}>
            {action.busy === 'signout' ? 'Signing out…' : 'Sign out'}
          </button>
        </div>
        <div className="billing-summary-grid">
          <article className="billing-stat">
            <span>Current plan</span>
            <strong>{activePaid ? PLAN_COPY[plan]?.name ?? plan : 'Free'}</strong>
            <p>
              {activePaid
                ? subscription?.cancel_at_period_end
                  ? 'Cancels at the end of the paid period.'
                  : subscription?.paid_until
                    ? `Paid through ${new Date(subscription.paid_until).toLocaleDateString()}.`
                    : 'Active seller plan.'
                : 'Free seller tools with 10 weekly customer targets.'}
            </p>
          </article>
          <article className="billing-stat">
            <span>Payment method</span>
            <strong>Managed by Stripe</strong>
            <p>View or update saved payment methods in Stripe. A completed purchase does not confirm that a card is saved.</p>
            <button
              className="button secondary small"
              type="button"
              onClick={openPortal}
              disabled={action.busy === 'portal' || !(activePaid || deposits.some((entry) => entry.state === 'complete'))}
            >
              {action.busy === 'portal' ? 'Opening…' : 'Manage payment method'}
            </button>
          </article>
        </div>
        {openCheckout ? (
          <p className="billing-message info" role="status">
            A checkout is open right now. Complete it in the Stripe page, or choose the same option
            again to reopen the same session.
          </p>
        ) : null}
        {action.message ? (
          <p className={`billing-message ${action.tone}`} role={action.tone === 'error' ? 'alert' : 'status'}>
            {action.message}
          </p>
        ) : null}
      </div>

      <div className="billing-card">
        <h2>Seller plans</h2>
        <p className="billing-note">
          Monthly USD prices and availability come from the live seller plan configuration. Paid
          access is in TEST mode until billing activation; annual plans and trials are not offered
          here.
        </p>
        {plans.length === 0 ? (
          <div className="billing-empty">
            <span className="status-chip">No seller plans configured</span>
            <p>
              An administrator has not published seller plans yet, so there is nothing to buy here.
              Check back later or contact support.
            </p>
          </div>
        ) : (
          <div className="billing-plan-grid">
            {plans.map((entry) => {
              const copy = PLAN_COPY[entry.code] ?? { name: entry.code, summary: 'Seller plan.' };
              const isCurrent = activePaid && plan === entry.code;
              const price = `${formatUsdMinor(entry.amount_minor)} USD / month`;
              return (
                <article className="billing-plan" key={entry.code}>
                  <h3>{copy.name}</h3>
                  <strong>{price}</strong>
                  <p>{copy.summary}</p>
                  <button
                    className="button primary"
                    type="button"
                    disabled={!entry.enabled || isCurrent || action.busy !== null || activePaid}
                    onClick={() => void startCheckout('subscription', entry.code)}
                  >
                    {!entry.enabled
                      ? 'Unavailable'
                      : isCurrent
                        ? 'Current plan'
                        : activePaid
                          ? 'Manage current plan'
                          : `Buy ${copy.name}`}
                  </button>
                </article>
              );
            })}
          </div>
        )}
      </div>

      <div className="billing-card">
        <h2>HocaCredits</h2>
        <p className="billing-note">
          Credits cover eligible targeting fees and are separate from weekly target limits. Each
          purchase keeps the rates shown at purchase time. Item payment stays offline.
        </p>
        {options.length === 0 ? (
          <div className="billing-empty">
            <span className="status-chip">No credit packs configured</span>
            <p>
              An administrator has not published credit packs yet, so there is nothing to buy here.
              Check back later or contact support.
            </p>
          </div>
        ) : (
          <div className="billing-pack-grid">
            {options.map((option) => (
              <article className="billing-pack" key={option.id}>
                <span className="status-chip">{formatUsdMinor(option.amount_minor)} pack</span>
                <strong>{formatUsdMinor(option.amount_minor)}</strong>
                <ul>
                  <li>Initial fee: {formatUsdMinor(option.initial_fee_minor)}</li>
                  <li>Winning total: {formatUsdMinor(option.winning_total_minor)}</li>
                  <li>Only the winning difference is charged later</li>
                </ul>
                <button
                  className="button primary"
                  type="button"
                  disabled={action.busy !== null}
                  onClick={() => void startCheckout('credit_deposit', option.id)}
                >
                  {action.busy === `credit_deposit:${option.id}` ? 'Opening checkout…' : 'Buy credits'}
                </button>
              </article>
            ))}
          </div>
        )}
      </div>

      <div className="billing-card">
        <h2>Recent credit purchases</h2>
        {deposits.length === 0 ? (
          <div className="billing-empty">
            <span className="status-chip">No purchases yet</span>
            <p>A completed credit purchase appears here after the payment is verified.</p>
          </div>
        ) : (
          <ul className="billing-history">
            {deposits.map((checkout) => (
              <li key={checkout.id}>
                <div>
                  <strong>{formatUsdMinor(checkout.amount_minor)} credit pack</strong>
                  <span>{new Date(checkout.created_at ?? '').toLocaleString()}</span>
                </div>
                <span className={`status-chip ${checkout.state === 'complete' ? 'success' : ''}`}>
                  {checkout.state === 'complete'
                    ? 'Verified — credited'
                    : checkout.state === 'open' || checkout.state === 'creating'
                      ? 'Awaiting payment'
                      : checkout.state}
                </span>
              </li>
            ))}
          </ul>
        )}
        <p className="billing-note">
          A purchase is credited only after a verified Stripe TEST event. A return to this site
          alone never adds credits. <a href="/billing/return">Check a recent checkout</a>.
        </p>
      </div>
    </section>
  );
}

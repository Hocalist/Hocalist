'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { formatUsdMinor } from '../lib/website-rules';
import { confirmationDelay, confirmationCopy } from '../lib/checkout-confirmation';
import BillingLoading from './BillingLoading';
import {
  resolveCheckoutView,
  type CheckoutRow,
  type CheckoutView
} from '../lib/website-checkout';

type Subscription = {
  plan?: string;
  provider_status?: string | null;
  paid_until?: string | null;
  cancel_at_period_end?: boolean;
} | null;

type State =
  | { kind: 'checking' }
  | { kind: 'signed_out'; message: string }
  | { kind: 'error'; message: string }
  | { kind: 'ready'; preview: boolean; view: CheckoutView; subscription: Subscription };

const PLAN_NAMES: Record<string, string> = { pro: 'Pro Seller', elite: 'Elite Seller' };

// Return/status page after hosted checkout. The URL's `checkout` value is a
// lookup hint only: the server authorizes it against the signed-in account and
// returns the exact row. Pending, verified, expired, missing and error states
// are shown honestly, and a completed older purchase is never substituted for
// the checkout the visitor actually departed from.
export function CheckoutReturn({
  cancelled = false,
  previewKind = null,
  checkoutHint = null
}: {
  cancelled?: boolean;
  previewKind?: string | null;
  checkoutHint?: string | null;
}) {
  const [state, setState] = useState<State>({ kind: 'checking' });
  const [delayed, setDelayed] = useState(false);
  const [retrying, setRetrying] = useState(false);
  const mounted = useRef(true);
  const generation = useRef(0);
  const inFlight = useRef<number | null>(null);
  const pendingSince = useRef<number | null>(null);

  const load = useCallback(async () => {
    const current = generation.current;
    if (inFlight.current === current) return;
    inFlight.current = current;
    const isCurrent = () => mounted.current && current === generation.current;
    try {
      const query = new URLSearchParams();
      if (previewKind) query.set('preview', previewKind);
      if (checkoutHint) query.set('checkout', checkoutHint);
      const suffix = query.size > 0 ? `?${query.toString()}` : '';
      const response = await fetch(`/api/billing/status${suffix}`, { cache: 'no-store', signal: AbortSignal.timeout(10_000) });
      const body = await response.json().catch(() => null);
      if (!isCurrent()) return;
      if (response.status === 401) {
        setState({ kind: 'signed_out', message: body?.message ?? 'Sign in again to check this checkout.' });
        return;
      }
      if (!response.ok || body?.state !== 'ready') {
        if (pendingSince.current !== null && response.status >= 500) {
          setRetrying(true);
        } else {
          setState({ kind: 'error', message: body?.message ?? 'Checkout status is unavailable right now.' });
        }
        return;
      }
      const selected: CheckoutRow | null = body.selected ?? null;
      const deposits: CheckoutRow[] = Array.isArray(body.deposits) ? body.deposits : [];
      const view = resolveCheckoutView({ selected, deposits }, { cancelled, hintProvided: Boolean(checkoutHint) });
      pendingSince.current = view.mode === 'pending' ? pendingSince.current ?? Date.now() : null;
      setDelayed(pendingSince.current !== null && Date.now() - pendingSince.current >= 60_000);
      setRetrying(false);
      setState({
        kind: 'ready',
        preview: body.preview === true,
        view,
        subscription: body.subscription ?? null
      });
    } catch {
      if (!isCurrent()) return;
      if (pendingSince.current !== null) setRetrying(true);
      else setState({ kind: 'error', message: 'Checkout status is unavailable right now.' });
    } finally {
      if (inFlight.current === current) inFlight.current = null;
    }
  }, [previewKind, checkoutHint, cancelled]);

  useEffect(() => {
    mounted.current = true;
    generation.current += 1;
    pendingSince.current = null;
    setDelayed(false);
    void load();
    return () => { mounted.current = false; generation.current += 1; };
  }, [load]);

  // One bounded request at a time, while this page is mounted and pending.
  useEffect(() => {
    const delay = confirmationDelay(state.kind === 'ready' && state.view.mode === 'pending', document.hidden);
    if (delay === null) return;
    const timer = window.setInterval(() => void load(), delay);
    const resume = () => { if (!document.hidden) void load(); };
    document.addEventListener('visibilitychange', resume);
    return () => { window.clearInterval(timer); document.removeEventListener('visibilitychange', resume); };
  }, [state.kind, state.kind === 'ready' ? state.view.mode : null, load]);

  const returnPath = checkoutHint
    ? `/billing/return?checkout=${encodeURIComponent(checkoutHint)}`
    : '/billing/return';

  if (state.kind === 'checking') {
    return (
      <section className="billing-section">
        <div className="billing-card billing-loading" aria-busy="true">
          <BillingLoading label="Checking your payment…" />
        </div>
      </section>
    );
  }

  if (state.kind === 'signed_out') {
    return (
      <section className="billing-section">
        <div className="billing-card">
          <span className="status-chip">Signed out</span>
          <h1>Sign in to check this checkout</h1>
          <p>{state.message} Sign in with the account that started the purchase.</p>
          <div className="billing-actions">
            <a className="button primary" href={`/billing?returnTo=${encodeURIComponent(returnPath)}`}>
              Sign in
            </a>
            <a className="button secondary" href="/support">Get help</a>
          </div>
        </div>
      </section>
    );
  }

  if (state.kind === 'error') {
    return (
      <section className="billing-section">
        <div className="billing-card">
          <span className="status-chip gold">Status unavailable</span>
          <h1>We could not check this checkout</h1>
          <p>{state.message}</p>
          <div className="billing-actions">
            <button className="button primary" type="button" onClick={() => void load()}>Retry</button>
            <a className="button secondary" href="/billing">Back to billing</a>
          </div>
        </div>
      </section>
    );
  }

  const banner = state.preview ? (
    <p className="billing-preview-banner" role="note">
      Local preview mode: this checkout status is synthetic and no provider is contacted.
    </p>
  ) : null;
  const { view, subscription } = state;

  if (view.mode === 'verified-deposit' && view.checkout) {
    return (
      <section className="billing-section">
        {banner}
        <div className="billing-card">
          <span className="status-chip success">Payment verified</span>
          <h1>Your credit purchase is confirmed</h1>
          <p>
            Hocalist verified the payment event for this checkout and added{' '}
            {formatUsdMinor(view.checkout.amount_minor)} to your seller credits
            {view.checkout.credited_at
              ? ` on ${new Date(view.checkout.credited_at).toLocaleString()}`
              : ''}. Your balance is visible in the app.
          </p>
          <div className="billing-actions">
            <a className="button primary" href="/billing">Back to billing</a>
            <a className="button secondary" href="/support">Get help</a>
          </div>
        </div>
      </section>
    );
  }

  if (view.mode === 'verified-subscription' && view.checkout) {
    const planName = PLAN_NAMES[view.checkout.plan_code ?? ''] ?? 'Seller plan';
    return (
      <section className="billing-section">
        {banner}
        <div className="billing-card">
          <span className="status-chip success">Subscription verified</span>
          <h1>Your seller plan is active</h1>
          <p>
            Hocalist verified the payment event for this checkout and activated the {planName}
            {subscription?.paid_until
              ? `, ${subscription.provider_status === 'trialing' ? 'trial ends' : 'current period ends'} ${new Date(subscription.paid_until).toLocaleDateString()}`
              : ''}. You can manage the payment method from the billing page.
          </p>
          <div className="billing-actions">
            <a className="button primary" href="/billing">Back to billing</a>
            <a className="button secondary" href="/support">Get help</a>
          </div>
        </div>
      </section>
    );
  }

  if (view.mode === 'pending') {
    return (
      <section className="billing-section">
        {banner}
        <div className="billing-card" aria-busy="true">
          <span className="billing-confirmation-spinner" aria-hidden="true" />
          <span className="status-chip gold">Confirmation in progress</span>
          <h1>{confirmationCopy.title}</h1>
          <p role="status">{delayed ? confirmationCopy.delayed : confirmationCopy.body}</p>
          {retrying ? <p>Connection interrupted. We’ll keep checking automatically.</p> : null}
          <div className="billing-actions">
            <button className="button primary" type="button" onClick={() => void load()}>Check again</button>
            <a className="button secondary" href="/billing">Back to billing</a>
          </div>
        </div>
      </section>
    );
  }

  if (view.mode === 'expired') {
    return (
      <section className="billing-section">
        {banner}
        <div className="billing-card">
          <span className="status-chip">Checkout closed</span>
          <h1>This checkout did not complete</h1>
          <p>
            This checkout expired or was closed without a verified payment, so nothing was credited
            for it. You can start a new purchase from the billing page.
          </p>
          <div className="billing-actions">
            <a className="button primary" href="/billing">Back to billing</a>
            <a className="button secondary" href="/support">Get help</a>
          </div>
        </div>
      </section>
    );
  }

  if (view.mode === 'missing') {
    return (
      <section className="billing-section">
        {banner}
        <div className="billing-card">
          <span className="status-chip">Checkout not found</span>
          <h1>This checkout is not on this account</h1>
          <p>
            The checkout link does not match a purchase on the signed-in account. If you paid with
            a different account, sign in with that account or contact support with the approximate
            payment time.
          </p>
          <div className="billing-actions">
            <button className="button primary" type="button" onClick={() => void load()}>Check again</button>
            <a className="button secondary" href="/billing">Back to billing</a>
            <a className="button secondary" href="/support">Get help</a>
          </div>
        </div>
      </section>
    );
  }

  return (
    <section className="billing-section">
      {banner}
      <div className="billing-card">
        <span className="status-chip">{cancelled ? 'Checkout not confirmed' : 'No checkout to confirm'}</span>
        <h1>{cancelled ? 'This page did not confirm a payment' : 'No recent checkout is waiting'}</h1>
        <p>
          {cancelled
            ? 'Leaving checkout does not by itself mean a payment failed. If you completed a payment, its status appears here once Stripe reports it; if you did not, nothing was charged. Start again from the billing page whenever you are ready.'
            : 'A return to this page never adds credits by itself. Verified payments appear in your billing history; if you expected a purchase here, check the exact checkout link from your receipt or contact support.'}
        </p>
        <div className="billing-actions">
          <button className="button primary" type="button" onClick={() => void load()}>Check again</button>
          <a className="button secondary" href="/billing">Start a purchase</a>
        </div>
      </div>
    </section>
  );
}

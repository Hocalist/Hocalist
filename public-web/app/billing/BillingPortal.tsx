'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import PaygoPaymentSetup from './PaygoPaymentSetup';
import BillingLoading from './BillingLoading';
import {paygoReturn} from './paygo-return';
import SellerBillingOverview, {type BillingEntitlement,type StandardRate} from './SellerBillingOverview';
import CreditFundingDialog from './CreditFundingDialog';
import PlanChangeDialog from './PlanChangeDialog';
import {isCurrentPlan} from './plan-presentation';
import PlanTargetingFees,{type PlanFeeRates} from './PlanTargetingFees';
import SellerPlanIdentity from './SellerPlanIdentity';
import PlanSelectionAction from './PlanSelectionAction';
import { formatUsdMinor, parsePortalBody, safeReturnPath } from '../lib/website-rules';
import {
  intentMatches,
  readIntent,
  shouldClearIntent,
  writeIntent,
  type CheckoutIntent,
  type CheckoutRow
} from '../lib/website-checkout';

type PlanRow = { code: string; amount_minor: number; currency?: string; enabled: boolean; billing_interval?: 'month' | 'year' };
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
  credit_purchase_allowed: boolean;
  effective_plan?: string;
  trial_days?: number;
  standard_deposits_enabled?: boolean;
  entitlement?: BillingEntitlement;
  standard_rates?: StandardRate[];
  plan_fee_rates?: PlanFeeRates[];
  subscription_price?: {amount_minor:number;currency:string;billing_interval:'month'|'year'};
};

type ViewState =
  | { kind: 'loading' }
  | { kind: 'signed_out'; message?: string }
  | { kind: 'forbidden'; message: string; review?: boolean }
  | { kind: 'error'; message: string }
  | { kind: 'ready'; data: StatusPayload };

const PLAN_COPY: Record<string, { name: string; summary: string }> = {
  pro: { name: 'Pro Seller', summary: 'Grow your customer reach with more listings and seller tools.' },
  elite: { name: 'Elite Seller', summary: 'Expand your reach with advanced insights and the best targeting rates.' }
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
  const [passwordVisible, setPasswordVisible] = useState(false);
  const [billingInterval, setBillingInterval] = useState<'month'|'year'>('month');
  const [fundingOpen,setFundingOpen]=useState(false);
  const [returningToCard,setReturningToCard]=useState(false);
  useEffect(()=>{
    const result=paygoReturn(new URL(window.location.href).searchParams);
    if(result.setupId||result.cancelled){setReturningToCard(true);setFundingOpen(true);}
  },[]);
  const [planChange,setPlanChange]=useState<string|null>(null);
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
      effective_plan: typeof body.effective_plan === 'string' ? body.effective_plan : undefined,
      trial_days: body.trial_days === 14 ? 14 : 0,
      standard_deposits_enabled: body.standard_deposits_enabled === true,
      entitlement: body.entitlement && typeof body.entitlement==='object' ? body.entitlement as BillingEntitlement : undefined,
      standard_rates: Array.isArray(body.standard_rates) ? body.standard_rates as StandardRate[] : [],
      plan_fee_rates: Array.isArray(body.plan_fee_rates) ? body.plan_fee_rates as PlanFeeRates[] : [],
      subscription_price: body.subscription_price && typeof body.subscription_price==='object' ? body.subscription_price as StatusPayload['subscription_price'] : undefined,
      account: (body.account as StatusPayload['account']) ?? null,
      plans: Array.isArray(body.plans) ? (body.plans as PlanRow[]) : [],
      options: Array.isArray(body.options) ? (body.options as BillingOption[]) : [],
      subscription: (body.subscription as BillingSubscription) ?? null,
      credit_purchase_allowed: body.credit_purchase_allowed === true,
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
      const response = await fetch('/api/session/logout', { method: 'POST' });
      if (!response.ok) throw new Error('logout_unavailable');
      membershipRef.current = null;
      setAction({ busy: null, message: null, tone: 'info' });
      setView({ kind: 'signed_out' });
    } catch {
      setAction({ busy: null, message: 'Sign-out could not be completed. Please try again.', tone: 'error' });
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
    let existing = readIntent(browserStorage(), membershipId);
    if (kind === 'subscription') {
      if (!value.includes(':')) value += ':month';
      if (existing?.kind === 'subscription' && !existing.value.includes(':')) existing = {...existing,value:`${existing.value}:month`};
    }
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
            ? { kind, plan: value.split(':')[0], interval: value.split(':')[1], idempotencyKey: intent.key }
            : { kind, ...(value.startsWith('standard:')?{amountMinor:Number(value.slice(9))}:{optionId:value}), idempotencyKey: intent.key }
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
      if (body?.code === 'checkout_pending' && !intent.checkoutId) {
        // A refused attempt created nothing; allow the retained checkout to resume.
        writeIntent(browserStorage(), membershipId, null);
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
          <BillingLoading label="Loading your plan and credits…" />
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
            Sign in with the same Hocalist account you use in the app to manage your plan,
            credits and payment details.
          </p>
          <form className="billing-form" onSubmit={signIn} noValidate>
            <label className="request-field wide">
              <span>Account email</span>
              <input type="email" name="email" autoComplete="email" required />
            </label>
            <label className="request-field wide">
              <span>Password</span>
              <input type={passwordVisible ? 'text' : 'password'} name="password" autoComplete="current-password" required />
              <button type="button" className="billing-password-toggle"
                aria-label={passwordVisible ? 'Hide password' : 'Show password'}
                aria-pressed={passwordVisible}
                onClick={() => setPasswordVisible(value => !value)}>
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
                  <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z" />
                  <circle cx="12" cy="12" r="3" />
                  {passwordVisible ? <path d="m3 3 18 18" /> : null}
                </svg>
              </button>
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
  const plan = view.data.effective_plan ?? ((subscription?.provider_status === 'active' || subscription?.provider_status === 'trialing') && subscription?.paid_until && new Date(subscription.paid_until).getTime()>Date.now() ? subscription.plan : 'free') ?? 'free';
  const activePaid = !!subscription && !subscription.requires_review &&
    (subscription.provider_status === 'active' || subscription.provider_status === 'trialing') &&
    !!subscription.paid_until && new Date(subscription.paid_until).getTime()>Date.now();
  const selectedPending = view.data.selected;
  const openCheckout = selectedPending && ['creating', 'open'].includes(selectedPending.state)
    ? selectedPending : deposits.find((checkout) => checkout.state === 'creating' || checkout.state === 'open');

  return (
    <section className="billing-section seller-billing-design">
      {preview ? (
        <p className="billing-preview-banner" role="note">
          Local preview mode: every value on this page is synthetic and no provider is contacted.
        </p>
      ) : null}
      <div className="billing-overview-grid"><SellerBillingOverview plan={plan} entitlement={view.data.entitlement} options={options}
        standard={view.data.standard_rates?.find(row=>row.plan_code===plan)}
        priceLabel={activePaid&&view.data.subscription_price?.currency==='usd'?`${formatUsdMinor(view.data.subscription_price.amount_minor)} / ${view.data.subscription_price.billing_interval}`:undefined}
        accessLabel={activePaid&&subscription?.paid_until?`${subscription.provider_status==='trialing'?'Trial ends':subscription.cancel_at_period_end?'Access ends':'Renews after'} ${new Date(subscription.paid_until).toLocaleDateString()}`:view.data.entitlement?.effective_source==='earned'?'Earned Pro · this calendar month':'Your seller benefits'}
        onAddCredits={()=>setFundingOpen(true)}
        onSelectPlan={()=>document.getElementById('seller-plans')?.scrollIntoView({behavior:'smooth',block:'start'})}/></div>
        {openCheckout ? (
          <div className="billing-message info" role="status">
            A checkout is open right now. Complete it in the Stripe page, or choose the same option
            again to reopen the same session.
            {(openCheckout.kind === 'subscription' && openCheckout.plan_code) ||
             (openCheckout.kind === 'credit_deposit' && (openCheckout.option_id||openCheckout.standard_deposit)) ? (
              <button className="button secondary" type="button" disabled={action.busy !== null}
                onClick={() => void startCheckout(openCheckout.kind === 'subscription' ? 'subscription' : 'credit_deposit',
                  (openCheckout.kind === 'subscription' ? `${openCheckout.plan_code}:${openCheckout.billing_interval ?? 'month'}` : openCheckout.standard_deposit?`standard:${openCheckout.amount_minor}`:openCheckout.option_id)!)}>
                Resume checkout
              </button>
            ) : null}
          </div>
        ) : null}
        {action.message ? (
          <p className={`billing-message ${action.tone}`} role={action.tone === 'error' ? 'alert' : 'status'}>
            {action.message}
          </p>
        ) : null}
      <div className="billing-card plan-selection-card" id="seller-plans">
        <h2>Seller plans</h2>
        <p className="billing-note">
          Choose monthly or annual billing. Your plan provides seller tools and limits;
          wallet credits cover targeting fees separately.
        </p>
        {plans.length === 0 ? (
          <div className="billing-empty">
            <span className="status-chip">No seller plans configured</span>
            <p>
              An administrator has not published seller plans yet, so there is nothing to buy here.
              Check back later or contact support.
            </p>
          </div>
        ) : null}
          <div className="billing-period-switch" role="group" aria-label="Billing period">
            <button type="button" aria-pressed={billingInterval==='month'} onClick={()=>setBillingInterval('month')}>Monthly</button>
            <button type="button" aria-pressed={billingInterval==='year'} onClick={()=>setBillingInterval('year')}>Annual</button>
          </div>
          {view.data.trial_days === 14 && !activePaid ? <p className="billing-note">Eligible new subscribers receive a 14-day trial. Your selected plan renews at the displayed price unless cancelled.</p> : null}
          <div className="billing-plan-grid">
            <article className="billing-plan tier-free">
              <SellerPlanIdentity plan="free" entitlement={view.data.entitlement} priceLabel="$0" current={!activePaid&&plan==='free'}/>
              <PlanTargetingFees rates={view.data.plan_fee_rates?.find(row=>row.plan_code==='free')}/>
              <div className="plan-choice-footer">{!activePaid&&<p className="billing-note plan-option-note">{plan==='pro'&&view.data.entitlement?.effective_source==='earned'?'Your account is Free with earned Pro benefits for this month.':'No monthly subscription payment.'}</p>}
              <PlanSelectionAction plan="free" disabled={!activePaid||action.busy!==null} onClick={()=>setPlanChange('free')} label={activePaid?'Switch to Free':plan==='free'?'Current plan':'Free account'}/>
              </div>
            </article>
            {plans.filter(entry=>(entry.billing_interval ?? 'month')===billingInterval).map((entry) => {
              const copy = PLAN_COPY[entry.code] ?? { name: entry.code, summary: 'Seller plan.' };
              const isCurrent = isCurrentPlan(activePaid,subscription?.plan??'',view.data.subscription_price?.billing_interval,entry.code,billingInterval);
              const price = `${formatUsdMinor(entry.amount_minor)} USD / ${billingInterval}`;
              return (
                <article className={`billing-plan tier-${entry.code}`} key={entry.code}>
                  <SellerPlanIdentity plan={entry.code} entitlement={view.data.entitlement} priceLabel={price} current={isCurrent}/>
                  <PlanTargetingFees rates={view.data.plan_fee_rates?.find(row=>row.plan_code===entry.code)}/>
                  <PlanSelectionAction plan={entry.code}
                    disabled={!entry.enabled || isCurrent || action.busy !== null}
                    onClick={() => activePaid ? setPlanChange(`${entry.code}:${billingInterval}`) : void startCheckout('subscription', `${entry.code}:${billingInterval}`)}
                    label={!entry.enabled
                      ? 'Unavailable'
                      : isCurrent
                        ? 'Current plan'
                        : `Switch to ${copy.name} · ${billingInterval==='year'?'Annual':'Monthly'}`}/>
                </article>
              );
            })}
          </div>
      </div>

      <CreditFundingDialog open={fundingOpen} initialMethod={returningToCard?'card':'wallet'} onClose={()=>{setFundingOpen(false);setReturningToCard(false);}} options={options}
        onManage={()=>{setFundingOpen(false);void openPortal();}}
        standard={view.data.standard_rates?.find(row=>row.plan_code===plan)}
        busy={action.busy!==null} allowed={view.data.credit_purchase_allowed} preview={preview===true} standardEnabled={view.data.standard_deposits_enabled===true}
        onChoose={id=>{setFundingOpen(false);void startCheckout('credit_deposit',id);}}
        onCustom={amount=>{setFundingOpen(false);void startCheckout('credit_deposit',`standard:${amount}`);}}/>
      <PlanChangeDialog target={planChange} onClose={()=>setPlanChange(null)} onContinue={()=>{setPlanChange(null);void openPortal();}} busy={action.busy!==null} entitlement={view.data.entitlement} paidUntil={subscription?.paid_until}/>
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
          Your credits appear after payment is confirmed. <a href="/billing/return">Check a recent checkout</a>.
        </p>
      </div>
      <div className="billing-card billing-account-tools">
        <h2>Payment settings</h2><p>Securely manage your payment method, invoices and subscription.</p>
        <div className="billing-actions"><button className="button secondary" type="button" onClick={openPortal} disabled={action.busy!==null}>{action.busy==='portal'?'Opening…':'Manage payment'}</button><button className="button secondary" type="button" onClick={signOut} disabled={action.busy!==null}>{action.busy==='signout'?'Signing out…':'Sign out'}</button></div>
        <PaygoPaymentSetup key={view.data.account?.membership_id ?? 'unavailable'} preview={preview} onManage={()=>void openPortal()}/>
      </div>
    </section>
  );
}

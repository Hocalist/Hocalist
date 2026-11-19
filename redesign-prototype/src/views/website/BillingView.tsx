import React, { useState } from 'react';
import { WebsiteRoute } from '../../types';
import {
  CreditCard,
  Shield,
  CheckCircle2,
  Lock,
  ArrowRight,
  ExternalLink,
  Zap,
  Clock,
  AlertTriangle,
  RotateCcw,
  User,
  KeyRound,
  Info
} from 'lucide-react';

interface BillingViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const BillingView: React.FC<BillingViewProps> = ({ setRoute }) => {
  // Portal Interactive View States
  const [sessionState, setSessionState] = useState<'ready' | 'signed_out' | 'forbidden' | 'error' | 'loading'>('ready');
  const [showForgotModal, setShowForgotModal] = useState(false);
  const [email, setEmail] = useState('seller@example.com');
  const [password, setPassword] = useState('••••••••••••');
  const [actionBusy, setActionBusy] = useState<string | null>(null);
  const [portalMessage, setPortalMessage] = useState<string | null>(null);

  // Active Seller Profile
  const [sellerPlan, setSellerPlan] = useState<'pro' | 'elite' | 'free'>('pro');
  const [creditBalance, setCreditBalance] = useState<number>(38.55);

  // Deposit batches fixture data following DECISIONS.md & PHASE2_FULL_COVERAGE_REGISTER.md
  const [batches, setBatches] = useState([
    {
      id: 'BATCH-2026-0925-A',
      depositAmount: 40.0,
      remainingCredits: 28.55,
      initialRate: 1.45,
      winningTotal: 3.25,
      winningDiff: 1.80,
      date: '2026-09-25',
      status: 'Active (FIFO Primary)'
    },
    {
      id: 'BATCH-2026-0920-B',
      depositAmount: 20.0,
      remainingCredits: 10.0,
      initialRate: 1.55,
      winningTotal: 3.75,
      winningDiff: 2.20,
      date: '2026-09-20',
      status: 'Secondary Batch'
    }
  ]);

  function handleSignIn(e: React.FormEvent) {
    e.preventDefault();
    setActionBusy('signin');
    setTimeout(() => {
      setActionBusy(null);
      setSessionState('ready');
      setPortalMessage('Signed in successfully as authorized seller.');
    }, 700);
  }

  function handleSignOut() {
    setSessionState('signed_out');
    setPortalMessage(null);
  }

  function simulateCheckout(kind: 'subscription' | 'deposit', value: string) {
    setActionBusy(`${kind}:${value}`);
    setTimeout(() => {
      setActionBusy(null);
      // Navigate to checkout return preview
      setRoute('billing-return');
    }, 900);
  }

  function openCustomerPortal() {
    setActionBusy('portal');
    setTimeout(() => {
      setActionBusy(null);
      setPortalMessage('Stripe Customer Portal launched in new secure window.');
    }, 800);
  }

  return (
    <div className="billing-portal-view">
      <section className="billing-hero">
        <div className="container">
          <div className="billing-hero-header">
            <div>
              <span className="badge badge-navy mb-2">Seller Financial Operations</span>
              <h1 className="billing-title">Hocalist Seller Billing Portal</h1>
              <p className="billing-sub">
                Manage your seller subscriptions, view immutable HocaCredit deposit batches, and access hosted Stripe billing tools.
              </p>
            </div>

            {/* Quick State Simulation Switcher for Review */}
            <div className="portal-state-switcher">
              <span className="switcher-lbl">Review Mode:</span>
              <button
                className={`switch-btn ${sessionState === 'ready' ? 'active' : ''}`}
                onClick={() => setSessionState('ready')}
              >
                Authenticated Seller
              </button>
              <button
                className={`switch-btn ${sessionState === 'signed_out' ? 'active' : ''}`}
                onClick={() => setSessionState('signed_out')}
              >
                Signed Out
              </button>
              <button
                className={`switch-btn ${sessionState === 'forbidden' ? 'active' : ''}`}
                onClick={() => setSessionState('forbidden')}
              >
                Buyer Account
              </button>
              <button
                className={`switch-btn ${sessionState === 'error' ? 'active' : ''}`}
                onClick={() => setSessionState('error')}
              >
                Service Error
              </button>
            </div>
          </div>

          {/* Boundaries Notice */}
          <div className="boundary-notice mt-4">
            <Shield size={18} />
            <div>
              <strong>Strict Scope of Website Billing:</strong> Stripe charges on this domain cover seller monthly subscriptions, weekly customer targeting capacity, and HocaCredit deposits only. Hocalist does not process buyer-to-seller item payments, shipping, or physical merchandise escrow.
            </div>
          </div>
        </div>
      </section>

      <section className="section">
        <div className="container">
          {portalMessage && (
            <div className="alert-banner mb-4 animate-fade-in">
              <CheckCircle2 size={16} className="text-success" />
              <span>{portalMessage}</span>
              <button className="close-alert" onClick={() => setPortalMessage(null)}>×</button>
            </div>
          )}

          {/* =========================================================================
              STATE 1: SIGNED OUT / SELLER LOGIN & SESSION RECOVERY
             ========================================================================= */}
          {sessionState === 'signed_out' && (
            <div className="portal-signed-out-card card animate-fade-in">
              <div className="login-header">
                <div className="icon-circle"><Lock size={22} className="text-primary" /></div>
                <h3>Sign in to Hocalist Seller Portal</h3>
                <p>Enter your verified seller account credentials to manage your subscription and targeting credits.</p>
              </div>

              <form onSubmit={handleSignIn} className="login-form">
                <div className="form-group mb-3">
                  <label htmlFor="portal-email">Seller Email</label>
                  <input
                    id="portal-email"
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                  />
                </div>

                <div className="form-group mb-3">
                  <div className="label-with-action">
                    <label htmlFor="portal-pw">Password</label>
                    <button
                      type="button"
                      className="link-btn"
                      onClick={() => setShowForgotModal(true)}
                    >
                      Forgot password?
                    </button>
                  </div>
                  <input
                    id="portal-pw"
                    type="password"
                    required
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                  />
                </div>

                <button
                  type="submit"
                  className="btn btn-primary btn-lg full-width"
                  disabled={actionBusy === 'signin'}
                >
                  {actionBusy === 'signin' ? 'Authenticating with Hocalist...' : 'Sign In to Portal'}
                </button>
              </form>

              <div className="login-footer-note">
                <span>Buyer account? Buyer features are managed directly in the mobile app.</span>
              </div>
            </div>
          )}

          {/* =========================================================================
              STATE 2: FORBIDDEN / BUYER ACCOUNT ATTEMPTING SELLER BILLING
             ========================================================================= */}
          {sessionState === 'forbidden' && (
            <div className="portal-error-card card animate-fade-in text-center">
              <div className="error-icon-wrap"><AlertTriangle size={36} className="text-warning" /></div>
              <h3>Buyer Account Detected</h3>
              <p className="error-desc">
                The signed-in account is registered as a <strong>Buyer</strong>. Hocalist website billing is reserved exclusively for seller subscriptions and merchant targeting credits.
              </p>
              <div className="boundary-notice text-left mb-4">
                <Shield size={16} />
                <span>
                  <strong>Buyers never pay fees on Hocalist:</strong> Posting requests and chatting with sellers is 100% free. Item payments are settled offline in person upon item inspection.
                </span>
              </div>
              <div className="btn-row">
                <button className="btn btn-primary" onClick={() => setRoute('home')}>
                  Return to Homepage
                </button>
                <button className="btn btn-secondary" onClick={() => setSessionState('signed_out')}>
                  Sign In with Seller Credentials
                </button>
              </div>
            </div>
          )}

          {/* =========================================================================
              STATE 3: ERROR STATE WITH RETRY
             ========================================================================= */}
          {sessionState === 'error' && (
            <div className="portal-error-card card animate-fade-in text-center">
              <div className="error-icon-wrap"><RotateCcw size={36} className="text-danger" /></div>
              <h3>Billing Status Unavailable</h3>
              <p className="error-desc">
                We were unable to contact the Stripe subscription authority or retrieve your credit ledger. Your account remains safe and no duplicate charges occurred.
              </p>
              <button
                className="btn btn-primary"
                onClick={() => {
                  setSessionState('ready');
                  setPortalMessage('Billing status refreshed successfully.');
                }}
              >
                <RotateCcw size={16} /> Retry Billing Connection
              </button>
            </div>
          )}

          {/* =========================================================================
              STATE 4: AUTHENTICATED SELLER READY VIEW (FULL DASHBOARD)
             ========================================================================= */}
          {sessionState === 'ready' && (
            <div className="portal-dashboard animate-fade-in">
              {/* Account Overview Bar */}
              <div className="account-overview-card card">
                <div className="account-meta-left">
                  <div className="account-avatar">
                    <User size={22} />
                  </div>
                  <div>
                    <div className="account-title-row">
                      <h3>Northside Tech Hub</h3>
                      <span className="badge badge-success">Verified Seller</span>
                      <span className="badge badge-navy">Stripe TEST Connected</span>
                    </div>
                    <span className="account-sub">Account ID: #MEM-20260925-0842 • {email}</span>
                  </div>
                </div>

                <div className="account-meta-right">
                  <button className="btn btn-outline btn-sm" onClick={openCustomerPortal} disabled={actionBusy === 'portal'}>
                    <ExternalLink size={14} /> Stripe Customer Portal
                  </button>
                  <button className="btn btn-ghost btn-sm" onClick={handleSignOut}>
                    Sign Out
                  </button>
                </div>
              </div>

              {/* Two Column Grid: Subscription & Credits */}
              <div className="portal-grid mt-4">
                {/* Left Column: Monthly Subscription Status */}
                <div className="card subscription-panel">
                  <div className="panel-header">
                    <div className="panel-title-wrap">
                      <CreditCard size={20} className="text-primary" />
                      <h4>Monthly Subscription Plan</h4>
                    </div>
                    <span className="badge badge-navy">Active Plan</span>
                  </div>

                  <div className="active-plan-box">
                    <div className="plan-title-line">
                      <span className="plan-name-lg">
                        {sellerPlan === 'pro' ? 'Pro Seller' : sellerPlan === 'elite' ? 'Elite Merchant' : 'Free Starter'}
                      </span>
                      <span className="plan-cost">
                        {sellerPlan === 'pro' ? '$15.00' : sellerPlan === 'elite' ? '$30.00' : '$0.00'}
                        <small>/month</small>
                      </span>
                    </div>
                    <p className="plan-summary-text">
                      {sellerPlan === 'pro'
                        ? 'Includes 50 weekly customer targets, up to 15 Store listings, and verified seller badge eligibility.'
                        : 'Includes 100 weekly customer targets, up to 50 Store listings, and Hocatrends top priority.'}
                    </p>
                    <div className="renewal-chip">
                      <Clock size={13} /> Next automated renewal: <strong>October 25, 2026</strong>
                    </div>
                  </div>

                  {/* Plan Switcher / Upgrade Actions */}
                  <div className="plan-actions-box">
                    <h5>Change Subscription Tier:</h5>
                    <div className="plan-buttons-row">
                      <button
                        className={`plan-choice-btn ${sellerPlan === 'pro' ? 'current' : ''}`}
                        onClick={() => setSellerPlan('pro')}
                      >
                        <strong>Pro Seller</strong>
                        <span>$15 / mo (50 targets/wk)</span>
                      </button>
                      <button
                        className={`plan-choice-btn ${sellerPlan === 'elite' ? 'current' : ''}`}
                        onClick={() => {
                          setSellerPlan('elite');
                          simulateCheckout('subscription', 'elite');
                        }}
                      >
                        <strong>Upgrade to Elite</strong>
                        <span>$30 / mo (100 targets/wk)</span>
                      </button>
                    </div>
                  </div>

                  <div className="cancellation-note">
                    <small>Cancel anytime before renewal date. Access remains active through period end.</small>
                  </div>
                </div>

                {/* Right Column: HocaCredits & Deposit Batches */}
                <div className="card credits-panel">
                  <div className="panel-header">
                    <div className="panel-title-wrap">
                      <Zap size={20} className="text-primary" />
                      <h4>HocaCredit Balance & Deposits</h4>
                    </div>
                    <span className="badge badge-success">{creditBalance.toFixed(2)} HC Available</span>
                  </div>

                  <div className="credit-balance-hero">
                    <div className="balance-col">
                      <span className="balance-lbl">Available Credits</span>
                      <span className="balance-number">{creditBalance.toFixed(2)} <small>HC</small></span>
                    </div>
                    <div className="balance-col">
                      <span className="balance-lbl">Reserved on Active Deals</span>
                      <span className="balance-number muted">3.75 <small>HC</small></span>
                    </div>
                    <div className="balance-col">
                      <span className="balance-lbl">Weekly Targets Used</span>
                      <span className="balance-number">12 <small>/ 50</small></span>
                    </div>
                  </div>

                  {/* Deposit Top-Up Actions */}
                  <div className="deposit-action-area">
                    <h5>Deposit Additional HocaCredits (1 USD = 1 HC):</h5>
                    <div className="deposit-options-row">
                      <div className="deposit-btn-box">
                        <button
                          className="btn btn-secondary full-width"
                          onClick={() => simulateCheckout('deposit', '20')}
                          disabled={actionBusy !== null}
                        >
                          Deposit $20.00 (20 HC)
                        </button>
                        <span className="deposit-rate-sub">Rates: 1.55 HC initial / 3.75 HC win</span>
                      </div>
                      <div className="deposit-btn-box">
                        <button
                          className="btn btn-primary full-width"
                          onClick={() => simulateCheckout('deposit', '40')}
                          disabled={actionBusy !== null}
                        >
                          Deposit $40.00 (40 HC)
                        </button>
                        <span className="deposit-rate-sub text-success">★ Lowest Rates: 1.45 HC initial / 3.25 HC win</span>
                      </div>
                    </div>
                  </div>

                  <div className="fifo-rule-badge">
                    <Info size={14} />
                    <span>Charges draw automatically from your oldest eligible batch. Rates never mix on a single customer target.</span>
                  </div>
                </div>
              </div>

              {/* Active Deposit Batches Ledger Table */}
              <div className="card mt-4 batches-ledger-panel">
                <div className="ledger-header">
                  <h4>Active Deposit Batches (FIFO Rate Ledger)</h4>
                  <span className="text-muted text-sm">2 active batches on file</span>
                </div>
                <div className="table-responsive">
                  <table className="ledger-table">
                    <thead>
                      <tr>
                        <th>Batch Identifier</th>
                        <th>Initial Deposit</th>
                        <th>Remaining HC</th>
                        <th>Initial / Losing Fee</th>
                        <th>Winning Total</th>
                        <th>Deposit Date</th>
                        <th>Queue Status</th>
                      </tr>
                    </thead>
                    <tbody>
                      {batches.map((b) => (
                        <tr key={b.id}>
                          <td><code>{b.id}</code></td>
                          <td>${b.depositAmount.toFixed(2)}</td>
                          <td><strong>{b.remainingCredits.toFixed(2)} HC</strong></td>
                          <td>{b.initialRate.toFixed(2)} HC</td>
                          <td>{b.winningTotal.toFixed(2)} HC (diff +{b.winningDiff.toFixed(2)})</td>
                          <td>{b.date}</td>
                          <td><span className="badge badge-navy">{b.status}</span></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          )}
        </div>
      </section>

      {/* Forgot Password Modal */}
      {showForgotModal && (
        <div className="modal-overlay" onClick={() => setShowForgotModal(false)}>
          <div className="modal-card card" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <KeyRound size={20} className="text-primary" />
              <h4>Reset Seller Password</h4>
            </div>
            <p className="modal-desc">
              Enter your registered seller email address and we'll dispatch an authoritative password reset link from Supabase Auth.
            </p>
            <input
              type="email"
              placeholder="seller@domain.com"
              defaultValue={email}
              className="modal-input mb-3"
            />
            <div className="modal-buttons">
              <button className="btn btn-ghost" onClick={() => setShowForgotModal(false)}>Cancel</button>
              <button
                className="btn btn-primary"
                onClick={() => {
                  setShowForgotModal(false);
                  setPortalMessage('Recovery instructions dispatched to your email.');
                }}
              >
                Send Reset Link
              </button>
            </div>
          </div>
        </div>
      )}

      <style>{`
        .billing-hero {
          padding: 4rem 0 2rem;
          background: linear-gradient(180deg, #F0F4FF 0%, #FFFFFF 100%);
          border-bottom: 1px solid var(--border-subtle);
        }
        .billing-hero-header {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: 2rem;
          flex-wrap: wrap;
        }
        .billing-title {
          font-size: 2.6rem;
          color: var(--hoca-navy);
          margin-bottom: 0.5rem;
        }
        .billing-sub {
          font-size: 1.05rem;
          color: var(--text-secondary);
          max-width: 600px;
        }
        .portal-state-switcher {
          background: white;
          border: 1px solid var(--border-medium);
          padding: 0.5rem 0.75rem;
          border-radius: var(--radius-md);
          display: flex;
          align-items: center;
          gap: 0.4rem;
          flex-wrap: wrap;
        }
        .switcher-lbl {
          font-size: 0.75rem;
          font-weight: 700;
          color: var(--text-muted);
          text-transform: uppercase;
        }
        .switch-btn {
          background: var(--bg-muted);
          border: 1px solid var(--border-subtle);
          padding: 0.3rem 0.6rem;
          border-radius: var(--radius-sm);
          font-size: 0.78rem;
          font-weight: 600;
          color: var(--text-secondary);
          transition: all 0.15s;
        }
        .switch-btn.active {
          background: var(--hoca-navy);
          color: white;
          border-color: var(--hoca-navy);
        }

        /* Alert Banner */
        .alert-banner {
          background: var(--success-bg);
          border: 1px solid var(--success-border);
          color: var(--success-green);
          padding: 0.75rem 1.25rem;
          border-radius: var(--radius-md);
          display: flex;
          align-items: center;
          gap: 0.6rem;
          font-size: 0.88rem;
          font-weight: 600;
        }
        .close-alert {
          margin-left: auto;
          background: transparent;
          font-size: 1.2rem;
          color: var(--success-green);
        }

        /* Signed Out Card */
        .portal-signed-out-card {
          max-width: 480px;
          margin: 0 auto;
          padding: 3rem 2.5rem;
          border: 1.5px solid var(--border-medium);
        }
        .login-header {
          text-align: center;
          margin-bottom: 2rem;
        }
        .icon-circle {
          width: 52px;
          height: 52px;
          background: var(--hoca-blue-tint);
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          margin: 0 auto 1rem;
        }
        .login-header h3 {
          font-size: 1.4rem;
          color: var(--hoca-navy);
          margin-bottom: 0.5rem;
        }
        .login-header p {
          font-size: 0.88rem;
          color: var(--text-secondary);
        }
        .form-group label {
          display: block;
          font-size: 0.82rem;
          font-weight: 700;
          color: var(--text-secondary);
          margin-bottom: 0.35rem;
        }
        .label-with-action {
          display: flex;
          align-items: center;
          justify-content: space-between;
        }
        .link-btn {
          background: transparent;
          color: var(--hoca-navy);
          font-size: 0.78rem;
          font-weight: 600;
        }
        .form-group input {
          width: 100%;
          padding: 0.75rem 1rem;
          border: 1.5px solid var(--border-medium);
          border-radius: var(--radius-md);
        }
        .login-footer-note {
          margin-top: 1.5rem;
          padding-top: 1.25rem;
          border-top: 1px solid var(--border-subtle);
          font-size: 0.78rem;
          color: var(--text-muted);
          text-align: center;
        }

        /* Error / Forbidden */
        .portal-error-card {
          max-width: 540px;
          margin: 0 auto;
          padding: 3rem 2rem;
          border: 1.5px solid var(--border-medium);
        }
        .error-icon-wrap {
          margin-bottom: 1rem;
        }
        .portal-error-card h3 {
          font-size: 1.45rem;
          color: var(--hoca-navy);
          margin-bottom: 0.5rem;
        }
        .error-desc {
          font-size: 0.95rem;
          color: var(--text-secondary);
          margin-bottom: 1.5rem;
        }
        .btn-row {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 1rem;
          flex-wrap: wrap;
        }

        /* Dashboard Styles */
        .account-overview-card {
          padding: 1.5rem 2rem;
          display: flex;
          align-items: center;
          justify-content: space-between;
          flex-wrap: wrap;
          gap: 1.5rem;
          border: 1.5px solid var(--border-medium);
        }
        .account-meta-left {
          display: flex;
          align-items: center;
          gap: 1rem;
        }
        .account-avatar {
          width: 48px;
          height: 48px;
          border-radius: 50%;
          background: var(--hoca-navy);
          color: white;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .account-title-row {
          display: flex;
          align-items: center;
          gap: 0.65rem;
          flex-wrap: wrap;
          margin-bottom: 0.2rem;
        }
        .account-title-row h3 {
          font-size: 1.25rem;
          color: var(--hoca-navy);
        }
        .account-sub {
          font-size: 0.82rem;
          color: var(--text-muted);
        }
        .account-meta-right {
          display: flex;
          align-items: center;
          gap: 0.75rem;
        }

        .portal-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 2rem;
        }
        @media (max-width: 900px) {
          .portal-grid {
            grid-template-columns: 1fr;
          }
        }
        .subscription-panel, .credits-panel {
          padding: 2.25rem;
          border: 1.5px solid var(--border-medium);
        }
        .panel-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 1.5rem;
          padding-bottom: 0.75rem;
          border-bottom: 1px solid var(--border-subtle);
        }
        .panel-title-wrap {
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .panel-title-wrap h4 {
          font-size: 1.15rem;
          color: var(--hoca-navy);
        }
        .active-plan-box {
          background: var(--hoca-blue-tint-soft);
          border: 1px solid rgba(0, 3, 108, 0.1);
          border-radius: var(--radius-md);
          padding: 1.25rem;
          margin-bottom: 1.5rem;
        }
        .plan-title-line {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          margin-bottom: 0.5rem;
        }
        .plan-name-lg {
          font-size: 1.35rem;
          font-weight: 800;
          color: var(--hoca-navy);
        }
        .plan-cost {
          font-size: 1.4rem;
          font-weight: 800;
          color: var(--hoca-navy);
        }
        .plan-cost small {
          font-size: 0.85rem;
          color: var(--text-muted);
          font-weight: 500;
        }
        .plan-summary-text {
          font-size: 0.85rem;
          line-height: 1.45;
          color: var(--text-secondary);
          margin-bottom: 0.75rem;
        }
        .renewal-chip {
          display: flex;
          align-items: center;
          gap: 0.35rem;
          font-size: 0.78rem;
          color: var(--text-muted);
        }
        .plan-actions-box h5 {
          font-size: 0.88rem;
          color: var(--text-secondary);
          margin-bottom: 0.75rem;
        }
        .plan-buttons-row {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 0.75rem;
          margin-bottom: 1rem;
        }
        .plan-choice-btn {
          border: 1.5px solid var(--border-medium);
          border-radius: var(--radius-md);
          padding: 0.75rem;
          background: white;
          text-align: left;
          display: flex;
          flex-direction: column;
          gap: 0.2rem;
          transition: all 0.15s;
        }
        .plan-choice-btn strong {
          font-size: 0.88rem;
          color: var(--hoca-navy);
        }
        .plan-choice-btn span {
          font-size: 0.75rem;
          color: var(--text-muted);
        }
        .plan-choice-btn.current {
          border-color: var(--hoca-navy);
          background: var(--hoca-blue-tint);
        }
        .cancellation-note {
          color: var(--text-muted);
          font-size: 0.78rem;
        }

        /* Credits Panel */
        .credit-balance-hero {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 1rem;
          background: #F8FAFC;
          border: 1px solid var(--border-subtle);
          border-radius: var(--radius-md);
          padding: 1.25rem;
          margin-bottom: 1.5rem;
          text-align: center;
        }
        .balance-lbl {
          display: block;
          font-size: 0.75rem;
          color: var(--text-muted);
          font-weight: 600;
          margin-bottom: 0.25rem;
        }
        .balance-number {
          font-size: 1.5rem;
          font-weight: 800;
          color: var(--hoca-navy);
        }
        .balance-number.muted {
          color: var(--text-muted);
        }
        .balance-number small {
          font-size: 0.85rem;
        }
        .deposit-action-area h5 {
          font-size: 0.88rem;
          color: var(--text-secondary);
          margin-bottom: 0.75rem;
        }
        .deposit-options-row {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 0.75rem;
          margin-bottom: 1rem;
        }
        .deposit-rate-sub {
          display: block;
          font-size: 0.72rem;
          color: var(--text-muted);
          margin-top: 0.25rem;
          text-align: center;
        }
        .fifo-rule-badge {
          background: var(--hoca-blue-tint-soft);
          border-left: 3px solid var(--hoca-navy);
          padding: 0.6rem 0.85rem;
          border-radius: var(--radius-sm);
          font-size: 0.78rem;
          color: var(--text-secondary);
          display: flex;
          align-items: flex-start;
          gap: 0.45rem;
        }

        /* Batches Ledger Table */
        .batches-ledger-panel {
          padding: 2rem;
        }
        .ledger-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 1.25rem;
        }
        .ledger-header h4 {
          font-size: 1.15rem;
          color: var(--hoca-navy);
        }
        .ledger-table {
          width: 100%;
          border-collapse: collapse;
          font-size: 0.88rem;
          text-align: left;
        }
        .ledger-table th, .ledger-table td {
          padding: 0.85rem 1rem;
          border-bottom: 1px solid var(--border-subtle);
        }
        .ledger-table th {
          background: #F8FAFC;
          font-weight: 700;
          color: var(--text-secondary);
        }
        .ledger-table code {
          background: var(--bg-muted);
          padding: 0.2rem 0.4rem;
          border-radius: 4px;
          font-size: 0.78rem;
        }

        /* Modal */
        .modal-overlay {
          position: fixed;
          inset: 0;
          background: rgba(0, 3, 108, 0.4);
          backdrop-filter: blur(4px);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 10000;
          padding: 1rem;
        }
        .modal-card {
          width: 100%;
          max-width: 440px;
          padding: 2rem;
          background: white;
          border: 1.5px solid var(--border-medium);
        }
        .modal-header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          margin-bottom: 0.75rem;
        }
        .modal-header h4 {
          font-size: 1.2rem;
          color: var(--hoca-navy);
        }
        .modal-desc {
          font-size: 0.85rem;
          line-height: 1.5;
          color: var(--text-secondary);
          margin-bottom: 1.25rem;
        }
        .modal-input {
          width: 100%;
          padding: 0.75rem 1rem;
          border: 1.5px solid var(--border-medium);
          border-radius: var(--radius-md);
        }
        .modal-buttons {
          display: flex;
          align-items: center;
          justify-content: flex-end;
          gap: 0.75rem;
        }
      `}</style>
    </div>
  );
};

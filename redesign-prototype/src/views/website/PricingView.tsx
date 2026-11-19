import React, { useState } from 'react';
import { WebsiteRoute } from '../../types';
import {
  Check,
  Shield,
  HelpCircle,
  ArrowRight,
  Sparkles,
  Zap,
  Info,
  DollarSign,
  ChevronDown,
  ChevronUp,
  Layers,
  CheckCircle2,
  TrendingUp,
  Store
} from 'lucide-react';

interface PricingViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const PricingView: React.FC<PricingViewProps> = ({ setRoute }) => {
  const [activeTab, setActiveTab] = useState<'plans' | 'credits'>('plans');
  const [openFaq, setOpenFaq] = useState<number | null>(0);

  const faqs = [
    {
      q: 'Does Hocalist take a percentage cut of my in-person item sales?',
      a: 'Never. Hocalist takes exactly 0% commission on your physical merchandise or in-person service transactions. When you meet the buyer offline, you collect 100% of the agreed cash or direct payment. Platform fees only apply to seller subscription tiers and per-interaction HocaCredits.'
    },
    {
      q: 'What is the difference between subscription tiers and HocaCredits?',
      a: 'Your subscription tier (Free, Pro, or Elite) provides your base weekly target capacity—how many unique customer requests you can respond to each week—plus your active Store listing allowance. HocaCredits are prepaid micro-balances used to unlock high-intent chats and win transactions with frozen 1:1 USD valuation.'
    },
    {
      q: 'What happens if a buyer doesn’t select my offer or cancels?',
      a: 'You only pay the minimal initial interaction fee (1.45–1.55 HC depending on your deposit batch). If the buyer selects another seller or the request expires without a deal, you are NEVER charged the winning difference fee. You only pay the full winning rate when a deal is closed with the buyer\'s 5-digit PIN.'
    },
    {
      q: 'How does the 5-Digit PIN protect me as a seller?',
      a: 'When you meet the buyer and hand over the inspected merchandise, the buyer provides their confidential 5-digit PIN from the app. You enter this PIN into your Hocalist seller app to confirm the transaction is closed. It proves you delivered the goods and prevents fraudulent dispute claims.'
    },
    {
      q: 'Can I change or cancel my seller subscription at any time?',
      a: 'Yes. You can upgrade, downgrade, or cancel your subscription at any time through our Stripe-powered Seller Portal. Cancellations take effect at the end of your current billing period, and your remaining HocaCredits never expire.'
    }
  ];

  return (
    <div className="pricing-view">
      {/* Hero Header */}
      <section className="pricing-hero">
        <div className="container">
          <div className="pricing-hero-header text-center">
            <div className="hero-kicker-pill">
              <Sparkles size={13} />
              <span>Transparent Seller Economics</span>
            </div>
            <h1 className="pricing-title">
              Keep 100% of your sales.<br />
              <span className="text-gradient">Pay only for qualified local demand.</span>
            </h1>
            <p className="pricing-sub">
              No listing taxes. No escrow cuts. Zero percentage commission on your merchandise.
              Subscribe to a tier for weekly target capacity, and fund buyer interactions transparently with HocaCredits.
            </p>

            {/* Reassurance Trust Strip */}
            <div className="pricing-reassurance-row">
              <div className="reassurance-item">
                <Shield size={16} className="reassurance-icon" />
                <span>0% Commission on Physical Items</span>
              </div>
              <div className="reassurance-dot" />
              <div className="reassurance-item">
                <DollarSign size={16} className="reassurance-icon" />
                <span>Direct In-Person Offline Settlement</span>
              </div>
              <div className="reassurance-dot" />
              <div className="reassurance-item">
                <Zap size={16} className="reassurance-icon" />
                <span>Transparent Immutable Credit Rates</span>
              </div>
            </div>

            {/* Plan Switcher Pills */}
            <div className="pricing-tabs-wrapper">
              <div className="pricing-tabs" role="tablist">
                <button
                  role="tab"
                  aria-selected={activeTab === 'plans'}
                  className={`pricing-tab-btn ${activeTab === 'plans' ? 'active' : ''}`}
                  onClick={() => setActiveTab('plans')}
                >
                  <Store size={15} />
                  <span>Monthly Subscription Tiers</span>
                </button>
                <button
                  role="tab"
                  aria-selected={activeTab === 'credits'}
                  className={`pricing-tab-btn ${activeTab === 'credits' ? 'active' : ''}`}
                  onClick={() => setActiveTab('credits')}
                >
                  <Zap size={15} />
                  <span>HocaCredit Deposit Batches</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Main Content Area */}
      <section className="pricing-main-section">
        <div className="container">
          {activeTab === 'plans' ? (
            /* ========================================================
               SUBSCRIPTION TIERS
               ======================================================== */
            <div className="plans-container">
              <div className="plans-grid">
                {/* Free Starter */}
                <div className="tier-card standard-card">
                  <div className="tier-badge-slot">
                    <span className="tier-tag">Individual Seller</span>
                  </div>
                  <h3 className="tier-name">Free Starter</h3>
                  <p className="tier-pitch">Perfect for casual neighborhood sellers and occasional deals.</p>

                  <div className="tier-pricing-block">
                    <div className="price-val">
                      <span className="currency">$</span>
                      <span className="amount">0</span>
                    </div>
                    <span className="billing-cycle">Free forever • No credit card</span>
                  </div>

                  <div className="tier-capacity-bar">
                    <span className="capacity-label">Weekly Outreach Capacity</span>
                    <strong className="capacity-value">10 customer targets / week</strong>
                  </div>

                  <ul className="tier-features-list">
                    <li>
                      <CheckCircle2 size={16} className="feature-check" />
                      <span>Up to <strong>3 active Store listings</strong></span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check" />
                      <span><strong>10 weekly customer targets</strong></span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check" />
                      <span>In-app encrypted buyer chat</span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check" />
                      <span>5-digit PIN transaction validation</span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check" />
                      <span><strong>0% commission</strong> on offline cash/payment</span>
                    </li>
                  </ul>

                  <button
                    className="btn btn-outline full-width tier-cta"
                    onClick={() => setRoute('billing')}
                  >
                    Start Free
                  </button>
                </div>

                {/* Pro Business - HIGHLIGHTED */}
                <div className="tier-card featured-card">
                  <div className="popular-banner">
                    <Sparkles size={13} />
                    <span>Recommended for Local Stores</span>
                  </div>
                  <div className="tier-badge-slot">
                    <span className="tier-tag popular-tag">Growing Merchant</span>
                  </div>
                  <h3 className="tier-name">Pro Business</h3>
                  <p className="tier-pitch">For phone repair shops, electronics dealers, and retail stores.</p>

                  <div className="tier-pricing-block">
                    <div className="price-val">
                      <span className="currency">$</span>
                      <span className="amount">15</span>
                      <span className="period">/ month</span>
                    </div>
                    <span className="billing-cycle">Billed monthly via Stripe • Cancel anytime</span>
                  </div>

                  <div className="tier-capacity-bar featured-capacity">
                    <span className="capacity-label">Weekly Outreach Capacity</span>
                    <strong className="capacity-value">50 customer targets / week</strong>
                  </div>

                  <ul className="tier-features-list">
                    <li>
                      <CheckCircle2 size={16} className="feature-check active-check" />
                      <span>Up to <strong>15 active Store listings</strong></span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check active-check" />
                      <span><strong>50 weekly customer targets</strong> (5x capacity)</span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check active-check" />
                      <span><strong>Verified Seller badge</strong> eligibility</span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check active-check" />
                      <span>Instant push alerts for matching buyer needs</span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check active-check" />
                      <span>Custom store profile banner & branding</span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check active-check" />
                      <span>Priority placement in category searches</span>
                    </li>
                  </ul>

                  <button
                    className="btn btn-primary full-width tier-cta primary-cta"
                    onClick={() => setRoute('billing')}
                  >
                    Upgrade to Pro ($15/mo)
                    <ArrowRight size={16} />
                  </button>
                </div>

                {/* Elite Merchant */}
                <div className="tier-card elite-card">
                  <div className="tier-badge-slot">
                    <span className="tier-tag">High-Volume Retail</span>
                  </div>
                  <h3 className="tier-name">Elite Merchant</h3>
                  <p className="tier-pitch">For high-turnover retailers and regional marketplace suppliers.</p>

                  <div className="tier-pricing-block">
                    <div className="price-val">
                      <span className="currency">$</span>
                      <span className="amount">30</span>
                      <span className="period">/ month</span>
                    </div>
                    <span className="billing-cycle">Billed monthly via Stripe • Full access</span>
                  </div>

                  <div className="tier-capacity-bar">
                    <span className="capacity-label">Weekly Outreach Capacity</span>
                    <strong className="capacity-value">100 customer targets / week</strong>
                  </div>

                  <ul className="tier-features-list">
                    <li>
                      <CheckCircle2 size={16} className="feature-check" />
                      <span>Up to <strong>50 active Store listings</strong></span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check" />
                      <span><strong>100 weekly customer targets</strong></span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check" />
                      <span><strong>Top-tier Hocatrends</strong> featured badge</span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check" />
                      <span>Lowest HocaCredit batch interaction rates</span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check" />
                      <span>Advanced demand analytics & buyer signals</span>
                    </li>
                    <li>
                      <CheckCircle2 size={16} className="feature-check" />
                      <span>Priority VIP merchant support queue</span>
                    </li>
                  </ul>

                  <button
                    className="btn btn-outline full-width tier-cta"
                    onClick={() => setRoute('billing')}
                  >
                    Subscribe to Elite ($30/mo)
                  </button>
                </div>
              </div>
            </div>
          ) : (
            /* ========================================================
               HOCACREDITS DEPOSIT BATCHES
               ======================================================== */
            <div className="credits-tab-content">
              <div className="credits-overview-card">
                <div className="credits-overview-head">
                  <div className="credits-icon-box">
                    <Zap size={24} />
                  </div>
                  <div>
                    <h2 className="credits-headline">The Immutable HocaCredit System</h2>
                    <p className="credits-sub">
                      HocaCredits fund customer interactions with mathematical certainty.
                      1.00 USD always converts 1:1 to 1.00 HocaCredit (HC), permanently frozen at the deposit rate.
                    </p>
                  </div>
                </div>

                <div className="batches-card-grid">
                  {/* $20 Batch */}
                  <div className="batch-box">
                    <div className="batch-box-head">
                      <span className="batch-price-tag">$20.00 Deposit</span>
                      <span className="batch-type-pill">Standard Batch</span>
                    </div>
                    <div className="batch-amount">20.00 HC</div>
                    <div className="batch-divider" />
                    <div className="batch-rates">
                      <div className="rate-row">
                        <span className="rate-lbl">Initial / Losing Fee:</span>
                        <strong className="rate-val">1.55 HC</strong>
                      </div>
                      <div className="rate-row">
                        <span className="rate-lbl">Winning Deal Total:</span>
                        <strong className="rate-val">3.75 HC</strong>
                      </div>
                      <div className="rate-row highlight-rate">
                        <span className="rate-lbl">Winning Adjustment:</span>
                        <strong className="rate-val">+2.20 HC</strong>
                      </div>
                    </div>
                    <p className="batch-explainer">
                      If you win the deal, only the 2.20 HC difference is deducted upon PIN validation. If the buyer doesn't choose you, you never pay the winning fee.
                    </p>
                  </div>

                  {/* $40 Batch */}
                  <div className="batch-box best-batch">
                    <div className="best-batch-banner">13% Savings on Winning Deals</div>
                    <div className="batch-box-head">
                      <span className="batch-price-tag best-price">$40.00 Deposit</span>
                      <span className="batch-type-pill best-pill">High-Volume Batch</span>
                    </div>
                    <div className="batch-amount">40.00 HC</div>
                    <div className="batch-divider" />
                    <div className="batch-rates">
                      <div className="rate-row">
                        <span className="rate-lbl">Initial / Losing Fee:</span>
                        <strong className="rate-val">1.45 HC</strong>
                      </div>
                      <div className="rate-row">
                        <span className="rate-lbl">Winning Deal Total:</span>
                        <strong className="rate-val">3.25 HC</strong>
                      </div>
                      <div className="rate-row highlight-rate">
                        <span className="rate-lbl">Winning Adjustment:</span>
                        <strong className="rate-val">+1.80 HC</strong>
                      </div>
                    </div>
                    <p className="batch-explainer">
                      Permanent frozen discount. Every deal you close saves you $0.50 compared to standard deposits. Rates never change for this batch until spent.
                    </p>
                  </div>
                </div>

                {/* 4 Core Rules */}
                <div className="core-rules-section">
                  <h3 className="rules-heading">Four Immutable Platform Rules</h3>
                  <div className="rules-grid">
                    <div className="rule-card">
                      <div className="rule-num">01</div>
                      <div className="rule-title">Oldest Eligible Batch FIFO</div>
                      <div className="rule-desc">Outreach charges always draw automatically from your oldest single deposit batch that can cover the full reservation.</div>
                    </div>
                    <div className="rule-card">
                      <div className="rule-num">02</div>
                      <div className="rule-title">Never Mix Rates</div>
                      <div className="rule-desc">One transaction is never split across two batches with different fees. Rates stay completely predictable.</div>
                    </div>
                    <div className="rule-card">
                      <div className="rule-num">03</div>
                      <div className="rule-title">Credits Never Expire</div>
                      <div className="rule-desc">Unused balances never vanish. Small leftovers stay in your wallet indefinitely to fund future transactions.</div>
                    </div>
                    <div className="rule-card">
                      <div className="rule-num">04</div>
                      <div className="rule-title">Adjustment Difference Only</div>
                      <div className="rule-desc">You are never charged initial and winning fees simultaneously. The winning total is the maximum you ever pay.</div>
                    </div>
                  </div>
                </div>

                <div className="credits-cta-row text-center">
                  <button className="btn btn-primary btn-lg" onClick={() => setRoute('billing')}>
                    Deposit HocaCredits in Seller Portal
                    <ArrowRight size={18} />
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* ========================================================
             DETAILED FEATURE COMPARISON TABLE
             ======================================================== */}
          <div className="comparison-section">
            <div className="section-header text-center">
              <h2 className="comparison-heading">Complete Plan Feature Comparison</h2>
              <p className="comparison-sub">Evaluate every benefit and choose the exact tier that fits your growth.</p>
            </div>

            <div className="comparison-card">
              <div className="table-responsive">
                <table className="comparison-table">
                  <thead>
                    <tr>
                      <th className="feature-th">Feature Breakdown</th>
                      <th className="tier-th">Free Starter</th>
                      <th className="tier-th pro-th">
                        <span className="th-tag">Popular</span>
                        Pro Business ($15)
                      </th>
                      <th className="tier-th">Elite Merchant ($30)</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr>
                      <td className="feat-title">Monthly Subscription Price</td>
                      <td>$0.00 / month</td>
                      <td className="pro-td font-bold">$15.00 / month</td>
                      <td>$30.00 / month</td>
                    </tr>
                    <tr>
                      <td className="feat-title">Weekly Customer Target Limit</td>
                      <td>10 customers / week</td>
                      <td className="pro-td font-bold">50 customers / week</td>
                      <td>100 customers / week</td>
                    </tr>
                    <tr>
                      <td className="feat-title">Active Store Listings Allowance</td>
                      <td>Up to 3 listings</td>
                      <td className="pro-td font-bold">Up to 15 listings</td>
                      <td>Up to 50 listings</td>
                    </tr>
                    <tr>
                      <td className="feat-title">Item Payment Commission (In-Person)</td>
                      <td className="commission-zero">0% (Keep 100%)</td>
                      <td className="pro-td commission-zero font-bold">0% (Keep 100%)</td>
                      <td className="commission-zero font-bold">0% (Keep 100%)</td>
                    </tr>
                    <tr>
                      <td className="feat-title">Direct In-App Buyer Negotiation Chat</td>
                      <td><Check size={18} className="table-check" /></td>
                      <td className="pro-td"><Check size={18} className="table-check check-primary" /></td>
                      <td><Check size={18} className="table-check" /></td>
                    </tr>
                    <tr>
                      <td className="feat-title">5-Digit Settlement PIN Protection</td>
                      <td><Check size={18} className="table-check" /></td>
                      <td className="pro-td"><Check size={18} className="table-check check-primary" /></td>
                      <td><Check size={18} className="table-check" /></td>
                    </tr>
                    <tr>
                      <td className="feat-title">Verified Merchant Badge Eligibility</td>
                      <td className="dim-dash">—</td>
                      <td className="pro-td"><Check size={18} className="table-check check-primary" /></td>
                      <td><Check size={18} className="table-check" /></td>
                    </tr>
                    <tr>
                      <td className="feat-title">Real-Time Matching Push Notifications</td>
                      <td className="dim-dash">—</td>
                      <td className="pro-td"><Check size={18} className="table-check check-primary" /></td>
                      <td><Check size={18} className="table-check" /></td>
                    </tr>
                    <tr>
                      <td className="feat-title">Hocatrends Featured Search Priority</td>
                      <td className="dim-dash">—</td>
                      <td className="pro-td">Standard Priority</td>
                      <td className="font-bold">Top VIP Priority</td>
                    </tr>
                    <tr>
                      <td className="feat-title">Advanced Demand & Competitor Analytics</td>
                      <td className="dim-dash">—</td>
                      <td className="pro-td">Basic Trends</td>
                      <td className="font-bold">Full Market Intel</td>
                    </tr>
                    <tr>
                      <td className="feat-title">Dedicated Support Queue</td>
                      <td>Standard Email</td>
                      <td className="pro-td">Priority 24/7 Email</td>
                      <td className="font-bold">Dedicated Merchant Rep</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          {/* ========================================================
             CLEAR BOUNDARY CARD (Professional Governance, not scary)
             ======================================================== */}
          <div className="governance-card">
            <div className="gov-icon-side">
              <Shield size={28} className="gov-icon" />
            </div>
            <div className="gov-content">
              <h3 className="gov-title">Platform Billing Scope & In-Person Settlement</h3>
              <p className="gov-text">
                <strong>Stripe Billing:</strong> Payments processed on this website cover seller monthly subscription plans, Store listing capacity, and prepaid HocaCredit deposit batches only.
              </p>
              <p className="gov-text">
                <strong>Item Payments:</strong> Hocalist is a reverse discovery and negotiation marketplace. We never process buyer-to-seller merchandise payments, escrow, or shipping fees. Physical goods and services are inspected and paid for directly offline between buyer and seller at the confirmed meeting.
              </p>
            </div>
          </div>

          {/* ========================================================
             FAQ ACCORDION
             ======================================================== */}
          <div className="pricing-faq-section">
            <div className="section-header text-center">
              <span className="badge badge-navy mb-2">Merchant FAQ</span>
              <h2 className="faq-main-title">Frequently Asked Questions</h2>
              <p className="faq-main-sub">Everything you need to know about selling and scaling on Hocalist.</p>
            </div>

            <div className="faq-accordion-list">
              {faqs.map((faq, idx) => (
                <div key={idx} className={`faq-row-card ${openFaq === idx ? 'expanded' : ''}`}>
                  <button
                    className="faq-row-trigger"
                    onClick={() => setOpenFaq(openFaq === idx ? null : idx)}
                    aria-expanded={openFaq === idx}
                  >
                    <span className="faq-q-text">{faq.q}</span>
                    <span className="faq-arrow-circle">
                      {openFaq === idx ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
                    </span>
                  </button>
                  {openFaq === idx && (
                    <div className="faq-row-answer">
                      <p>{faq.a}</p>
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* ========================================================
             FINAL BOTTOM CALL TO ACTION
             ======================================================== */}
          <div className="pricing-final-cta text-center">
            <h2 className="cta-headline">Ready to capture qualified local demand?</h2>
            <p className="cta-subtitle">Join thousands of verified local merchants closing offline deals on Hocalist.</p>
            <div className="cta-btn-group">
              <button className="btn btn-primary btn-lg" onClick={() => setRoute('billing')}>
                Get Started with Stripe Portal
                <ArrowRight size={18} />
              </button>
              <button className="btn btn-secondary btn-lg" onClick={() => setRoute('how-it-works')}>
                Learn How It Works
              </button>
            </div>
          </div>
        </div>
      </section>

      <style>{`
        .pricing-view {
          background: #FAFAFC;
          min-height: 100vh;
        }

        /* Hero */
        .pricing-hero {
          padding: 5rem 0 3.5rem;
          background: radial-gradient(circle at 50% 0%, #EEF2FF 0%, #FAFAFC 70%);
          border-bottom: 1px solid var(--border-subtle);
        }
        .hero-kicker-pill {
          display: inline-flex;
          align-items: center;
          gap: 0.4rem;
          background: var(--hoca-blue-tint);
          color: var(--hoca-navy);
          border: 1px solid #C7D2FE;
          padding: 0.35rem 0.85rem;
          border-radius: 9999px;
          font-size: 0.82rem;
          font-weight: 700;
          letter-spacing: 0.02em;
          margin-bottom: 1.5rem;
        }
        .pricing-title {
          font-size: 3.2rem;
          font-weight: 850;
          line-height: 1.15;
          letter-spacing: -0.03em;
          color: var(--hoca-navy-deep);
          margin-bottom: 1.25rem;
        }
        @media (max-width: 768px) {
          .pricing-title {
            font-size: 2.3rem;
          }
        }
        .text-gradient {
          background: linear-gradient(135deg, var(--hoca-navy) 0%, var(--hoca-blue) 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
        }
        .pricing-sub {
          font-size: 1.15rem;
          line-height: 1.6;
          color: var(--text-secondary);
          max-width: 720px;
          margin: 0 auto 2rem;
        }

        /* Reassurance Strip */
        .pricing-reassurance-row {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 1.25rem;
          flex-wrap: wrap;
          margin-bottom: 2.5rem;
        }
        .reassurance-item {
          display: flex;
          align-items: center;
          gap: 0.45rem;
          font-size: 0.88rem;
          font-weight: 600;
          color: var(--text-primary);
        }
        .reassurance-icon {
          color: var(--hoca-blue);
        }
        .reassurance-dot {
          width: 4px;
          height: 4px;
          border-radius: 50%;
          background: #CBD5E1;
        }

        /* Tabs Switcher */
        .pricing-tabs-wrapper {
          display: flex;
          justify-content: center;
        }
        .pricing-tabs {
          display: inline-flex;
          background: #E2E8F0;
          padding: 4px;
          border-radius: 9999px;
          box-shadow: inset 0 1px 3px rgba(0, 0, 0, 0.08);
        }
        .pricing-tab-btn {
          display: inline-flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.65rem 1.4rem;
          border-radius: 9999px;
          font-size: 0.92rem;
          font-weight: 600;
          color: var(--text-secondary);
          background: transparent;
          border: none;
          cursor: pointer;
          transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
        }
        .pricing-tab-btn.active {
          background: white;
          color: var(--hoca-navy);
          font-weight: 700;
          box-shadow: 0 4px 12px rgba(0, 3, 108, 0.1);
        }

        /* Main Section */
        .pricing-main-section {
          padding: 4.5rem 0 6rem;
        }

        /* Tier Cards Grid */
        .plans-grid {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 2rem;
          align-items: stretch;
          margin-bottom: 5rem;
        }
        @media (max-width: 960px) {
          .plans-grid {
            grid-template-columns: 1fr;
            max-width: 480px;
            margin: 0 auto 4rem;
          }
        }
        .tier-card {
          background: white;
          border-radius: 20px;
          border: 1px solid var(--border-subtle);
          padding: 2.25rem 2rem;
          display: flex;
          flex-direction: column;
          box-shadow: 0 4px 16px rgba(0, 3, 108, 0.04);
          position: relative;
          transition: transform 0.25s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.25s ease;
        }
        .tier-card:hover {
          transform: translateY(-4px);
          box-shadow: 0 12px 32px rgba(0, 3, 108, 0.08);
        }

        /* Featured Card */
        .featured-card {
          border: 2px solid var(--hoca-blue);
          box-shadow: 0 12px 40px rgba(26, 40, 212, 0.12);
          transform: scale(1.02);
        }
        .featured-card:hover {
          transform: scale(1.02) translateY(-4px);
          box-shadow: 0 16px 48px rgba(26, 40, 212, 0.18);
        }
        .popular-banner {
          position: absolute;
          top: -14px;
          left: 50%;
          transform: translateX(-50%);
          background: linear-gradient(135deg, var(--hoca-navy) 0%, var(--hoca-blue) 100%);
          color: white;
          font-size: 0.76rem;
          font-weight: 700;
          letter-spacing: 0.03em;
          text-transform: uppercase;
          padding: 0.35rem 1rem;
          border-radius: 9999px;
          display: flex;
          align-items: center;
          gap: 0.35rem;
          box-shadow: 0 4px 12px rgba(26, 40, 212, 0.3);
          white-space: nowrap;
        }

        .tier-badge-slot {
          margin-bottom: 0.75rem;
        }
        .tier-tag {
          font-size: 0.75rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: var(--text-muted);
        }
        .popular-tag {
          color: var(--hoca-blue);
        }
        .tier-name {
          font-size: 1.5rem;
          font-weight: 800;
          color: var(--hoca-navy-deep);
          margin-bottom: 0.4rem;
        }
        .tier-pitch {
          font-size: 0.88rem;
          line-height: 1.45;
          color: var(--text-secondary);
          margin-bottom: 1.5rem;
          min-height: 42px;
        }
        .tier-pricing-block {
          margin-bottom: 1.5rem;
          padding-bottom: 1.25rem;
          border-bottom: 1px solid var(--border-subtle);
        }
        .price-val {
          display: flex;
          align-items: baseline;
          gap: 0.2rem;
          margin-bottom: 0.25rem;
        }
        .currency {
          font-size: 1.4rem;
          font-weight: 700;
          color: var(--hoca-navy);
        }
        .amount {
          font-size: 3rem;
          font-weight: 850;
          letter-spacing: -0.04em;
          color: var(--hoca-navy-deep);
        }
        .period {
          font-size: 1rem;
          font-weight: 600;
          color: var(--text-muted);
          margin-left: 0.2rem;
        }
        .billing-cycle {
          font-size: 0.8rem;
          color: var(--text-muted);
        }

        .tier-capacity-bar {
          background: #F8FAFC;
          border: 1px solid #E2E8F0;
          border-radius: 10px;
          padding: 0.75rem 1rem;
          margin-bottom: 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 0.2rem;
        }
        .featured-capacity {
          background: var(--hoca-blue-tint);
          border-color: #C7D2FE;
        }
        .capacity-label {
          font-size: 0.72rem;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          color: var(--text-muted);
          font-weight: 600;
        }
        .capacity-value {
          font-size: 0.95rem;
          font-weight: 750;
          color: var(--hoca-navy);
        }

        .tier-features-list {
          list-style: none;
          padding: 0;
          margin: 0 0 2rem;
          display: flex;
          flex-direction: column;
          gap: 0.85rem;
          flex: 1;
        }
        .tier-features-list li {
          display: flex;
          align-items: flex-start;
          gap: 0.65rem;
          font-size: 0.9rem;
          line-height: 1.45;
          color: var(--text-secondary);
        }
        .feature-check {
          color: #10B981;
          flex-shrink: 0;
          margin-top: 2px;
        }
        .active-check {
          color: var(--hoca-blue);
        }
        .tier-cta {
          margin-top: auto;
          padding: 0.85rem 1.25rem;
          font-weight: 700;
          font-size: 0.95rem;
        }
        .primary-cta {
          box-shadow: 0 4px 14px rgba(26, 40, 212, 0.35);
        }

        /* Credits Overview Card */
        .credits-overview-card {
          background: white;
          border-radius: 24px;
          border: 1px solid var(--border-subtle);
          padding: 3rem;
          box-shadow: 0 6px 24px rgba(0, 3, 108, 0.05);
          margin-bottom: 5rem;
        }
        @media (max-width: 768px) {
          .credits-overview-card {
            padding: 1.5rem;
          }
        }
        .credits-overview-head {
          display: flex;
          align-items: flex-start;
          gap: 1.25rem;
          margin-bottom: 2.5rem;
        }
        .credits-icon-box {
          width: 52px;
          height: 52px;
          border-radius: 14px;
          background: var(--hoca-blue-tint);
          color: var(--hoca-blue);
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }
        .credits-headline {
          font-size: 1.8rem;
          font-weight: 800;
          color: var(--hoca-navy-deep);
          margin-bottom: 0.4rem;
        }
        .credits-sub {
          font-size: 1rem;
          line-height: 1.5;
          color: var(--text-secondary);
        }

        /* Batches Grid */
        .batches-card-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 2rem;
          margin-bottom: 3.5rem;
        }
        @media (max-width: 768px) {
          .batches-card-grid {
            grid-template-columns: 1fr;
          }
        }
        .batch-box {
          background: #F8FAFC;
          border: 1px solid #E2E8F0;
          border-radius: 16px;
          padding: 2rem;
          position: relative;
          display: flex;
          flex-direction: column;
        }
        .best-batch {
          background: #FFFFFF;
          border: 2px solid var(--hoca-blue);
          box-shadow: 0 8px 24px rgba(26, 40, 212, 0.08);
        }
        .best-batch-banner {
          position: absolute;
          top: -12px;
          right: 20px;
          background: #10B981;
          color: white;
          font-size: 0.72rem;
          font-weight: 750;
          padding: 0.25rem 0.75rem;
          border-radius: 9999px;
          text-transform: uppercase;
          letter-spacing: 0.03em;
        }
        .batch-box-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 0.5rem;
        }
        .batch-price-tag {
          font-size: 1.25rem;
          font-weight: 800;
          color: var(--hoca-navy);
        }
        .best-price {
          color: var(--hoca-blue);
        }
        .batch-type-pill {
          font-size: 0.75rem;
          font-weight: 700;
          background: #E2E8F0;
          color: var(--text-secondary);
          padding: 0.2rem 0.55rem;
          border-radius: 6px;
        }
        .best-pill {
          background: var(--hoca-blue-tint);
          color: var(--hoca-blue);
        }
        .batch-amount {
          font-size: 2.2rem;
          font-weight: 850;
          color: var(--hoca-navy-deep);
          margin-bottom: 1rem;
        }
        .batch-divider {
          height: 1px;
          background: #E2E8F0;
          margin-bottom: 1.25rem;
        }
        .batch-rates {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
          margin-bottom: 1.25rem;
        }
        .rate-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          font-size: 0.9rem;
          color: var(--text-secondary);
        }
        .highlight-rate {
          color: var(--hoca-navy);
          font-weight: 700;
          border-top: 1px dashed #CBD5E1;
          padding-top: 0.5rem;
        }
        .batch-explainer {
          font-size: 0.82rem;
          line-height: 1.5;
          color: var(--text-muted);
          margin: 0;
        }

        /* 4 Core Rules */
        .core-rules-section {
          background: #F1F5F9;
          border-radius: 16px;
          padding: 2rem;
          margin-bottom: 2.5rem;
        }
        .rules-heading {
          font-size: 1.2rem;
          font-weight: 800;
          color: var(--hoca-navy-deep);
          margin-bottom: 1.5rem;
          text-align: center;
        }
        .rules-grid {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: 1.25rem;
        }
        @media (max-width: 900px) {
          .rules-grid {
            grid-template-columns: 1fr 1fr;
          }
        }
        @media (max-width: 550px) {
          .rules-grid {
            grid-template-columns: 1fr;
          }
        }
        .rule-card {
          background: white;
          border-radius: 12px;
          padding: 1.25rem;
          display: flex;
          flex-direction: column;
          gap: 0.35rem;
          box-shadow: 0 2px 6px rgba(0, 0, 0, 0.03);
        }
        .rule-num {
          font-size: 0.85rem;
          font-weight: 850;
          color: var(--hoca-blue);
        }
        .rule-title {
          font-size: 0.9rem;
          font-weight: 750;
          color: var(--hoca-navy);
        }
        .rule-desc {
          font-size: 0.8rem;
          line-height: 1.45;
          color: var(--text-secondary);
        }

        /* Comparison Section */
        .comparison-section {
          margin-bottom: 5rem;
        }
        .comparison-heading {
          font-size: 2.2rem;
          font-weight: 850;
          color: var(--hoca-navy-deep);
          margin-bottom: 0.5rem;
        }
        .comparison-sub {
          font-size: 1.05rem;
          color: var(--text-secondary);
          margin-bottom: 2.5rem;
        }
        .comparison-card {
          background: white;
          border-radius: 20px;
          border: 1px solid var(--border-subtle);
          box-shadow: 0 4px 16px rgba(0, 3, 108, 0.04);
          overflow: hidden;
        }
        .comparison-table {
          width: 100%;
          border-collapse: collapse;
          text-align: left;
        }
        .comparison-table th {
          padding: 1.25rem 1.5rem;
          font-size: 0.9rem;
          font-weight: 750;
          background: #F8FAFC;
          color: var(--hoca-navy);
          border-bottom: 2px solid #E2E8F0;
        }
        .comparison-table td {
          padding: 1.1rem 1.5rem;
          font-size: 0.92rem;
          color: var(--text-secondary);
          border-bottom: 1px solid #F1F5F9;
        }
        .feature-th {
          width: 40%;
        }
        .tier-th {
          width: 20%;
          text-align: center;
        }
        .comparison-table td:not(:first-child) {
          text-align: center;
        }
        .pro-th {
          background: var(--hoca-blue-tint);
          color: var(--hoca-navy);
          position: relative;
        }
        .th-tag {
          display: block;
          font-size: 0.65rem;
          text-transform: uppercase;
          background: var(--hoca-blue);
          color: white;
          padding: 0.15rem 0.45rem;
          border-radius: 4px;
          width: fit-content;
          margin: 0 auto 0.25rem;
        }
        .pro-td {
          background: rgba(238, 242, 255, 0.4);
          color: var(--hoca-navy);
        }
        .commission-zero {
          color: #10B981;
          font-weight: 750;
        }
        .table-check {
          color: #10B981;
          display: inline-block;
        }
        .check-primary {
          color: var(--hoca-blue);
        }
        .dim-dash {
          color: #CBD5E1;
        }

        /* Governance Card */
        .governance-card {
          background: white;
          border: 1px solid var(--border-subtle);
          border-left: 4px solid var(--hoca-navy);
          border-radius: 16px;
          padding: 2rem;
          display: flex;
          gap: 1.5rem;
          box-shadow: 0 4px 16px rgba(0, 3, 108, 0.03);
          margin-bottom: 5rem;
        }
        @media (max-width: 650px) {
          .governance-card {
            flex-direction: column;
            gap: 1rem;
          }
        }
        .gov-icon-side {
          display: flex;
          align-items: flex-start;
        }
        .gov-icon {
          color: var(--hoca-navy);
        }
        .gov-title {
          font-size: 1.15rem;
          font-weight: 800;
          color: var(--hoca-navy-deep);
          margin-bottom: 0.6rem;
        }
        .gov-text {
          font-size: 0.9rem;
          line-height: 1.55;
          color: var(--text-secondary);
          margin-bottom: 0.5rem;
        }
        .gov-text:last-child {
          margin-bottom: 0;
        }

        /* FAQ Section */
        .pricing-faq-section {
          max-width: 800px;
          margin: 0 auto 5rem;
        }
        .faq-main-title {
          font-size: 2.2rem;
          font-weight: 850;
          color: var(--hoca-navy-deep);
          margin-bottom: 0.4rem;
        }
        .faq-main-sub {
          font-size: 1rem;
          color: var(--text-secondary);
          margin-bottom: 2.5rem;
        }
        .faq-accordion-list {
          display: flex;
          flex-direction: column;
          gap: 0.85rem;
        }
        .faq-row-card {
          background: white;
          border: 1px solid var(--border-subtle);
          border-radius: 14px;
          overflow: hidden;
          transition: all 0.2s ease;
        }
        .faq-row-card.expanded {
          border-color: #C7D2FE;
          box-shadow: 0 4px 16px rgba(0, 3, 108, 0.05);
        }
        .faq-row-trigger {
          width: 100%;
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 1.25rem 1.5rem;
          background: transparent;
          border: none;
          text-align: left;
          cursor: pointer;
        }
        .faq-q-text {
          font-size: 1.05rem;
          font-weight: 750;
          color: var(--hoca-navy-deep);
          padding-right: 1rem;
        }
        .faq-arrow-circle {
          width: 28px;
          height: 28px;
          border-radius: 50%;
          background: #F1F5F9;
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--hoca-navy);
          flex-shrink: 0;
        }
        .faq-row-answer {
          padding: 0 1.5rem 1.25rem;
          font-size: 0.92rem;
          line-height: 1.6;
          color: var(--text-secondary);
          border-top: 1px solid #F1F5F9;
          padding-top: 0.85rem;
        }

        /* Final CTA */
        .pricing-final-cta {
          padding: 4rem 2rem;
          background: linear-gradient(135deg, var(--hoca-navy-deep) 0%, var(--hoca-navy) 100%);
          border-radius: 24px;
          color: white;
          box-shadow: 0 12px 36px rgba(0, 3, 108, 0.2);
        }
        .cta-headline {
          font-size: 2.4rem;
          font-weight: 850;
          letter-spacing: -0.025em;
          margin-bottom: 0.75rem;
        }
        @media (max-width: 600px) {
          .cta-headline {
            font-size: 1.8rem;
          }
        }
        .cta-subtitle {
          font-size: 1.1rem;
          color: #CBD5E1;
          margin-bottom: 2rem;
        }
        .cta-btn-group {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 1rem;
          flex-wrap: wrap;
        }
      `}</style>
    </div>
  );
};

import React from 'react';
import { WebsiteRoute } from '../../types';
import { Shield, RotateCcw, AlertCircle, Clock, CheckCircle2, ArrowRight } from 'lucide-react';

interface RefundCancellationViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const RefundCancellationView: React.FC<RefundCancellationViewProps> = ({ setRoute }) => {
  return (
    <div className="legal-view">
      <section className="legal-hero">
        <div className="container">
          <span className="badge badge-navy mb-2">Billing Policy</span>
          <h1 className="legal-title">Refund & Cancellation Policy</h1>
          <p className="legal-meta">
            <Clock size={14} /> Last Updated: October 2026 • Effective Date: October 2026
          </p>
        </div>
      </section>

      <section className="section">
        <div className="container">
          <div className="legal-body card">
            {/* Top Boundary Alert */}
            <div className="boundary-notice mb-4">
              <Shield size={20} />
              <div>
                <strong>Two Distinct Financial Domains:</strong> This policy governs Stripe-billed platform fees (seller monthly subscriptions and HocaCredit deposit batches). Physical items, merchandise, and local services are paid directly offline between users; Hocalist does not hold escrow or issue refunds for offline item transactions.
              </div>
            </div>

            <section className="legal-clause">
              <h2>1. Seller Monthly Subscriptions</h2>
              <p>
                <strong>Cancellation Anytime:</strong> Sellers may cancel their Pro ($15/mo) or Elite ($30/mo) subscription at any time via the Hocalist Seller Billing Portal or the Stripe hosted customer management portal.
              </p>
              <p>
                <strong>Billing Period Access:</strong> When a cancellation is requested, your plan will remain active with full weekly customer target capacity and Store listing allowances through the end of your current paid billing period. You will not be billed on the next renewal date.
              </p>
              <p>
                <strong>Prorated Refunds:</strong> Monthly subscription fees are generally non-refundable once the billing period has commenced. In the event of documented technical service outages or billing duplicate charges, contact <a href="mailto:support@hocalist.com">support@hocalist.com</a> within 14 days for manual review.
              </p>
            </section>

            <section className="legal-clause">
              <h2>2. Prepaid HocaCredit Deposit Batches</h2>
              <p>
                <strong>Permanent Rate Preservation:</strong> Each $20 or $40 deposit batch establishes an immutable credit balance with frozen fee rates. Unspent HocaCredits do not expire as long as your account remains in good standing.
              </p>
              <p>
                <strong>Unspent Balance Refunds:</strong> If you wish to close your seller account, you may request a refund for any completely unspent, non-reserved deposit batches within 30 days of the deposit date. Partially consumed batches are non-refundable.
              </p>
              <p>
                <strong>Transaction Fee Deductions:</strong> HocaCredit refunds are subject to deduction of original third-party payment processing fees incurred during initial deposit.
              </p>
            </section>

            <section className="legal-clause">
              <h2>3. Offline Merchandise & Item Payments</h2>
              <p>
                <strong>Direct Buyer-Seller Agreement:</strong> Because Hocalist does not process, intermediate, or receive funds for physical items or services, all merchandise return and refund policies are determined strictly between buyer and seller offline.
              </p>
              <p>
                <strong>Mandatory In-Person Inspection:</strong> Buyers are required to test, inspect, and confirm the condition of items before providing their 5-digit Purchase PIN and handing over offline payment.
              </p>
              <p>
                Hocalist customer support cannot reverse cash payments, initiate bank clawbacks, or adjudicate offline merchant return disputes once a transaction PIN has been validated.
              </p>
            </section>

            <section className="legal-clause">
              <h2>4. Chargebacks & Dispute Procedure</h2>
              <p>
                If you believe a Stripe platform charge was made in error or without authorization, please contact Hocalist Support first before filing a financial chargeback with your card issuer. Unwarranted chargebacks may result in immediate suspension of seller targeting privileges.
              </p>
            </section>

            <div className="mt-4 pt-4 border-top text-center">
              <button className="btn btn-primary" onClick={() => setRoute('billing')}>
                Manage Subscriptions in Billing Portal
                <ArrowRight size={16} />
              </button>
            </div>
          </div>
        </div>
      </section>

      <style>{`
        .legal-hero {
          padding: 4.5rem 0 2.5rem;
          background: linear-gradient(180deg, #F0F4FF 0%, #FFFFFF 100%);
          border-bottom: 1px solid var(--border-subtle);
        }
        .legal-title {
          font-size: 2.8rem;
          color: var(--hoca-navy);
          margin-bottom: 0.5rem;
        }
        .legal-meta {
          font-size: 0.88rem;
          color: var(--text-muted);
          display: flex;
          align-items: center;
          gap: 0.4rem;
        }
        .legal-body {
          padding: 3rem;
          border: 1.5px solid var(--border-medium);
          max-width: 900px;
          margin: 0 auto;
        }
        .legal-clause {
          margin-bottom: 2.5rem;
          padding-bottom: 2rem;
          border-bottom: 1px solid var(--border-subtle);
        }
        .legal-clause:last-child {
          border-bottom: none;
          margin-bottom: 0;
          padding-bottom: 0;
        }
        .legal-clause h2 {
          font-size: 1.35rem;
          color: var(--hoca-navy);
          margin-bottom: 1rem;
        }
        .legal-clause p {
          font-size: 0.95rem;
          line-height: 1.7;
          color: var(--text-secondary);
          margin-bottom: 1rem;
        }
        .border-top {
          border-top: 1px solid var(--border-subtle);
        }
      `}</style>
    </div>
  );
};

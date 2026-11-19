import React from 'react';
import { WebsiteRoute } from '../../types';
import { Shield, ArrowRight, RotateCcw, CheckCircle2 } from 'lucide-react';

interface BillingCancelViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const BillingCancelView: React.FC<BillingCancelViewProps> = ({ setRoute }) => {
  return (
    <div className="billing-cancel-view">
      <section className="cancel-hero">
        <div className="container text-center">
          <span className="badge badge-neutral mb-2">Checkout Left</span>
          <h1 className="cancel-title">Checkout Cancelled</h1>
          <p className="cancel-sub">
            You exited the Stripe checkout session without completing payment.
          </p>
        </div>
      </section>

      <section className="section">
        <div className="container">
          <div className="cancel-card card text-center">
            <div className="info-icon-wrap">
              <Shield size={44} className="text-primary" />
            </div>
            <h2>No Charges Were Made</h2>
            <p className="cancel-explanation">
              Your credit card was not billed and your previous Hocalist seller plan and HocaCredit balances remain completely unchanged. You can resume checkout at any time.
            </p>

            <div className="status-box text-left">
              <div className="status-row">
                <CheckCircle2 size={16} className="text-success" />
                <span>Existing subscription tier preserved</span>
              </div>
              <div className="status-row">
                <CheckCircle2 size={16} className="text-success" />
                <span>Prepaid HocaCredit balance intact</span>
              </div>
              <div className="status-row">
                <CheckCircle2 size={16} className="text-success" />
                <span>Weekly customer targeting capacity active</span>
              </div>
            </div>

            <div className="cancel-btn-row mt-4">
              <button className="btn btn-primary btn-lg" onClick={() => setRoute('billing')}>
                Return to Seller Billing Portal
                <ArrowRight size={18} />
              </button>
              <button className="btn btn-secondary btn-lg" onClick={() => setRoute('pricing')}>
                Review Plan Features
              </button>
            </div>
          </div>
        </div>
      </section>

      <style>{`
        .cancel-hero {
          padding: 4.5rem 0 2rem;
          background: linear-gradient(180deg, #F0F4FF 0%, #FFFFFF 100%);
          border-bottom: 1px solid var(--border-subtle);
        }
        .cancel-title {
          font-size: 2.6rem;
          color: var(--hoca-navy);
          margin-bottom: 0.5rem;
        }
        .cancel-sub {
          font-size: 1.05rem;
          color: var(--text-secondary);
          max-width: 600px;
          margin: 0 auto;
        }
        .cancel-card {
          max-width: 580px;
          margin: 0 auto;
          padding: 3rem 2.5rem;
          border: 1.5px solid var(--border-medium);
        }
        .info-icon-wrap {
          margin-bottom: 1.25rem;
        }
        .cancel-card h2 {
          font-size: 1.6rem;
          color: var(--hoca-navy);
          margin-bottom: 0.75rem;
        }
        .cancel-explanation {
          font-size: 0.95rem;
          line-height: 1.6;
          color: var(--text-secondary);
          margin-bottom: 1.75rem;
        }
        .status-box {
          background: #F8FAFC;
          border: 1px solid var(--border-subtle);
          border-radius: var(--radius-md);
          padding: 1.25rem;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }
        .status-row {
          display: flex;
          align-items: center;
          gap: 0.6rem;
          font-size: 0.88rem;
          color: var(--text-secondary);
        }
        .cancel-btn-row {
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

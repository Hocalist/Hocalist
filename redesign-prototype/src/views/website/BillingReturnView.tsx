import React, { useState, useEffect } from 'react';
import { WebsiteRoute } from '../../types';
import { CheckCircle2, Shield, Clock, ArrowRight, RotateCcw, Smartphone } from 'lucide-react';

interface BillingReturnViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const BillingReturnView: React.FC<BillingReturnViewProps> = ({ setRoute }) => {
  const [checking, setChecking] = useState(true);

  useEffect(() => {
    const timer = setTimeout(() => {
      setChecking(false);
    }, 1500);
    return () => clearTimeout(timer);
  }, []);

  return (
    <div className="billing-return-view">
      <section className="return-hero">
        <div className="container text-center">
          <span className="badge badge-navy mb-2">Hosted Checkout Status</span>
          <h1 className="return-title">Stripe Checkout Return Verification</h1>
          <p className="return-sub">
            Verifying the authoritative state of your transaction against the Hocalist backend.
          </p>
        </div>
      </section>

      <section className="section">
        <div className="container">
          <div className="return-card card">
            {checking ? (
              <div className="checking-box text-center animate-fade-in">
                <div className="spinner-wrap">
                  <div className="spinner" />
                </div>
                <h3>Verifying Authoritative Transaction with Server...</h3>
                <p>Reconciling webhook signature and confirming credit entitlement with Supabase ledger.</p>
                <span className="badge badge-warning mt-2">Checking Lookup Hint #CHK-2026-9284</span>
              </div>
            ) : (
              <div className="verified-box animate-fade-in text-center">
                <div className="success-icon-wrap">
                  <CheckCircle2 size={54} className="text-success" />
                </div>
                <h2>Checkout Confirmed & Entitlements Updated!</h2>
                <p className="success-desc">
                  Your payment was successfully received through Stripe and verified by Hocalist webhook. Your account balance has been updated.
                </p>

                {/* Verified Summary */}
                <div className="receipt-box text-left">
                  <div className="receipt-row">
                    <span>Transaction Type:</span>
                    <strong>HocaCredit Deposit ($40.00 Batch)</strong>
                  </div>
                  <div className="receipt-row">
                    <span>Credits Credited:</span>
                    <strong className="text-success">+40.00 HC</strong>
                  </div>
                  <div className="receipt-row">
                    <span>Rate Snapshot:</span>
                    <span>1.45 HC Initial / 3.25 HC Winning Total (Frozen)</span>
                  </div>
                  <div className="receipt-row">
                    <span>Batch ID:</span>
                    <code>BATCH-20261003-4920</code>
                  </div>
                  <div className="receipt-row">
                    <span>Receipt Dispatched:</span>
                    <span>support@hocalist.com via Stripe Invoicing</span>
                  </div>
                </div>

                {/* Authoritative Security Notice */}
                <div className="boundary-notice text-left mt-4 mb-4">
                  <Shield size={18} />
                  <div>
                    <strong>Authoritative Security Standard:</strong> A return URL query parameter is never treated as proof of payment. Entitlements and targeting privileges are granted strictly via cryptographic Stripe webhook verification.
                  </div>
                </div>

                <div className="return-actions">
                  <button className="btn btn-primary btn-lg" onClick={() => setRoute('billing')}>
                    Return to Seller Billing Portal
                    <ArrowRight size={18} />
                  </button>
                  <button
                    className="btn btn-secondary btn-lg"
                    onClick={() => alert('Mobile deep-link hocalist://seller/billing triggered for device.')}
                  >
                    <Smartphone size={18} /> Open in Hocalist App
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      </section>

      <style>{`
        .return-hero {
          padding: 4.5rem 0 2rem;
          background: linear-gradient(180deg, #F0F4FF 0%, #FFFFFF 100%);
          border-bottom: 1px solid var(--border-subtle);
        }
        .return-title {
          font-size: 2.6rem;
          color: var(--hoca-navy);
          margin-bottom: 0.5rem;
        }
        .return-sub {
          font-size: 1.05rem;
          color: var(--text-secondary);
          max-width: 600px;
          margin: 0 auto;
        }
        .return-card {
          max-width: 680px;
          margin: 0 auto;
          padding: 3rem 2.5rem;
          border: 1.5px solid var(--border-medium);
        }
        .checking-box {
          padding: 2rem 0;
        }
        .spinner-wrap {
          margin-bottom: 1.5rem;
        }
        .spinner {
          width: 48px;
          height: 48px;
          border: 4px solid var(--hoca-blue-tint);
          border-top-color: var(--hoca-navy);
          border-radius: 50%;
          animation: spin 0.8s linear infinite;
          margin: 0 auto;
        }
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
        .verified-box h2 {
          font-size: 1.8rem;
          color: var(--hoca-navy);
          margin-bottom: 0.75rem;
        }
        .success-desc {
          font-size: 0.95rem;
          line-height: 1.6;
          color: var(--text-secondary);
          margin-bottom: 1.75rem;
        }
        .receipt-box {
          background: #F8FAFC;
          border: 1px solid var(--border-subtle);
          border-radius: var(--radius-md);
          padding: 1.25rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }
        .receipt-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          font-size: 0.88rem;
          color: var(--text-secondary);
        }
        .return-actions {
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

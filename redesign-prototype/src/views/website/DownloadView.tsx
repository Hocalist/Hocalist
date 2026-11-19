import React, { useState } from 'react';
import { WebsiteRoute } from '../../types';
import {
  Smartphone,
  CheckCircle2,
  Mail,
  ArrowRight,
  Shield,
  QrCode,
  Sparkles,
  Download,
  Clock,
  MapPin,
  Lock,
  Zap,
  Star,
  Users
} from 'lucide-react';

interface DownloadViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const DownloadView: React.FC<DownloadViewProps> = ({ setRoute }) => {
  const [role, setRole] = useState<'buyer' | 'seller'>('buyer');
  const [email, setEmail] = useState('');
  const [city, setCity] = useState('');
  const [submitted, setSubmitted] = useState(false);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!email) return;
    setSubmitted(true);
  }

  return (
    <div className="download-view">
      {/* Hero Section */}
      <section className="download-hero">
        <div className="container">
          <div className="download-hero-grid">
            {/* Left Column: Value Prop & Intake */}
            <div className="hero-copy-col">
              <div className="hero-kicker-pill">
                <Sparkles size={13} />
                <span>Native iOS & Android App</span>
              </div>
              <h1 className="hero-title">
                Buy and sell locally.<br />
                <span className="text-gradient">At the speed of a push alert.</span>
              </h1>
              <p className="hero-sub">
                No more endless scrolling through outdated listings. Post what you want and your budget, receive competitive offers from verified local sellers, and coordinate safe public meetups.
              </p>

              {/* Conversion Intake Card */}
              <div className="intake-card">
                {!submitted ? (
                  <form onSubmit={handleSubmit} className="waitlist-form">
                    <div className="intake-header">
                      <h3 className="intake-title">Claim Your VIP Early Access Pass</h3>
                      <p className="intake-desc">Be the first to trade in your neighborhood with verified priority status.</p>
                    </div>

                    {/* Role Selector Tabs */}
                    <div className="role-pills">
                      <button
                        type="button"
                        className={`role-pill-btn ${role === 'buyer' ? 'active' : ''}`}
                        onClick={() => setRole('buyer')}
                      >
                        <Users size={15} />
                        <span>I Want to Buy</span>
                      </button>
                      <button
                        type="button"
                        className={`role-pill-btn ${role === 'seller' ? 'active' : ''}`}
                        onClick={() => setRole('seller')}
                      >
                        <Zap size={15} />
                        <span>I am a Local Seller</span>
                      </button>
                    </div>

                    <div className="form-fields-grid">
                      <div className="field-group">
                        <label htmlFor="user-email" className="field-label">Email Address</label>
                        <div className="input-box">
                          <Mail size={16} className="input-icon" />
                          <input
                            id="user-email"
                            type="email"
                            required
                            placeholder="you@domain.com"
                            value={email}
                            onChange={(e) => setEmail(e.target.value)}
                          />
                        </div>
                      </div>

                      <div className="field-group">
                        <label htmlFor="user-city" className="field-label">Metro Area / City</label>
                        <div className="input-box">
                          <MapPin size={16} className="input-icon" />
                          <input
                            id="user-city"
                            type="text"
                            placeholder="e.g. Austin, Dallas, Chicago"
                            value={city}
                            onChange={(e) => setCity(e.target.value)}
                          />
                        </div>
                      </div>
                    </div>

                    <div className="consent-text">
                      <Shield size={13} className="text-muted" />
                      <span>We respect your privacy. No spam, ever. Unsubscribe with one click.</span>
                    </div>

                    <button type="submit" className="btn btn-primary btn-lg full-width submit-cta">
                      <span>Reserve My Early Access Pass</span>
                      <ArrowRight size={18} />
                    </button>
                  </form>
                ) : (
                  <div className="success-state text-center">
                    <div className="success-check-circle">
                      <CheckCircle2 size={36} />
                    </div>
                    <h3 className="success-title">VIP Priority Pass Reserved!</h3>
                    <p className="success-desc">
                      We've assigned priority queue access to <strong>{email}</strong> for <strong>{city || 'your area'}</strong> as an early <strong>{role === 'buyer' ? 'Buyer' : 'Verified Merchant'}</strong>.
                    </p>
                    <div className="vip-badge-row">
                      <div className="vip-chip">
                        <span className="chip-label">Priority Pass</span>
                        <strong className="chip-code">#HOCA-8492</strong>
                      </div>
                      <div className="vip-chip">
                        <span className="chip-label">Platform Role</span>
                        <strong className="chip-code">{role === 'buyer' ? 'Early Buyer' : 'Merchant Pro'}</strong>
                      </div>
                    </div>
                    <p className="invite-note">We'll dispatch your direct download link and TestFlight / APK preview code directly to your inbox.</p>
                    <button
                      className="btn btn-outline btn-sm reset-btn"
                      onClick={() => setSubmitted(false)}
                    >
                      Register another email
                    </button>
                  </div>
                )}
              </div>

              {/* Trust Features Strip */}
              <div className="hero-trust-row">
                <div className="trust-item">
                  <CheckCircle2 size={16} className="trust-check" />
                  <span>iOS 16+ & Android 12+</span>
                </div>
                <div className="trust-item">
                  <CheckCircle2 size={16} className="trust-check" />
                  <span>5-Digit PIN Exchange</span>
                </div>
                <div className="trust-item">
                  <CheckCircle2 size={16} className="trust-check" />
                  <span>0% Item Commission</span>
                </div>
              </div>
            </div>

            {/* Right Column: App Mockup & App Highlights */}
            <div className="hero-mockup-col">
              <div className="phone-mockup-frame">
                <div className="phone-screen-glass">
                  <div className="phone-notch">
                    <div className="speaker" />
                    <div className="camera-dot" />
                  </div>
                  <div className="phone-screen-content">
                    <div className="app-preview-header">
                      <img
                        src="/brand/hocalist-logo-with-no-background.png"
                        alt="Hocalist Logo"
                        height={26}
                      />
                      <span className="live-status-pill">● LIVE IN LOCAL FEED</span>
                    </div>

                    {/* Offer Showcase Card */}
                    <div className="preview-buyer-card">
                      <div className="pbc-top">
                        <span className="pbc-tag">Incoming Verified Offer</span>
                        <span className="pbc-time">2m ago</span>
                      </div>
                      <div className="pbc-title">iPad Air 5th Gen (64GB, Space Gray)</div>
                      <div className="pbc-budget-row">
                        <span className="pbc-price">$380</span>
                        <span className="pbc-save">Within your $400 budget</span>
                      </div>
                      <div className="pbc-seller">
                        <div className="seller-avatar">AS</div>
                        <div>
                          <div className="seller-name">Austin Tech & Trade</div>
                          <div className="seller-meta">⭐ 4.9 (48 deals) • 1.8 mi away</div>
                        </div>
                      </div>
                      <div className="pbc-actions">
                        <button className="preview-btn primary">Open Secure Chat</button>
                        <button className="preview-btn secondary">Compare 2 Others</button>
                      </div>
                    </div>

                    {/* PIN Security Badge */}
                    <div className="preview-pin-card">
                      <div className="pin-icon-wrap">
                        <Lock size={15} />
                      </div>
                      <div className="pin-text-wrap">
                        <strong>5-Digit Settlement PIN Ready</strong>
                        <p>Disclose only after physical inspection in public.</p>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Feature Pillars Section */}
      <section className="download-features-section">
        <div className="container">
          <div className="section-head text-center">
            <span className="badge badge-navy mb-2">Designed for Real Life</span>
            <h2 className="sec-title">Engineered for Safe Local Transactions</h2>
            <p className="sec-sub">Everything you need to buy and sell confidently in your neighborhood.</p>
          </div>

          <div className="features-tri-grid">
            <div className="feat-box">
              <div className="feat-icon-circle">
                <Zap size={24} />
              </div>
              <h3 className="feat-heading">Zero Endless Browsing</h3>
              <p className="feat-body">
                Forget opening 30 tabs and messaging unresponsive sellers. Post what you want once. Qualified local merchants with active inventory send direct offers straight to your notifications.
              </p>
            </div>

            <div className="feat-box">
              <div className="feat-icon-circle">
                <Lock size={24} />
              </div>
              <h3 className="feat-heading">Encrypted In-App Chat</h3>
              <p className="feat-body">
                Negotiate terms, confirm condition, exchange high-resolution pictures, and schedule meetups without revealing your personal cell phone number, real email, or home address.
              </p>
            </div>

            <div className="feat-box">
              <div className="feat-icon-circle">
                <Shield size={24} />
              </div>
              <h3 className="feat-heading">Offline 5-Digit PIN Protocol</h3>
              <p className="feat-body">
                Inspect physical merchandise thoroughly in person before paying. Once you are 100% satisfied, share your 5-digit PIN to finalize the deal. Zero escrow cuts, zero hidden percentages.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Boundary Callout */}
      <section className="download-boundary-strip">
        <div className="container">
          <div className="boundary-card">
            <Shield size={26} className="bound-icon" />
            <div className="bound-body">
              <strong>Offline Item Payment Architecture:</strong> Hocalist connects buyers and sellers and coordinates negotiations. Merchandise payments are completed directly offline between parties. Platform billing covers seller plans and HocaCredits only.
            </div>
          </div>
        </div>
      </section>

      <style>{`
        .download-view {
          background: #FAFAFC;
          min-height: 100vh;
        }

        /* Hero */
        .download-hero {
          padding: 5rem 0 4.5rem;
          background: radial-gradient(circle at 30% 10%, #EEF2FF 0%, #FAFAFC 70%);
          border-bottom: 1px solid var(--border-subtle);
        }
        .download-hero-grid {
          display: grid;
          grid-template-columns: 1.15fr 0.85fr;
          gap: 4rem;
          align-items: center;
        }
        @media (max-width: 960px) {
          .download-hero-grid {
            grid-template-columns: 1fr;
            gap: 3rem;
          }
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
          margin-bottom: 1.25rem;
        }
        .hero-title {
          font-size: 3.2rem;
          font-weight: 850;
          line-height: 1.15;
          letter-spacing: -0.03em;
          color: var(--hoca-navy-deep);
          margin-bottom: 1.25rem;
        }
        @media (max-width: 600px) {
          .hero-title {
            font-size: 2.3rem;
          }
        }
        .text-gradient {
          background: linear-gradient(135deg, var(--hoca-navy) 0%, var(--hoca-blue) 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
        }
        .hero-sub {
          font-size: 1.12rem;
          line-height: 1.6;
          color: var(--text-secondary);
          margin-bottom: 2rem;
        }

        /* Intake Card */
        .intake-card {
          background: white;
          border-radius: 20px;
          border: 1px solid var(--border-subtle);
          padding: 2.25rem;
          box-shadow: 0 8px 30px rgba(0, 3, 108, 0.06);
          margin-bottom: 1.75rem;
        }
        .intake-header {
          margin-bottom: 1.5rem;
        }
        .intake-title {
          font-size: 1.35rem;
          font-weight: 800;
          color: var(--hoca-navy-deep);
          margin-bottom: 0.3rem;
        }
        .intake-desc {
          font-size: 0.88rem;
          color: var(--text-secondary);
        }

        /* Role Pills */
        .role-pills {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 0.75rem;
          margin-bottom: 1.5rem;
        }
        .role-pill-btn {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
          padding: 0.75rem 1rem;
          border-radius: 10px;
          background: #F8FAFC;
          border: 1.5px solid #E2E8F0;
          color: var(--text-secondary);
          font-size: 0.9rem;
          font-weight: 650;
          cursor: pointer;
          transition: all 0.2s ease;
        }
        .role-pill-btn.active {
          background: var(--hoca-blue-tint);
          border-color: var(--hoca-blue);
          color: var(--hoca-navy);
          font-weight: 750;
          box-shadow: 0 2px 8px rgba(26, 40, 212, 0.12);
        }

        /* Form Fields */
        .form-fields-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 1rem;
          margin-bottom: 1.25rem;
        }
        @media (max-width: 600px) {
          .form-fields-grid {
            grid-template-columns: 1fr;
          }
        }
        .field-group {
          display: flex;
          flex-direction: column;
          gap: 0.35rem;
        }
        .field-label {
          font-size: 0.8rem;
          font-weight: 700;
          color: var(--hoca-navy);
          text-transform: uppercase;
          letter-spacing: 0.03em;
        }
        .input-box {
          position: relative;
          display: flex;
          align-items: center;
        }
        .input-icon {
          position: absolute;
          left: 1rem;
          color: #94A3B8;
          pointer-events: none;
        }
        .input-box input {
          width: 100%;
          padding: 0.75rem 1rem 0.75rem 2.5rem;
          border-radius: 10px;
          border: 1px solid #CBD5E1;
          background: #FFFFFF;
          font-size: 0.95rem;
          font-family: inherit;
          color: var(--hoca-navy-deep);
          transition: border-color 0.2s, box-shadow 0.2s;
        }
        .input-box input:focus {
          outline: none;
          border-color: var(--hoca-blue);
          box-shadow: 0 0 0 3px rgba(26, 40, 212, 0.15);
        }

        .consent-text {
          display: flex;
          align-items: center;
          gap: 0.45rem;
          font-size: 0.78rem;
          color: var(--text-muted);
          margin-bottom: 1.5rem;
        }

        .submit-cta {
          padding: 0.9rem 1.5rem;
          font-size: 1rem;
          font-weight: 750;
          box-shadow: 0 4px 16px rgba(26, 40, 212, 0.35);
        }

        /* Success State */
        .success-state {
          padding: 1.5rem 0.5rem;
        }
        .success-check-circle {
          width: 64px;
          height: 64px;
          border-radius: 50%;
          background: #ECFDF5;
          color: #10B981;
          display: flex;
          align-items: center;
          justify-content: center;
          margin: 0 auto 1.25rem;
        }
        .success-title {
          font-size: 1.5rem;
          font-weight: 850;
          color: var(--hoca-navy-deep);
          margin-bottom: 0.5rem;
        }
        .success-desc {
          font-size: 0.95rem;
          line-height: 1.55;
          color: var(--text-secondary);
          margin-bottom: 1.5rem;
        }
        .vip-badge-row {
          display: flex;
          justify-content: center;
          gap: 1rem;
          margin-bottom: 1.5rem;
        }
        .vip-chip {
          background: #F8FAFC;
          border: 1px solid #E2E8F0;
          border-radius: 10px;
          padding: 0.6rem 1rem;
          display: flex;
          flex-direction: column;
          gap: 0.2rem;
        }
        .chip-label {
          font-size: 0.7rem;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          color: var(--text-muted);
          font-weight: 600;
        }
        .chip-code {
          font-size: 1rem;
          font-weight: 800;
          color: var(--hoca-navy);
        }
        .invite-note {
          font-size: 0.85rem;
          color: var(--text-muted);
          margin-bottom: 1.25rem;
        }
        .reset-btn {
          border-radius: 8px;
        }

        /* Trust Strip */
        .hero-trust-row {
          display: flex;
          align-items: center;
          gap: 1.5rem;
          flex-wrap: wrap;
        }
        .trust-item {
          display: flex;
          align-items: center;
          gap: 0.45rem;
          font-size: 0.86rem;
          font-weight: 650;
          color: var(--text-secondary);
        }
        .trust-check {
          color: #10B981;
        }

        /* Phone Mockup Frame */
        .hero-mockup-col {
          display: flex;
          justify-content: center;
        }
        .phone-mockup-frame {
          width: 320px;
          height: 620px;
          background: #00022E;
          border-radius: 46px;
          padding: 12px;
          box-shadow: 0 24px 60px rgba(0, 3, 108, 0.25), 0 0 0 1px rgba(255, 255, 255, 0.1);
          position: relative;
        }
        .phone-screen-glass {
          width: 100%;
          height: 100%;
          background: #FFFFFF;
          border-radius: 36px;
          overflow: hidden;
          display: flex;
          flex-direction: column;
          position: relative;
        }
        .phone-notch {
          height: 24px;
          background: #00022E;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
          border-bottom-left-radius: 14px;
          border-bottom-right-radius: 14px;
          width: 130px;
          margin: 0 auto;
        }
        .speaker {
          width: 40px;
          height: 4px;
          background: #334155;
          border-radius: 2px;
        }
        .camera-dot {
          width: 8px;
          height: 8px;
          background: #1E293B;
          border-radius: 50%;
        }
        .phone-screen-content {
          padding: 1.25rem 1rem;
          display: flex;
          flex-direction: column;
          gap: 1rem;
          flex: 1;
        }
        .app-preview-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding-bottom: 0.5rem;
          border-bottom: 1px solid #F1F5F9;
        }
        .live-status-pill {
          font-size: 0.65rem;
          font-weight: 800;
          color: #10B981;
          letter-spacing: 0.04em;
        }

        /* Mockup Cards */
        .preview-buyer-card {
          background: #FFFFFF;
          border: 1.5px solid #C7D2FE;
          border-radius: 16px;
          padding: 1rem;
          box-shadow: 0 4px 14px rgba(26, 40, 212, 0.08);
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .pbc-top {
          display: flex;
          align-items: center;
          justify-content: space-between;
        }
        .pbc-tag {
          font-size: 0.68rem;
          font-weight: 750;
          text-transform: uppercase;
          background: var(--hoca-blue-tint);
          color: var(--hoca-navy);
          padding: 0.15rem 0.45rem;
          border-radius: 4px;
        }
        .pbc-time {
          font-size: 0.7rem;
          color: var(--text-muted);
        }
        .pbc-title {
          font-size: 0.95rem;
          font-weight: 800;
          color: var(--hoca-navy-deep);
        }
        .pbc-budget-row {
          display: flex;
          align-items: baseline;
          gap: 0.5rem;
        }
        .pbc-price {
          font-size: 1.4rem;
          font-weight: 850;
          color: var(--hoca-blue);
        }
        .pbc-save {
          font-size: 0.72rem;
          color: #10B981;
          font-weight: 650;
        }
        .pbc-seller {
          display: flex;
          align-items: center;
          gap: 0.6rem;
          background: #F8FAFC;
          padding: 0.5rem;
          border-radius: 8px;
        }
        .seller-avatar {
          width: 30px;
          height: 30px;
          border-radius: 50%;
          background: var(--hoca-navy);
          color: white;
          font-size: 0.75rem;
          font-weight: 750;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .seller-name {
          font-size: 0.8rem;
          font-weight: 700;
          color: var(--hoca-navy);
        }
        .seller-meta {
          font-size: 0.68rem;
          color: var(--text-muted);
        }
        .pbc-actions {
          display: flex;
          gap: 0.4rem;
          margin-top: 0.25rem;
        }
        .preview-btn {
          flex: 1;
          padding: 0.45rem 0.25rem;
          border-radius: 6px;
          font-size: 0.75rem;
          font-weight: 700;
          border: none;
          cursor: default;
        }
        .preview-btn.primary {
          background: var(--hoca-blue);
          color: white;
        }
        .preview-btn.secondary {
          background: #F1F5F9;
          color: var(--text-secondary);
        }

        .preview-pin-card {
          background: #FEF3C7;
          border: 1px solid #FDE68A;
          border-radius: 12px;
          padding: 0.75rem;
          display: flex;
          align-items: center;
          gap: 0.65rem;
        }
        .pin-icon-wrap {
          color: #B45309;
        }
        .pin-text-wrap strong {
          display: block;
          font-size: 0.78rem;
          color: #92400E;
        }
        .pin-text-wrap p {
          font-size: 0.68rem;
          color: #78350F;
          margin: 0;
        }

        /* Feature Pillars */
        .download-features-section {
          padding: 5rem 0;
          background: white;
        }
        .sec-title {
          font-size: 2.3rem;
          font-weight: 850;
          color: var(--hoca-navy-deep);
          margin-bottom: 0.5rem;
        }
        .sec-sub {
          font-size: 1.05rem;
          color: var(--text-secondary);
          margin-bottom: 3.5rem;
        }
        .features-tri-grid {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 2rem;
        }
        @media (max-width: 900px) {
          .features-tri-grid {
            grid-template-columns: 1fr;
          }
        }
        .feat-box {
          background: #FAFAFC;
          border: 1px solid var(--border-subtle);
          border-radius: 18px;
          padding: 2.25rem 2rem;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
          transition: transform 0.2s ease;
        }
        .feat-box:hover {
          transform: translateY(-3px);
          box-shadow: 0 8px 24px rgba(0, 3, 108, 0.05);
        }
        .feat-icon-circle {
          width: 52px;
          height: 52px;
          border-radius: 14px;
          background: var(--hoca-blue-tint);
          color: var(--hoca-blue);
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 0.5rem;
        }
        .feat-heading {
          font-size: 1.25rem;
          font-weight: 800;
          color: var(--hoca-navy-deep);
        }
        .feat-body {
          font-size: 0.92rem;
          line-height: 1.6;
          color: var(--text-secondary);
          margin: 0;
        }

        /* Boundary Strip */
        .download-boundary-strip {
          padding: 0 0 5rem;
          background: white;
        }
        .boundary-card {
          background: #F8FAFC;
          border: 1px solid #E2E8F0;
          border-left: 4px solid var(--hoca-navy);
          border-radius: 12px;
          padding: 1.25rem 1.5rem;
          display: flex;
          align-items: center;
          gap: 1rem;
        }
        .bound-icon {
          color: var(--hoca-navy);
          flex-shrink: 0;
        }
        .bound-body {
          font-size: 0.88rem;
          line-height: 1.5;
          color: var(--text-secondary);
        }
      `}</style>
    </div>
  );
};

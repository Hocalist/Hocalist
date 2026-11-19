import React from 'react';
import { WebsiteRoute } from '../types';
import { Shield, Mail, CheckCircle2 } from 'lucide-react';

interface FooterProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const Footer: React.FC<FooterProps> = ({ setRoute }) => {
  function handleNavigate(route: WebsiteRoute) {
    setRoute(route);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  return (
    <footer className="site-footer">
      <div className="container footer-top">
        <div className="footer-grid">
          {/* Col 1: Brand & Mission */}
          <div className="footer-col footer-brand-col">
            <div className="footer-brand" onClick={() => handleNavigate('home')}>
              <img
                src="/brand/hocalist-logo-with-no-background.png"
                alt="Hocalist Logo"
                className="footer-logo"
                height={40}
              />
            </div>
            <p className="footer-desc">
              Hocalist is the mobile-first reverse marketplace connecting local buyers and sellers. Buyers post what they need, sellers send tailored offers, buyers choose who to deal with, and details are finalized in private chat.
            </p>
            <div className="footer-boundary-chip">
              <Shield size={16} />
              <span>Item payments are arranged offline. In-person inspection is required before funds exchange.</span>
            </div>
          </div>

          {/* Col 2: Marketplace Pages */}
          <div className="footer-col">
            <h4 className="footer-heading">Marketplace</h4>
            <ul className="footer-links">
              <li><button onClick={() => handleNavigate('home')}>Home</button></li>
              <li><button onClick={() => handleNavigate('how-it-works')}>How It Works</button></li>
              <li><button onClick={() => handleNavigate('pricing')}>Seller Plans & Credits</button></li>
              <li><button onClick={() => handleNavigate('download')}>Download & Waitlist</button></li>
              <li><button onClick={() => handleNavigate('safety')}>Safety Guide</button></li>
            </ul>
          </div>

          {/* Col 3: Seller Billing & Portal */}
          <div className="footer-col">
            <h4 className="footer-heading">Seller Billing</h4>
            <ul className="footer-links">
              <li><button onClick={() => handleNavigate('billing')}>Seller Billing Portal</button></li>
              <li><button onClick={() => handleNavigate('pricing')}>Subscription Tiers ($0 / $15 / $30)</button></li>
              <li><button onClick={() => handleNavigate('pricing')}>HocaCredit Batches ($20 / $40)</button></li>
              <li><button onClick={() => handleNavigate('billing-return')}>Checkout Return Check</button></li>
              <li><button onClick={() => handleNavigate('billing-cancel')}>Checkout Cancel Policy</button></li>
            </ul>
          </div>

          {/* Col 4: Trust, Legal & Support */}
          <div className="footer-col">
            <h4 className="footer-heading">Trust & Legal</h4>
            <ul className="footer-links">
              <li><button onClick={() => handleNavigate('terms')}>Terms of Service</button></li>
              <li><button onClick={() => handleNavigate('privacy')}>Privacy Policy</button></li>
              <li><button onClick={() => handleNavigate('refund-cancellation')}>Refund & Cancellation</button></li>
              <li><button onClick={() => handleNavigate('support')}>Help & Support Cases</button></li>
            </ul>
            <div className="footer-contact">
              <Mail size={14} />
              <span>support@hocalist.com</span>
            </div>
          </div>
        </div>
      </div>

      {/* Footer Bottom Bar */}
      <div className="footer-bottom">
        <div className="container footer-bottom-inner">
          <div className="footer-copy">
            © 2026 Hocalist. All rights reserved. Reverse marketplace platform for local requests & offers.
          </div>
          <div className="footer-tags">
            <span className="footer-tag"><CheckCircle2 size={13} /> Zero Buyer Fees</span>
            <span className="footer-tag"><CheckCircle2 size={13} /> Offline Item Payments</span>
            <span className="footer-tag"><CheckCircle2 size={13} /> Verified Seller PIN Protocol</span>
          </div>
        </div>
      </div>

      <style>{`
        .site-footer {
          background-color: var(--hoca-navy-deep);
          color: #E2E8F0;
          margin-top: auto;
          border-top: 1px solid rgba(255, 255, 255, 0.08);
        }
        .footer-top {
          padding: 4.5rem 1.5rem 3.5rem;
        }
        .footer-grid {
          display: grid;
          grid-template-columns: 2fr 1fr 1fr 1fr;
          gap: 3rem;
        }
        @media (max-width: 960px) {
          .footer-grid {
            grid-template-columns: 1fr 1fr;
            gap: 2rem;
          }
        }
        @media (max-width: 600px) {
          .footer-grid {
            grid-template-columns: 1fr;
            gap: 2rem;
          }
        }
        .footer-brand {
          cursor: pointer;
          display: inline-block;
          margin-bottom: 1.25rem;
          filter: brightness(0) invert(1);
        }
        .footer-logo {
          height: 38px;
          width: auto;
        }
        .footer-desc {
          font-size: 0.9rem;
          line-height: 1.6;
          color: #94A3B8;
          margin-bottom: 1.5rem;
          max-width: 380px;
        }
        .footer-boundary-chip {
          background: rgba(255, 255, 255, 0.06);
          border: 1px solid rgba(255, 255, 255, 0.12);
          border-radius: var(--radius-md);
          padding: 0.75rem 1rem;
          display: flex;
          align-items: flex-start;
          gap: 0.65rem;
          font-size: 0.8rem;
          line-height: 1.45;
          color: #CBD5E1;
          max-width: 400px;
        }
        .footer-boundary-chip svg {
          flex-shrink: 0;
          margin-top: 0.15rem;
          color: #60A5FA;
        }
        .footer-heading {
          font-size: 0.95rem;
          font-weight: 700;
          color: #FFFFFF;
          margin-bottom: 1.25rem;
          letter-spacing: 0.02em;
        }
        .footer-links {
          list-style: none;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }
        .footer-links button {
          background: transparent;
          color: #94A3B8;
          font-size: 0.88rem;
          text-align: left;
          padding: 0;
          transition: color 0.15s ease;
        }
        .footer-links button:hover {
          color: #FFFFFF;
          text-decoration: underline;
        }
        .footer-contact {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          margin-top: 1.25rem;
          font-size: 0.85rem;
          color: #94A3B8;
        }
        .footer-bottom {
          background: rgba(0, 0, 0, 0.25);
          border-top: 1px solid rgba(255, 255, 255, 0.06);
          padding: 1.5rem 0;
        }
        .footer-bottom-inner {
          display: flex;
          align-items: center;
          justify-content: space-between;
          flex-wrap: wrap;
          gap: 1rem;
        }
        .footer-copy {
          font-size: 0.82rem;
          color: #64748B;
        }
        .footer-tags {
          display: flex;
          align-items: center;
          gap: 1.25rem;
          flex-wrap: wrap;
        }
        .footer-tag {
          display: inline-flex;
          align-items: center;
          gap: 0.35rem;
          font-size: 0.78rem;
          color: #94A3B8;
        }
        .footer-tag svg {
          color: #22C55E;
        }
      `}</style>
    </footer>
  );
};

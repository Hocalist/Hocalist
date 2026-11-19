import React, { useState } from 'react';
import { WebsiteRoute } from '../../types';
import { Shield, BookOpen, Clock, ArrowRight } from 'lucide-react';

interface TermsViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const TermsView: React.FC<TermsViewProps> = ({ setRoute }) => {
  const [activeSection, setActiveSection] = useState('scope');

  const sections = [
    { id: 'scope', title: '1. Platform Scope & Reverse Marketplace' },
    { id: 'offline-payments', title: '2. Offline Item Payments & Zero Escrow' },
    { id: 'pin-protocol', title: '3. 5-Digit Purchase PIN Protocol' },
    { id: 'seller-fees', title: '4. Seller Subscriptions & HocaCredits' },
    { id: 'user-conduct', title: '5. In-Person Safety & Prohibited Items' },
    { id: 'disclaimers', title: '6. Limitation of Liability & Disclaimers' },
    { id: 'termination', title: '7. Account Restrictions & Termination' }
  ];

  function scrollToSection(id: string) {
    setActiveSection(id);
    const element = document.getElementById(id);
    if (element) {
      element.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  }

  return (
    <div className="legal-view">
      <section className="legal-hero">
        <div className="container">
          <span className="badge badge-navy mb-2">Legal Terms</span>
          <h1 className="legal-title">Terms of Service</h1>
          <p className="legal-meta">
            <Clock size={14} /> Last Updated: October 2026 • Effective Date: October 2026
          </p>
        </div>
      </section>

      <section className="section">
        <div className="container">
          <div className="legal-layout">
            {/* Table of Contents Sticky Sidebar */}
            <aside className="legal-toc-sidebar">
              <div className="toc-box card">
                <h4>Table of Contents</h4>
                <ul className="toc-links">
                  {sections.map((s) => (
                    <li key={s.id}>
                      <button
                        className={`toc-btn ${activeSection === s.id ? 'active' : ''}`}
                        onClick={() => scrollToSection(s.id)}
                      >
                        {s.title}
                      </button>
                    </li>
                  ))}
                </ul>
                <div className="toc-contact-note">
                  Questions? Contact <a href="mailto:support@hocalist.com">support@hocalist.com</a>
                </div>
              </div>
            </aside>

            {/* Legal Document Content */}
            <article className="legal-body card">
              <div className="boundary-notice mb-4">
                <Shield size={18} />
                <div>
                  <strong>Important Notice:</strong> Hocalist is a reverse marketplace communication and matchmaking technology platform. Hocalist does not buy, sell, warehouse, ship, or process payments for physical goods or local services. All item transactions are settled directly offline between buyer and seller.
                </div>
              </div>

              <section id="scope" className="legal-clause">
                <h2>1. Platform Scope & Reverse Marketplace</h2>
                <p>
                  Hocalist Inc. ("Hocalist", "we", "us", or "our") operates a mobile-first reverse marketplace connecting buyers who publish requests with local sellers who submit targeted offers. Access to and use of our mobile applications, public website, and seller administrative services is governed by these Terms of Service.
                </p>
                <p>
                  By creating an account, posting a buyer request, submitting a seller offer, or accessing Hocalist services, you agree to comply with and be bound by these Terms. If you do not agree, you must immediately cease using the platform.
                </p>
              </section>

              <section id="offline-payments" className="legal-clause">
                <h2>2. Offline Item Payments & Zero Escrow</h2>
                <p>
                  <strong>No Item Payment Processing:</strong> Hocalist does not process buyer-to-seller item payments, credit card swipes for merchandise, peer-to-peer item transfers, escrow holdings, or delivery shipping services.
                </p>
                <p>
                  <strong>Direct In-Person Settlement:</strong> All physical items, merchandise exchanges, and service compensations are negotiated directly and paid offline (e.g. cash, personal check, store terminal, or agreed in-person payment) at the time and location agreed between buyer and seller.
                </p>
                <p>
                  <strong>Inspection Obligation:</strong> Buyers bear the sole responsibility to inspect, test, and authenticate all goods prior to handing over funds. Once funds are exchanged offline, Hocalist cannot reverse or issue refunds for item transactions.
                </p>
              </section>

              <section id="pin-protocol" className="legal-clause">
                <h2>3. 5-Digit Purchase PIN Protocol</h2>
                <p>
                  Upon agreement to a meetup schedule between an authorized buyer and seller, Hocalist generates a unique, transient 5-digit Purchase PIN for the buyer.
                </p>
                <ul>
                  <li>The PIN confirms the buyer's authorization that the meetup occurred and the deal was finalized.</li>
                  <li>Buyers must not disclose the PIN prior to holding, inspecting, and confirming the item in person.</li>
                  <li>Entering the PIN in the Seller application completes the transaction record and triggers any applicable buyer rewards and seller fee adjustments.</li>
                </ul>
              </section>

              <section id="seller-fees" className="legal-clause">
                <h2>4. Seller Subscriptions & HocaCredits</h2>
                <p>
                  <strong>Platform Charges:</strong> Sellers access platform discovery, weekly customer targeting capacity, and Store profile tools via paid subscriptions (Free, Pro at $15/month, Elite at $30/month) processed through Stripe.
                </p>
                <p>
                  <strong>Prepaid HocaCredits:</strong> Customer interactions are funded via prepaid deposit batches ($20 or $40 deposits, where $1.00 USD = 1.00 HC). Each deposit creates an immutable batch with frozen rate snapshots. Charges draw from the oldest eligible batch under a FIFO rule. Winning fees deduct only the remaining difference from initial charges upon PIN confirmation.
                </p>
                <p>
                  <strong>Zero Item Commission:</strong> Hocalist takes zero commission on the physical merchandise or service transaction settled offline.
                </p>
              </section>

              <section id="user-conduct" className="legal-clause">
                <h2>5. In-Person Safety & Prohibited Items</h2>
                <p>
                  Users must exercise standard personal safety precautions during all in-person meetings. Meeting in designated Safe Exchange Zones (such as local police station parking lots) is strongly recommended.
                </p>
                <p>
                  The following items and requests are strictly prohibited on Hocalist:
                </p>
                <ul>
                  <li>Illegal drugs, narcotics, prescription medications, and drug paraphernalia;</li>
                  <li>Firearms, ammunition, explosive devices, and tactical weapons;</li>
                  <li>Stolen goods, counterfeit trademark merchandise, or items with defaced serial numbers;</li>
                  <li>Adult services, pornographic material, and escort requests;</li>
                  <li>Financial instruments, remote wire transfer schemes, and gift card cash-outs.</li>
                </ul>
              </section>

              <section id="disclaimers" className="legal-clause">
                <h2>6. Limitation of Liability & Disclaimers</h2>
                <p>
                  Hocalist provides the platform on an "AS IS" and "AS AVAILABLE" basis without warranties of any kind. Hocalist does not guarantee the condition, quality, safety, legality, or availability of any item advertised or offered by local sellers.
                </p>
                <p>
                  IN NO EVENT SHALL HOCALIST BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, OR CONSEQUENTIAL DAMAGES ARISING OUT OF IN-PERSON MEETINGS, OFFLINE ITEM PAYMENTS, PHYSICAL INJURY, OR PROPERTY DAMAGE.
                </p>
              </section>

              <section id="termination" className="legal-clause">
                <h2>7. Account Restrictions & Termination</h2>
                <p>
                  We reserve the right to suspend, restrict, or terminate user accounts for violations of these Terms, repeated no-shows, harassment, fraudulent claims, or conduct threatening community safety.
                </p>
              </section>
            </article>
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
        .legal-layout {
          display: grid;
          grid-template-columns: 280px 1fr;
          gap: 3rem;
          align-items: flex-start;
        }
        @media (max-width: 860px) {
          .legal-layout {
            grid-template-columns: 1fr;
          }
          .legal-toc-sidebar {
            display: none;
          }
        }
        .legal-toc-sidebar {
          position: sticky;
          top: 100px;
        }
        .toc-box {
          padding: 1.5rem;
          border: 1.5px solid var(--border-medium);
        }
        .toc-box h4 {
          font-size: 1rem;
          color: var(--hoca-navy);
          margin-bottom: 1rem;
          padding-bottom: 0.5rem;
          border-bottom: 1px solid var(--border-subtle);
        }
        .toc-links {
          list-style: none;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .toc-btn {
          background: transparent;
          font-size: 0.85rem;
          color: var(--text-secondary);
          text-align: left;
          padding: 0.35rem 0.5rem;
          border-radius: var(--radius-sm);
          width: 100%;
          line-height: 1.4;
          transition: all 0.15s;
        }
        .toc-btn:hover {
          color: var(--hoca-navy);
          background: var(--bg-muted);
        }
        .toc-btn.active {
          color: var(--hoca-navy);
          font-weight: 700;
          background: var(--hoca-blue-tint);
        }
        .toc-contact-note {
          margin-top: 1.25rem;
          padding-top: 1rem;
          border-top: 1px solid var(--border-subtle);
          font-size: 0.78rem;
          color: var(--text-muted);
        }
        .toc-contact-note a {
          color: var(--hoca-navy);
          font-weight: 600;
        }
        .legal-body {
          padding: 3rem;
          border: 1.5px solid var(--border-medium);
        }
        @media (max-width: 600px) {
          .legal-body {
            padding: 1.5rem;
          }
        }
        .legal-clause {
          margin-bottom: 2.75rem;
          padding-bottom: 2rem;
          border-bottom: 1px solid var(--border-subtle);
        }
        .legal-clause:last-child {
          border-bottom: none;
          margin-bottom: 0;
          padding-bottom: 0;
        }
        .legal-clause h2 {
          font-size: 1.4rem;
          color: var(--hoca-navy);
          margin-bottom: 1rem;
        }
        .legal-clause p {
          font-size: 0.95rem;
          line-height: 1.7;
          color: var(--text-secondary);
          margin-bottom: 1rem;
        }
        .legal-clause ul {
          padding-left: 1.5rem;
          margin-bottom: 1rem;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .legal-clause li {
          font-size: 0.92rem;
          line-height: 1.55;
          color: var(--text-secondary);
        }
      `}</style>
    </div>
  );
};

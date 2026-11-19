import React, { useState } from 'react';
import { WebsiteRoute } from '../../types';
import { Shield, Lock, Eye, Clock } from 'lucide-react';

interface PrivacyViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const PrivacyView: React.FC<PrivacyViewProps> = ({ setRoute }) => {
  const [activeSection, setActiveSection] = useState('info-collect');

  const sections = [
    { id: 'info-collect', title: '1. Information We Collect' },
    { id: 'location-privacy', title: '2. Location Privacy & Geocoding' },
    { id: 'chat-privacy', title: '3. Encrypted In-App Chat Retention' },
    { id: 'billing-data', title: '4. Stripe Billing & Financial Metadata' },
    { id: 'data-sharing', title: '5. Information Sharing Boundaries' },
    { id: 'user-rights', title: '6. Your Rights & Data Deletion' }
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
          <span className="badge badge-navy mb-2">Data Protection</span>
          <h1 className="legal-title">Privacy Policy</h1>
          <p className="legal-meta">
            <Clock size={14} /> Last Updated: October 2026 • Effective Date: October 2026
          </p>
        </div>
      </section>

      <section className="section">
        <div className="container">
          <div className="legal-layout">
            {/* Table of Contents */}
            <aside className="legal-toc-sidebar">
              <div className="toc-box card">
                <h4>Privacy Sections</h4>
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
                  Privacy inquiries: <a href="mailto:privacy@hocalist.com">privacy@hocalist.com</a>
                </div>
              </div>
            </aside>

            {/* Privacy Policy Document Body */}
            <article className="legal-body card">
              <div className="boundary-notice mb-4">
                <Lock size={18} />
                <div>
                  <strong>Location Privacy Commitment:</strong> Hocalist never shares your precise GPS coordinates or private home address with prospective sellers. Sellers only see your broad neighborhood, city, and approximate search radius.
                </div>
              </div>

              <section id="info-collect" className="legal-clause">
                <h2>1. Information We Collect</h2>
                <p>
                  We collect information necessary to operate the Hocalist reverse marketplace safely and efficiently:
                </p>
                <ul>
                  <li><strong>Account Registration:</strong> Email address, phone number (for SMS verification), chosen display name, and role preference (Buyer or Seller).</li>
                  <li><strong>Buyer Requests:</strong> Item descriptions, target price ranges, condition choices, and coarse geographic zone.</li>
                  <li><strong>Seller Profile & Store Listings:</strong> Business name, store address (for physical storefronts), offered merchandise descriptions, and uploaded product photos.</li>
                  <li><strong>Transaction Verification:</strong> System-generated 5-digit Purchase PIN records and meetup completion timestamps.</li>
                </ul>
              </section>

              <section id="location-privacy" className="legal-clause">
                <h2>2. Location Privacy & Geocoding</h2>
                <p>
                  <strong>Private Coordinates vs. Public Display:</strong> When creating a request, you select a location or neighborhood. We store confirmed geographical coordinates securely in dedicated server records to calculate approximate travel distance for seller matching.
                </p>
                <p>
                  Sellers are displayed only rounded distances (e.g., "within 2.5 miles") and broad locality names (e.g., "Chicago - River North"). Your exact street address is never published or exposed.
                </p>
              </section>

              <section id="chat-privacy" className="legal-clause">
                <h2>3. Encrypted In-App Chat Retention</h2>
                <p>
                  Buyer-seller messaging is facilitated through private in-app channels. Messages are accessible exclusively to the two negotiating parties and authorized Hocalist support personnel for dispute resolution and trust/safety reviews.
                </p>
                <p>
                  We do not sell message transcripts to third-party advertisers. Chat media attachments are stored in private encrypted storage buckets.
                </p>
              </section>

              <section id="billing-data" className="legal-clause">
                <h2>4. Stripe Billing & Financial Metadata</h2>
                <p>
                  <strong>Stripe Processing:</strong> All website billing operations (seller monthly plans and prepaid HocaCredit deposit batches) are processed through Stripe. Hocalist does not store raw credit card numbers or banking credentials on our application servers.
                </p>
                <p>
                  We retain billing metadata including Stripe Customer ID, active subscription tier, credit batch deposit history, and webhook confirmation records.
                </p>
              </section>

              <section id="data-sharing" className="legal-clause">
                <h2>5. Information Sharing Boundaries</h2>
                <p>
                  We do not sell, rent, or trade your personal data. We share information only under these strict circumstances:
                </p>
                <ul>
                  <li>With trusted infrastructure providers (Supabase database, Twilio SMS verification, Stripe billing);</li>
                  <li>When required by lawful subpoena, search warrant, or emergency court order;</li>
                  <li>To investigate and mitigate imminent physical harm or fraudulent violations of our community safety policies.</li>
                </ul>
              </section>

              <section id="user-rights" className="legal-clause">
                <h2>6. Your Rights & Data Deletion</h2>
                <p>
                  You have the right to inspect, export, or request permanent deletion of your personal account data at any time. Account deletion requests can be initiated in the Mobile App Settings or by submitting an email to <a href="mailto:privacy@hocalist.com">privacy@hocalist.com</a>.
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

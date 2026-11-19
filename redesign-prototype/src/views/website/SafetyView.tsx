import React from 'react';
import { WebsiteRoute } from '../../types';
import {
  Shield,
  Lock,
  AlertTriangle,
  Eye,
  MapPin,
  CheckCircle2,
  PhoneCall,
  ArrowRight
} from 'lucide-react';

interface SafetyViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const SafetyView: React.FC<SafetyViewProps> = ({ setRoute }) => {
  return (
    <div className="safety-view">
      <section className="safety-hero">
        <div className="container text-center">
          <span className="badge badge-navy mb-3">Community Security</span>
          <h1 className="safety-title">Safety & In-Person Meetup Standards</h1>
          <p className="safety-subtitle">
            Hocalist pairs direct in-person inspection with cryptographic 5-digit transaction validation. Follow these guidelines to ensure every transaction is secure, verified, and transparent.
          </p>
        </div>
      </section>

      <section className="section">
        <div className="container">
          {/* Main 4 Pillars */}
          <div className="pillars-grid">
            <div className="pillar-card card">
              <div className="pillar-icon"><MapPin size={24} className="text-primary" /></div>
              <h3>1. Designated Public Exchange Zones</h3>
              <p>
                Never invite strangers to your private residence or meet in deserted parking lots. Always select busy, public, and surveillance-monitored locations:
              </p>
              <ul className="pillar-bullets">
                <li>Local police department Safe Exchange Zones</li>
                <li>Bank lobbies or busy public shopping centers</li>
                <li>Well-lit daytime coffee shops or public transit terminals</li>
              </ul>
            </div>

            <div className="pillar-card card">
              <div className="pillar-icon"><Eye size={24} className="text-primary" /></div>
              <h3>2. Physical Inspection Before Payment</h3>
              <p>
                You are never obligated to complete a purchase if the merchandise fails to meet your expectations or matches the seller's offer description:
              </p>
              <ul className="pillar-bullets">
                <li>Power on electronics, test ports, screen, and battery</li>
                <li>Verify clean IMEI / serial numbers against iCloud or Google lock</li>
                <li>Check all included accessories, boxes, and receipts</li>
              </ul>
            </div>

            <div className="pillar-card card">
              <div className="pillar-icon"><Lock size={24} className="text-primary" /></div>
              <h3>3. The 5-Digit Purchase PIN Rule</h3>
              <p>
                When a meeting is scheduled, Hocalist generates a unique 5-digit PIN for the buyer. Keep this PIN private until the moment of final settlement:
              </p>
              <ul className="pillar-bullets">
                <li>Do NOT send the PIN over chat before the physical meeting</li>
                <li>Only disclose the PIN after you have physically inspected the goods</li>
                <li>The seller inputs this PIN to officially close the deal in the app</li>
              </ul>
            </div>

            <div className="pillar-card card">
              <div className="pillar-icon"><AlertTriangle size={24} className="text-warning" /></div>
              <h3>4. Red Flags & Zero Wire Transfers</h3>
              <p>
                Hocalist strictly enforces direct in-person offline settlement. Be immediately alert to any user requesting upfront remote money:
              </p>
              <ul className="pillar-bullets">
                <li>Refuse requests to wire funds via Zelle or CashApp before meeting</li>
                <li>Do not accept gift cards, cashier's checks, or overseas shipping claims</li>
                <li>Report any user asking to communicate outside the Hocalist app</li>
              </ul>
            </div>
          </div>

          {/* Boundaries Clarification */}
          <div className="safety-disclaimer card mt-5">
            <div className="disclaimer-header">
              <Shield size={28} className="text-primary" />
              <div>
                <h3>Platform Escrow & Item Payment Disclaimer</h3>
                <p>
                  Hocalist does NOT provide shipping services, electronic escrow, buyer purchase guarantees, or buyer-to-seller item payment processing. Users must independently evaluate merchandise, negotiate offline item payment terms, and exercise reasonable personal safety during all in-person meetings.
                </p>
              </div>
            </div>
          </div>

          {/* Action Row */}
          <div className="safety-actions mt-5 text-center">
            <h3>Experienced a problem or need to file a report?</h3>
            <p className="mt-2 text-muted">Our safety desk reviews all reported incidents promptly.</p>
            <div className="action-btn-row mt-3">
              <button className="btn btn-primary" onClick={() => setRoute('support')}>
                Submit a Safety Report
                <ArrowRight size={16} />
              </button>
              <button className="btn btn-outline" onClick={() => setRoute('how-it-works')}>
                Review Reverse Marketplace Flow
              </button>
            </div>
          </div>
        </div>
      </section>

      <style>{`
        .safety-hero {
          padding: 4.5rem 0 2.5rem;
          background: linear-gradient(180deg, #F0F4FF 0%, #FFFFFF 100%);
        }
        .safety-title {
          font-size: 2.8rem;
          color: var(--hoca-navy);
          margin-bottom: 0.85rem;
        }
        .safety-subtitle {
          font-size: 1.15rem;
          line-height: 1.6;
          color: var(--text-secondary);
          max-width: 720px;
          margin: 0 auto;
        }
        .pillars-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 2rem;
        }
        @media (max-width: 800px) {
          .pillars-grid {
            grid-template-columns: 1fr;
          }
        }
        .pillar-card {
          padding: 2.25rem;
          border: 1.5px solid var(--border-medium);
        }
        .pillar-icon {
          margin-bottom: 1rem;
        }
        .pillar-card h3 {
          font-size: 1.3rem;
          color: var(--hoca-navy);
          margin-bottom: 0.75rem;
        }
        .pillar-card p {
          font-size: 0.92rem;
          line-height: 1.55;
          color: var(--text-secondary);
          margin-bottom: 1rem;
        }
        .pillar-bullets {
          list-style: none;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .pillar-bullets li {
          position: relative;
          padding-left: 1.25rem;
          font-size: 0.88rem;
          color: var(--text-secondary);
          line-height: 1.45;
        }
        .pillar-bullets li::before {
          content: '•';
          position: absolute;
          left: 0;
          color: var(--hoca-navy);
          font-weight: 800;
          font-size: 1.2rem;
          line-height: 1;
        }
        .safety-disclaimer {
          background: #F8FAFC;
          border-left: 4px solid var(--hoca-navy);
          padding: 2rem;
        }
        .disclaimer-header {
          display: flex;
          align-items: flex-start;
          gap: 1.25rem;
        }
        .disclaimer-header h3 {
          font-size: 1.2rem;
          color: var(--hoca-navy);
          margin-bottom: 0.5rem;
        }
        .disclaimer-header p {
          font-size: 0.9rem;
          line-height: 1.6;
          color: var(--text-secondary);
        }
        .action-btn-row {
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

import React, { useState } from 'react';
import { WebsiteRoute } from '../../types';
import {
  FileText,
  Send,
  MessageSquare,
  MapPin,
  Lock,
  DollarSign,
  Shield,
  CheckCircle2,
  ArrowRight,
  UserCheck,
  Store
} from 'lucide-react';

interface HowItWorksViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const HowItWorksView: React.FC<HowItWorksViewProps> = ({ setRoute }) => {
  const [activeTab, setActiveTab] = useState<'buyer' | 'seller'>('buyer');

  return (
    <div className="how-it-works-view">
      {/* Hero Header */}
      <section className="hiw-hero">
        <div className="container text-center">
          <span className="badge badge-navy mb-3">Reverse Marketplace Model</span>
          <h1 className="hiw-title">How Hocalist Works</h1>
          <p className="hiw-subtitle">
            A transparent, in-person marketplace where buyers declare what they want, verified local sellers submit competitive offers, and deals are settled safely offline.
          </p>

          <div className="role-tab-pill-box">
            <button
              className={`role-pill-btn ${activeTab === 'buyer' ? 'active' : ''}`}
              onClick={() => setActiveTab('buyer')}
            >
              <UserCheck size={16} />
              <span>For Buyers (100% Free)</span>
            </button>
            <button
              className={`role-pill-btn ${activeTab === 'seller' ? 'active' : ''}`}
              onClick={() => setActiveTab('seller')}
            >
              <Store size={16} />
              <span>For Local Sellers</span>
            </button>
          </div>
        </div>
      </section>

      {/* Main Stepper Walkthrough */}
      <section className="section">
        <div className="container">
          {activeTab === 'buyer' ? (
            <div className="timeline-container animate-fade-in">
              <div className="timeline-item">
                <div className="timeline-number-col">
                  <div className="step-circle">1</div>
                  <div className="step-connector" />
                </div>
                <div className="timeline-content-card card">
                  <div className="step-badge-row">
                    <span className="badge badge-navy">Step 1 • Need Creation</span>
                    <span className="step-time">Instant</span>
                  </div>
                  <h3>Post what you want to buy</h3>
                  <p>
                    Enter your item description, brand, condition (e.g. New, Open Box, Refurbished), budget range, and location area. Hocalist protects your exact home address—sellers only see your coarse neighborhood or radius.
                  </p>
                  <div className="step-media-preview">
                    <img src="/assets/how-it-works/buyer-request.png" alt="Buyer Request Step" className="step-img" />
                  </div>
                  <div className="step-callout">
                    <FileText size={16} />
                    <span><strong>No browsing required:</strong> Broadcasts your need directly to qualified sellers nearby.</span>
                  </div>
                </div>
              </div>

              <div className="timeline-item">
                <div className="timeline-number-col">
                  <div className="step-circle">2</div>
                  <div className="step-connector" />
                </div>
                <div className="timeline-content-card card">
                  <div className="step-badge-row">
                    <span className="badge badge-navy">Step 2 • Competitive Offers</span>
                    <span className="step-time">Minutes to Hours</span>
                  </div>
                  <h3>Receive & compare custom offers</h3>
                  <p>
                    Local stores, merchants, and verified sellers review your request and send tailored offers. Compare prices, distances, merchant ratings, warranty options, and real item photos.
                  </p>
                  <div className="step-media-preview">
                    <img src="/assets/how-it-works/seller-offer.png" alt="Seller Offer Step" className="step-img" />
                  </div>
                  <div className="step-callout">
                    <DollarSign size={16} />
                    <span><strong>Better prices:</strong> Sellers compete for your business rather than charging inflated catalog prices.</span>
                  </div>
                </div>
              </div>

              <div className="timeline-item">
                <div className="timeline-number-col">
                  <div className="step-circle">3</div>
                  <div className="step-connector" />
                </div>
                <div className="timeline-content-card card">
                  <div className="step-badge-row">
                    <span className="badge badge-navy">Step 3 • Selection & Private Chat</span>
                    <span className="step-time">Coordinated</span>
                  </div>
                  <h3>Select your preferred seller & open chat</h3>
                  <p>
                    When you accept an offer, a private encrypted chat opens between you and the seller. Finalize specs, ask questions, agree on meeting time, and select a safe public meetup location.
                  </p>
                  <div className="step-media-preview">
                    <img src="/assets/how-it-works/buyer-seller-coordinate.png" alt="Coordinate Meetup Step" className="step-img" />
                  </div>
                  <div className="step-callout">
                    <MessageSquare size={16} />
                    <span><strong>Privacy protected:</strong> Neither party sees personal phone numbers or email addresses.</span>
                  </div>
                </div>
              </div>

              <div className="timeline-item">
                <div className="timeline-number-col">
                  <div className="step-circle">4</div>
                </div>
                <div className="timeline-content-card card highlight-card">
                  <div className="step-badge-row">
                    <span className="badge badge-success">Step 4 • Inspection & PIN Settlement</span>
                    <span className="step-time">In Person</span>
                  </div>
                  <h3>Meet in person, inspect item, pay offline</h3>
                  <p>
                    Meet at your chosen public location. Inspect and test the item thoroughly. Once 100% satisfied, share your secure 5-digit Purchase PIN with the seller to validate completion, and settle item payment directly (cash, card, or agreed peer-to-peer).
                  </p>
                  <div className="step-media-preview pin-showcase">
                    <div className="pin-highlight-box">
                      <Lock size={18} />
                      <span className="pin-code-text">5-Digit Secure PIN Protocol</span>
                    </div>
                  </div>
                  <div className="boundary-notice">
                    <Shield size={16} />
                    <div>
                      <strong>Offline Item Payment Boundary:</strong> Hocalist never holds item escrow or processes buyer item payments. You only pay after you hold and inspect the item.
                    </div>
                  </div>
                </div>
              </div>
            </div>
          ) : (
            <div className="timeline-container animate-fade-in">
              <div className="timeline-item">
                <div className="timeline-number-col">
                  <div className="step-circle">1</div>
                  <div className="step-connector" />
                </div>
                <div className="timeline-content-card card">
                  <div className="step-badge-row">
                    <span className="badge badge-navy">Step 1 • Lead Discovery</span>
                    <span className="step-time">Real-Time</span>
                  </div>
                  <h3>View live buyer demand in your area</h3>
                  <p>
                    Browse real-time customer requests filtered by your merchandise categories, target radius, and budget limits. See exactly what local buyers are ready to purchase today.
                  </p>
                  <div className="step-callout">
                    <MapPin size={16} />
                    <span><strong>Qualified intent:</strong> Every request represents a real customer actively looking to buy.</span>
                  </div>
                </div>
              </div>

              <div className="timeline-item">
                <div className="timeline-number-col">
                  <div className="step-circle">2</div>
                  <div className="step-connector" />
                </div>
                <div className="timeline-content-card card">
                  <div className="step-badge-row">
                    <span className="badge badge-navy">Step 2 • Submit Targeted Offer</span>
                    <span className="step-time">FIFO HocaCredits</span>
                  </div>
                  <h3>Submit a competitive offer from inventory</h3>
                  <p>
                    Propose your price, delivery or meetup options, photos, and warranty terms. Your weekly subscription quota (10, 50, or 100 customer targets) tracks interactions, while prepaid HocaCredits cover initial and winning fees under immutable deposit batch rates.
                  </p>
                  <div className="step-callout">
                    <DollarSign size={16} />
                    <span><strong>Transparent credit deduction:</strong> Spent from your oldest eligible deposit batch. Winning fee is the total—pay only the remaining difference on deal win.</span>
                  </div>
                </div>
              </div>

              <div className="timeline-item">
                <div className="timeline-number-col">
                  <div className="step-circle">3</div>
                  <div className="step-connector" />
                </div>
                <div className="timeline-content-card card">
                  <div className="step-badge-row">
                    <span className="badge badge-navy">Step 3 • Chat & Schedule Meetup</span>
                    <span className="step-time">Direct</span>
                  </div>
                  <h3>Coordinate meetup at your store or safe public zone</h3>
                  <p>
                    When the buyer accepts your offer, direct in-app chat opens. Answer questions, provide store directions, and schedule a convenient meeting time before the request countdown ends.
                  </p>
                  <div className="step-callout">
                    <MessageSquare size={16} />
                    <span><strong>Store or public:</strong> Invite customers to your storefront or meet at agreed safe public exchange points.</span>
                  </div>
                </div>
              </div>

              <div className="timeline-item">
                <div className="timeline-number-col">
                  <div className="step-circle">4</div>
                </div>
                <div className="timeline-content-card card highlight-card">
                  <div className="step-badge-row">
                    <span className="badge badge-success">Step 4 • Verify PIN & Collect 100% Payment</span>
                    <span className="step-time">Complete</span>
                  </div>
                  <h3>Enter the buyer's PIN and collect full payment offline</h3>
                  <p>
                    Present the item. Once the buyer inspects it, enter their 5-digit Purchase PIN into your Hocalist Seller App. The deal is officially confirmed, your seller reputation updates, and you collect 100% of the item sale price directly without any platform cut.
                  </p>
                  <div className="boundary-notice">
                    <Shield size={16} />
                    <div>
                      <strong>Keep 100% of Sales:</strong> Zero marketplace commissions on items. Stripe covers your subscription and targeting credits only.
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Bottom Action Card */}
          <div className="hiw-cta-box text-center">
            <h3>Ready to get started?</h3>
            <p>Join thousands of buyers and local businesses redefining local commerce.</p>
            <div className="hiw-btn-row">
              <button className="btn btn-primary btn-lg" onClick={() => setRoute('download')}>
                Join Buyer Waitlist
                <ArrowRight size={18} />
              </button>
              <button className="btn btn-secondary btn-lg" onClick={() => setRoute('pricing')}>
                Explore Seller Subscription Plans
              </button>
            </div>
          </div>
        </div>
      </section>

      <style>{`
        .hiw-hero {
          padding: 4.5rem 0 2.5rem;
          background: linear-gradient(180deg, #F0F4FF 0%, #FFFFFF 100%);
        }
        .hiw-title {
          font-size: 2.8rem;
          color: var(--hoca-navy);
          margin-bottom: 1rem;
        }
        .hiw-subtitle {
          font-size: 1.15rem;
          line-height: 1.6;
          color: var(--text-secondary);
          max-width: 680px;
          margin: 0 auto 2.25rem;
        }
        .role-tab-pill-box {
          display: inline-flex;
          background: #E2E8F0;
          padding: 4px;
          border-radius: var(--radius-full);
          gap: 4px;
        }
        .role-pill-btn {
          display: inline-flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.65rem 1.5rem;
          border-radius: var(--radius-full);
          font-size: 0.92rem;
          font-weight: 700;
          color: var(--text-secondary);
          background: transparent;
          transition: all var(--transition-fast);
        }
        .role-pill-btn.active {
          background: var(--hoca-navy);
          color: white;
          box-shadow: 0 2px 6px rgba(0, 3, 108, 0.2);
        }

        /* Timeline Styles */
        .timeline-container {
          max-width: 820px;
          margin: 0 auto;
          display: flex;
          flex-direction: column;
        }
        .timeline-item {
          display: flex;
          gap: 2rem;
        }
        @media (max-width: 640px) {
          .timeline-item {
            gap: 1rem;
          }
        }
        .timeline-number-col {
          display: flex;
          flex-direction: column;
          align-items: center;
        }
        .step-circle {
          width: 44px;
          height: 44px;
          border-radius: 50%;
          background: var(--hoca-navy);
          color: white;
          font-size: 1.15rem;
          font-weight: 800;
          display: flex;
          align-items: center;
          justify-content: center;
          box-shadow: 0 4px 10px rgba(0, 3, 108, 0.2);
          flex-shrink: 0;
        }
        .step-connector {
          width: 3px;
          background: #CBD5E1;
          flex: 1;
          margin: 0.5rem 0;
          min-height: 40px;
        }
        .timeline-content-card {
          flex: 1;
          margin-bottom: 2rem;
          padding: 2rem;
          border: 1.5px solid var(--border-subtle);
        }
        .highlight-card {
          border-color: #86EFAC;
          background: #F8FFF9;
        }
        .step-badge-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 0.75rem;
        }
        .step-time {
          font-size: 0.78rem;
          font-weight: 600;
          color: var(--text-muted);
        }
        .timeline-content-card h3 {
          font-size: 1.35rem;
          color: var(--hoca-navy);
          margin-bottom: 0.75rem;
        }
        .timeline-content-card p {
          font-size: 0.95rem;
          line-height: 1.6;
          color: var(--text-secondary);
          margin-bottom: 1.25rem;
        }
        .step-media-preview {
          margin-bottom: 1.25rem;
          border-radius: var(--radius-md);
          overflow: hidden;
          background: #F1F5F9;
          border: 1px solid var(--border-subtle);
          padding: 0.5rem;
          display: flex;
          justify-content: center;
        }
        .step-img {
          max-height: 220px;
          width: auto;
          max-width: 100%;
          object-fit: contain;
          border-radius: var(--radius-sm);
        }
        .pin-showcase {
          background: #00036C;
          padding: 1.5rem;
        }
        .pin-highlight-box {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          color: white;
          font-weight: 700;
          font-size: 1rem;
        }
        .pin-code-text {
          font-family: monospace;
          letter-spacing: 0.15em;
          color: #93C5FD;
        }
        .step-callout {
          background: var(--hoca-blue-tint-soft);
          border-left: 3px solid var(--hoca-navy);
          padding: 0.65rem 0.85rem;
          border-radius: var(--radius-sm);
          font-size: 0.85rem;
          color: var(--text-secondary);
          display: flex;
          align-items: flex-start;
          gap: 0.5rem;
        }
        .step-callout svg {
          color: var(--hoca-navy);
          flex-shrink: 0;
          margin-top: 0.15rem;
        }

        .hiw-cta-box {
          background: #F8FAFC;
          border: 1px solid var(--border-medium);
          border-radius: var(--radius-xl);
          padding: 3rem 2rem;
          margin-top: 2rem;
        }
        .hiw-cta-box h3 {
          font-size: 1.8rem;
          color: var(--hoca-navy);
          margin-bottom: 0.5rem;
        }
        .hiw-cta-box p {
          font-size: 1rem;
          color: var(--text-secondary);
          margin-bottom: 1.75rem;
        }
        .hiw-btn-row {
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

import React, { useState } from 'react';
import { WebsiteRoute } from '../../types';
import {
  Mail,
  MessageSquare,
  Shield,
  HelpCircle,
  Clock,
  CheckCircle2,
  ArrowRight,
  ExternalLink
} from 'lucide-react';

interface SupportViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const SupportView: React.FC<SupportViewProps> = ({ setRoute }) => {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [topic, setTopic] = useState('general');
  const [message, setMessage] = useState('');
  const [submitted, setSubmitted] = useState(false);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!email || !message) return;
    setSubmitted(true);
  }

  return (
    <div className="support-view">
      <section className="support-hero">
        <div className="container text-center">
          <span className="badge badge-navy mb-3">Customer Assistance</span>
          <h1 className="support-title">How Can We Help You?</h1>
          <p className="support-subtitle">
            Have questions about local requests, seller subscription billing, or safety guidelines? Our dedicated support team is here to assist.
          </p>
        </div>
      </section>

      <section className="section">
        <div className="container">
          <div className="support-grid">
            {/* Left: Contact Channels & SLA */}
            <div className="support-channels-col">
              <div className="card channel-card">
                <div className="channel-icon-wrap">
                  <Mail size={24} className="text-primary" />
                </div>
                <h3>Direct Email Inquiries</h3>
                <p>For account assistance, billing questions, or merchant verification.</p>
                <div className="email-highlight">support@hocalist.com</div>
                <div className="sla-chip">
                  <Clock size={13} /> Responses within 2 business days
                </div>
                <a
                  href="mailto:support@hocalist.com"
                  className="btn btn-outline btn-sm mt-3"
                >
                  Open Default Mail Client <ExternalLink size={13} />
                </a>
              </div>

              <div className="card channel-card mt-4">
                <div className="channel-icon-wrap">
                  <Shield size={24} className="text-primary" />
                </div>
                <h3>Safety & Urgent Reports</h3>
                <p>If you experienced suspicious behavior or safety violations during an in-person meeting, contact our safety desk immediately.</p>
                <button
                  className="btn btn-secondary btn-sm mt-2"
                  onClick={() => setRoute('safety')}
                >
                  Read Safety Protocol & Reporting
                </button>
              </div>

              <div className="card channel-card mt-4">
                <div className="channel-icon-wrap">
                  <HelpCircle size={24} className="text-primary" />
                </div>
                <h3>Seller Billing Portal</h3>
                <p>Manage your Stripe subscriptions, download invoice receipts, or review HocaCredit deposit balances.</p>
                <button
                  className="btn btn-primary btn-sm mt-2"
                  onClick={() => setRoute('billing')}
                >
                  Go to Seller Portal
                </button>
              </div>
            </div>

            {/* Right: Interactive Support Ticket Form */}
            <div className="support-form-col">
              <div className="card form-card">
                {!submitted ? (
                  <form onSubmit={handleSubmit}>
                    <h3>Send Us a Message</h3>
                    <p className="form-sub">
                      Fill out the form below and a representative will follow up at your email address.
                    </p>

                    <div className="form-group mb-3">
                      <label htmlFor="sup-name">Your Full Name</label>
                      <input
                        id="sup-name"
                        type="text"
                        required
                        placeholder="Jane Doe"
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                      />
                    </div>

                    <div className="form-group mb-3">
                      <label htmlFor="sup-email">Email Address</label>
                      <input
                        id="sup-email"
                        type="email"
                        required
                        placeholder="jane@example.com"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                      />
                    </div>

                    <div className="form-group mb-3">
                      <label htmlFor="sup-topic">Inquiry Topic</label>
                      <select
                        id="sup-topic"
                        value={topic}
                        onChange={(e) => setTopic(e.target.value)}
                      >
                        <option value="general">General Marketplace Question</option>
                        <option value="seller-billing">Seller Plan & Stripe Billing</option>
                        <option value="credits">HocaCredits & Deposit Batches</option>
                        <option value="safety">Report User / In-Person Safety Concern</option>
                        <option value="bug">Technical App Feedback</option>
                      </select>
                    </div>

                    <div className="form-group mb-4">
                      <label htmlFor="sup-msg">Message Details</label>
                      <textarea
                        id="sup-msg"
                        required
                        rows={5}
                        placeholder="Please describe your question or issue in detail..."
                        value={message}
                        onChange={(e) => setMessage(e.target.value)}
                      />
                    </div>

                    <div className="boundary-notice mb-4">
                      <Shield size={16} />
                      <div>
                        <strong>Notice:</strong> Submitting this form sends an authenticated inquiry to Hocalist customer operations. For emergency safety issues, contact local authorities first.
                      </div>
                    </div>

                    <button type="submit" className="btn btn-primary btn-lg full-width">
                      <span>Submit Inquiry</span>
                      <ArrowRight size={18} />
                    </button>
                  </form>
                ) : (
                  <div className="support-submitted animate-fade-in text-center">
                    <div className="success-icon-wrap">
                      <CheckCircle2 size={44} className="text-success" />
                    </div>
                    <h3>Support Request Recorded</h3>
                    <p>
                      Thank you, <strong>{name || email}</strong>. Your ticket has been logged under topic <strong>{topic}</strong>.
                    </p>
                    <div className="ticket-id-chip">Reference ID: #HOC-CASE-8492</div>
                    <p className="mt-3 text-muted">
                      A confirmation email has been dispatched to <strong>{email}</strong>. Our support desk will reply within 2 business days.
                    </p>
                    <button
                      className="btn btn-outline btn-sm mt-4"
                      onClick={() => setSubmitted(false)}
                    >
                      Send Another Inquiry
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </section>

      <style>{`
        .support-hero {
          padding: 4.5rem 0 2.5rem;
          background: linear-gradient(180deg, #F0F4FF 0%, #FFFFFF 100%);
        }
        .support-title {
          font-size: 2.8rem;
          color: var(--hoca-navy);
          margin-bottom: 0.85rem;
        }
        .support-subtitle {
          font-size: 1.15rem;
          line-height: 1.6;
          color: var(--text-secondary);
          max-width: 680px;
          margin: 0 auto;
        }
        .support-grid {
          display: grid;
          grid-template-columns: 0.9fr 1.1fr;
          gap: 3rem;
          align-items: flex-start;
        }
        @media (max-width: 860px) {
          .support-grid {
            grid-template-columns: 1fr;
          }
        }
        .channel-card {
          padding: 2rem;
          border: 1px solid var(--border-medium);
        }
        .channel-icon-wrap {
          margin-bottom: 1rem;
        }
        .channel-card h3 {
          font-size: 1.25rem;
          color: var(--hoca-navy);
          margin-bottom: 0.45rem;
        }
        .channel-card p {
          font-size: 0.88rem;
          color: var(--text-secondary);
          margin-bottom: 1rem;
        }
        .email-highlight {
          font-size: 1.1rem;
          font-weight: 700;
          color: var(--hoca-navy);
          margin-bottom: 0.5rem;
        }
        .sla-chip {
          display: inline-flex;
          align-items: center;
          gap: 0.35rem;
          font-size: 0.8rem;
          color: var(--text-muted);
          background: var(--bg-muted);
          padding: 0.25rem 0.6rem;
          border-radius: var(--radius-sm);
        }
        .form-card {
          padding: 2.5rem;
          border: 1.5px solid var(--border-medium);
        }
        .form-card h3 {
          font-size: 1.45rem;
          color: var(--hoca-navy);
          margin-bottom: 0.4rem;
        }
        .form-sub {
          font-size: 0.9rem;
          color: var(--text-secondary);
          margin-bottom: 1.75rem;
        }
        .form-group label {
          display: block;
          font-size: 0.82rem;
          font-weight: 700;
          color: var(--text-secondary);
          margin-bottom: 0.35rem;
        }
        .form-group input, .form-group select, .form-group textarea {
          width: 100%;
          padding: 0.75rem 1rem;
          border: 1.5px solid var(--border-medium);
          border-radius: var(--radius-md);
        }
        .form-group textarea {
          resize: vertical;
        }
        .support-submitted {
          padding: 2rem 1rem;
        }
        .ticket-id-chip {
          background: var(--hoca-blue-tint);
          color: var(--hoca-navy);
          font-weight: 700;
          font-size: 0.9rem;
          padding: 0.5rem 1rem;
          border-radius: var(--radius-full);
          display: inline-block;
          margin-top: 1rem;
        }
      `}</style>
    </div>
  );
};

import Link from 'next/link';
import { OfflineNotice, PageShell } from '../site-content';

export const metadata = {
  title: 'Contact Hocalist Support',
  description: 'Contact Hocalist for general support, seller billing, safety reports, and legal or privacy questions.'
};

const supportEmail = 'support@hocalist.com';

const supportTypes = [
  {
    title: 'Account help',
    body: 'Questions about account access, profile details, or early access status.',
    action: 'Email account support',
    subject: 'Hocalist account help',
    email: 'support@hocalist.com'
  },
  {
    title: 'Buyer request help',
    body: 'Help with creating a request, request details, offer comparison, or request status labels.',
    action: 'Email buyer support',
    subject: 'Hocalist buyer request help',
    email: 'support@hocalist.com'
  },
  {
    title: 'Seller offer help',
    body: 'Help with seller profiles, request visibility, submitting offers, or offer status labels.',
    action: 'Email seller support',
    subject: 'Hocalist seller offer help',
    email: 'sellers@hocalist.com'
  },
  {
    title: 'Billing and subscriptions',
    body: 'Help with seller plans, credits, promoted visibility, platform access, or seller tool billing.',
    action: 'Email billing support',
    subject: 'Hocalist seller billing support',
    email: 'billing@hocalist.com'
  },
  {
    title: 'Safety report',
    body: 'Report a marketplace concern, suspicious activity, profile issue, or buyer-seller coordination problem.',
    action: 'Email safety support',
    subject: 'Hocalist safety report',
    email: 'safety@hocalist.com'
  },
  {
    title: 'Technical issue',
    body: 'Report a website, app preview, notification, or access problem that blocks normal use.',
    action: 'Email technical support',
    subject: 'Hocalist technical issue',
    email: 'support@hocalist.com'
  },
  {
    title: 'Privacy request',
    body: 'Ask about privacy, account data, written notices, terms, refunds, or cancellation questions.',
    action: 'Email privacy and legal support',
    subject: 'Hocalist privacy request',
    email: 'privacy@hocalist.com'
  }
];

const prepItems = [
  'Your Hocalist account email, if you have one',
  'Whether you are a buyer, seller, or visitor',
  'The request, offer, chat, seller plan, or credit issue involved',
  'Screenshots or dates that make the issue easier to review'
];

function mailtoFor(subject: string, email = supportEmail) {
  return `mailto:${email}?subject=${encodeURIComponent(subject)}`;
}

export default function SupportPage() {
  const formAction = mailtoFor('Hocalist support form request');

  return (
    <PageShell>
      <main className="support-page">
        <section className="support-hero reveal">
          <div className="support-hero-copy">
            <p className="eyebrow">Hocalist support</p>
            <h1>A little help.<br /><em>A clearer next step.</em></h1>
            <p>
              Contact Hocalist for public support, seller billing questions, safety reports,
              privacy requests, or help understanding the buyer request and seller offer flow.
            </p>
            <div className="support-hero-actions">
              <a className="button primary" href={mailtoFor('Hocalist support request')}>
                Email Hocalist support
              </a>
              <Link className="button secondary" href="/terms">
                View terms
              </Link>
            </div>
          </div>
          <aside className="support-contact-panel" aria-label="Support contact details">
            <svg className="support-envelope" width="44" height="36" viewBox="0 0 44 36" fill="none" aria-hidden="true"><rect x="2" y="4" width="40" height="28" rx="5" stroke="currentColor" strokeWidth="1.5"/><path d="m3 7 19 14L41 7M3 29l12-11m26 11L29 18" stroke="currentColor" strokeWidth="1.5"/></svg>
            <span className="status-chip success">Response target</span>
            <h2>Email support</h2>
            <a className="support-email" href={`mailto:${supportEmail}`}>
              {supportEmail}
            </a>
            <p>We aim to respond within 2 business days.</p>
            <p className="fine-print">For written notices, email support for current mailing details.</p>
          </aside>
        </section>

        <section className="support-proof-strip reveal delay-1" aria-label="Hocalist support scope">
          <span>Buyer requests</span>
          <span>Seller offers</span>
          <span>Seller billing</span>
          <span>Safety reports</span>
          <span>Privacy questions</span>
        </section>

        <section className="support-layout">
          <div className="support-detail-column">
            <form className="support-form-card reveal" action={formAction} method="post" encType="text/plain">
              <div className="support-form-heading">
                <p className="eyebrow">Email Hocalist</p>
                <h2>Send a support request</h2>
                <p>
                  Add your information below, then submit to open your email app with the message
                  addressed to Hocalist support.
                </p>
              </div>
              <div className="support-form-grid">
                <label className="support-field">
                  <span>Your name</span>
                  <input name="Name" type="text" autoComplete="name" placeholder="Your full name" required />
                </label>
                <label className="support-field">
                  <span>Email address</span>
                  <input name="Email" type="email" autoComplete="email" placeholder="you@example.com" required />
                </label>
              </div>
              <label className="support-field">
                <span>Support topic</span>
                <select name="Topic" defaultValue="Account help" required>
                  {supportTypes.map((type) => (
                    <option key={type.title} value={type.title}>
                      {type.title}
                    </option>
                  ))}
                </select>
              </label>
              <label className="support-field">
                <span>How can we help?</span>
                <textarea
                  name="Message"
                  placeholder="Share the request, offer, seller billing, safety, account, privacy, or legal question you need help with."
                  rows={6}
                  required
                />
              </label>
              <div className="support-form-actions">
                <button className="button primary" type="submit">
                  Open email app
                </button>
                <a className="text-link" href={mailtoFor('Hocalist support request')}>
                  Or email {supportEmail}
                </a>
              </div>
              <p className="support-form-note">
                Item payment, pickup, delivery, and handoff details are arranged directly
                between buyers and sellers outside Hocalist.
              </p>
            </form>
          </div>

          <aside className="support-side-stack">
            <div className="support-card support-route-card reveal delay-1">
              <p className="eyebrow">Contact form</p>
              <h2>Tell us what happened and we will review it by email.</h2>
              <p>
                This form opens your email app so you can send the details directly to
                Hocalist support. This page does not store your message before you send it.
              </p>
            </div>
            <div className="support-guidance-card support-prep-card reveal delay-1">
              <p className="eyebrow">What to include</p>
              <h2>Send enough detail for a useful first reply.</h2>
              <ul>
                {prepItems.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </div>
          </aside>
        </section>

        <section className="support-topic-section">
          <div className="support-section-heading reveal">
            <p className="eyebrow">Choose a support path</p>
            <h2>Use the topic cards when you already know where the issue belongs.</h2>
          </div>
          <div className="support-topic-grid" aria-label="Support topics">
            {supportTypes.map((type, index) => (
              <article className={`support-topic-card reveal ${index === 1 ? 'delay-1' : ''}`} key={type.title}>
                <span className="support-topic-number">{String(index + 1).padStart(2, '0')}</span>
                <h3>{type.title}</h3>
                <p>{type.body}</p>
                <a className="text-link" href={mailtoFor(type.subject, type.email)}>
                  {type.action}
                </a>
              </article>
            ))}
          </div>
        </section>

        <section className="support-guidance-section">
          <div className="support-card support-route-card support-guidance-intro reveal">
            <p className="eyebrow">Boundaries</p>
            <h2>Support can explain Hocalist flow, seller tools, and where payment happens.</h2>
            <p>
              Buyer-to-seller item payment is arranged directly between users, outside Hocalist.
            </p>
          </div>
          <div className="support-boundary-stack reveal delay-1">
            <OfflineNotice />
            <article className="support-boundary-card">
              <span className="status-chip gold">Seller billing boundary</span>
              <h3>Seller plan payment is for seller tools and platform access.</h3>
              <p>
                Hocalist support can help with seller plans, credits, promoted visibility, and
                related seller access questions. Item payment between buyers and sellers is
                arranged directly outside Hocalist.
              </p>
            </article>
          </div>
        </section>

        <section className="support-link-band reveal">
          <div>
            <p className="eyebrow">Related pages</p>
            <h2>Need policy details before emailing?</h2>
          </div>
          <div className="support-link-actions">
            <Link className="button secondary" href="/privacy">
              Privacy
            </Link>
            <Link className="button secondary" href="/terms">
              Terms
            </Link>
            <Link className="button secondary" href="/safety">
              Safety
            </Link>
          </div>
        </section>
      </main>
    </PageShell>
  );
}

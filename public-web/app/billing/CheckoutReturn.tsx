import Link from 'next/link';
import { PageShell } from '../site-content';

export function CheckoutReturn({ cancelled = false }: { cancelled?: boolean }) {
  return (
    <PageShell>
      <main>
        <section className="subpage-hero">
          <p className="eyebrow">Seller subscription</p>
          <h1>{cancelled ? 'You left checkout' : 'Check your subscription in Hocalist'}</h1>
          <p>
            {cancelled
              ? 'Your subscription status has not been changed by this page. Return to Hocalist to check your current plan before starting checkout again.'
              : 'Return to Hocalist to see your current plan. Your subscription will appear after your payment has been confirmed.'}
          </p>
          <p>
            This page cannot confirm a payment or activate a plan. If your payment is still being processed,
            allow a moment for your account to update before trying again.
          </p>
          <div className="hero-actions" style={{ justifyContent: 'center' }}>
            <Link className="button primary" href="/pricing">View seller plans</Link>
            <Link className="button secondary" href="/support">Get help</Link>
          </div>
        </section>
      </main>
    </PageShell>
  );
}

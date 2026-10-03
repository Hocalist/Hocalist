import { OfflineNotice, PageShell } from '../site-content';
import BillingPortal from './BillingPortal';

export const metadata = {
  title: 'Seller billing and HocaCredits | Hocalist',
  description:
    'Manage your Hocalist seller plan, HocaCredits and payment method. Item payment stays between buyer and seller.',
  robots: { index: false, follow: false },
  alternates: { canonical: 'https://hocalist.com/billing' }
};

export default async function BillingPage({
  searchParams
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const previewKind = typeof params.preview === 'string' ? params.preview : null;
  const returnTo = typeof params.returnTo === 'string' ? params.returnTo : null;

  return (
    <PageShell>
      <main className="billing-page">
        <section className="subpage-hero reveal">
          <p className="eyebrow">Seller billing</p>
          <h1>Your seller plan, credits, and payment method in one place</h1>
          <p>
            Seller plans and HocaCredits are purchased here through Stripe Checkout. Billing is in
            TEST mode until activation. Buyers never pay Hocalist for items; item payment stays
            between buyer and seller.
          </p>
        </section>
        <BillingPortal previewKind={previewKind} returnTo={returnTo} />
        <section className="page-section billing-boundary">
          <OfflineNotice />
          <div className="billing-boundary-copy">
            <h2>What you can pay for here</h2>
            <ul>
              <li>Seller plan subscriptions: Free $0, Pro $15/month, Elite $30/month in USD.</li>
              <li>HocaCredits for eligible targeting fees, separate from weekly target limits.</li>
              <li>Payment method updates through the Stripe-hosted billing portal.</li>
            </ul>
            <p className="billing-note">
              Annual plans and trials are not offered on this page. Refund and cancellation terms
              are in the <a href="/refund-cancellation">refund and cancellation policy</a>.
            </p>
          </div>
        </section>
      </main>
    </PageShell>
  );
}

import { OfflineNotice, PageShell } from '../site-content';
import BillingPortal from './BillingPortal';
import { ReturnToApp } from './ReturnToApp';
import './seller-billing.css';

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
        <ReturnToApp />
        <BillingPortal previewKind={previewKind} returnTo={returnTo} />
        <section className="page-section billing-boundary">
          <div className="billing-boundary-copy">
            <p className="billing-note">
              Subscription prices are in USD; targeting fees are in HC. Read the <a href="/refund-cancellation">refund and cancellation policy</a> before purchasing.
            </p>
          </div>
          <OfflineNotice />
        </section>
      </main>
    </PageShell>
  );
}

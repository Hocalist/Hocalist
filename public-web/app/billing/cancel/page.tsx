import { PageShell } from '../../site-content';
import { CheckoutReturn } from '../CheckoutReturn';

export const metadata = {
  title: 'Checkout closed',
  robots: { index: false, follow: false },
  alternates: { canonical: 'https://hocalist.com/billing/cancel' }
};

export default async function BillingCancelPage({
  searchParams
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  return (
    <PageShell>
      <main className="billing-page">
        <CheckoutReturn
          cancelled
          previewKind={typeof params.preview === 'string' ? params.preview : null}
          checkoutHint={typeof params.checkout === 'string' ? params.checkout : null}
        />
      </main>
    </PageShell>
  );
}

import { PageShell } from '../../site-content';
import { CheckoutReturn } from '../CheckoutReturn';

export const metadata = {
  title: 'Checkout status',
  robots: { index: false, follow: false },
  alternates: { canonical: 'https://hocalist.com/billing/return' }
};

export default async function BillingReturnPage({
  searchParams
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  return (
    <PageShell>
      <main className="billing-page">
        <CheckoutReturn
          previewKind={typeof params.preview === 'string' ? params.preview : null}
          checkoutHint={typeof params.checkout === 'string' ? params.checkout : null}
        />
      </main>
    </PageShell>
  );
}

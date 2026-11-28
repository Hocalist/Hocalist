import { PageShell } from '../../site-content';
import { CheckoutReturn } from '../CheckoutReturn';
import { ReturnLink, ReturnToApp } from '../ReturnToApp';
import {redirect} from 'next/navigation';
import {uuidHint} from '../../lib/website-rules';

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
  if (params.pilot === '1') {
    return (
      <PageShell>
        <main className="billing-page">
          <section className="page-section" aria-labelledby="pilot-return-heading">
            <h1 id="pilot-return-heading">Return to Hocalist</h1>
            <p>Open Seller Plans or Credits in the app to check your verified Stripe activity.</p>
            <ReturnLink href="com.hocalist.app://billing-return/" />
          </section>
        </main>
      </PageShell>
    );
  }
  const setupId=uuidHint(params.paygo_setup);
  if(setupId)redirect(`/billing?paygo_setup=${encodeURIComponent(setupId)}`);
  return (
    <PageShell>
      <main className="billing-page">
        <ReturnToApp />
        <CheckoutReturn
          previewKind={typeof params.preview === 'string' ? params.preview : null}
          checkoutHint={typeof params.checkout === 'string' ? params.checkout : null}
        />
      </main>
    </PageShell>
  );
}

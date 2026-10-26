import { PageShell } from '../../site-content';
import { CheckoutReturn } from '../CheckoutReturn';
import { ReturnToApp } from '../ReturnToApp';
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

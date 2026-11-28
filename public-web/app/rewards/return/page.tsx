import type { Metadata } from 'next';
import { ReturnLink } from '../../billing/ReturnToApp';
import { PageShell } from '../../site-content';

export const metadata: Metadata = {
  title: 'Return to Hocalist Rewards',
  robots: { index: false, follow: false },
  referrer: 'no-referrer',
};

export default function BuyerPayoutReturnPage() {
  return (
    <PageShell>
      <main className="billing-page">
        <section className="page-section" aria-labelledby="payout-return-heading">
          <h1 id="payout-return-heading">Return to Hocalist Rewards</h1>
          <p>Open Rewards in the Hocalist app to check your payout account.</p>
          <p>If Stripe asked you to try again, open Payout account in Rewards to get a fresh setup link.</p>
          <ReturnLink href="com.hocalist.app://billing-return/" />
        </section>
      </main>
    </PageShell>
  );
}

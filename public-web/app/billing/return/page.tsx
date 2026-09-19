import { CheckoutReturn } from '../CheckoutReturn';

export const metadata = {
  title: 'Return to Hocalist',
  robots: { index: false, follow: false },
  alternates: { canonical: 'https://hocalist.com/billing/return' },
};

export default function BillingReturnPage() {
  return <CheckoutReturn />;
}

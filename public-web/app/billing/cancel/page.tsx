import { CheckoutReturn } from '../CheckoutReturn';

export const metadata = {
  title: 'Checkout closed',
  robots: { index: false, follow: false },
  alternates: { canonical: 'https://hocalist.com/billing/cancel' },
};

export default function BillingCancelPage() {
  return <CheckoutReturn cancelled />;
}

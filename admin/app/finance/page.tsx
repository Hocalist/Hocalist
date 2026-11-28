import { AdminShell, PageHeader } from '../components';
import { financePreview } from '../lib/finance-preview';
import { loadFinanceReview } from '../lib/finance-review';
import { FinancePanel } from './finance-panel';

export const dynamic = 'force-dynamic';

export default async function FinancePage() {
  const review = await loadFinanceReview();
  const example = process.env.NODE_ENV === 'development' &&
    process.env.HOCALIST_ADMIN_FINANCE_PREVIEW === 'true' ? financePreview : null;
  return <AdminShell>
    <PageHeader title="Profit & Costs" description="Track earned revenue, direct costs, and operating profit by month." />
    <FinancePanel view="profit" example={review ? null : example} review={review} />
  </AdminShell>;
}

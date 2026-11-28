import { AdminShell, PageHeader } from '../components';
import { FinancePanel } from '../finance/finance-panel';
import { financePreview } from '../lib/finance-preview';
import { loadFinanceReview } from '../lib/finance-review';

export const dynamic = 'force-dynamic';

export default async function RewardsImpactPage() {
  const review = await loadFinanceReview();
  const example = process.env.NODE_ENV === 'development' &&
    process.env.HOCALIST_ADMIN_FINANCE_PREVIEW === 'true' ? financePreview : null;
  return <AdminShell>
    <PageHeader title="Rewards & User Impact" description="See what buyers received and which marketplace outcomes are verified." />
    <FinancePanel view="impact" example={review ? null : example} review={review} />
  </AdminShell>;
}

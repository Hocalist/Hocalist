import { AdminShell, PageHeader } from "../components";
import { WithdrawalsPanel } from "../trust-panels";

export const dynamic = "force-dynamic";

export default function Withdrawals() {
  return (
    <AdminShell>
      <PageHeader
        title="Buyer withdrawals"
        description="Provider-neutral withdrawal requests with reserved amounts, explicit net payouts and reconciliation states. Read-only: settlement stays with the provider-owned service path."
      />
      <WithdrawalsPanel />
    </AdminShell>
  );
}

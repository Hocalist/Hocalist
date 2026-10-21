import { AdminShell, PageHeader } from "../components";
import { DeliveryPanel } from "../delivery-panel";

export const dynamic = "force-dynamic";

export default function Delivery() {
  return (
    <AdminShell>
      <PageHeader
        title="Delivery operations"
        description="Read-only push queue health: status counts and recent failures. Retries, provider reconciliation and device delivery are separate steps."
      />
      <DeliveryPanel />
    </AdminShell>
  );
}

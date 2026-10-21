import { AdminShell, PageHeader } from "../components";
import { TrustPanel } from "../trust-panels";

export const dynamic = "force-dynamic";

export default function Trust() {
  return (
    <AdminShell>
      <PageHeader
        title="Trust review"
        description="Reviewed identity/business evidence, seller-health report signals, recorded restrictions and appeals. Every decision keeps its reviewer reason; one report never restricts an account by itself."
      />
      <TrustPanel />
    </AdminShell>
  );
}

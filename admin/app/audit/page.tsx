import { AdminShell, PageHeader } from "../components";
import { AuditPanel } from "../audit-panel";

export const dynamic = "force-dynamic";

export default function Audit() {
  return (
    <AdminShell>
      <PageHeader
        title="Audit log"
        description="Reviewed administrator, moderation, support, trust, call-setting and withdrawal actions from their existing append-only records. Filters and paging are bounded; private content is excluded."
      />
      <AuditPanel />
    </AdminShell>
  );
}

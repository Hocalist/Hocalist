import { AdminShell, PageHeader } from "../components";
import { EventsPanel } from "../events-panel";

export const dynamic = "force-dynamic";

export default function Events() {
  return (
    <AdminShell>
      <PageHeader
        title="Failed provider events"
        description="Bounded, read-only view of Stripe TEST receipt and reconciliation events that still need attention, with sanitized error classes. Email bounce ingestion is not connected."
      />
      <EventsPanel />
    </AdminShell>
  );
}

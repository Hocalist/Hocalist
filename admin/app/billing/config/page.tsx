import { AdminStateNotice } from "../../admin-state";
import { AdminShell, PageHeader } from "../../components";
import { decodeCommercialConfig } from "../../lib/admin-commercial";
import { loadCommercialConfig } from "../../lib/admin-data";

import { CommercialConfigPanel } from "./commercial-config";

export const dynamic = "force-dynamic";

export default async function CommercialConfig() {
  const load = await loadCommercialConfig();
  const decoded = load.state === "ok" ? decodeCommercialConfig(load.data) : null;
  return (
    <AdminShell>
      <PageHeader
        title="Deposit & reward configuration"
        description="Admin-managed deposit options and buyer reward policy. Every edit passes the reviewed commercial command with a carried revision; historical batches keep their frozen rates."
      />
      <AdminStateNotice
        load={load.state === "ok" && !decoded ? { state: "error", message: "The backend returned an invalid configuration." } : load}
      />
      {decoded ? <CommercialConfigPanel initial={decoded} /> : null}
    </AdminShell>
  );
}

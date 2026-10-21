import { AdminStateNotice } from "../admin-state";
import { AdminShell, PageHeader } from "../components";
import { loadLocations, loadTimezones } from "../lib/admin-data";

import { LocationsActions } from "./locations-actions";

export const dynamic = "force-dynamic";

export default async function Locations() {
  const [load, zones] = await Promise.all([loadLocations(), loadTimezones()]);
  return (
    <AdminShell>
      <PageHeader
        title="Locations"
        description="Admin-managed market list used by request and Store forms. Values are backend configuration, not client defaults."
      />
      <AdminStateNotice load={load} />
      {zones.state !== "ok" && <AdminStateNotice load={zones} />}
      {load.state === "ok" && zones.state === "ok" ? <LocationsActions locations={load.data} timezones={zones.data} /> : null}
    </AdminShell>
  );
}

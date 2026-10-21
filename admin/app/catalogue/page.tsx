import { AdminStateNotice } from "../admin-state";
import { AdminShell, PageHeader } from "../components";
import { loadCatalogue } from "../lib/admin-data";

import { CatalogueActions } from "./catalogue-actions";

export const dynamic = "force-dynamic";

export default async function Catalogue() {
  const load = await loadCatalogue();
  return (
    <AdminShell>
      <PageHeader
        title="Catalogue"
        description="Admin-managed categories, option groups and options for request and Store forms."
      />
      <AdminStateNotice load={load} />
      {load.state === "ok" ? (
        load.data.length > 0 ? (
          <CatalogueActions categories={load.data} />
        ) : (
          <div className="demo-notice">
            <strong>No catalogue entries yet</strong>
            <span>
              Add the first category below. Retiring an entry keeps historical
              requests and listings readable.
            </span>
          </div>
        )
      ) : null}
      {load.state === "ok" && load.data.length === 0 ? (
        <CatalogueActions categories={load.data} />
      ) : null}
    </AdminShell>
  );
}

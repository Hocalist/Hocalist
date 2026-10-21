import { AdminStateNotice } from "../admin-state";
import { AdminShell, PageHeader } from "../components";
import { loadModerationQueue } from "../lib/admin-data";

import { ModerationActions } from "./moderation-actions";

export const dynamic = "force-dynamic";

export default async function Moderation() {
  const load = await loadModerationQueue();
  return (
    <AdminShell>
      <PageHeader
        title="Store moderation"
        description="New and edited Store listings stay private until an administrator approves them. Rejections keep the listing and its history."
      />
      <AdminStateNotice load={load} />
      {load.state === "ok" ? <ModerationActions listings={load.data} /> : null}
    </AdminShell>
  );
}

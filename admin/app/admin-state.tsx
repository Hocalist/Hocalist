import Link from "next/link";

import type { AdminLoad } from "./lib/admin-data";

// Renders the non-data states for admin configuration pages. The page body is
// only shown for an authorized, configured session.
export function AdminStateNotice({ load }: { load: AdminLoad<unknown> }) {
  if (load.state === "ok") return null;
  if (load.state === "unconfigured") {
    return (
      <div className="demo-notice">
        <strong>Backend not configured</strong>
        <span>
          Set <code>HOCALIST_SUPABASE_URL</code> and{" "}
          <code>HOCALIST_SUPABASE_ANON_KEY</code> in the server environment to
          connect this portal. No live data is read or written without them.
        </span>
      </div>
    );
  }
  if (load.state === "signed_out") {
    return (
      <div className="demo-notice">
        <strong>Sign in required</strong>
        <span>
          Administrator sessions are short-lived. <Link href="/login">Sign in</Link>{" "}
          to load live configuration.
        </span>
      </div>
    );
  }
  if (load.state === "forbidden") {
    return (
      <div className="demo-notice">
        <strong>Administrator access required</strong>
        <span>
          This account is not provisioned in <code>hocalist.platform_admins</code>.
          Provisioning is a reviewed database action, never a client command.
        </span>
      </div>
    );
  }
  return (
    <div className="demo-notice">
      <strong>Backend error</strong>
      <span>{load.message}</span>
    </div>
  );
}

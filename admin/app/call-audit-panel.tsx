"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { adminRpc } from "./lib/admin-client";
import { decodeCallAuditHistory } from "./lib/admin-call-audit";

export function CallAuditPanel() {
  const [data, setData] = useState<ReturnType<typeof decodeCallAuditHistory>>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const generation = useRef(0);

  async function refresh() {
    const current = ++generation.current;
    setBusy(true);
    setError(null);
    const result = await adminRpc("admin_call_settings_history", {});
    if (current !== generation.current) return;
    setBusy(false);
    if (!result.ok) {
      setData(null);
      setError(
        result.state === "signed_out"
          ? "Sign in to view the call history."
          : result.state === "forbidden"
          ? "Administrator access is required."
          : "Call history is unavailable. The read contract may not be deployed yet.",
      );
      return;
    }
    const decoded = decodeCallAuditHistory(result.data);
    setData(decoded);
    if (!decoded) setError("The backend returned an invalid call history.");
  }

  useEffect(() => {
    void refresh();
    return () => {
      ++generation.current;
    };
  }, []);

  return (
    <section className="section">
      <div className="section-title">
        <h2>Video calling change history</h2>
        <button onClick={() => void refresh()} disabled={busy}>
          Refresh history
        </button>
      </div>
      {busy && <p role="status">Loading call history…</p>}
      {error && (
        <div role="alert" className="demo-notice">
          <span>{error}</span>
          <Link href="/login">Sign in</Link>
        </div>
      )}
      {data && (
        <>
          <p>
            Current call setting:{" "}
            <strong>{data.current_enabled ? "On" : "Off"}</strong>
          </p>
          {data.items.length === 0 ? (
            <p>No call-setting changes recorded yet.</p>
          ) : (
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Revision</th>
                    <th>Setting</th>
                    <th>Changed by</th>
                    <th>Changed at</th>
                  </tr>
                </thead>
                <tbody>
                  {data.items.map((row) => (
                    <tr key={row.revision}>
                      <td><strong>{row.revision}</strong></td>
                      <td>{row.enabled ? "On" : "Off"}</td>
                      <td>{row.changed_by}</td>
                      <td>{row.changed_at}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
      <div className="boundary">
        <strong>Read-only audit</strong>
        <span>
          This history never changes the call setting. Calls stay off until a
          paid relay and two-device acceptance are approved separately.
        </span>
      </div>
    </section>
  );
}

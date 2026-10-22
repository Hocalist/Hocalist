"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { adminRpc } from "./lib/admin-client";
import { decodeDeliveryOverview } from "./lib/admin-delivery";
import { Stat } from "./components";

export function DeliveryPanel() {
  const [data, setData] = useState<ReturnType<typeof decodeDeliveryOverview>>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const generation = useRef(0);

  async function refresh() {
    const current = ++generation.current;
    setBusy(true);
    setError(null);
    const result = await adminRpc("admin_delivery_overview", {});
    if (current !== generation.current) return;
    setBusy(false);
    if (!result.ok) {
      setData(null);
      setError(
        result.state === "signed_out"
          ? "Sign in to view delivery health."
          : result.state === "forbidden"
          ? "Administrator access is required."
          : "Delivery health is unavailable. The read contract may not be deployed yet.",
      );
      return;
    }
    const decoded = decodeDeliveryOverview(result.data);
    setData(decoded);
    if (!decoded) setError("The backend returned an invalid delivery summary.");
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
        <h2>Push delivery health</h2>
        <button onClick={() => void refresh()} disabled={busy}>
          Refresh delivery
        </button>
      </div>
      {busy && <p role="status">Loading delivery health…</p>}
      {error && (
        <div role="alert" className="demo-notice">
          <span>{error}</span>
          <Link href="/login">Sign in</Link>
        </div>
      )}
      {data && (
        <>
          <div className="stats compact">
            <Stat label="Pending" value={String(data.pending)} note="Queued, not yet claimed" />
            <Stat label="Sending" value={String(data.sending)} note="Leased to the worker" />
            <Stat label="Accepted" value={String(data.accepted)} note="Provider accepted" />
            <Stat
              label="Failed"
              value={String(data.failed)}
              note={`${data.failed_last_24h} in the last 24h`}
              tone="red"
            />
          </div>
          <p>
            Oldest pending: {data.oldest_pending_at ?? "none"}
            {" · "}
            Skipped: {data.skipped}
          </p>
          <h3>Recent failures</h3>
          {data.recent_failures.length === 0 ? (
            <p>No failed deliveries recorded.</p>
          ) : (
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Delivery</th>
                    <th>Event kind</th>
                    <th>Recipient</th>
                    <th>Attempts</th>
                    <th>Last error</th>
                    <th>Available at</th>
                  </tr>
                </thead>
                <tbody>
                  {data.recent_failures.map((row) => (
                    <tr key={row.id}>
                      <td><strong>{row.id}</strong></td>
                      <td>{row.kind}</td>
                      <td>{row.user_id}</td>
                      <td>{row.attempts}</td>
                      <td>{row.last_error || "—"}</td>
                      <td>{row.available_at}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
      <div className="boundary">
        <strong>Delivery boundaries</strong>
        <span>
          This view is read-only: it never retries or deletes a delivery. The push
          schedule is managed separately, no device token or notification content is shown,
          and provider/device delivery is not proved by these counts.
        </span>
      </div>
    </section>
  );
}

"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";

import { adminRpc } from "./lib/admin-client";
import {
  decodeFailedEventDetail,
  decodeFailedEvents,
  FAILED_EVENT_STATUSES,
  FAILED_EVENT_TYPES,
  type FailedEventDetail,
  type FailedEventPage,
} from "./lib/admin-events";

type Loaded = { page: FailedEventPage };

export function EventsPanel() {
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  const [status, setStatus] = useState("");
  const [type, setType] = useState("");
  const [detail, setDetail] = useState<FailedEventDetail | null>(null);
  const [busy, setBusy] = useState(true);
  const [detailBusy, setDetailBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [signedOut, setSignedOut] = useState(false);
  const generation = useRef(0);
  const filters = useRef({ status: "", type: "" });

  const fetchPage = useCallback(async (cursor: string | null, append = false) => {
    const current = ++generation.current;
    setBusy(true);
    setError(null);
    const result = await adminRpc("admin_failed_events", {
      p_limit: 50,
      p_cursor: cursor,
      p_status: filters.current.status || null,
      p_type: filters.current.type || null,
    });
    if (current !== generation.current) return;
    setBusy(false);
    if (!result.ok) {
      const state = result.state;
      setSignedOut(state === "signed_out");
      setError(
        state === "signed_out"
          ? "Sign in to view failed provider events."
          : state === "forbidden"
          ? "Administrator access is required."
          : state === "unconfigured"
          ? "The admin backend is not configured."
          : "Failed events could not be loaded. The read contract may not be deployed yet.",
      );
      if (state === "signed_out" || state === "forbidden") setLoaded(null);
      return;
    }
    const decoded = decodeFailedEvents(result.data);
    if (!decoded) {
      setError("The backend returned an invalid failed-event page.");
      return;
    }
    setSignedOut(false);
    setLoaded((previous) => {
      if (!append || !previous) return { page: decoded };
      const seen = new Set(previous.page.items.map((row) => row.event_id));
      return {
        page: {
          ...decoded,
          items: [
            ...previous.page.items,
            ...decoded.items.filter((row) => !seen.has(row.event_id)),
          ],
        },
      };
    });
  }, []);

  useEffect(() => {
    void fetchPage(null);
    return () => {
      ++generation.current;
    };
  }, [fetchPage]);

  function search(event: FormEvent) {
    event.preventDefault();
    filters.current = { status, type };
    setLoaded(null);
    setDetail(null);
    void fetchPage(null);
  }

  async function inspect(eventId: string) {
    if (detail?.event_id === eventId) {
      setDetail(null);
      return;
    }
    setDetailBusy(true);
    setError(null);
    const result = await adminRpc("admin_failed_event_detail", { p_event_id: eventId });
    setDetailBusy(false);
    if (!result.ok) {
      setError(
        result.state === "signed_out"
          ? "Sign in again to inspect an event."
          : "That event detail could not be loaded. Refresh the list and try again.",
      );
      return;
    }
    const decoded = decodeFailedEventDetail(result.data);
    if (!decoded) {
      setError("The backend returned invalid event detail.");
      return;
    }
    setDetail(decoded);
  }

  const filtered = filters.current.status !== "" || filters.current.type !== "";

  return (
    <section className="section">
      <form className="filters" onSubmit={search}>
        <select aria-label="Filter event status" value={status} onChange={(event) => setStatus(event.target.value)}>
          <option value="">All statuses</option>
          {FAILED_EVENT_STATUSES.map((value) => (
            <option key={value} value={value}>
              {value}
            </option>
          ))}
        </select>
        <select aria-label="Filter event type" value={type} onChange={(event) => setType(event.target.value)}>
          <option value="">All event types</option>
          {FAILED_EVENT_TYPES.map((value) => (
            <option key={value} value={value}>
              {value}
            </option>
          ))}
        </select>
        <button disabled={busy} type="submit">
          Filter
        </button>
        <button
          disabled={busy}
          type="button"
          onClick={() => {
            setLoaded(null);
            setDetail(null);
            void fetchPage(null);
          }}
        >
          Refresh
        </button>
      </form>
      {error && (
        <div role="alert" className="demo-notice">
          <span>{error}</span>
          {signedOut && <Link href="/login">Sign in</Link>}
          <button disabled={busy} onClick={() => void fetchPage(null)}>
            Try again
          </button>
        </div>
      )}
      {busy && <p role="status">Loading failed events…</p>}
      {loaded && loaded.page.email_events_available === false && (
        <div className="demo-notice">
          <strong>Email delivery events are not ingested</strong>
          <span>
            Bounce and suppression status is unavailable. No email status is
            inferred from provider keys or configuration; provider event
            ingestion is coordinator-owned work.
          </span>
        </div>
      )}
      {loaded && (
        <>
          {loaded.page.items.length === 0 ? (
            <p>
              {filtered
                ? "No failed events match these filters."
                : "No failed provider events are recorded."}
            </p>
          ) : (
            <div className="table-card">
              <div className="table-scroll">
                <table>
                  <thead>
                    <tr>
                      <th>Event</th>
                      <th>Type</th>
                      <th>Status</th>
                      <th>Attempts</th>
                      <th>Error class</th>
                      <th>Next attempt</th>
                      <th>Received</th>
                      <th>
                        <span className="sr-only">Actions</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {loaded.page.items.map((row) => (
                      <tr key={row.event_id}>
                        <td>
                          <strong>{row.event_id}</strong>
                        </td>
                        <td>{row.event_type}</td>
                        <td>{row.status}</td>
                        <td>{row.attempts}</td>
                        <td>{row.error_class || "—"}</td>
                        <td>{row.available_at}</td>
                        <td>{row.received_at}</td>
                        <td>
                          <button
                            className="row-action"
                            disabled={detailBusy}
                            onClick={() => void inspect(row.event_id)}
                          >
                            {detail?.event_id === row.event_id ? "Hide" : "Inspect"}
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <footer className="pagination">
                <span>{loaded.page.items.length} events loaded · newest first</span>
                {loaded.page.next_cursor && (
                  <button
                    disabled={busy}
                    onClick={() => void fetchPage(loaded.page.next_cursor, true)}
                  >
                    Load more
                  </button>
                )}
              </footer>
            </div>
          )}
          {detail && (
            <div className="ledger-detail">
              <h3>Event {detail.event_id}</h3>
              <dl className="detail-list">
                <div><dt>Type</dt><dd>{detail.event_type}</dd></div>
                <div><dt>Status</dt><dd>{detail.status}</dd></div>
                <div><dt>Attempts</dt><dd>{detail.attempts}</dd></div>
                <div><dt>Object class</dt><dd>{detail.object_kind}</dd></div>
                <div><dt>Error class</dt><dd>{detail.error_class || "—"}</dd></div>
                <div><dt>Provider created</dt><dd>{new Date(detail.event_created * 1000).toISOString()}</dd></div>
                <div><dt>Next attempt</dt><dd>{detail.available_at}</dd></div>
                <div><dt>Test mode</dt><dd>{detail.livemode ? "Live" : "TEST"}</dd></div>
              </dl>
              <p>
                The provider object id, payload, customer and payment detail are
                deliberately not exposed here.
              </p>
            </div>
          )}
        </>
      )}
      <div className="boundary">
        <strong>Read-only operations</strong>
        <span>
          This view never retries, replays, quarantines or deletes an event. A
          broad retry action would need a separately reviewed idempotent worker
          command with reconciliation proof.
        </span>
      </div>
    </section>
  );
}

"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";

import { adminRpc } from "./lib/admin-client";
import { AUDIT_SOURCES, decodeAuditFeed, type AuditFeed } from "./lib/admin-audit";

const uuid = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

export function AuditPanel() {
  const [feed, setFeed] = useState<AuditFeed | null>(null);
  const [source, setSource] = useState("");
  const [actor, setActor] = useState("");
  const [query, setQuery] = useState("");
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [signedOut, setSignedOut] = useState(false);
  const generation = useRef(0);
  const filters = useRef({ source: "", actor: "", query: "" });

  const fetchPage = useCallback(async (cursor: string | null, append = false) => {
    const current = ++generation.current;
    setBusy(true);
    setError(null);
    const result = await adminRpc("admin_audit_feed", {
      p_limit: 50,
      p_cursor: cursor,
      p_source: filters.current.source || null,
      p_actor: filters.current.actor || null,
      p_query: filters.current.query || null,
    });
    if (current !== generation.current) return;
    setBusy(false);
    if (!result.ok) {
      const state = result.state;
      setSignedOut(state === "signed_out");
      setError(
        state === "signed_out"
          ? "Sign in to view the audit feed."
          : state === "forbidden"
          ? "Administrator access is required."
          : state === "unconfigured"
          ? "The admin backend is not configured."
          : "The audit feed is unavailable. The read contract may not be deployed yet.",
      );
      if (state === "signed_out" || state === "forbidden") setFeed(null);
      return;
    }
    const decoded = decodeAuditFeed(result.data);
    if (!decoded) {
      setError("The backend returned an invalid audit page.");
      return;
    }
    setSignedOut(false);
    setFeed((previous) => {
      if (!append || !previous) return decoded;
      const seen = new Set(previous.items.map((row) => row.id));
      return {
        ...decoded,
        items: [...previous.items, ...decoded.items.filter((row) => !seen.has(row.id))],
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
    const trimmedActor = actor.trim();
    if (trimmedActor.length > 0 && !uuid.test(trimmedActor)) {
      setError("An actor filter must be a full user id (UUID).");
      return;
    }
    if (query.trim().length > 100) {
      setError("The search text must be 100 characters or fewer.");
      return;
    }
    filters.current = { source, actor: trimmedActor, query: query.trim() };
    setFeed(null);
    void fetchPage(null);
  }

  const filtered =
    filters.current.source !== "" ||
    filters.current.actor !== "" ||
    filters.current.query !== "";

  return (
    <section className="section">
      <form className="filters" onSubmit={search}>
        <select aria-label="Filter audit source" value={source} onChange={(event) => setSource(event.target.value)}>
          <option value="">All sources</option>
          {AUDIT_SOURCES.map((value) => (
            <option key={value} value={value}>
              {value}
            </option>
          ))}
        </select>
        <label>
          <span>⌕</span>
          <input
            aria-label="Filter actor by user id"
            maxLength={36}
            placeholder="Actor user id (optional)"
            value={actor}
            onChange={(event) => setActor(event.target.value)}
          />
        </label>
        <label>
          <span>⌕</span>
          <input
            aria-label="Search audit actions"
            maxLength={100}
            placeholder="Action, target or decision text"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
          />
        </label>
        <button disabled={busy} type="submit">
          Search
        </button>
        <button
          disabled={busy}
          type="button"
          onClick={() => {
            setFeed(null);
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
      {busy && <p role="status">Loading the audit feed…</p>}
      {feed && (
        <div className="table-card">
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Source</th>
                  <th>Action</th>
                  <th>Actor</th>
                  <th>Target</th>
                  <th>Detail</th>
                </tr>
              </thead>
              <tbody>
                {feed.items.length === 0 ? (
                  <tr>
                    <td colSpan={6}>
                      {filtered
                        ? "No audit entries match these filters."
                        : "No audited administrator or review actions are recorded yet."}
                    </td>
                  </tr>
                ) : (
                  feed.items.map((row) => (
                    <tr key={row.id}>
                      <td>{row.occurred_at}</td>
                      <td>{row.source}</td>
                      <td>
                        <strong>{row.action}</strong>
                      </td>
                      <td>{row.actor}</td>
                      <td>{row.target || "—"}</td>
                      <td>
                        {row.summary || "—"}
                        {row.detail ? <small className="audit-detail"> {row.detail}</small> : null}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
          <footer className="pagination">
            <span>{feed.items.length} entries loaded · newest first</span>
            {feed.next_cursor && (
              <button disabled={busy} onClick={() => void fetchPage(feed.next_cursor, true)}>
                Load more
              </button>
            )}
          </footer>
        </div>
      )}
      <div className="boundary">
        <strong>Audit boundaries</strong>
        <span>
          This viewer reads a fixed set of reviewed audit sources. It never runs a
          client-named query or table, and it excludes support response bodies,
          chat content, provider payloads and credentials.
        </span>
      </div>
    </section>
  );
}

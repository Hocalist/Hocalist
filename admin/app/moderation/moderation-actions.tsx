"use client";

import { useRouter } from "next/navigation";
import { useRef, useState } from "react";

import { adminCommand } from "../lib/admin-client";
import { AdminIntent } from "../lib/admin-intent";
import type { AdminListing } from "../lib/admin-data";

function decisionError(message: string, state?: string): string {
  if (state === "signed_out") return "Sign in again to record a moderation decision.";
  if (state === "forbidden") return "Administrator access is required.";
  if (state === "unconfigured") return "The admin backend is not configured.";
  const normalized = message.toLowerCase();
  if (normalized.includes("revision_conflict")) {
    return "Another administrator changed this listing. Refresh the queue before deciding.";
  }
  if (normalized.includes("idempotency_conflict")) {
    return "This decision key was already used for a different change. Refresh before deciding again.";
  }
  return "The decision was not confirmed. Retry the same decision or refresh the queue.";
}

export function ModerationActions({ listings }: { listings: AdminListing[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [retry, setRetry] = useState<Record<string, unknown> | null>(null);
  const intent = useRef(new AdminIntent());
  const inFlight = useRef(false);

  async function execute(operation: string, input: Record<string, unknown>) {
    if (inFlight.current) return;
    const prepared = intent.current.prepare(operation, input);
    inFlight.current = true;
    setBusy(true);
    setError(null);
    setMessage(null);
    const result = await adminCommand(operation, prepared.input, prepared.key);
    inFlight.current = false;
    setBusy(false);
    if (!result.ok) {
      setRetry(prepared.input);
      setError(decisionError(result.message, result.state));
      return;
    }
    intent.current.acknowledged();
    setRetry(null);
    setMessage("Decision recorded. The queue was refreshed.");
    router.refresh();
  }

  async function decide(listing: AdminListing, decision: "approved" | "rejected") {
    await execute("store.set_moderation", {
      listing_id: listing.id,
      expected_revision: listing.revision,
      moderation_status: decision,
    });
  }

  return (
    <section className="section">
      {error && (
        <div role="alert" className="demo-notice">
          <span>{error}</span>
          <button disabled={busy} onClick={() => router.refresh()}>
            Refresh queue
          </button>
        </div>
      )}
      {message ? <p role="status">{message}</p> : null}
      {retry && (
        <div className="form-actions">
          <button
            disabled={busy}
            onClick={() =>
              void execute(
                "store.set_moderation",
                retry as Record<string, unknown>,
              )
            }
          >
            Retry same decision
          </button>
          <button
            disabled={busy}
            onClick={() => {
              intent.current.acknowledged();
              setRetry(null);
              setError(null);
              setMessage("Retry discarded. The queue was refreshed; check whether the decision saved.");
              router.refresh();
            }}
          >
            Discard retry and refresh
          </button>
        </div>
      )}
      <div className="table-card">
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Listing</th>
                <th>Kind</th>
                <th>Category</th>
                <th>Price</th>
                <th>Status</th>
                <th>
                  <span className="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {listings.map((listing) => (
                <tr key={listing.id}>
                  <td>
                    <strong>{listing.title}</strong>
                  </td>
                  <td>{listing.kind}</td>
                  <td>{listing.category_label}</td>
                  <td>{listing.price_label}</td>
                  <td>{listing.status}</td>
                  <td>
                    <button
                      className="row-action"
                      disabled={busy || !!retry}
                      onClick={() => void decide(listing, "approved")}
                    >
                      Approve
                    </button>
                    <button
                      className="row-action"
                      disabled={busy || !!retry}
                      onClick={() => void decide(listing, "rejected")}
                    >
                      Reject
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
      {listings.length === 0 ? (
        <div className="demo-notice">
          <strong>Queue is clear</strong>
          <span>
            New and edited Store listings wait here until an administrator
            approves or rejects them.
          </span>
        </div>
      ) : null}
      <div className="boundary">
        <strong>Moderation record</strong>
        <span>
          Every decision is revision-checked and kept in the append-only operation
          receipts. A structured free-text moderation reason is not accepted by
          the current command, so this queue does not pretend to collect one;
          adding it needs a reviewed contract change.
        </span>
      </div>
    </section>
  );
}

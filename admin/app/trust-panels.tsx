"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { adminRpc, trustCommand } from "./lib/admin-client";
import { requestEvidence } from "./lib/admin-evidence-client";
import { AdminIntent } from "./lib/admin-intent";
import {
  decodeReviewQueue,
  decodeWithdrawalQueue,
  mergeReviewSection,
  trustErrorMessage,
  type ReviewQueue,
} from "./lib/admin-trust";
import {SectionTabs} from "./section-tabs";
import { Stat } from "./components";

function usd(minor: number): string {
  return `$${Math.floor(minor / 100)}.${String(minor % 100).padStart(2, "0")}`;
}

type Section = "verifications" | "health_reviews" | "restrictions";

const DEFAULT_FILTERS = {
  verificationStatus: "pending",
  healthState: "needs_review",
  restrictionStatus: "active",
};

export function TrustPanel() {
  const [data, setData] = useState<ReviewQueue | null>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [healthDecision, setHealthDecision] = useState("no_action");
  const [filterUi, setFilterUi] = useState(DEFAULT_FILTERS);
  const [retry, setRetry] = useState<{ operation: string; input: Record<string, unknown> } | null>(null);
  const [evidenceNotice, setEvidenceNotice] = useState<string | null>(null);
  const [evidenceBusy, setEvidenceBusy] = useState<string | null>(null);
  const [evidencePreview, setEvidencePreview] = useState<string | null>(null);
  const evidenceGeneration = useRef(0);
  useEffect(() => () => {
    if (evidencePreview?.startsWith("blob:")) URL.revokeObjectURL(evidencePreview);
  }, [evidencePreview]);
  const intent = useRef(new AdminIntent());
  const generation = useRef(0);
  const inFlight = useRef(false);
  const filters = useRef(DEFAULT_FILTERS);
  const loaded = useRef<ReviewQueue | null>(null);

  async function load(replace = true, section?: Section) {
    ++evidenceGeneration.current;
    setEvidencePreview(null);
    setEvidenceBusy(null);
    const cursor =
      replace || !section || !loaded.current
        ? null
        : loaded.current[section].next_cursor;
    if (!replace && (!section || !cursor)) return;
    const current = ++generation.current;
    setBusy(true);
    setError(null);
    const result = await adminRpc("admin_review_queue", {
      p_limit: 25,
      p_verifications_cursor: section === "verifications" && !replace ? cursor : null,
      p_health_cursor: section === "health_reviews" && !replace ? cursor : null,
      p_restrictions_cursor: section === "restrictions" && !replace ? cursor : null,
      p_verification_status: filters.current.verificationStatus || null,
      p_health_state: filters.current.healthState || null,
      p_restriction_status: filters.current.restrictionStatus || null,
    });
    if (current !== generation.current) return;
    setBusy(false);
    if (!result.ok) {
      setData(null);
      loaded.current = null;
      setError(
        result.state === "signed_out"
          ? "Sign in to review trust queues."
          : result.state === "forbidden"
          ? "Administrator access is required."
          : result.state === "unconfigured"
          ? "The admin backend is not configured."
          : "The review queue is unavailable. The read contract may not be deployed yet.",
      );
      return;
    }
    const decoded = decodeReviewQueue(result.data);
    if (!decoded) {
      setData(null);
      loaded.current = null;
      setError("The backend returned an invalid review queue.");
      return;
    }
    if (replace || !section || !loaded.current) {
      setData(decoded);
      loaded.current = decoded;
      return;
    }
    const merged = mergeReviewSection(loaded.current, decoded, section);
    setData(merged);
    loaded.current = merged;
  }

  useEffect(() => {
    void load(true);
    return () => {
      ++generation.current;
      ++evidenceGeneration.current;
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  function applyFilter(next: Partial<typeof DEFAULT_FILTERS>) {
    if (busy || retry) return;
    filters.current = { ...filters.current, ...next };
    setFilterUi(filters.current);
    loaded.current = null;
    void load(true);
  }

  async function execute(operation: string, input: Record<string, unknown>) {
    if (inFlight.current) return;
    if (reason.trim().length === 0) {
      setError("A recorded reason is required before deciding.");
      return;
    }
    const prepared = intent.current.prepare(operation, { ...input, reason: reason.trim() });
    inFlight.current = true;
    setBusy(true);
    setError(null);
    setMessage(null);
    const result = await trustCommand(operation, prepared.input, prepared.key);
    inFlight.current = false;
    setBusy(false);
    if (!result.ok) {
      setRetry({ operation, input: prepared.input });
      setError(trustErrorMessage(result.message, result.state));
      return;
    }
    intent.current.acknowledged();
    setRetry(null);
    setReason("");
    setMessage("Decision recorded with its reviewer reason.");
    await load(true);
  }

  async function viewEvidence(submissionId: string, mediaId: string) {
    const current = ++evidenceGeneration.current;
    const key = `${submissionId}:${mediaId}`;
    setEvidenceBusy(key);
    setEvidenceNotice(null);
    setEvidencePreview(null);
    const result = await requestEvidence(submissionId, mediaId);
    if (current !== evidenceGeneration.current) {
      if (result.ok && result.url.startsWith("blob:")) URL.revokeObjectURL(result.url);
      return;
    }
    setEvidenceBusy(null);
    if (result.ok) {
      setEvidencePreview(result.url);
      setEvidenceNotice("Photo ready to review.");
      return;
    }
    setEvidenceNotice(result.message);
  }

  return (
    <section className="section">
      <div className="section-title">
        <h2>Manual review queue</h2>
        <button onClick={() => void load(true)} disabled={busy || !!retry}>
          Refresh queue
        </button>
      </div>
      {busy && <p role="status">Loading review queues…</p>}
      {error && (
        <div role="alert" className="demo-notice">
          <span>{error}</span>
          <Link href="/login">Sign in</Link>
          <button disabled={busy} onClick={() => void load(true)}>
            Try again
          </button>
        </div>
      )}
      {message && <p role="status">{message}</p>}
      {retry && (
        <div className="form-actions">
          <button disabled={busy} onClick={() => void execute(retry.operation, retry.input)}>
            Retry same decision
          </button>
          <button
            disabled={busy}
            onClick={() => {
              intent.current.acknowledged();
              setRetry(null);
              setMessage("Retry discarded. The queue was reloaded; check whether the decision saved before deciding again.");
              void load(true);
            }}
          >
            Discard retry and refresh
          </button>
        </div>
      )}
      {data && (
        <>
          <div className="stats compact">
            <Stat
              label="Verifications shown"
              value={String(data.verifications.items.length)}
              note={`Filter: ${filterUi.verificationStatus || "all"} · newest first`}
            />
            <Stat
              label="Health reports shown"
              value={String(data.health_reviews.items.length)}
              note={`Filter: ${filterUi.healthState || "all"}`}
            />
            <Stat
              label="Restrictions shown"
              value={String(data.restrictions.items.length)}
              note={`Filter: ${filterUi.restrictionStatus || "all"}`}
              tone="red"
            />
            <Stat
              label="Appeals in view"
              value={String(
                data.restrictions.items.filter((row) => row.appeal_status === "submitted").length,
              )}
              note="Awaiting a decision"
            />
          </div>
          <label>
            Reviewer reason (required for every decision)
            <input
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              maxLength={500}
              disabled={busy || !!retry}
            />
          </label>
          {evidenceNotice && <p role="status">{evidenceNotice}</p>}
          {evidencePreview && <section aria-label="Verification photo" className="section">
            <div className="section-title"><h3>Verification photo</h3>
              <button onClick={() => { setEvidencePreview(null); setEvidenceNotice(null); }}>Close photo</button>
            </div>
            {/* Evidence must remain readable without cropping or pop-up permissions. */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={evidencePreview} alt="Photo attached to the selected verification review" style={{display:"block",width:"100%",maxHeight:"70vh",objectFit:"contain"}} />
          </section>}

          <SectionTabs label="Trust review sections" sections={[{title:"Verification",content:<><h3>Evidence submissions</h3>
          <form className="filters" onSubmit={(event) => event.preventDefault()}>
            <select
              aria-label="Filter verification status"
              value={filterUi.verificationStatus}
              disabled={busy || !!retry}
              onChange={(event) => applyFilter({ verificationStatus: event.target.value })}
            >
              <option value="pending">Pending</option>
              <option value="approved">Approved</option>
              <option value="rejected">Rejected</option>
              <option value="">All</option>
            </select>
          </form>
          {data.verifications.items.length === 0 ? (
            <p>No verification submissions match this filter.</p>
          ) : (
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Seller</th>
                    <th>Kind</th>
                    <th>Note</th>
                    <th>Evidence</th>
                    <th>Status</th>
                    <th>Decision (revision carried)</th>
                  </tr>
                </thead>
                <tbody>
                  {data.verifications.items.map((row) => (
                    <tr key={row.id}>
                      <td><strong>{row.user_id}</strong></td>
                      <td>{row.kind}</td>
                      <td>{row.note.slice(0, 120)}</td>
                      <td>
                        {row.evidence_count === 0 ? (
                          <span>No evidence attached.</span>
                        ) : (
                          <>
                            {row.evidence_media_ids.map((mediaId, index) => (
                              <button
                                key={mediaId}
                                className="row-action"
                                disabled={busy || evidenceBusy !== null}
                                onClick={() => void viewEvidence(row.id, mediaId)}
                              >
                                {evidenceBusy === `${row.id}:${mediaId}`
                                  ? "Requesting…"
                                  : `View ${index + 1}`}
                              </button>
                            ))}
                            <small> · {row.evidence_count} reference(s)</small>
                          </>
                        )}
                      </td>
                      <td>{row.status}</td>
                      <td>
                        {row.status === "pending" ? (
                          <>
                            <button
                              disabled={busy || !!retry}
                              onClick={() =>
                                void execute("verification.decide", {
                                  submission_id: row.id,
                                  status: "approved",
                                  expected_revision: row.revision,
                                })
                              }
                            >
                              Approve
                            </button>{" "}
                            <button
                              disabled={busy || !!retry}
                              onClick={() =>
                                void execute("verification.decide", {
                                  submission_id: row.id,
                                  status: "rejected",
                                  expected_revision: row.revision,
                                })
                              }
                            >
                              Reject
                            </button>
                          </>
                        ) : (
                          <span>
                            {row.status} · revision {row.revision}
                            {row.decision_reason ? ` · ${row.decision_reason}` : ""}
                          </span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {data.verifications.next_cursor && (
                <div className="form-actions">
                  <button
                    disabled={busy || !!retry}
                    onClick={() => void load(false, "verifications")}
                  >
                    Load more verifications
                  </button>
                </div>
              )}
            </div>
          )}

          </>},{title:"Account health",content:<><h3>Seller-health reports</h3>
          <form className="filters" onSubmit={(event) => event.preventDefault()}>
            <select
              aria-label="Filter health review state"
              value={filterUi.healthState}
              disabled={busy || !!retry}
              onChange={(event) => applyFilter({ healthState: event.target.value })}
            >
              <option value="needs_review">Needs review</option>
              <option value="reviewed">Reviewed</option>
              <option value="">All</option>
            </select>
          </form>
          {data.health_reviews.items.length === 0 ? (
            <p>No health reports match this filter.</p>
          ) : (
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Case</th>
                    <th>Reason</th>
                    <th>Report</th>
                    <th>Review</th>
                  </tr>
                </thead>
                <tbody>
                  {data.health_reviews.items.map((row) => (
                    <tr key={row.case_id}>
                      <td><strong>{row.case_id}</strong></td>
                      <td>{row.reason_code}</td>
                      <td>{row.body.slice(0, 140)}</td>
                      <td>
                        {row.decision ? (
                          <span>
                            {row.decision}: {row.decision_reason}
                          </span>
                        ) : (
                          <>
                            <select
                              aria-label="Health review decision"
                              value={healthDecision}
                              disabled={busy || !!retry}
                              onChange={(event) => setHealthDecision(event.target.value)}
                            >
                              <option value="no_action">No action</option>
                              <option value="watch">Watch</option>
                              <option value="restriction_recommended">
                                Restriction recommended
                              </option>
                            </select>{" "}
                            <button
                              disabled={busy || !!retry}
                              onClick={() =>
                                void execute("health.review", {
                                  case_id: row.case_id,
                                  decision: healthDecision,
                                })
                              }
                            >
                              Save review
                            </button>
                          </>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {data.health_reviews.next_cursor && (
                <div className="form-actions">
                  <button
                    disabled={busy || !!retry}
                    onClick={() => void load(false, "health_reviews")}
                  >
                    Load more health reports
                  </button>
                </div>
              )}
            </div>
          )}

          </>},{title:"Restrictions & appeals",content:<><h3>Restrictions and appeals</h3>
          <form className="filters" onSubmit={(event) => event.preventDefault()}>
            <select
              aria-label="Filter restriction status"
              value={filterUi.restrictionStatus}
              disabled={busy || !!retry}
              onChange={(event) => applyFilter({ restrictionStatus: event.target.value })}
            >
              <option value="active">Active</option>
              <option value="revoked">Revoked</option>
              <option value="">All</option>
            </select>
          </form>
          {data.restrictions.items.length === 0 ? (
            <p>No restrictions match this filter.</p>
          ) : (
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>User</th>
                    <th>Scope</th>
                    <th>Reason</th>
                    <th>Status</th>
                    <th>Appeal</th>
                    <th>Action</th>
                  </tr>
                </thead>
                <tbody>
                  {data.restrictions.items.map((row) => (
                    <tr key={row.id}>
                      <td><strong>{row.user_id}</strong></td>
                      <td>{row.scope}</td>
                      <td>{row.reason}</td>
                      <td>{row.status} · revision {row.revision}</td>
                      <td>
                        {row.appeal_status ?? "none"}
                        {row.appeal_revision !== null ? ` · revision ${row.appeal_revision}` : ""}
                      </td>
                      <td>
                        {row.status === "active" && (
                          <button
                            disabled={busy || !!retry}
                            onClick={() =>
                              void execute("restriction.revoke", {
                                restriction_id: row.id,
                                expected_revision: row.revision,
                              })
                            }
                          >
                            Revoke
                          </button>
                        )}
                        {row.appeal_status === "submitted" &&
                          row.appeal_id &&
                          row.appeal_revision !== null && (
                            <>
                              <button
                                disabled={busy || !!retry}
                                onClick={() =>
                                  void execute("appeal.decide", {
                                    appeal_id: row.appeal_id,
                                    status: "upheld",
                                    expected_revision: row.appeal_revision,
                                  })
                                }
                              >
                                Uphold
                              </button>{" "}
                              <button
                                disabled={busy || !!retry}
                                onClick={() =>
                                  void execute("appeal.decide", {
                                    appeal_id: row.appeal_id,
                                    status: "reversed",
                                    expected_revision: row.appeal_revision,
                                  })
                                }
                              >
                                Reverse
                              </button>
                            </>
                          )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {data.restrictions.next_cursor && (
                <div className="form-actions">
                  <button
                    disabled={busy || !!retry}
                    onClick={() => void load(false, "restrictions")}
                  >
                    Load more restrictions
                  </button>
                </div>
              )}
            </div>
          )}
          </>}]} />
        </>
      )}
      <div className="boundary">
        <strong>Review boundaries</strong>
        <span>
          One report never restricts an account by itself. A restriction needs a
          recorded reviewer reason and keeps an appeal route. Applying a new
          restriction stays a reviewed server command until a case exposes the
          account it concerns; this queue exposes revocation and appeal decisions
          with their committed revisions. Evidence preview requires the accounts
          media gateway and is reported as unavailable until it is integrated.
        </span>
      </div>
    </section>
  );
}

export function WithdrawalsPanel() {
  const [data, setData] = useState<ReturnType<typeof decodeWithdrawalQueue>>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const generation = useRef(0);

  async function refresh() {
    const current = ++generation.current;
    setBusy(true);
    setError(null);
    const result = await adminRpc("admin_withdrawal_queue", { p_limit: 50 });
    if (current !== generation.current) return;
    setBusy(false);
    if (!result.ok) {
      setData(null);
      setError(
        result.state === "signed_out"
          ? "Sign in to view withdrawals."
          : result.state === "forbidden"
          ? "Administrator access is required."
          : result.state === "unconfigured"
          ? "The admin backend is not configured."
          : "The withdrawal queue is unavailable. The read contract may not be deployed yet.",
      );
      return;
    }
    const decoded = decodeWithdrawalQueue(result.data);
    setData(decoded);
    if (!decoded) setError("The backend returned an invalid withdrawal summary.");
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
        <h2>Buyer withdrawals</h2>
        <button onClick={() => void refresh()} disabled={busy}>
          Refresh withdrawals
        </button>
      </div>
      {busy && <p role="status">Loading withdrawal queue…</p>}
      {error && (
        <div role="alert" className="demo-notice">
          <span>{error}</span>
          <Link href="/login">Sign in</Link>
        </div>
      )}
      {data && (
        <>
          <div className="stats compact">
            <Stat label="Requests" value={String(data.items.length)} note="Most recent 50" />
            <Stat
              label="Reserved"
              value={usd(data.processing_minor)}
              note="Processing; restored on confirmed failure"
            />
            <Stat
              label="Failed"
              value={String(data.items.filter((row) => row.status === "failed").length)}
              note="Funds restored"
              tone="red"
            />
            <Stat
              label="Paid"
              value={String(data.items.filter((row) => row.status === "paid").length)}
              note="Provider reference recorded"
            />
          </div>
          {data.items.length === 0 ? (
            <p>No withdrawal requests recorded.</p>
          ) : (
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Buyer</th>
                    <th>Gross</th>
                    <th>Fee</th>
                    <th>Net</th>
                    <th>Status</th>
                    <th>Provider reference</th>
                    <th>Failure</th>
                  </tr>
                </thead>
                <tbody>
                  {data.items.map((row) => (
                    <tr key={row.id}>
                      <td><strong>{row.display_name}</strong></td>
                      <td>{usd(row.amount_minor)}</td>
                      <td>{usd(row.fee_minor)}</td>
                      <td>{usd(row.net_minor)}</td>
                      <td>{row.status}</td>
                      <td>{row.provider_reference ?? "—"}</td>
                      <td>{row.failure_reason ?? "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
      <div className="boundary">
        <strong>Payout boundaries</strong>
        <span>
          This queue is read-only. Settlement is provider-owned and idempotent:
          a recorded failure restores the reserved amount and a late provider
          success is flagged for reconciliation instead of paying twice.
        </span>
      </div>
    </section>
  );
}

"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { adminRpc } from "./lib/admin-client";
import { LedgerRequestFence } from "./lib/ledger-request-fence";
import {
  decodeCreditDetail,
  decodeCreditSummary,
  decodeRewardSummary,
  formatHc,
  formatUsd,
  type CreditDetail,
  type CreditSummaryRow,
  type RewardSummaryRow,
} from "./lib/admin-ledger";

type Loaded<T> = { rows: T[]; next: string | null };

export function LedgerPanel() {
  const [credits, setCredits] = useState<Loaded<CreditSummaryRow> | null>(null);
  const [rewards, setRewards] = useState<Loaded<RewardSummaryRow> | null>(null);
  const [detail, setDetail] = useState<CreditDetail | null>(null);
  const [detailBusy, setDetailBusy] = useState(false);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const generation = useRef(0);
  const detailRequests = useRef(new LedgerRequestFence());
  const pageRequests = useRef(new LedgerRequestFence());

  async function inspect(userId: string) {
    const request = detailRequests.current.begin();
    if (detail?.user_id === userId) {
      setDetail(null);
      setDetailBusy(false);
      return;
    }
    setDetail(null);
    setDetailBusy(true);
    setError(null);
    const result = await adminRpc("admin_credit_detail", { p_user: userId });
    if (!detailRequests.current.accepts(request)) return;
    setDetailBusy(false);
    if (!result.ok) {
      setError(
        result.state === "signed_out"
          ? "Sign in again to inspect a ledger."
          : result.state === "forbidden"
          ? "Administrator access is required."
          : "The seller ledger detail could not be loaded. Refresh and try again.",
      );
      return;
    }
    const decoded = decodeCreditDetail(result.data);
    if (!decoded) {
      setError("The backend returned invalid ledger detail.");
      return;
    }
    setDetail(decoded);
  }

  const refresh = useCallback(async () => {
    const current = ++generation.current;
    detailRequests.current.invalidate();
    pageRequests.current.invalidate();
    setDetail(null);
    setDetailBusy(false);
    setBusy(true);
    setError(null);
    const [creditResult, rewardResult] = await Promise.all([
      adminRpc("admin_credit_summary", { p_limit: 50, p_cursor: null }),
      adminRpc("admin_reward_summary", { p_limit: 50, p_cursor: null }),
    ]);
    if (current !== generation.current) return;
    setBusy(false);
    if (!creditResult.ok || !rewardResult.ok) {
      setCredits(null);
      setRewards(null);
      const state = !creditResult.ok ? creditResult.state : rewardResult.ok ? undefined : rewardResult.state;
      setError(
        state === "signed_out"
          ? "Sign in to view the commercial ledgers."
          : state === "forbidden"
          ? "Administrator access is required."
          : state === "unconfigured"
          ? "The admin backend is not configured."
          : "The commercial ledgers are unavailable. The read contracts may not be deployed yet.",
      );
      return;
    }
    const decodedCredits = decodeCreditSummary(creditResult.data);
    const decodedRewards = decodeRewardSummary(rewardResult.data);
    if (!decodedCredits || !decodedRewards) {
      setCredits(null);
      setRewards(null);
      setError("The backend returned an invalid ledger summary.");
      return;
    }
    setCredits({ rows: decodedCredits.items, next: decodedCredits.next_cursor });
    setRewards({ rows: decodedRewards.items, next: decodedRewards.next_cursor });
  }, []);

  useEffect(() => {
    void refresh();
    return () => {
      ++generation.current;
      detailRequests.current.invalidate();
      pageRequests.current.invalidate();
    };
  }, [refresh]);

  const loadMore = async (kind: "credits" | "rewards") => {
    const cursor = kind === "credits" ? credits?.next : rewards?.next;
    if (!cursor) return;
    const request = pageRequests.current.begin();
    setBusy(true);
    const result = await adminRpc(
      kind === "credits" ? "admin_credit_summary" : "admin_reward_summary",
      { p_limit: 50, p_cursor: cursor },
    );
    if (!pageRequests.current.accepts(request)) return;
    setBusy(false);
    if (!result.ok) {
      setError(
        result.state === "signed_out"
          ? "Sign in again to load more ledger rows."
          : result.state === "forbidden"
          ? "Administrator access is required."
          : "More ledger rows could not be loaded. Retry the same page.",
      );
      return;
    }
    if (kind === "credits") {
      const decoded = decodeCreditSummary(result.data);
      if (!decoded) {
        setError("The backend returned an invalid ledger summary.");
        return;
      }
      setCredits((previous) => ({
        rows: [...(previous?.rows ?? []), ...decoded.items],
        next: decoded.next_cursor,
      }));
    } else {
      const decoded = decodeRewardSummary(result.data);
      if (!decoded) {
        setError("The backend returned an invalid ledger summary.");
        return;
      }
      setRewards((previous) => ({
        rows: [...(previous?.rows ?? []), ...decoded.items],
        next: decoded.next_cursor,
      }));
    }
  };

  return (
    <section className="section">
      <div className="section-title">
        <h2>Commercial ledgers</h2>
        <button onClick={() => void refresh()} disabled={busy}>
          Refresh ledgers
        </button>
      </div>
      {busy && <p role="status">Loading commercial ledgers…</p>}
      {error && (
        <div role="alert" className="demo-notice">
          <span>{error}</span>
          <Link href="/login">Sign in</Link>
        </div>
      )}
      {credits && rewards && (
        <>
          <h3>Seller HocaCredit batches</h3>
          {credits.rows.length === 0 ? (
            <p>No credit deposits recorded yet.</p>
          ) : (
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Seller membership</th>
                    <th>Batches</th>
                    <th>Original</th>
                    <th>Remaining</th>
                    <th>Reserved</th>
                    <th>Available</th>
                    <th>Spent</th>
                    <th>Targets (won/released)</th>
                    <th>Last deposit</th>
                    <th>Detail</th>
                  </tr>
                </thead>
                <tbody>
                  {credits.rows.map((row) => (
                    <tr key={row.user_id}>
                      <td><strong>{row.user_id}</strong></td>
                      <td>{row.batch_count}</td>
                      <td>{formatHc(row.original_minor)}</td>
                      <td>{formatHc(row.remaining_minor)}</td>
                      <td>{formatHc(row.reserved_minor)}</td>
                      <td>{formatHc(row.available_minor)}</td>
                      <td>{row.spent_percent}%</td>
                      <td>
                        {row.target_count} ({row.won_count}/{row.released_count})
                      </td>
                      <td>{row.last_deposit_at ?? "—"}</td>
                      <td>
                        <button
                          onClick={() => void inspect(row.user_id)}
                          disabled={detailBusy}
                        >
                          {detail?.user_id === row.user_id ? "Hide" : "Inspect"}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {detail && (
            <div className="ledger-detail">
              <h4>Batch and target detail · {detail.user_id}</h4>
              <p>Available: {formatHc(detail.available_minor)}</p>
              <div className="table-scroll">
                <table>
                  <thead>
                    <tr>
                      <th>Batch</th>
                      <th>Original</th>
                      <th>Remaining</th>
                      <th>Reserved</th>
                      <th>Initial fee</th>
                      <th>Winning total</th>
                      <th>Rate</th>
                    </tr>
                  </thead>
                  <tbody>
                    {detail.batches.map((batch) => (
                      <tr key={batch.id}>
                        <td><strong>{batch.id}</strong></td>
                        <td>{formatHc(batch.original_minor)}</td>
                        <td>{formatHc(batch.balance_minor)}</td>
                        <td>{formatHc(batch.reserved_minor)}</td>
                        <td>{formatHc(batch.initial_fee_minor)}</td>
                        <td>{formatHc(batch.winning_total_minor)}</td>
                        <td>{batch.rate_version}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="table-scroll">
                <table>
                  <thead>
                    <tr>
                      <th>Target</th>
                      <th>Request</th>
                      <th>Status</th>
                      <th>Charged</th>
                      <th>Reserved</th>
                      <th>Week</th>
                    </tr>
                  </thead>
                  <tbody>
                    {detail.targets.map((target) => (
                      <tr key={target.id}>
                        <td><strong>{target.id}</strong></td>
                        <td>{target.request_id}</td>
                        <td>{target.status}</td>
                        <td>{formatHc(target.charged_minor)}</td>
                        <td>{formatHc(target.reserved_minor)}</td>
                        <td>{target.week_start}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
          {credits.next && (
            <button onClick={() => void loadMore("credits")} disabled={busy}>
              Load more credit ledgers
            </button>
          )}

          <h3>Buyer reward ledger</h3>
          {rewards.rows.length === 0 ? (
            <p>No buyer rewards recorded yet.</p>
          ) : (
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Buyer membership</th>
                    <th>Rewards</th>
                    <th>Total</th>
                    <th>Last reward</th>
                  </tr>
                </thead>
                <tbody>
                  {rewards.rows.map((row) => (
                    <tr key={row.buyer_user_id}>
                      <td><strong>{row.buyer_user_id}</strong></td>
                      <td>{row.reward_count}</td>
                      <td>{formatUsd(row.total_minor)}</td>
                      <td>{row.last_reward_at ?? "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {rewards.next && (
            <button onClick={() => void loadMore("rewards")} disabled={busy}>
              Load more reward ledgers
            </button>
          )}
        </>
      )}
      <div className="boundary">
        <strong>Separate ledgers</strong>
        <span>
          Seller HocaCredits, subscriptions and weekly targeting slots are separate
          from buyer rewards. Withdrawals, payouts, fee settlement and
          reconciliation are not connected to this view yet.
        </span>
      </div>
    </section>
  );
}

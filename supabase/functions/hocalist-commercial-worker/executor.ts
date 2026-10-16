// Provider-neutral payout execution cycle over the reviewed 183 state machine.
//
// The executor never decides a balance, never fabricates a success and never
// creates a replacement intent: each cycle expires stale leases, claims new
// intents whose identity is already persisted, reconciles unknown outcomes
// through the same key, and polls submitted attempts. Every item carries the
// attempt's immutable provider binding, and a worker only touches its own
// provider's attempts.
import {
  PayoutConfigurationError,
  PayoutProviderError,
  type PayoutProvider,
  type PayoutRequest,
  type PayoutResult,
} from "./payout_provider.ts";

export type CommercialRpc = (
  functionName: string,
  params: Record<string, unknown>,
) => Promise<Record<string, unknown>>;

export interface PayoutCycleDependencies {
  rpc: CommercialRpc;
  provider: PayoutProvider;
  claimLimit?: number;
  batchLimit?: number;
}

export interface PayoutCycleSummary {
  status: "completed";
  expired: number;
  claimed: number;
  submitted: number;
  succeeded: number;
  failed: number;
  review: number;
  deferred: number;
  polled: number;
  reconciled: number;
  foreignProvider: number;
  referenceMismatch: number;
}

const record = (value: unknown, field: string): Record<string, unknown> => {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`invalid_worker_response:${field}`);
  }
  return value as Record<string, unknown>;
};

const text = (value: unknown, field: string): string => {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`invalid_worker_response:${field}`);
  }
  return value;
};

const optionalText = (value: unknown, field: string): string | null => {
  if (value === null || value === undefined) return null;
  return text(value, field);
};

const integer = (value: unknown, field: string): number => {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error(`invalid_worker_response:${field}`);
  }
  return value;
};

const list = (value: unknown, field: string): unknown[] => {
  if (!Array.isArray(value)) throw new Error(`invalid_worker_response:${field}`);
  return value;
};

interface ClaimItem {
  attemptId: string;
  providerKey: string;
  request: PayoutRequest;
}

interface ReconcileItem {
  attemptId: string;
  providerKey: string;
  reference: string | null;
  request: PayoutRequest;
}

interface PollItem {
  attemptId: string;
  providerKey: string;
  reference: string;
}

function decodeClaimItem(value: unknown): ClaimItem {
  const item = record(value, "claim_item");
  return {
    attemptId: text(item.attempt_id, "attempt_id"),
    providerKey: text(item.provider_key, "provider_key"),
    request: {
      withdrawalId: text(item.withdrawal_id, "withdrawal_id"),
      requestKey: text(item.request_key, "request_key"),
      amountMinor: integer(item.amount_minor, "amount_minor"),
      feeMinor: integer(item.fee_minor, "fee_minor"),
      netMinor: integer(item.net_minor, "net_minor"),
      currency: text(item.currency, "currency"),
    },
  };
}

function decodeReconcileItem(value: unknown): ReconcileItem {
  const item = record(value, "reconcile_item");
  return {
    attemptId: text(item.attempt_id, "attempt_id"),
    providerKey: text(item.provider_key, "provider_key"),
    reference: optionalText(item.provider_reference, "provider_reference"),
    request: {
      withdrawalId: text(item.withdrawal_id, "withdrawal_id"),
      requestKey: text(item.request_key, "request_key"),
      amountMinor: integer(item.amount_minor, "amount_minor"),
      feeMinor: integer(item.fee_minor, "fee_minor"),
      netMinor: integer(item.net_minor, "net_minor"),
      currency: text(item.currency, "currency"),
    },
  };
}

function decodePollItem(value: unknown): PollItem {
  const item = record(value, "poll_item");
  return {
    attemptId: text(item.attempt_id, "attempt_id"),
    providerKey: text(item.provider_key, "provider_key"),
    reference: text(item.provider_reference, "provider_reference"),
  };
}

async function report(
  rpc: CommercialRpc,
  attemptId: string,
  result: PayoutResult,
): Promise<"succeeded" | "submitted" | "failed" | "review" | "referenceMismatch"> {
  if (result.state === "succeeded") {
    const settled = await rpc("payout_settle_internal", {
      p_attempt: attemptId,
      p_result: "succeeded",
      p_reference: result.reference,
      p_reason: null,
    });
    const status = text(settled.status, "settle_status");
    if (status === "succeeded") return "succeeded";
    if (status === "late_success_review" || status === "reconciliation_required") {
      return "review";
    }
    if (status === "reference_mismatch") return "referenceMismatch";
    throw new Error(`invalid_worker_response:settle_status:${status}`);
  }
  if (result.state === "pending") {
    const settled = await rpc("payout_settle_internal", {
      p_attempt: attemptId,
      p_result: "submitted",
      p_reference: result.reference,
      p_reason: null,
    });
    if (text(settled.status, "settle_status") !== "submitted") {
      throw new Error("invalid_worker_response:settle_status");
    }
    return "submitted";
  }
  const settled = await rpc("payout_settle_internal", {
    p_attempt: attemptId,
    p_result: "failed",
    p_reference: null,
    p_reason: result.reason,
  });
  if (text(settled.status, "settle_status") !== "failed") {
    throw new Error("invalid_worker_response:settle_status");
  }
  return "failed";
}

export async function runPayoutCycle(
  deps: PayoutCycleDependencies,
): Promise<PayoutCycleSummary> {
  const { rpc, provider } = deps;
  const claimLimit = deps.claimLimit ?? 10;
  const batchLimit = deps.batchLimit ?? 20;
  const summary: PayoutCycleSummary = {
    status: "completed",
    expired: 0,
    claimed: 0,
    submitted: 0,
    succeeded: 0,
    failed: 0,
    review: 0,
    deferred: 0,
    polled: 0,
    reconciled: 0,
    foreignProvider: 0,
    referenceMismatch: 0,
  };

  const expired = await rpc("payout_lease_expire_internal", { p_limit: batchLimit });
  summary.expired = integer(expired.expired ?? 0, "expired");

  const claim = await rpc("payout_claim_internal", {
    p_limit: claimLimit,
    p_runner: "commercial-worker",
  });
  const claimStatus = text(claim.status, "claim_status");
  if (claimStatus === "claimed") {
    const items = list(claim.items, "claim_items").map(decodeClaimItem);
    summary.claimed = items.length;
    for (const item of items) {
      if (item.providerKey !== provider.key) {
        // Never dispatch an intent through a provider the SQL policy did not
        // select. This is a configuration fault, not a per-item condition.
        throw new PayoutConfigurationError(
          `provider_key_mismatch:${item.providerKey}`,
        );
      }
      try {
        const result = await provider.submit(item.request);
        summary[await report(rpc, item.attemptId, result)] += 1;
      } catch (error) {
        if (error instanceof PayoutConfigurationError) throw error;
        if (error instanceof PayoutProviderError) {
          // No outcome was confirmed: the intent stays persisted and will be
          // reconciled through the same key on a later cycle.
          summary.deferred += 1;
          continue;
        }
        throw error;
      }
    }
  } else if (claimStatus !== "disabled" && claimStatus !== "skipped") {
    throw new Error(`invalid_worker_response:claim_status:${claimStatus}`);
  }

  // Reconcile unknown outcomes before any replacement could ever be written.
  const reconcile = await rpc("payout_reconcile_batch_internal", {
    p_limit: batchLimit,
  });
  const reconcileStatus = text(reconcile.status, "reconcile_status");
  if (reconcileStatus !== "ok") {
    throw new Error(`invalid_worker_response:reconcile_status:${reconcileStatus}`);
  }
  for (const item of list(reconcile.items, "reconcile_items").map(decodeReconcileItem)) {
    summary.reconciled += 1;
    if (item.providerKey !== provider.key) {
      summary.foreignProvider += 1;
      continue;
    }
    try {
      const result = item.reference === null
        ? await provider.submit(item.request)
        : await provider.poll(item.reference);
      summary[await report(rpc, item.attemptId, result)] += 1;
    } catch (error) {
      if (error instanceof PayoutConfigurationError) throw error;
      if (error instanceof PayoutProviderError) {
        summary.deferred += 1;
        continue;
      }
      throw error;
    }
  }

  // Poll submitted attempts. This continues even when new claims are disabled,
  // because an already-dispatched intent must still be settled.
  const poll = await rpc("payout_poll_batch_internal", { p_limit: batchLimit });
  const pollStatus = text(poll.status, "poll_status");
  if (pollStatus !== "ok") {
    throw new Error(`invalid_worker_response:poll_status:${pollStatus}`);
  }
  for (const item of list(poll.items, "poll_items").map(decodePollItem)) {
    summary.polled += 1;
    if (item.providerKey !== provider.key) {
      // A different provider's attempt is left untouched for its own worker.
      summary.foreignProvider += 1;
      continue;
    }
    try {
      const result = await provider.poll(item.reference);
      const outcome = await report(rpc, item.attemptId, result);
      if (outcome === "submitted") {
        summary.submitted += 1;
      } else {
        summary[outcome] += 1;
      }
    } catch (error) {
      if (error instanceof PayoutConfigurationError) throw error;
      if (error instanceof PayoutProviderError) {
        summary.deferred += 1;
        continue;
      }
      throw error;
    }
  }
  return summary;
}

// Executor proof with an injected fake provider. No real provider exists in
// this package: the fake scripts outcomes and records intents so the
// single-intent and no-fabrication invariants are testable locally.
import { deepStrictEqual, rejects, strictEqual } from "node:assert/strict";
import { runPayoutCycle, type CommercialRpc } from "./executor.ts";
import {
  PayoutConfigurationError,
  PayoutProviderError,
  type PayoutProvider,
  type PayoutRequest,
  type PayoutResult,
} from "./payout_provider.ts";

interface Intent {
  state: "accepted" | "succeeded" | "failed";
  reference: string;
}

class FakeProvider implements PayoutProvider {
  readonly key: string;
  readonly intents = new Map<string, Intent>();
  readonly submissions: string[] = [];
  readonly polls: string[] = [];
  dropNextResponse = false;
  private submitResult: PayoutResult | null = null;
  private pollResult: PayoutResult | null = null;

  constructor(key = "fake_payout") {
    this.key = key;
  }

  setSubmitResult(result: PayoutResult | null): void {
    this.submitResult = result;
  }

  setPollResult(result: PayoutResult | null): void {
    this.pollResult = result;
  }

  submit(request: PayoutRequest): Promise<PayoutResult> {
    this.submissions.push(request.requestKey);
    let intent = this.intents.get(request.requestKey);
    if (!intent) {
      intent = { state: "accepted", reference: `ref-${this.intents.size + 1}` };
      this.intents.set(request.requestKey, intent);
    }
    if (this.dropNextResponse) {
      this.dropNextResponse = false;
      return Promise.reject(new PayoutProviderError("timeout_after_acceptance"));
    }
    if (this.submitResult) return Promise.resolve(this.submitResult);
    return Promise.resolve({ state: "pending", reference: intent.reference });
  }

  poll(reference: string): Promise<PayoutResult> {
    this.polls.push(reference);
    if (this.pollResult) return Promise.resolve(this.pollResult);
    const intent = [...this.intents.values()].find((i) => i.reference === reference);
    if (!intent) return Promise.reject(new PayoutProviderError("unknown_reference"));
    if (intent.state === "accepted") {
      return Promise.resolve({ state: "pending", reference });
    }
    if (intent.state === "succeeded") {
      return Promise.resolve({ state: "succeeded", reference });
    }
    return Promise.resolve({ state: "failed", reason: "provider_failed" });
  }

  settleIntent(reference: string): void {
    const intent = [...this.intents.values()].find((i) => i.reference === reference);
    if (intent) intent.state = "succeeded";
  }
}

interface ScriptedRpc extends CommercialRpc {
  calls: { functionName: string; params: Record<string, unknown> }[];
}

function scriptedRpc(
  responses: Record<
    string,
    Record<string, unknown> | (() => Record<string, unknown>)
  >,
  settleResults: Record<string, unknown>[] = [{ status: "succeeded" }],
): ScriptedRpc {
  const calls: ScriptedRpc["calls"] = [];
  const rpc: ScriptedRpc = async (functionName, params) => {
    calls.push({ functionName, params });
    if (functionName === "payout_settle_internal") {
      const next = settleResults.shift();
      if (!next) throw new Error("unexpected settle call");
      return next;
    }
    const response = responses[functionName];
    if (!response) throw new Error(`unexpected rpc ${functionName}`);
    return typeof response === "function" ? response() : response;
  };
  rpc.calls = calls;
  return rpc;
}

const claimItem = {
  withdrawal_id: "w-1",
  attempt_id: "a-1",
  attempt: 1,
  request_key: "w-1",
  provider_key: "fake_payout",
  currency: "USD",
  amount_minor: 3000,
  fee_minor: 250,
  net_minor: 2750,
};

const emptyPoll = { status: "ok", provider_key: "fake_payout", items: [] };
const emptyReconcile = { status: "ok", provider_key: "fake_payout", items: [] };
const disabledClaim = {
  status: "disabled",
  provider_configured: false,
  execution_enabled: false,
  items: [],
};

const settleParams = (rpc: ScriptedRpc) =>
  rpc.calls
    .filter((call) => call.functionName === "payout_settle_internal")
    .map((call) => call.params);

Deno.test("executor: a disabled claim never calls the provider", async () => {
  const provider = new FakeProvider();
  const rpc = scriptedRpc({
    payout_lease_expire_internal: { status: "expired", expired: 0 },
    payout_claim_internal: disabledClaim,
    payout_reconcile_batch_internal: emptyReconcile,
    payout_poll_batch_internal: emptyPoll,
  });
  const summary = await runPayoutCycle({ rpc, provider });
  strictEqual(summary.claimed, 0);
  strictEqual(summary.succeeded, 0);
  strictEqual(provider.submissions.length, 0);
  strictEqual(provider.polls.length, 0);
});

Deno.test("executor: the real SQL claim shape decodes and settles once", async () => {
  const provider = new FakeProvider();
  provider.setSubmitResult({ state: "succeeded", reference: "transfer_1" });
  const rpc = scriptedRpc(
    {
      payout_lease_expire_internal: { status: "expired", expired: 0 },
      payout_claim_internal: {
        status: "claimed",
        claimed: 1,
        provider_key: "fake_payout",
        items: [claimItem],
      },
      payout_reconcile_batch_internal: emptyReconcile,
      payout_poll_batch_internal: emptyPoll,
    },
    [{ status: "succeeded" }],
  );
  const summary = await runPayoutCycle({ rpc, provider });
  strictEqual(summary.succeeded, 1);
  deepStrictEqual(provider.submissions, ["w-1"]);
  deepStrictEqual(settleParams(rpc), [
    { p_attempt: "a-1", p_result: "succeeded", p_reference: "transfer_1", p_reason: null },
  ]);
});

Deno.test("executor: a submitted attempt is polled and provider-bound", async () => {
  const provider = new FakeProvider();
  provider.setPollResult({ state: "succeeded", reference: "ref-pending" });
  const rpc = scriptedRpc(
    {
      payout_lease_expire_internal: { status: "expired", expired: 0 },
      payout_claim_internal: disabledClaim,
      payout_reconcile_batch_internal: emptyReconcile,
      payout_poll_batch_internal: {
        status: "ok",
        provider_key: "fake_payout",
        items: [{
          attempt_id: "a-2",
          withdrawal_id: "w-2",
          attempt: 1,
          request_key: "w-2",
          provider_key: "fake_payout",
          provider_reference: "ref-pending",
        }],
      },
    },
    [{ status: "succeeded" }],
  );
  const summary = await runPayoutCycle({ rpc, provider });
  strictEqual(summary.polled, 1);
  strictEqual(summary.succeeded, 1);
  deepStrictEqual(provider.polls, ["ref-pending"]);
});

Deno.test("executor: foreign provider attempts are never polled or settled", async () => {
  const provider = new FakeProvider("provider_b");
  const rpc = scriptedRpc({
    payout_lease_expire_internal: { status: "expired", expired: 0 },
    payout_claim_internal: disabledClaim,
    payout_reconcile_batch_internal: {
      status: "ok",
      provider_key: "provider_b",
      items: [{
        attempt_id: "a-foreign",
        withdrawal_id: "w-f",
        attempt: 1,
        request_key: "w-f",
        provider_key: "provider_a",
        provider_reference: "provider_a_reference",
        currency: "USD",
        amount_minor: 2000,
        fee_minor: 250,
        net_minor: 1750,
      }],
    },
    payout_poll_batch_internal: {
      status: "ok",
      provider_key: "provider_b",
      items: [{
        attempt_id: "a-foreign",
        withdrawal_id: "w-f",
        attempt: 1,
        request_key: "w-f",
        provider_key: "provider_a",
        provider_reference: "provider_a_reference",
      }],
    },
  });
  const summary = await runPayoutCycle({ rpc, provider });
  strictEqual(summary.foreignProvider, 2);
  strictEqual(summary.reconciled, 1);
  strictEqual(summary.polled, 1);
  strictEqual(summary.succeeded, 0);
  strictEqual(provider.polls.length, 0);
  strictEqual(settleParams(rpc).length, 0);
});

Deno.test("executor: a mismatched claim provider is a configuration fault", async () => {
  const provider = new FakeProvider("different_provider");
  const rpc = scriptedRpc({
    payout_lease_expire_internal: { status: "expired", expired: 0 },
    payout_claim_internal: {
      status: "claimed",
      claimed: 1,
      provider_key: "fake_payout",
      items: [claimItem],
    },
    payout_reconcile_batch_internal: emptyReconcile,
    payout_poll_batch_internal: emptyPoll,
  });
  await rejects(() => runPayoutCycle({ rpc, provider }), PayoutConfigurationError);
  strictEqual(provider.submissions.length, 0);
  strictEqual(settleParams(rpc).length, 0);
});

Deno.test("executor: an accepted-but-lost response reconciles the same intent", async () => {
  const provider = new FakeProvider();
  let leaseExpired = false;
  let attemptExists = false;
  let attemptState = "reserved";
  const rpc = scriptedRpc(
    {
      payout_lease_expire_internal: () => {
        if (attemptExists && !leaseExpired && attemptState === "reserved") {
          leaseExpired = true;
          attemptState = "outcome_unknown";
          return { status: "expired", expired: 1 };
        }
        return { status: "expired", expired: 0 };
      },
      payout_claim_internal: () => {
        if (!attemptExists) attemptExists = true;
        if (attemptState === "reserved" && !leaseExpired) {
          return {
            status: "claimed",
            claimed: 1,
            provider_key: "fake_payout",
            items: [claimItem],
          };
        }
        return { status: "claimed", claimed: 0, provider_key: "fake_payout", items: [] };
      },
      payout_reconcile_batch_internal: () =>
        attemptState === "outcome_unknown"
          ? {
            status: "ok",
            provider_key: "fake_payout",
            items: [{
              attempt_id: "a-1",
              withdrawal_id: "w-1",
              attempt: 1,
              request_key: "w-1",
              provider_key: "fake_payout",
              provider_reference: null,
              currency: "USD",
              amount_minor: 3000,
              fee_minor: 250,
              net_minor: 2750,
            }],
          }
          : emptyReconcile,
      payout_poll_batch_internal: emptyPoll,
    },
    [{ status: "succeeded" }],
  );

  // Cycle 1: the provider accepts the intent but the response is lost. The
  // attempt stays reserved with the immutable key already persisted.
  provider.dropNextResponse = true;
  const first = await runPayoutCycle({ rpc, provider });
  strictEqual(first.deferred, 1);
  strictEqual(provider.intents.size, 1);
  deepStrictEqual(provider.submissions, ["w-1"]);

  // Lease expiry authorizes reconciliation, not replacement. The provider
  // dedupes by key and returns the original (already accepted) outcome.
  provider.setSubmitResult({ state: "succeeded", reference: "ref-1" });
  const second = await runPayoutCycle({ rpc, provider });
  strictEqual(second.expired, 1);
  strictEqual(second.reconciled, 1);
  strictEqual(second.succeeded, 1);
  // The same key was resubmitted; the provider still has exactly one intent.
  deepStrictEqual(provider.submissions, ["w-1", "w-1"]);
  strictEqual(provider.intents.size, 1);
  deepStrictEqual(settleParams(rpc), [
    { p_attempt: "a-1", p_result: "succeeded", p_reference: "ref-1", p_reason: null },
  ]);
});

Deno.test("executor: a provider transport failure leaves the intent untouched", async () => {
  const provider = new FakeProvider();
  provider.setSubmitResult(null);
  provider.dropNextResponse = true;
  const rpc = scriptedRpc({
    payout_lease_expire_internal: { status: "expired", expired: 0 },
    payout_claim_internal: {
      status: "claimed",
      claimed: 1,
      provider_key: "fake_payout",
      items: [claimItem],
    },
    payout_reconcile_batch_internal: emptyReconcile,
    payout_poll_batch_internal: emptyPoll,
  });
  const summary = await runPayoutCycle({ rpc, provider });
  strictEqual(summary.deferred, 1);
  strictEqual(summary.succeeded, 0);
  strictEqual(summary.failed, 0);
  strictEqual(settleParams(rpc).length, 0);
});

Deno.test("executor: a late success is accepted as review, never a second payout", async () => {
  const provider = new FakeProvider();
  provider.setPollResult({ state: "succeeded", reference: "ref-late" });
  const rpc = scriptedRpc(
    {
      payout_lease_expire_internal: { status: "expired", expired: 0 },
      payout_claim_internal: disabledClaim,
      payout_reconcile_batch_internal: emptyReconcile,
      payout_poll_batch_internal: {
        status: "ok",
        provider_key: "fake_payout",
        items: [{
          attempt_id: "a-3",
          withdrawal_id: "w-3",
          attempt: 1,
          request_key: "w-3",
          provider_key: "fake_payout",
          provider_reference: "ref-late",
        }],
      },
    },
    [{ status: "late_success_review" }],
  );
  const summary = await runPayoutCycle({ rpc, provider });
  strictEqual(summary.review, 1);
  strictEqual(summary.succeeded, 0);
});

Deno.test("executor: a reference mismatch is counted, not paid", async () => {
  const provider = new FakeProvider();
  provider.setPollResult({ state: "succeeded", reference: "different-transfer" });
  const rpc = scriptedRpc(
    {
      payout_lease_expire_internal: { status: "expired", expired: 0 },
      payout_claim_internal: disabledClaim,
      payout_reconcile_batch_internal: emptyReconcile,
      payout_poll_batch_internal: {
        status: "ok",
        provider_key: "fake_payout",
        items: [{
          attempt_id: "a-4",
          withdrawal_id: "w-4",
          attempt: 1,
          request_key: "w-4",
          provider_key: "fake_payout",
          provider_reference: "original-transfer",
        }],
      },
    },
    [{ status: "reference_mismatch" }],
  );
  const summary = await runPayoutCycle({ rpc, provider });
  strictEqual(summary.referenceMismatch, 1);
  strictEqual(summary.succeeded, 0);
  strictEqual(summary.review, 0);
});

Deno.test("executor: an unknown worker response fails loudly", async () => {
  const provider = new FakeProvider();
  const rpc = scriptedRpc({
    payout_lease_expire_internal: { status: "expired", expired: 0 },
    payout_claim_internal: { status: "mystery" },
    payout_reconcile_batch_internal: emptyReconcile,
    payout_poll_batch_internal: emptyPoll,
  });
  await rejects(
    () => runPayoutCycle({ rpc, provider }),
    { message: /invalid_worker_response/ },
  );
  strictEqual(provider.submissions.length, 0);
});

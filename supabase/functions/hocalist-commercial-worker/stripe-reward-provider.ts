import { stripeSandboxClient } from "../_shared/stripe-reward-client.ts";
import type { CommercialRpc } from "./executor.ts";
import type { PayoutProvider, PayoutResult } from "./payout_provider.ts";

export function stripeRewardProvider(
  secret: string,
  financialAccount: string,
  rpc: CommercialRpc,
  fetcher: typeof fetch,
): PayoutProvider {
  const stripe = stripeSandboxClient(secret, fetcher);
  function result(
    intent: { id: string; status: string; livemode?: boolean },
  ): PayoutResult {
    if (intent.livemode === true || !/^poi_[a-zA-Z0-9_]+$/.test(intent.id)) {
      throw Error("unexpected_payout_intent");
    }
    if (intent.status === "posted") {
      return { state: "succeeded", reference: intent.id };
    }
    if (intent.status === "canceled") {
      return { state: "failed", reason: "Stripe canceled the payout" };
    }
    return { state: "pending", reference: intent.id };
  }
  return {
    key: "stripe_global_sandbox",
    async submit(request) {
      const dest = await rpc("stripe_reward_destination_internal", {
        p_withdrawal: request.withdrawalId,
        p_environment: "sandbox",
      });
      const age = Date.now() - Date.parse(String(dest.created_at));
      // Do not replay ambiguous old submissions outside the idempotency window.
      if (!Number.isFinite(age) || age < 0 || age >= 86400000) {
        throw Error("review_payout_before_retry");
      }
      if (
        typeof dest.recipient !== "string" ||
        !/^acct_[a-zA-Z0-9]+$/.test(dest.recipient) ||
        request.currency.toUpperCase() !== "USD" ||
        !Number.isSafeInteger(request.netMinor) || request.netMinor <= 0
      ) {
        throw Error("invalid_payout_destination_or_amount");
      }
      const intent = await stripe("money_management/payout_intents", {
        from: { financial_account: financialAccount, currency: "usd" },
        to: {
          recipient: dest.recipient,
          payout_method_options: {
            bank_account: { preferred_networks: ["ach"] },
          },
        },
        amount: { value: request.netMinor, currency: "usd" },
        description: "Hocalist buyer reward",
      }, "hocalist-reward-" + request.requestKey);
      return result(intent);
    },
    async poll(reference) {
      if (!/^poi_[a-zA-Z0-9_]+$/.test(reference)) {
        throw Error("invalid_payout_reference");
      }
      return result(
        await stripe("money_management/payout_intents/" + reference),
      );
    },
  };
}

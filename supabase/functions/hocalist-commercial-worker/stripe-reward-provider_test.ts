import {
  deepStrictEqual,
  rejects,
  strictEqual,
  throws,
} from "node:assert/strict";
import { stripeRewardProvider } from "./stripe-reward-provider.ts";
const req = {
  withdrawalId: "withdraw1",
  requestKey: "withdraw1",
  amountMinor: 1200,
  feeMinor: 100,
  netMinor: 1100,
  currency: "USD",
};
Deno.test("Stripe sandbox sends net amount to server-bound buyer and reuses the withdrawal key", async () => {
  const calls: RequestInit[] = [];
  const provider = stripeRewardProvider(
    "sk_test_example",
    "fa_test_funds",
    async (_name, params) => {
      strictEqual(params.p_withdrawal, "withdraw1");
      return { recipient: "acct_test1", created_at: new Date().toISOString() };
    },
    async (_url, init) => {
      calls.push(init!);
      return Response.json({
        id: "poi_test1",
        status: "pending",
        livemode: false,
      });
    },
  );
  await provider.submit(req);
  await provider.submit(req);
  for (const call of calls) {
    const b = JSON.parse(String(call.body));
    strictEqual(b.to.recipient, "acct_test1");
    deepStrictEqual(b.amount, { value: 1100, currency: "usd" });
    strictEqual(
      new Headers(call.headers).get("Idempotency-Key"),
      "hocalist-reward-withdraw1",
    );
  }
});
Deno.test("Sandbox rejects live keys and refuses to replay a stale intent", async () => {
  throws(() =>
    stripeRewardProvider("sk_live_example", "fa_test", async () => ({}), fetch)
  );
  const provider = stripeRewardProvider(
    "sk_test_example",
    "fa_test",
    async () => ({ recipient: "acct_test1", created_at: "2020-01-01" }),
    () => {
      throw Error("unexpected dispatch");
    },
  );
  await rejects(provider.submit(req), /review_payout_before_retry/);
});

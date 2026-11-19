import assert from "node:assert/strict";
import { offerFundingHandler } from "./handler.ts";
import type { Backend } from "../_shared/stripe-test-billing.ts";
const config = {
  enabled: true,
  success: "https://hocalist.com/billing/return",
  cancel: "https://hocalist.com/billing",
};
for (const saved of [true, false]) {
  Deno.test(
    "offer funding reads only the signed-in seller card: " + saved,
    async () => {
      const writes: unknown[] = [];
      const api = {
        user: async () => "seller",
        userEmail: () => undefined,
        rpc: async (name: string, args: Record<string, unknown>) => {
          if (name === "paygo_customer") {
            return { customer_id: "cus_Test", membership_id: "member" };
          }
          if (name === "paygo_card_context") {
            return null;
          }
          if (name === "paygo_authorize_saved_card") {
            writes.push(args);
            return null;
          }
          throw Error(name);
        },
        stripe: async (path: string) => {
          if (path === "account") return { id: "acct_1Le6hqDmHEV44E5Y" };
          if (path === "customers/cus_Test") {
            return { id: "cus_Test", livemode: false, invoice_settings: {} };
          }
          if (path === "payment_methods?type=card&limit=1&customer=cus_Test") {
            return {
              data: saved
                ? [{
                  id: "pm_Test",
                  customer: "cus_Test",
                  type: "card",
                  livemode: false,
                  card: { brand: "visa", last4: "4242" },
                }]
                : [],
            };
          }
          throw Error(path);
        },
      };
      const handler = offerFundingHandler(api as Backend, config);
      const call = (body: Record<string, unknown>) =>
        handler(
          new Request("https://example.test", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Origin: "http://localhost:7359",
            },
            body: JSON.stringify(body),
          }),
        );
      const view = await (await call({ operation: "inspect" })).json();
      assert.equal(view.card?.last4, saved ? "4242" : undefined);
      const consent = {
        operation: "authorize",
        method: "pm_Test",
        idempotency_key: crypto.randomUUID(),
        consent_version: "paygo-v1",
      };
      assert.equal(
        (await call({ ...consent, consent_version: null })).status,
        400,
      );
      assert.equal(
        (await call({ ...consent, method: "pm_Other" })).status,
        409,
      );
      assert.equal((await call(consent)).status, saved ? 200 : 409);
      assert.equal(writes.length, saved ? 1 : 0);
    },
  );
}

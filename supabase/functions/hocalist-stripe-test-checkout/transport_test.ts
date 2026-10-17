import { strict as assert } from "node:assert";
import { ACCOUNT, backend, PROJECT } from "../_shared/stripe-test-billing.ts";
import { createCheckoutHandler } from "./handler.ts";

for (const knownCustomer of [false, true]) {
Deno.test(`checkout prefills the verified email for ${knownCustomer ? 'existing' : 'new'} customers and accepts void acknowledgements`, async () => {
  const names = [
    "SUPABASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
    "HOCALIST_STRIPE_TEST_API_KEY",
  ];
  const saved = names.map((name) => Deno.env.get(name));
  const originalFetch = globalThis.fetch;
  const checkout = "2f0c9d1a-0000-4000-8000-000000000003";
  const calls: string[] = [];
  try {
    Deno.env.set(names[0], PROJECT);
    Deno.env.set(names[1], "synthetic-service-key");
    Deno.env.set(names[2], "rk_test_synthetic");
    globalThis.fetch = (input, init) => {
      const url = String(input);
      const path = new URL(url).pathname;
      calls.push(path);
      const reply = (body: unknown) => Promise.resolve(Response.json(body));
      if (path === "/auth/v1/user") return reply({ id: "test-user", email: "seller@example.test", email_confirmed_at: "2026-10-17T00:00:00Z" });
      if (path === "/v1/account") return reply({ id: ACCOUNT });
      if (path === "/rest/v1/rpc/stripe_test_deposit_begin") {
        return reply({
          checkout_id: checkout,
          membership_id: "test-membership",
          customer_id: knownCustomer ? "cus_test1" : null,
          amount_minor: 2000,
          expires_at: 1900000000,
          session_id: null,
        });
      }
      if (path === (knownCustomer ? "/v1/customers/cus_test1" : "/v1/customers")) {
        assert.equal(new URLSearchParams(String((init as { body?: unknown })?.body)).get("email"), "seller@example.test");
        return reply({ id: "cus_test1", livemode: false });
      }
      if (path === "/rest/v1/rpc/stripe_test_deposit_bind") {
        assert.equal((init as { method?: string })?.method, "POST");
        return Promise.resolve(new Response(null, { status: 204 }));
      }
      if (path === "/v1/checkout/sessions") {
        return reply({
          id: "cs_test_session1",
          livemode: false,
          url: "https://checkout.stripe.com/c/pay/test",
        });
      }
      throw new Error(`Unexpected synthetic request: ${path}`);
    };
    const response = await createCheckoutHandler(backend(), {
      enabled: true,
      success: "https://hocalist.com/billing/return",
      cancel: "https://hocalist.com/billing/cancel",
    })(
      new Request("https://example.invalid/checkout", {
        method: "POST",
        headers: {
          Authorization: "Bearer synthetic",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          kind: "credit_deposit",
          option_id: "2f0c9d1a-0000-4000-8000-000000000002",
          idempotency_key: "2f0c9d1a-0000-4000-8000-000000000001",
        }),
      }),
    );
    assert.equal(response.status, 200);
    assert.equal(calls.filter((path) => path === "/auth/v1/user").length, 1);
    assert.deepEqual(await response.json(), {
      checkout_id: checkout,
      url: "https://checkout.stripe.com/c/pay/test",
    });
    assert.equal(
      calls.filter((path) => path.endsWith("stripe_test_deposit_bind")).length,
      knownCustomer ? 1 : 2,
    );
    assert.equal(
      calls.filter((path) => path === "/v1/checkout/sessions").length,
      1,
    );
  } finally {
    globalThis.fetch = originalFetch;
    names.forEach((name, index) =>
      saved[index] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, saved[index]!)
    );
  }
});
}

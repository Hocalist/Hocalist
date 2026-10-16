// Hosted billing-portal handler tests with an injected database and provider:
// no Stripe key, no live call, no real customer.
import { strict as assert } from "node:assert";
import { ACCOUNT, type Backend, BillingError, type ObjectMap } from "../_shared/stripe-test-billing.ts";
import { createPortalHandler } from "./handler.ts";

const USER = "00000000-0000-4000-8000-00000000000a";

class FakeBackend {
  calls: { rpc: Array<{ name: string; body: ObjectMap }>; stripe: Array<{ path: string; params?: Record<string, string> }> } =
    { rpc: [], stripe: [] };
  userResult: string | Error = USER;
  access: unknown = {
    membership_id: "10000000-0000-4000-8000-00000000000a",
    customer_id: "cus_testportal1",
    requires_review: false,
  };
  portal: ObjectMap = {
    id: "bps_test1",
    livemode: false,
    url: "https://billing.stripe.com/p/session/test_portal",
  };

  async user(): Promise<string> {
    if (this.userResult instanceof Error) throw this.userResult;
    return this.userResult;
  }

  async rpc(name: string, body: ObjectMap = {}): Promise<unknown> {
    this.calls.rpc.push({ name, body });
    if (name !== "stripe_test_portal_access") throw new Error(`unexpected rpc ${name}`);
    if (this.access instanceof Error) throw this.access;
    return this.access;
  }

  async stripe(path: string, params?: Record<string, string>): Promise<ObjectMap> {
    this.calls.stripe.push({ path, params });
    if (path === "account") return { id: ACCOUNT, livemode: false };
    if (path === "billing_portal/sessions") {
      if (this.portal instanceof Error) throw this.portal;
      return this.portal;
    }
    throw new Error(`unexpected stripe ${path}`);
  }

  asBackend(): Backend {
    return this as unknown as Backend;
  }
}

const config = {
  enabled: true,
  origin: "https://hocalist.com",
  returnPaths: ["/billing", "/billing/return"],
};

const post = (body: unknown, method = "POST") =>
  new Request("http://localhost/portal", {
    method,
    headers: { "Content-Type": "application/json" },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });

Deno.test("portal returns a hosted session for the authenticated customer", async () => {
  const api = new FakeBackend();
  const response = await createPortalHandler(api.asBackend(), config)(post({ return_path: "/billing/return" }));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { url: "https://billing.stripe.com/p/session/test_portal" });
  const created = api.calls.stripe.find((call) => call.path === "billing_portal/sessions");
  assert.equal(created?.params?.customer, "cus_testportal1");
  assert.equal(created?.params?.return_url, "https://hocalist.com/billing/return");
  assert.equal(api.calls.rpc[0].body.p_user, USER);
});

Deno.test("portal refuses a forbidden return path or malformed body", async () => {
  const api = new FakeBackend();
  const handler = createPortalHandler(api.asBackend(), config);
  for (const body of [{ return_path: "https://evil.example/steal" }, { return_path: "/admin" }, { extra: true }]) {
    const response = await handler(post(body));
    assert.equal(response.status, 400);
  }
  assert.equal(api.calls.stripe.length, 0);
});

Deno.test("portal reports signed-out, forbidden, review and missing customer states", async () => {
  const signedOut = new FakeBackend();
  signedOut.userResult = new BillingError("authentication_required", 401);
  assert.equal((await createPortalHandler(signedOut.asBackend(), config)(post({}))).status, 401);

  const forbidden = new FakeBackend();
  forbidden.access = new BillingError("billing_access_denied", 403);
  assert.deepEqual(
    await (await createPortalHandler(forbidden.asBackend(), config)(post({}))).json(),
    { error: "billing_access_denied" },
  );

  const review = new FakeBackend();
  review.access = {
    membership_id: "10000000-0000-4000-8000-00000000000a",
    customer_id: null,
    requires_review: true,
  };
  const reviewResponse = await createPortalHandler(review.asBackend(), config)(post({}));
  assert.equal(reviewResponse.status, 403);
  assert.deepEqual(await reviewResponse.json(), { error: "billing_review_required" });
  assert.equal(review.calls.stripe.some((call) => call.path === "billing_portal/sessions"), false);

  const unmapped = new FakeBackend();
  unmapped.access = { membership_id: "10000000-0000-4000-8000-00000000000a", customer_id: null, requires_review: false };
  const unmappedResponse = await createPortalHandler(unmapped.asBackend(), config)(post({}));
  assert.equal(unmappedResponse.status, 409);
  assert.deepEqual(await unmappedResponse.json(), { error: "customer_unavailable" });
});

Deno.test("portal never forwards a live-mode or foreign provider URL", async () => {
  const live = new FakeBackend();
  live.portal = { id: "bps_live", livemode: true, url: "https://billing.stripe.com/p/session/live" };
  assert.equal((await createPortalHandler(live.asBackend(), config)(post({}))).status, 503);

  const foreign = new FakeBackend();
  foreign.portal = { id: "bps_test2", livemode: false, url: "https://evil.example/session" };
  assert.equal((await createPortalHandler(foreign.asBackend(), config)(post({}))).status, 503);
});

Deno.test("portal is unavailable when disabled and rejects other methods", async () => {
  const api = new FakeBackend();
  const disabled = createPortalHandler(api.asBackend(), { ...config, enabled: false });
  assert.equal((await disabled(post({}))).status, 503);
  const enabled = createPortalHandler(api.asBackend(), config);
  assert.equal((await enabled(post({}, "GET"))).status, 405);
});

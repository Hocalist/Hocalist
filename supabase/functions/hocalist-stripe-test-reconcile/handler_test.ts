// Reconciliation dispatch tests with an injected database and provider: no
// Stripe key, no live call. Classification comes from the stored
// session/checkout binding: a paid deposit credits exactly one batch, and
// missing, altered or contradictory classification quarantines visibly instead
// of silently consuming the event.
import { strict as assert } from "node:assert";
import { ACCOUNT, type Backend, type ObjectMap } from "../_shared/stripe-test-billing.ts";
import { authorizedBySecret, createReconcileHandler } from "./handler.ts";

const CUSTOMER = "cus_testdeposit1";
const MEMBERSHIP = "10000000-0000-4000-8000-00000000000a";
const CHECKOUT = "2f0c9d1a-0000-4000-8000-000000000003";
const EVENT = "evt_deposit1";
const SESSION = "cs_test_deposit1";
const TOKEN = "2f0c9d1a-0000-4000-8000-00000000000f";

type Call = { name: string; body: ObjectMap };

class FakeBackend {
  rpcCalls: Call[] = [];
  stripeCalls: string[] = [];
  claim: unknown = {
    token: TOKEN, event_id: EVENT,
    event_type: "checkout.session.completed", object_id: SESSION,
  };
  event: ObjectMap = {};
  session: ObjectMap = {};
  context: unknown = null;
  depositResult: unknown = { status: "complete", checkout_id: CHECKOUT, batch_id: "b".repeat(8) };
  depositCalls: Call[] = [];
  finishCalls: Call[] = [];

  async user(): Promise<string> {
    throw new Error("not used");
  }

  async rpc(name: string, body: ObjectMap = {}): Promise<unknown> {
    this.rpcCalls.push({ name, body });
    if (name === "stripe_test_claim") return this.claim;
    if (name === "website_checkout_context") {
      if (this.context instanceof Error) throw this.context;
      return this.context;
    }
    if (name === "stripe_test_deposit_finish") {
      this.depositCalls.push({ name, body });
      if (this.depositResult instanceof Error) throw this.depositResult;
      return this.depositResult;
    }
    if (name === "stripe_test_finish") {
      this.finishCalls.push({ name, body });
      return null;
    }
    throw new Error(`unexpected rpc ${name}`);
  }

  async stripe(path: string): Promise<ObjectMap> {
    this.stripeCalls.push(path);
    if (path === "account") return { id: ACCOUNT, livemode: false };
    if (path.startsWith("events/")) return this.event;
    if (path.startsWith("checkout/sessions/")) return this.session;
    if (path.startsWith("subscriptions?")) return { data: [], has_more: false };
    throw new Error(`unexpected stripe ${path}`);
  }

  asBackend(): Backend {
    return this as unknown as Backend;
  }
}

const claimOf = (type: string, objectId: string) => ({
  token: TOKEN, event_id: EVENT, event_type: type, object_id: objectId,
});

const eventOf = (type: string, objectId: string, changes: ObjectMap = {}): ObjectMap => ({
  id: EVENT, object: "event", livemode: false,
  created: Math.floor(Date.now() / 1000), type,
  data: { object: { id: objectId, livemode: false, customer: CUSTOMER } },
  ...changes,
});

const depositSession = (changes: ObjectMap = {}): ObjectMap => ({
  id: SESSION,
  livemode: false,
  customer: CUSTOMER,
  mode: "payment",
  status: "complete",
  payment_status: "paid",
  amount_total: 2000,
  currency: "usd",
  payment_intent: "pi_testdeposit1",
  metadata: {
    app: "hocalist",
    kind: "credit_deposit",
    checkout_id: CHECKOUT,
    membership_id: MEMBERSHIP,
  },
  ...changes,
});

const storedCheckout = (changes: ObjectMap = {}): ObjectMap => ({
  id: CHECKOUT, kind: "credit_deposit", state: "open", session_id: SESSION,
  plan_code: null, price_id: null, amount_minor: 2000, option_id: null,
  credit_batch_id: null, provider_reference: null,
  ...changes,
});

const contextOf = (options: { checkouts?: ObjectMap[]; membership?: string } = {}) => ({
  membership_id: options.membership ?? MEMBERSHIP,
  requires_review: false,
  plans: [],
  checkouts: options.checkouts ?? [storedCheckout()],
});

function handler(api: FakeBackend) {
  return createReconcileHandler({
    authorized: async (request) => request.headers.get("Authorization") === "Bearer synthetic-worker-secret",
    api: api.asBackend(),
  });
}

const post = (authorized = true) =>
  new Request("http://localhost/reconcile", {
    method: "POST",
    headers: authorized ? { Authorization: "Bearer synthetic-worker-secret" } : {},
  });

function depositApi(): FakeBackend {
  const api = new FakeBackend();
  api.event = eventOf("checkout.session.completed", SESSION);
  api.session = depositSession();
  api.context = contextOf();
  return api;
}

Deno.test("a verified paid deposit event credits exactly one batch", async () => {
  const api = depositApi();
  const response = await handler(api)(post());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: "deposit_credited", granted: true, checkout_id: CHECKOUT,
    batch_id: "b".repeat(8), event_id: EVENT,
  });
  assert.deepEqual(api.depositCalls, [{
    name: "stripe_test_deposit_finish",
    body: { p_checkout: CHECKOUT, p_customer: CUSTOMER, p_paid_amount: 2000, p_reference: "pi_testdeposit1" },
  }]);
  const finish = api.finishCalls.find((call) => call.body.p_error === undefined || call.body.p_error === null);
  assert.equal(finish?.body.p_snapshot, null);
  assert.equal(finish?.body.p_token, TOKEN);
});

Deno.test("an altered amount quarantines the checkout without crediting", async () => {
  const api = depositApi();
  api.session = depositSession({ amount_total: 1900 });
  const response = await handler(api)(post());
  assert.equal(response.status, 503);
  assert.equal(api.depositCalls[0].body.p_error, "review_required");
  assert.equal(api.depositCalls[0].body.p_reference, null);
  const finish = api.finishCalls[0];
  assert.equal(finish.body.p_error, "review_required");
  assert.equal(finish.body.p_snapshot, null);
});

Deno.test("missing classification metadata on a bound paid deposit quarantines it", async () => {
  const api = depositApi();
  api.session = depositSession({ metadata: {} });
  const response = await handler(api)(post());
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "billing_unavailable" });
  assert.equal(api.depositCalls[0].body.p_error, "review_required", "no credit is granted");
  assert.equal(api.finishCalls[0].body.p_error, "review_required", "the receipt is not silently consumed");
});

Deno.test("altered or contradictory classification quarantines instead of falling through", async () => {
  const altered = depositApi();
  altered.session = depositSession({
    metadata: { app: "hocalist", kind: "not_a_kind", checkout_id: CHECKOUT, membership_id: MEMBERSHIP },
  });
  assert.equal((await handler(altered)(post())).status, 503);
  assert.equal(altered.depositCalls[0].body.p_error, "review_required");

  const wrongMembership = depositApi();
  wrongMembership.session = depositSession({
    metadata: { app: "hocalist", kind: "credit_deposit", checkout_id: CHECKOUT, membership_id: "other-membership" },
  });
  assert.equal((await handler(wrongMembership)(post())).status, 503);
  assert.equal(wrongMembership.depositCalls[0].body.p_error, "review_required");

  const wrongMode = depositApi();
  wrongMode.session = depositSession({ mode: "subscription" });
  assert.equal((await handler(wrongMode)(post())).status, 503);
  assert.equal(wrongMode.depositCalls[0].body.p_error, "review_required");

  // A stored subscription checkout cannot be claimed by deposit metadata.
  const contradictory = depositApi();
  contradictory.context = contextOf({ checkouts: [storedCheckout({ kind: "subscription" })] });
  assert.equal((await handler(contradictory)(post())).status, 503);
  assert.equal(contradictory.depositCalls.length, 0);
  assert.equal(contradictory.finishCalls[0].body.p_error, "review_required");
});

Deno.test("a mapped customer's unbound session quarantines visibly", async () => {
  const api = depositApi();
  api.context = contextOf({ checkouts: [storedCheckout({ session_id: "cs_test_other" })] });
  const response = await handler(api)(post());
  assert.equal(response.status, 503);
  assert.equal(api.depositCalls.length, 0);
  assert.equal(api.finishCalls[0].body.p_error, "review_required");
  assert.equal(api.finishCalls[0].body.p_snapshot, null);
});

Deno.test("duplicate and out-of-order deposit events replay the same reference", async () => {
  for (const type of ["checkout.session.completed", "checkout.session.async_payment_succeeded"]) {
    const api = new FakeBackend();
    api.claim = claimOf(type, SESSION);
    api.event = eventOf(type, SESSION);
    api.session = depositSession();
    api.context = contextOf();
    const response = await handler(api)(post());
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      status: "deposit_credited", granted: true, checkout_id: CHECKOUT,
      batch_id: "b".repeat(8), event_id: EVENT,
    });
    assert.equal(api.depositCalls[0].body.p_reference, "pi_testdeposit1");
  }
});

Deno.test("failed and unpaid sessions never credit", async () => {
  const failed = new FakeBackend();
  failed.claim = claimOf("checkout.session.async_payment_failed", SESSION);
  failed.event = eventOf("checkout.session.async_payment_failed", SESSION);
  failed.session = depositSession({ status: "complete", payment_status: "unpaid" });
  failed.context = contextOf();
  const failedResponse = await handler(failed)(post());
  assert.equal(failedResponse.status, 200);
  assert.deepEqual(await failedResponse.json(), {
    status: "deposit_payment_failed", granted: false, event_id: EVENT,
  });
  assert.equal(failed.depositCalls.length, 0);
  assert.equal(failed.finishCalls[0].body.p_error ?? null, null);

  const pending = depositApi();
  pending.session = depositSession({ status: "complete", payment_status: "unpaid" });
  const pendingResponse = await handler(pending)(post());
  assert.equal(pendingResponse.status, 200);
  assert.deepEqual(await pendingResponse.json(), {
    status: "deposit_pending", granted: false, event_id: EVENT,
  });
  assert.equal(pending.depositCalls.length, 0);
});

Deno.test("subscription checkout events keep the existing snapshot path", async () => {
  const api = new FakeBackend();
  const subscriptionSession = {
    id: SESSION, livemode: false, customer: CUSTOMER,
    metadata: { app: "hocalist", checkout_id: CHECKOUT, membership_id: MEMBERSHIP },
  };
  api.event = eventOf("checkout.session.completed", SESSION);
  api.session = subscriptionSession;
  api.context = contextOf({ checkouts: [storedCheckout({ kind: "subscription", plan_code: "pro" })] });
  const response = await handler(api)(post());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "processed", event_id: EVENT });
  assert.equal(api.depositCalls.length, 0, "a subscription session never reaches the deposit handler");
  assert.equal(api.stripeCalls.includes("subscriptions?customer=cus_testdeposit1&status=all&limit=100"), true);
});

Deno.test("an unmapped customer is explicitly ignored", async () => {
  const api = depositApi();
  api.context = null;
  const response = await handler(api)(post());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ignored_unmapped_customer", event_id: EVENT });
  assert.equal(api.depositCalls.length, 0);
});

Deno.test("authorization, method, idle and identity mismatches are safe", async () => {
  const api = depositApi();
  assert.equal((await handler(api)(post(false))).status, 401);
  assert.equal((await handler(api)(new Request("http://localhost/reconcile", { method: "GET" }))).status, 405);

  const idle = new FakeBackend();
  idle.claim = null;
  const idleResponse = await handler(idle)(post());
  assert.equal(idleResponse.status, 200);
  assert.deepEqual(await idleResponse.json(), { status: "idle" });

  const mismatched = new FakeBackend();
  mismatched.event = eventOf("checkout.session.completed", "cs_test_other");
  mismatched.session = depositSession();
  mismatched.context = contextOf();
  assert.equal((await handler(mismatched)(post())).status, 503);
  assert.equal(mismatched.depositCalls.length, 0);
});

Deno.test("worker secret comparison accepts only the exact configured value", async () => {
  const secret = "s".repeat(48);
  const request = (value: string) =>
    new Request("http://localhost/reconcile", { headers: { Authorization: `Bearer ${value}` } });
  assert.equal(await authorizedBySecret(request(secret), secret), true);
  assert.equal(await authorizedBySecret(request(secret.slice(0, -1)), secret), false);
  assert.equal(await authorizedBySecret(request(""), secret), false);
  assert.equal(await authorizedBySecret(request(secret), "short"), false);
});

// Deposit/subscription checkout handler tests. The provider and the database
// are injected fakes: no Stripe key, no live call and no real product config.
import { strict as assert } from "node:assert";
import { ACCOUNT, type Backend, BillingError, type ObjectMap } from "../_shared/stripe-test-billing.ts";
import { createCheckoutHandler, parseCheckoutInput } from "./handler.ts";

const USER = "00000000-0000-4000-8000-00000000000a";
const KEY = "2f0c9d1a-0000-4000-8000-000000000001";
const OPTION = "2f0c9d1a-0000-4000-8000-000000000002";
const CHECKOUT = "2f0c9d1a-0000-4000-8000-000000000003";

type Stored = { rpc: Array<{ name: string; body: ObjectMap }>; stripe: Array<{ path: string; params?: Record<string, string>; key?: string }> };

class FakeBackend {
  userEmail(): string | undefined { return undefined; }
  calls: Stored = { rpc: [], stripe: [] };
  userResult: string | Error = USER;
  rpcHandlers: Record<string, (body: ObjectMap) => unknown> = {};
  stripeMatchers: Array<{ match: RegExp; value: ObjectMap | ((path: string, params?: Record<string, string>) => ObjectMap) }> = [];

  async user(): Promise<string> {
    if (this.userResult instanceof Error) throw this.userResult;
    return this.userResult;
  }

  async rpc(name: string, body: ObjectMap = {}): Promise<unknown> {
    this.calls.rpc.push({ name, body });
    const handler = this.rpcHandlers[name];
    if (!handler) throw new Error(`unexpected rpc ${name}`);
    return handler(body);
  }

  async stripe(path: string, params?: Record<string, string>, key?: string): Promise<ObjectMap> {
    this.calls.stripe.push({ path, params, key });
    for (const matcher of this.stripeMatchers) {
      if (matcher.match.test(path)) {
        return typeof matcher.value === "function" ? matcher.value(path, params) : matcher.value;
      }
    }
    throw new Error(`unexpected stripe ${path}`);
  }

  asBackend(): Backend {
    return this as unknown as Backend;
  }
}

const session = (changes: ObjectMap = {}): ObjectMap => ({
  id: "cs_test_session1",
  object: "checkout.session",
  livemode: false,
  status: "open",
  url: "https://checkout.stripe.com/c/pay/test",
  customer: "cus_test1",
  ...changes,
});

const depositCheckout = (changes: ObjectMap = {}): ObjectMap => ({
  checkout_id: CHECKOUT,
  membership_id: "10000000-0000-4000-8000-00000000000a",
  customer_id: "cus_test1",
  option_id: OPTION,
  amount_minor: 2000,
  currency: "usd",
  initial_fee_minor: 155,
  winning_total_minor: 375,
  rate_version: "deposit-20-v1",
  session_id: null,
  session_url: null,
  expires_at: 1900000000,
  state: "creating",
  ...changes,
});

const subscriptionCheckout = (changes: ObjectMap = {}): ObjectMap => ({
  checkout_id: CHECKOUT,
  membership_id: "10000000-0000-4000-8000-00000000000a",
  customer_id: "cus_test1",
  price_id: "price_test_pro",
  amount_minor: 1500,
  plan_code: "pro",
  session_id: null,
  session_url: null,
  expires_at: 1900000000,
  state: "creating",
  ...changes,
});

const config = {
  enabled: true,
  success: "https://hocalist.com/billing/return",
  cancel: "https://hocalist.com/billing/cancel",
};

function post(body: unknown, method = "POST"): Request {
  return new Request("http://localhost/checkout", {
    method,
    headers: { "Content-Type": "application/json" },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

Deno.test("checkout input keeps the reviewed subscription body and adds deposits", () => {
  assert.deepEqual(parseCheckoutInput({ idempotency_key: KEY, plan: "pro" }), {
    kind: "subscription", plan: "pro", key: KEY,
  });
  assert.deepEqual(parseCheckoutInput({ kind: "credit_deposit", idempotency_key: KEY, option_id: OPTION }), {
    kind: "credit_deposit", option: OPTION, key: KEY,
  });
  for (const body of [
    { idempotency_key: KEY, plan: "free" },
    { idempotency_key: KEY, kind: "credit_deposit", plan: "pro" },
    { idempotency_key: KEY, kind: "credit_deposit", option_id: "not-a-uuid" },
    { idempotency_key: KEY },
    { idempotency_key: "x", plan: "pro" },
  ]) assert.throws(() => parseCheckoutInput(body), BillingError);
});

Deno.test("a configured deposit checkout selects the server amount and binds the session", async () => {
  const api = new FakeBackend();
  api.rpcHandlers = {
    stripe_test_deposit_begin: () => depositCheckout(),
    stripe_test_deposit_bind: () => null,
    stripe_test_checkout_expire: () => null,
  };
  api.stripeMatchers = [
    { match: /^account$/, value: { id: ACCOUNT, livemode: false } },
    {
      match: /^checkout\/sessions$/,
      value: (path, params) => {
        assert.equal(params?.mode, "payment");
        assert.equal(params?.["invoice_creation[enabled]"], "true");
        assert.equal(params?.["line_items[0][price_data][unit_amount]"], "2000");
        assert.equal(params?.["line_items[0][price_data][currency]"], "usd");
        assert.equal(params?.["metadata[kind]"], "credit_deposit");
        assert.equal(params?.["metadata[checkout_id]"], CHECKOUT);
        assert.equal(params?.client_reference_id, CHECKOUT);
        assert.equal(params?.success_url, `https://hocalist.com/billing/return?checkout=${CHECKOUT}`);
        assert.equal(params?.cancel_url, `https://hocalist.com/billing/cancel?checkout=${CHECKOUT}`);
        return session({ id: "cs_test_deposit1" });
      },
    },
  ];
  const response = await createCheckoutHandler(api.asBackend(), config)(
    post({ kind: "credit_deposit", idempotency_key: KEY, option_id: OPTION }),
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    checkout_id: CHECKOUT,
    url: "https://checkout.stripe.com/c/pay/test",
  });
  const bind = api.calls.rpc.find((call) => call.name === "stripe_test_deposit_bind");
  assert.equal(bind?.body.p_session, "cs_test_deposit1");
  const created = api.calls.stripe.find((call) => call.path === "checkout/sessions");
  assert.equal(created?.key, `hocalist-deposit-checkout-${CHECKOUT}`);
});

Deno.test("an existing open deposit session is reused, an expired one closes safely", async () => {
  const openApi = new FakeBackend();
  openApi.rpcHandlers = { stripe_test_deposit_begin: () => depositCheckout({ session_id: "cs_test_existing1", state: "open" }) };
  openApi.stripeMatchers = [
    { match: /^account$/, value: { id: ACCOUNT, livemode: false } },
    { match: /^checkout\/sessions\//, value: session({ id: "cs_test_existing1" }) },
  ];
  const openResponse = await createCheckoutHandler(openApi.asBackend(), config)(
    post({ kind: "credit_deposit", idempotency_key: KEY, option_id: OPTION }),
  );
  assert.equal(openResponse.status, 200);
  assert.deepEqual(await openResponse.json(), {
    checkout_id: CHECKOUT,
    url: "https://checkout.stripe.com/c/pay/test",
  });

  const expiredApi = new FakeBackend();
  expiredApi.rpcHandlers = {
    stripe_test_deposit_begin: () => depositCheckout({ session_id: "cs_test_expired1", state: "open" }),
    stripe_test_checkout_expire: () => null,
  };
  expiredApi.stripeMatchers = [
    { match: /^account$/, value: { id: ACCOUNT, livemode: false } },
    { match: /^checkout\/sessions\//, value: session({ id: "cs_test_expired1", status: "expired" }) },
  ];
  const expiredResponse = await createCheckoutHandler(expiredApi.asBackend(), config)(
    post({ kind: "credit_deposit", idempotency_key: KEY, option_id: OPTION }),
  );
  assert.equal(expiredResponse.status, 409);
  assert.deepEqual(await expiredResponse.json(), { error: "checkout_closed" });
  assert.ok(expiredApi.calls.rpc.some((call) => call.name === "stripe_test_checkout_expire"));
});

Deno.test("a live-mode or foreign deposit session is refused without binding", async () => {
  const api = new FakeBackend();
  api.rpcHandlers = { stripe_test_deposit_begin: () => depositCheckout() };
  api.stripeMatchers = [
    { match: /^account$/, value: { id: ACCOUNT, livemode: false } },
    { match: /^checkout\/sessions$/, value: session({ livemode: true }) },
  ];
  const response = await createCheckoutHandler(api.asBackend(), config)(
    post({ kind: "credit_deposit", idempotency_key: KEY, option_id: OPTION }),
  );
  assert.equal(response.status, 503);
  assert.equal(api.calls.rpc.some((call) => call.name === "stripe_test_deposit_bind"), false);
});

Deno.test("checkout preserves subscription behavior and safe failure states", async () => {
  const api = new FakeBackend();
  api.rpcHandlers = {
    stripe_test_checkout_begin: () => subscriptionCheckout(),
    stripe_test_checkout_bind: () => null,
  };
  api.stripeMatchers = [
    { match: /^account$/, value: { id: ACCOUNT, livemode: false } },
    { match: /^subscriptions\?/, value: { data: [], has_more: false } },
    { match: /^prices\//, value: { active: true, livemode: false, currency: "usd", unit_amount: 1500, recurring: { interval: "month", interval_count: 1 } } },
    {
      match: /^checkout\/sessions$/,
      value: (path, params) => {
        assert.equal(params?.mode, "subscription");
        assert.equal(params?.success_url, `https://hocalist.com/billing/return?checkout=${CHECKOUT}`);
        return session({ id: "cs_test_subscription1" });
      },
    },
  ];
  const response = await createCheckoutHandler(api.asBackend(), config)(
    post({ idempotency_key: KEY, plan: "pro" }),
  );
  assert.equal(response.status, 200);
  assert.equal(api.calls.rpc.some((call) => call.name === "stripe_test_checkout_begin" && call.body.p_plan === "pro"), true);
  assert.equal(api.calls.rpc.some((call) => call.name === "stripe_test_deposit_begin"), false);
  assert.equal(api.calls.rpc.some((call) => call.name === "stripe_test_checkout_bind" && call.body.p_session === "cs_test_subscription1"), true);

  const denied = new FakeBackend();
  denied.rpcHandlers = { stripe_test_deposit_begin: () => { throw new BillingError("billing_access_denied", 403); } };
  denied.stripeMatchers = [{ match: /^account$/, value: { id: ACCOUNT } }];
  const deniedResponse = await createCheckoutHandler(denied.asBackend(), config)(
    post({ kind: "credit_deposit", idempotency_key: KEY, option_id: OPTION }),
  );
  assert.equal(deniedResponse.status, 403);
  assert.deepEqual(await deniedResponse.json(), { error: "billing_access_denied" });
});

Deno.test("disabled billing, wrong method and invalid request fail closed", async () => {
  const api = new FakeBackend();
  const handler = createCheckoutHandler(api.asBackend(), { ...config, enabled: false });
  assert.equal((await handler(post({ idempotency_key: KEY, plan: "pro" }))).status, 503);
  assert.equal((await handler(post({}, "GET"))).status, 405);
  const enabled = createCheckoutHandler(api.asBackend(), config);
  const invalid = await enabled(new Request("http://localhost/checkout", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ idempotency_key: KEY, plan: "pro", extra: true }),
  }));
  assert.equal(invalid.status, 400);
  assert.deepEqual(await invalid.json(), { error: "invalid_request" });
});

for (const status of ['expired','open','complete','foreign','live','unbound','different']) {
 Deno.test(`retained checkout recovery verifies provider state: ${status}`,async()=>{
  const api=new FakeBackend(); let begins=0;
  api.rpcHandlers={
   stripe_test_deposit_begin:(body)=>{begins++; if(begins===1)throw new BillingError('checkout_pending',409); if(status==='open'||status==='unbound')assert.equal(body.p_key,OPTION); return depositCheckout({session_id:status==='open'?'cs_test_session1':null});},
   stripe_test_pending_checkout:()=>depositCheckout({kind:status==='expired'||status==='different'?'subscription':'credit_deposit',request_key:OPTION,session_id:status==='unbound'?null:'cs_test_session1'}),
   stripe_test_checkout_expire:()=>null,
   stripe_test_deposit_bind:()=>null,
  };
  api.stripeMatchers=[
   {match:/^account$/,value:{id:ACCOUNT,livemode:false}},
   {match:/^checkout\/sessions\//,value:session({status:status==='foreign'||status==='live'?'expired':status==='different'?'open':status,...(status==='foreign'?{customer:'cus_other'}:{}),...(status==='live'?{livemode:true}:{})})},
   {match:/^checkout\/sessions$/,value:session()},
  ];
  const response=await createCheckoutHandler(api.asBackend(),config)(post({kind:'credit_deposit',option_id:OPTION,idempotency_key:KEY}));
  assert.equal(response.status,['expired','open','unbound'].includes(status)?200:['complete','different'].includes(status)?409:503);
  assert.equal(api.calls.rpc.filter(c=>c.name==='stripe_test_checkout_expire').length,status==='expired'?1:0);
  assert.equal(api.calls.stripe.filter(c=>c.path==='checkout/sessions').length,['expired','unbound'].includes(status)?1:0);
 });
}

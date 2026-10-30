import { strict as assert } from "node:assert";
import {
  ACCOUNT,
  type Backend,
  type ObjectMap,
} from "../_shared/stripe-test-billing.ts";
import { createPaygoSetupHandler } from "./handler.ts";
const SETUP = "10000000-0000-4000-8000-000000000001";
const KEY = "10000000-0000-4000-8000-000000000002";
class Fake {
  calls: string[] = [];
  account = ACCOUNT;
  session: ObjectMap = {
    id: "cs_test_setup",
    customer: "cus_test",
    livemode: false,
    mode: "setup",
    status: "complete",
    setup_intent: "seti_test",
    url: "https://checkout.stripe.com/c/pay/test",
  };
  intent: ObjectMap = {
    id: "seti_test",
    customer: "cus_test",
    livemode: false,
    status: "succeeded",
    usage: "off_session",
    payment_method: "pm_test",
    metadata: { app: "hocalist", setup_id: SETUP },
  };
  method: ObjectMap = {
    id: "pm_test",
    customer: "cus_test",
    livemode: false,
    type: "card",
  };
  setup: ObjectMap = {
    id: SETUP,
    setup_id: SETUP,
    customer_id: "cus_test",
    membership_id: KEY,
    session_id: "cs_test_setup",
    created_at: new Date().toISOString(),
  };
  params: Record<string, string> | undefined;
  async user() {
    return KEY;
  }
  userEmail() {
    return "controlled@example.com";
  }
  async rpc(name: string) {
    this.calls.push(name);
    if(name==='paygo_card_context')return {customer_id:'cus_test',payment_method_id:'pm_test'};
    return name === "paygo_customer"
      ? { customer_id: "cus_test", membership_id: KEY }
      : this.setup;
  }
  async stripe(path: string, params?: Record<string, string>) {
    this.calls.push(path);
    if (path === "account") return { id: this.account };
    if (path.startsWith("checkout/sessions")) {
      if (params) this.params = params;
      return this.session;
    }
    if (path.startsWith("setup_intents/")) return this.intent;
    if (path.startsWith("payment_methods/")) return this.method;
    if (path==='customers/cus_test') return {id:'cus_test',livemode:false};
    throw new Error("Unexpected provider request");
  }
  run(body: unknown, enabled = true) {
    return createPaygoSetupHandler(this as unknown as Backend, {
      enabled,
      success: "https://hocalist.com/billing/return?checkout={CHECKOUT_SESSION_ID}",
      cancel: "https://hocalist.com/billing/cancel",
    })(
      new Request("https://example.com", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      }),
    );
  }
}
Deno.test('expired setup is closed before allowing a replacement', async () => {
  const f = new Fake();
  f.session.status = 'expired';
  const response = await f.run({operation:'begin',idempotency_key:KEY,consent_version:'paygo-v1'});
  assert.equal(response.status,409);
  assert.deepEqual(await response.json(),{error:'setup_expired'});
  assert.ok(f.calls.includes('paygo_setup_finish'));
  assert.equal(f.params,undefined);
});
Deno.test('a completed setup resumes verification without creating another session', async () => {
  const f = new Fake();
  const response = await f.run({operation:'begin',idempotency_key:KEY,consent_version:'paygo-v1'});
  assert.deepEqual(await response.json(),{setup_id:SETUP,state:'needs_confirmation'});
  assert.equal(f.params,undefined);
  assert.ok(!f.calls.includes('paygo_setup_finish'));
});
Deno.test('a different Stripe account cannot access payment setup', async () => {
  const f = new Fake();f.account='acct_other';
  assert.equal((await f.run({operation:'confirm',setup_id:SETUP})).status,503);
  assert.ok(!f.calls.includes('paygo_setup_context'));
});
Deno.test("only a verified setup saves a card; setup creates no payment", async () => {
  const f = new Fake();
  const result = await f.run({ operation: "confirm", setup_id: SETUP });
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { state: "authorised" });
  assert.ok(f.calls.includes("paygo_setup_finish"));
  assert.ok(
    !f.calls.some((x) =>
      x.startsWith("payment_intents") || x.startsWith("charges")
    ),
  );
});
for (
  const [label, change] of [
    ["wrong customer", (f: Fake) => {
      f.session.customer = "cus_other";
    }],
    ["live session", (f: Fake) => {
      f.session.livemode = true;
    }],
    ["wrong mode", (f: Fake) => {
      f.session.mode = "payment";
    }],
    ["foreign setup intent", (f: Fake) => {
      f.intent.metadata = { app: "hocalist", setup_id: KEY };
    }],
    ["unverified intent", (f: Fake) => {
      f.intent.status = "requires_action";
    }],
    ["wrong method owner", (f: Fake) => {
      f.method.customer = "cus_other";
    }],
    ["live card", (f: Fake) => {
      f.method.livemode = true;
    }],
  ] as const
) {
  Deno.test(`reject ${label} without saving authorisation`, async () => {
    const f = new Fake();
    change(f);
    assert.equal(
      (await f.run({ operation: "confirm", setup_id: SETUP })).status,
      503,
    );
    assert.ok(!f.calls.includes("paygo_setup_finish"));
  });
}
Deno.test("unfinished setup stays pending without saving a card", async () => {
  const f = new Fake();
  f.session.status = "open";
  const r = await f.run({ operation: "confirm", setup_id: SETUP });
  assert.deepEqual(await r.json(), { state: "pending" });
  assert.ok(!f.calls.includes("paygo_setup_finish"));
});
Deno.test("disabled setup and missing consent do not start checkout", async () => {
  const f = new Fake();
  assert.equal((await f.run({}, false)).status, 503);
  assert.equal(f.calls.length, 0);
  assert.equal(
    (await f.run({ operation: "begin", idempotency_key: KEY })).status,
    400,
  );
  assert.ok(!f.calls.includes("paygo_setup_begin"));
});
Deno.test("begin uses hosted setup mode and explains the charging trigger", async () => {
  const f = new Fake();
  f.setup.session_id = null;
  f.session.status = "open";
  const r = await f.run({
    operation: "begin",
    idempotency_key: KEY,
    consent_version: "paygo-v1",
  });
  assert.equal(r.status, 200);
  assert.equal(f.params?.mode, "setup");
  assert.equal(f.params?.customer, "cus_test");
  assert.equal(new URL(f.params!.success_url).pathname,'/billing');
  assert.equal(new URL(f.params!.success_url).origin,'https://www.hocalist.com');
  assert.equal(new URL(f.params!.success_url).searchParams.get('paygo_setup'),f.setup.setup_id);
  assert.equal(new URL(f.params!.success_url).searchParams.has('checkout'),false);
  assert.equal(new URL(f.params!.cancel_url).pathname,'/billing');
  assert.equal(new URL(f.params!.cancel_url).origin,'https://www.hocalist.com');
  assert.equal(new URL(f.params!.cancel_url).searchParams.get('paygo_cancelled'),'1');
  assert.match(
    f.params?.["custom_text[submit][message]"] ?? "",
    /Free and Pro initial fees apply after the buyer replies/,
  );
  assert.match(f.params?.["custom_text[submit][message]"] ?? "", /Elite fees wait until a PIN-confirmed purchase or the seven-day deadline/);
  assert.match(f.params?.["custom_text[submit][message]"] ?? "", /eligible no-purchase fees are waived/);
  assert.equal(f.params?.amount, undefined);
  assert.ok(f.calls.includes("paygo_setup_bind"));
});
Deno.test("retry resumes the bound session instead of creating another", async () => {
  const f = new Fake();
  f.session.status = "open";
  assert.equal(
    (await f.run({
      operation: "begin",
      idempotency_key: KEY,
      consent_version: "paygo-v1",
    })).status,
    200,
  );
  assert.equal(f.params, undefined);
  assert.ok(!f.calls.includes("paygo_setup_bind"));
});

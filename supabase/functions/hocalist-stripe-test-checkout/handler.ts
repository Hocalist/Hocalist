import {
  assertAccount,
  type Backend,
  BillingError,
  boundedBody,
  failure,
  id,
  json,
  object,
  paymentReference,
  positiveMinor,
  providerUrl,
  rows,
  serviceUrl,
  uuid,
} from "../_shared/stripe-test-billing.ts";

// Subscription checkout keeps its reviewed body. The credit-deposit entry is
// additive: the server selects the option and amount, and the browser never
// supplies a price, currency or customer.
type Input =
  | { kind: "subscription"; plan: string; key: string }
  | { kind: "credit_deposit"; option: string; key: string };

export type CheckoutConfig = {
  enabled: boolean;
  success: string;
  cancel: string;
};

export function parseCheckoutInput(input: Record<string, unknown>): Input {
  const keys = Object.keys(input).sort().join(",");
  const key = input.idempotency_key;
  if (keys === "idempotency_key,plan" || (keys === "idempotency_key,kind,plan" && input.kind === "subscription")) {
    if (!["pro", "elite"].includes(String(input.plan))) {
      throw new BillingError("invalid_request", 400);
    }
    return { kind: "subscription", plan: String(input.plan), key: uuid(key) };
  }
  if (keys === "idempotency_key,kind,option_id" && input.kind === "credit_deposit") {
    return { kind: "credit_deposit", option: uuid(input.option_id), key: uuid(key) };
  }
  throw new BillingError("invalid_request", 400);
}

// The hosted return/cancel URLs carry the exact checkout id as a lookup hint.
// The website treats it as a hint only and re-authorizes it on the server.
export function withCheckoutHint(destination: string, checkoutId: string): string {
  const url = new URL(destination);
  url.searchParams.set("checkout", checkoutId);
  return serviceUrl(url.toString());
}

async function ensureCustomer(
  api: Backend,
  checkout: Record<string, unknown>,
  bind: string,
): Promise<string> {
  let customer = typeof checkout.customer_id === "string" ? checkout.customer_id : "";
  if (customer) {
    if (!/^cus_[A-Za-z0-9]+$/.test(customer)) throw new Error("review_required");
    return customer;
  }
  customer = id(
    await api.stripe("customers", {
      "metadata[app]": "hocalist",
      "metadata[membership_id]": String(checkout.membership_id),
    }, `hocalist-customer-${checkout.membership_id}`),
  );
  if (!/^cus_[A-Za-z0-9]+$/.test(customer)) throw new Error("review_required");
  await api.rpc(bind, {
    p_checkout: checkout.checkout_id,
    p_customer: customer,
  });
  return customer;
}

// A stored session is retrieved from the provider and must belong to the bound
// customer and be open; an expired session closes the checkout without any
// entitlement, and any other state needs reconciliation instead of a retry.
async function recoverSession(
  api: Backend,
  checkout: Record<string, unknown>,
  customer: string,
): Promise<string | null> {
  if (!checkout.session_id) return null;
  const existing = await api.stripe(
    `checkout/sessions/${encodeURIComponent(String(checkout.session_id))}`,
  );
  if (
    id(existing.customer) !== customer || existing.livemode !== false ||
    existing.id !== checkout.session_id
  ) throw new Error("review_required");
  if (existing.status === "expired") {
    await api.rpc("stripe_test_checkout_expire", {
      p_checkout: checkout.checkout_id,
      p_session: existing.id,
      p_customer: customer,
    });
    throw new BillingError("checkout_closed", 409);
  }
  if (existing.status !== "open") {
    throw new BillingError("checkout_reconciliation_required", 409);
  }
  return providerUrl(existing.url, "checkout.stripe.com");
}

export function createCheckoutHandler(api: Backend, config: CheckoutConfig) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    if (!config.enabled) {
      return json({ error: "billing_unavailable" }, 503);
    }
    try {
      const user = await api.user(request);
      const input = parseCheckoutInput(await boundedBody(request));
      const success = serviceUrl(config.success);
      const cancel = serviceUrl(config.cancel);
      await assertAccount(api);

      if (input.kind === "credit_deposit") {
        const checkout = object(
          await api.rpc("stripe_test_deposit_begin", {
            p_user: user,
            p_option: input.option,
            p_key: input.key,
          }),
        );
        const customer = await ensureCustomer(api, checkout, "stripe_test_deposit_bind");
        const recovered = await recoverSession(api, checkout, customer);
        if (recovered) return json({ checkout_id: checkout.checkout_id, url: recovered });
        const amount = positiveMinor(checkout.amount_minor);
        const session = await api.stripe("checkout/sessions", {
          mode: "payment",
          customer,
          "payment_method_types[0]": "card",
          "line_items[0][price_data][currency]": "usd",
          "line_items[0][price_data][unit_amount]": String(amount),
          "line_items[0][price_data][product_data][name]":
            `Hocalist HocaCredits ($${(amount / 100).toFixed(2)})`,
          "line_items[0][quantity]": "1",
          success_url: withCheckoutHint(success, String(checkout.checkout_id)),
          cancel_url: withCheckoutHint(cancel, String(checkout.checkout_id)),
          expires_at: String(checkout.expires_at),
          client_reference_id: String(checkout.checkout_id),
          "metadata[app]": "hocalist",
          "metadata[kind]": "credit_deposit",
          "metadata[membership_id]": String(checkout.membership_id),
          "metadata[checkout_id]": String(checkout.checkout_id),
          "metadata[option_id]": String(checkout.option_id ?? input.option),
          "metadata[amount_minor]": String(amount),
        }, `hocalist-deposit-checkout-${checkout.checkout_id}`);
        if (session.livemode !== false || !/^cs_test_[A-Za-z0-9]+$/.test(String(session.id))) {
          throw new Error("review_required");
        }
        const url = providerUrl(session.url, "checkout.stripe.com");
        await api.rpc("stripe_test_deposit_bind", {
          p_checkout: checkout.checkout_id,
          p_customer: customer,
          p_session: session.id,
          p_url: url,
        });
        return json({ checkout_id: checkout.checkout_id, url });
      }

      const checkout = object(
        await api.rpc("stripe_test_checkout_begin", {
          p_user: user,
          p_plan: input.plan,
          p_key: input.key,
        }),
      );
      const metadata = {
        "metadata[app]": "hocalist",
        "metadata[membership_id]": String(checkout.membership_id),
        "metadata[checkout_id]": String(checkout.checkout_id),
      };
      const customer = await ensureCustomer(api, checkout, "stripe_test_checkout_bind");
      const recovered = await recoverSession(api, checkout, customer);
      if (recovered) return json({ checkout_id: checkout.checkout_id, url: recovered });
      const subscriptions = rows(
        await api.stripe(
          `subscriptions?customer=${encodeURIComponent(customer)}&status=all&limit=100`,
        ),
      );
      if (
        subscriptions.some((subscription) =>
          !["canceled", "incomplete_expired"].includes(String(subscription.status))
        )
      ) throw new BillingError("subscription_exists", 409);
      const price = await api.stripe(
        `prices/${encodeURIComponent(String(checkout.price_id))}`,
      );
      if (
        price.active !== true || price.livemode !== false ||
        price.currency !== "usd" || price.unit_amount !== checkout.amount_minor ||
        object(price.recurring).interval !== "month" ||
        object(price.recurring).interval_count !== 1
      ) throw new Error("configuration_unavailable");
      const session = await api.stripe("checkout/sessions", {
        mode: "subscription",
        customer,
        "payment_method_types[0]": "card",
        "line_items[0][price]": String(checkout.price_id),
        "line_items[0][quantity]": "1",
        success_url: withCheckoutHint(success, String(checkout.checkout_id)),
        cancel_url: withCheckoutHint(cancel, String(checkout.checkout_id)),
        expires_at: String(checkout.expires_at),
        client_reference_id: String(checkout.checkout_id),
        ...metadata,
        "subscription_data[metadata][app]": "hocalist",
        "subscription_data[metadata][membership_id]": String(checkout.membership_id),
        "subscription_data[metadata][checkout_id]": String(checkout.checkout_id),
      }, `hocalist-checkout-${checkout.checkout_id}`);
      if (
        session.livemode !== false || typeof session.url !== "string" ||
        !session.url.startsWith("https://checkout.stripe.com/")
      ) throw new Error("review_required");
      await api.rpc("stripe_test_checkout_bind", {
        p_checkout: checkout.checkout_id,
        p_customer: customer,
        p_session: session.id,
        p_url: session.url,
      });
      return json({ checkout_id: checkout.checkout_id, url: session.url });
    } catch (error) {
      return failure(error);
    }
  };
}

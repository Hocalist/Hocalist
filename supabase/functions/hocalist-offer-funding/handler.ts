import {
  assertAccount,
  type Backend,
  BillingError,
  boundedBody,
  failure,
  id,
  json,
  object,
  uuid,
} from "../_shared/stripe-test-billing.ts";
import { createPaygoSetupHandler } from "../hocalist-paygo-setup/handler.ts";

// Prefer the billing default. Where no default is set, show the most recent
// attached card and require explicit confirmation of that exact card.
async function savedOfferCard(api: Backend, customerId: string) {
  const customer = await api.stripe(
    "customers/" + encodeURIComponent(customerId),
  );
  if (
    id(customer) !== customerId || customer.deleted ||
    customer.livemode !== false
  ) throw Error("customer_mismatch");
  const defaultId =
    object(customer.invoice_settings ?? {}).default_payment_method;
  let method = defaultId
    ? await api.stripe("payment_methods/" + encodeURIComponent(id(defaultId)))
    : null;
  if (method?.type !== "card") {
    const list = await api.stripe(
      "payment_methods?type=card&limit=1&customer=" +
        encodeURIComponent(customerId),
    );
    method = Array.isArray(list.data) && list.data.length
      ? object(list.data[0])
      : null;
  }
  if (!method) return null;
  if (
    method.type !== "card" || method.livemode !== false ||
    id(method.customer) !== customerId
  ) throw Error("card_mismatch");
  const card = object(method.card);
  return { id: id(method), brand: card.brand, last4: card.last4 };
}
export function offerFundingHandler(
  api: Backend,
  config: {
    enabled: boolean;
    success: string;
    cancel: string;
    appOrigin?: string;
  },
) {
  return async (req: Request) => {
    const origin = req.headers.get("origin");
    const web = origin &&
      (["http://127.0.0.1:7359", "http://localhost:7359"].includes(origin) ||
        (origin === config.appOrigin && origin.startsWith("https://")));
    const headers = {
      "Access-Control-Allow-Origin": web ? origin! : "null",
      "Access-Control-Allow-Headers":
        "authorization, apikey, x-client-info, content-type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    };
    async function handle() {
      if (origin && !web) return json({ error: "origin_denied" }, 403);
      if (req.method === "OPTIONS") return new Response(null, { status: 204 });
      if (req.method !== "POST") {
        return json({ error: "method_not_allowed" }, 405);
      }
      if (!config.enabled) return json({ error: "billing_unavailable" }, 503);
      const input = await boundedBody(req.clone());
      if (input.operation === "begin" || input.operation === "confirm") {
        return createPaygoSetupHandler(api, {
          ...config,
          offerReturnUrl: web
            ? origin + "/offer-payment-return.html"
            : undefined,
        })(req);
      }
      const user = await api.user(req);
      await assertAccount(api);
      const context = object(await api.rpc("paygo_customer", { p_user: user }));
      const customer = context.customer_id;
      const card = typeof customer === "string"
        ? await savedOfferCard(api, customer)
        : null;
      if (input.operation === "inspect") {
        const authorization = await api.rpc("paygo_card_context", {
          p_user: user,
        });
        return json({
          card,
          authorised: !!(authorization && card &&
            object(authorization).payment_method_id === card.id),
        });
      }
      if (
        input.operation !== "authorize" || input.consent_version !== "paygo-v1"
      ) throw new BillingError("consent_required", 400);
      if (!card || input.method !== card.id) {
        throw new BillingError("card_changed", 409);
      }
      await api.rpc("paygo_authorize_saved_card", {
        p_user: user,
        p_key: uuid(input.idempotency_key),
        p_customer: customer,
        p_method: card.id,
        p_consent: "paygo-v1",
      });
      return json({ state: "authorised" });
    }
    let result: Response;
    try {
      result = await handle();
    } catch (error) {
      result = failure(error);
    }
    for (const [key, value] of Object.entries(headers)) {
      result.headers.set(key, value);
    }
    return result;
  };
}

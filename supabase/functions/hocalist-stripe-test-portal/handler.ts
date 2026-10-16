import {
  assertAccount,
  type Backend,
  BillingError,
  boundedBody,
  failure,
  json,
  object,
  providerUrl,
  serviceUrl,
} from "../_shared/stripe-test-billing.ts";

export type PortalConfig = {
  enabled: boolean;
  origin: string;
  returnPaths: readonly string[];
};

// Hosted billing-portal session: the provider customer is derived from the
// verified account inside the database, the return URL is built from the
// approved origin and path allowlist, and no card data or customer id ever
// reaches the browser.
export function createPortalHandler(api: Backend, config: PortalConfig) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    if (!config.enabled) {
      return json({ error: "billing_unavailable" }, 503);
    }
    try {
      const user = await api.user(request);
      const input = await boundedBody(request);
      const keys = Object.keys(input).sort().join(",");
      if (keys !== "" && keys !== "return_path") {
        throw new BillingError("invalid_request", 400);
      }
      const path = keys === "" ? config.returnPaths[0] : String(input.return_path);
      if (!config.returnPaths.includes(path)) {
        throw new BillingError("invalid_request", 400);
      }
      const returnUrl = serviceUrl(new URL(path, serviceUrl(config.origin)).toString());
      await assertAccount(api);
      const access = object(
        await api.rpc("stripe_test_portal_access", { p_user: user }),
      );
      if (access.requires_review === true) {
        throw new BillingError("billing_review_required", 403);
      }
      if (
        typeof access.customer_id !== "string" ||
        !/^cus_[A-Za-z0-9]+$/.test(access.customer_id)
      ) {
        throw new BillingError("customer_unavailable", 409);
      }
      const session = await api.stripe("billing_portal/sessions", {
        customer: access.customer_id,
        return_url: returnUrl,
      });
      if (session.livemode !== false) throw new Error("review_required");
      return json({ url: providerUrl(session.url, "billing.stripe.com") });
    } catch (error) {
      return failure(error);
    }
  };
}

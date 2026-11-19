import { backend, failure } from "../_shared/stripe-test-billing.ts";
import { createPortalHandler } from "./handler.ts";
import { sharedBillingAccount, qaAccount } from "../_shared/stripe-test-project.ts";

// Native authenticated invocation. Browser CORS is deliberately not enabled;
// the website server forwards the signed-in user's access token.
const config = {
  enabled: Deno.env.get("HOCALIST_STRIPE_TEST_ENABLED") === "true",
  origin: Deno.env.get("HOCALIST_WEBSITE_ORIGIN") ?? "https://hocalist.com",
  returnPaths: ["/billing", "/billing/return"],
};

Deno.serve(async (request) => {
  try {
    const qa = Deno.env.get("HOCALIST_SELLER_TEST_ACCOUNT_ID") === qaAccount ? backend(qaAccount) : undefined;
    return await createPortalHandler(backend(sharedBillingAccount), config, qa)(request);
  } catch (error) {
    return failure(error);
  }
});

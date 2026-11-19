import { backend, failure } from "../_shared/stripe-test-billing.ts";
import { createCheckoutHandler } from "./handler.ts";
import { sharedBillingAccount, qaAccount } from "../_shared/stripe-test-project.ts";

// Native authenticated invocation. Browser checkout entry/CORS is deliberately
// not enabled; the website server forwards the signed-in user's access token.
const config = {
  enabled: Deno.env.get("HOCALIST_STRIPE_TEST_ENABLED") === "true",
  success: Deno.env.get("HOCALIST_STRIPE_TEST_SUCCESS_URL") ?? "",
  cancel: Deno.env.get("HOCALIST_STRIPE_TEST_CANCEL_URL") ?? "",
};

Deno.serve(async (request) => {
  try {
    const qa = Deno.env.get("HOCALIST_SELLER_TEST_ACCOUNT_ID") === qaAccount ? backend(qaAccount) : undefined;
    return await createCheckoutHandler(backend(sharedBillingAccount), config, qa)(request);
  } catch (error) {
    return failure(error);
  }
});

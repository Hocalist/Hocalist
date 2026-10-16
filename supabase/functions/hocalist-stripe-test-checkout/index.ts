import { backend, failure } from "../_shared/stripe-test-billing.ts";
import { createCheckoutHandler } from "./handler.ts";

// Native authenticated invocation. Browser checkout entry/CORS is deliberately
// not enabled; the website server forwards the signed-in user's access token.
const config = {
  enabled: Deno.env.get("HOCALIST_STRIPE_TEST_ENABLED") === "true",
  success: Deno.env.get("HOCALIST_STRIPE_TEST_SUCCESS_URL") ?? "",
  cancel: Deno.env.get("HOCALIST_STRIPE_TEST_CANCEL_URL") ?? "",
};

Deno.serve(async (request) => {
  try {
    return await createCheckoutHandler(backend(), config)(request);
  } catch (error) {
    return failure(error);
  }
});

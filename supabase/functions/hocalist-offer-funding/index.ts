import { backend } from "../_shared/stripe-test-billing.ts";
import { offerFundingHandler } from "./handler.ts";
{
  Deno.serve(offerFundingHandler(backend(), {
    enabled: Deno.env.get("HOCALIST_PAYGO_TEST_ENABLED") === "true",
    success: Deno.env.get("HOCALIST_STRIPE_TEST_SUCCESS_URL") ?? "",
    cancel: Deno.env.get("HOCALIST_STRIPE_TEST_CANCEL_URL") ?? "",
    appOrigin: Deno.env.get("HOCALIST_OFFER_APP_ORIGIN"),
  }));
}
import { backend } from "../_shared/stripe-test-billing.ts";
import { createPaygoSetupHandler } from "./handler.ts";
Deno.serve(createPaygoSetupHandler(backend(), {
  enabled: Deno.env.get("HOCALIST_PAYGO_TEST_ENABLED") === "true",
  success: Deno.env.get("HOCALIST_STRIPE_TEST_SUCCESS_URL") ?? "",
  cancel: Deno.env.get("HOCALIST_STRIPE_TEST_CANCEL_URL") ?? "",
}));

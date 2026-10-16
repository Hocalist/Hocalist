import { backend, failure } from "../_shared/stripe-test-billing.ts";
import { authorizedBySecret, createReconcileHandler } from "./handler.ts";

// Worker entry. It owns the injected provider/database boundary and the
// configured worker secret; the reconciliation logic is in handler.ts.
const secret = Deno.env.get("HOCALIST_STRIPE_TEST_WORKER_SECRET") ?? "";

Deno.serve(async (request) => {
  try {
    return await createReconcileHandler({
      authorized: (req) => authorizedBySecret(req, secret),
      api: backend(),
    })(request);
  } catch (error) {
    return failure(error);
  }
});

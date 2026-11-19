import { assertAccount, backend, failure, json, object } from "../_shared/stripe-test-billing.ts";
import { qaAccount, sharedBillingAccount } from "../_shared/stripe-test-project.ts";
import { authorizedBySecret, createReconcileHandler, reconcileDeposit, snapshot } from "./handler.ts";

// Worker entry. It owns the injected provider/database boundary and the
// configured worker secret; the reconciliation logic is in handler.ts.
const secret = Deno.env.get("HOCALIST_STRIPE_TEST_WORKER_SECRET") ?? "";

Deno.serve(async (request) => {
  try {
    const queue = new URL(request.url).searchParams.get("queue");
    if (request.method === "POST" && (queue === "qa-credits" || queue === "qa-subscriptions")) {
      if (!await authorizedBySecret(request, secret)) return json({ error: "authentication_required" }, 401);
      if (Deno.env.get("HOCALIST_SELLER_TEST_ACCOUNT_ID") !== qaAccount) return json({ status: "disabled" });
      const api = backend(qaAccount);
      await assertAccount(api);
      const due = await api.rpc(queue === "qa-credits" ? "qa_credit_pending_sessions" : "qa_subscription_due");
      if (!Array.isArray(due)) throw Error("invalid_queue");
      let errors = 0;
      for (const row of due) {
        try {
          const stored = object(row);
          const session = await api.stripe("checkout/sessions/" + encodeURIComponent(String(stored.session_id)));
          if (session.id !== stored.session_id || session.customer !== stored.customer_id || session.livemode !== false)
            throw Error("session_conflict");
          if (session.status === "expired") {
            await api.rpc("stripe_test_checkout_expire", {p_checkout: stored.id ?? stored.checkout,p_session: session.id,p_customer: stored.customer_id});
          } else if (queue === "qa-subscriptions") {
            if (session.status !== "complete") continue;
            const metadata = object(session.metadata);
            if (session.mode !== "subscription" || !session.subscription || metadata.app !== "hocalist" ||
                metadata.checkout_id !== stored.checkout || metadata.membership_id !== stored.membership_id)
              throw Error("subscription_binding_mismatch");
            const verified = await snapshot(api, String(stored.customer_id), stored);
            if (!verified || verified.subscription_id !== session.subscription ||
                verified.checkout_id !== stored.checkout) throw Error("subscription_snapshot_mismatch");
            await api.rpc("qa_subscription_apply", {p_checkout: stored.checkout,p_customer: stored.customer_id,
              p_generation: stored.checked_at,p_snapshot: verified});
          } else {
            await reconcileDeposit(api, session, String(stored.customer_id), stored, stored, "checkout.session.completed");
          }
        } catch { errors++; }
      }
      return json({ checked: due.length, errors }, errors ? 503 : 200);
    }
    return await createReconcileHandler({
      authorized: (req) => authorizedBySecret(req, secret),
      api: backend(sharedBillingAccount),
    })(request);
  } catch (error) {
    return failure(error);
  }
});

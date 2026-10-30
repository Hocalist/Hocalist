import {
  assertAccount,
  type Backend,
  BillingError,
  boundedBody,
  failure,
  id,
  json,
  object,
  providerUrl,
  serviceUrl,
  uuid,
} from "../_shared/stripe-test-billing.ts";
import {refreshManagedPaygoCard} from '../_shared/paygo-managed-card.ts';
export function createPaygoSetupHandler(
  api: Backend,
  config: { enabled: boolean; success: string; cancel: string },
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    if (!config.enabled) return json({ error: "billing_unavailable" }, 503);
    try {
      const user = await api.user(request), input = await boundedBody(request);
      await assertAccount(api);
      if(input.operation==='sync'&&Object.keys(input).join(',')==='operation'){
        await refreshManagedPaygoCard(api,user);return json({state:'ready'});
      }
      if (input.operation === "begin") {
        if (
          Object.keys(input).sort().join(",") !==
            "consent_version,idempotency_key,operation" ||
          input.consent_version !== "paygo-v1"
        ) throw new BillingError("consent_required", 400);
        const key = uuid(input.idempotency_key);
        let customerContext = object(
          await api.rpc("paygo_customer", { p_user: user }),
        );
        if (!customerContext.customer_id) {
          const created = await api.stripe("customers", {
            "metadata[app]": "hocalist",
            "metadata[membership_id]": String(customerContext.membership_id),
            ...(api.userEmail(request)
              ? { email: api.userEmail(request)! }
              : {}),
          }, `hocalist-customer-${customerContext.membership_id}`);
          customerContext = object(
            await api.rpc("paygo_customer", {
              p_user: user,
              p_customer: id(created),
            }),
          );
        }
        const setup = object(
          await api.rpc("paygo_setup_begin", {
            p_user: user,
            p_key: key,
            p_consent: "paygo-v1",
          }),
        );
        if (setup.session_id) {
          const existing = await api.stripe(
            `checkout/sessions/${encodeURIComponent(String(setup.session_id))}`,
          );
          if (
            existing.id !== setup.session_id ||
            id(existing.customer) !== setup.customer_id ||
            existing.livemode !== false || existing.mode !== "setup"
          ) throw new Error("review_required");
          if (existing.status === "expired") {
            await api.rpc("paygo_setup_finish", {
              p_setup: setup.setup_id,
              p_customer: setup.customer_id,
              p_session: existing.id,
              p_method: null,
              p_expired: true,
            });
            throw new BillingError("setup_expired", 409);
          }
          if (existing.status === "complete") {
            return json({
              setup_id: setup.setup_id,
              state: "needs_confirmation",
            });
          }
          if (existing.status !== "open") {
            throw new BillingError("setup_needs_confirmation", 409);
          }
          return json({
            setup_id: setup.setup_id,
            url: providerUrl(existing.url, "checkout.stripe.com"),
          });
        }
        if (
          Date.now() - Date.parse(String(setup.created_at)) > 25 * 60 * 1000
        ) throw new BillingError("setup_needs_review", 409);
        // Card setup returns to its own controls, not purchase reconciliation.
        const returnUrl = new URL('/billing', serviceUrl(config.success));
        returnUrl.hostname='www.hocalist.com';
        returnUrl.searchParams.set("paygo_setup", String(setup.setup_id));
        const cancelUrl = new URL('/billing', serviceUrl(config.cancel));
        cancelUrl.hostname='www.hocalist.com';
        cancelUrl.searchParams.set('paygo_cancelled','1');
        const session = await api.stripe("checkout/sessions", {
          mode: "setup",
          currency: "usd",
          customer: String(setup.customer_id),
          "payment_method_types[0]": "card",
          success_url: returnUrl.toString(),
          cancel_url: cancelUrl.toString(),
          "custom_text[submit][message]":
            "Sending an offer is free. Free and Pro initial fees apply after the buyer replies. Elite fees wait until a PIN-confirmed purchase or the seven-day deadline; eligible no-purchase fees are waived. A purchase may add the remaining winning fee. See your plan rates before sending an offer. Use Manage payment to update your card.",
          "metadata[app]": "hocalist",
          "metadata[kind]": "paygo_setup",
          "metadata[setup_id]": String(setup.setup_id),
          "setup_intent_data[metadata][app]": "hocalist",
          "setup_intent_data[metadata][setup_id]": String(setup.setup_id),
        }, `hocalist-paygo-setup-${setup.setup_id}`);
        if (
          session.livemode !== false || session.mode !== "setup" ||
          id(session.customer) !== setup.customer_id
        ) throw new Error("review_required");
        const url = providerUrl(session.url, "checkout.stripe.com");
        await api.rpc("paygo_setup_bind", {
          p_setup: setup.setup_id,
          p_customer: setup.customer_id,
          p_session: session.id,
          p_url: url,
        });
        return json({ setup_id: setup.setup_id, url });
      }
      if (input.operation === "confirm") {
        if (Object.keys(input).sort().join(",") !== "operation,setup_id") {
          throw new BillingError("invalid_request", 400);
        }
        const setup = object(
          await api.rpc("paygo_setup_context", {
            p_user: user,
            p_setup: uuid(input.setup_id),
          }),
        );
        if (!setup.session_id) throw new BillingError("setup_pending", 409);
        const session = await api.stripe(
          `checkout/sessions/${encodeURIComponent(String(setup.session_id))}`,
        );
        if (
          session.id !== setup.session_id ||
          id(session.customer) !== setup.customer_id ||
          session.livemode !== false || session.mode !== "setup"
        ) throw new Error("review_required");
        if (session.status === "expired") {
          await api.rpc("paygo_setup_finish", {
            p_setup: setup.id,
            p_customer: setup.customer_id,
            p_session: session.id,
            p_method: null,
            p_expired: true,
          });
          return json({ state: "expired" });
        }
        if (session.status !== "complete") return json({ state: "pending" });
        const intent = await api.stripe(
          `setup_intents/${encodeURIComponent(id(session.setup_intent))}`,
        );
        if (
          intent.livemode !== false ||
          id(intent.customer) !== setup.customer_id ||
          intent.status !== "succeeded" || intent.usage !== "off_session" ||
          object(intent.metadata).setup_id !== setup.id ||
          object(intent.metadata).app !== "hocalist"
        ) throw new Error("review_required");
        const method = await api.stripe(
          `payment_methods/${encodeURIComponent(id(intent.payment_method))}`,
        );
        if (
          id(method.customer) !== setup.customer_id || method.type !== "card" ||
          method.livemode !== false
        ) throw new Error("review_required");
        await api.rpc("paygo_setup_finish", {
          p_setup: setup.id,
          p_customer: setup.customer_id,
          p_session: session.id,
          p_method: method.id,
        });
        const activeCard=await api.rpc('paygo_card_context',{p_user:user});
        if(activeCard===null)return json({state:'expired'});
        if(object(activeCard).customer_id!==setup.customer_id||object(activeCard).payment_method_id!==method.id)throw new Error('review_required');
        await api.stripe(`customers/${String(setup.customer_id)}`,{'invoice_settings[default_payment_method]':String(method.id)},`hocalist-paygo-default-${String(setup.id)}`);
        return json({ state: "authorised" });
      }
      throw new BillingError("invalid_request", 400);
    } catch (error) {
      return failure(error);
    }
  };
}

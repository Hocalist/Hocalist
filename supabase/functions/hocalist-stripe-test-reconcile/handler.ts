import {
  ACCOUNT,
  assertAccount,
  type Backend,
  BillingError,
  failure,
  id,
  isDepositSession,
  json,
  object,
  type ObjectMap,
  paymentReference,
  positiveMinor,
  rows,
} from "../_shared/stripe-test-billing.ts";

// Constant-time worker authorization. The configured secret is required to be
// long; the comparison digest avoids returning on a matching token prefix.
export async function authorizedBySecret(
  request: Request,
  expected: string,
): Promise<boolean> {
  if (expected.length < 32) return false;
  const actual =
    request.headers.get("Authorization")?.replace(/^Bearer /, "") ?? "";
  const digest = async (value: string) =>
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    );
  const [a, b] = await Promise.all([digest(actual), digest(expected)]);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

// Retrieve current provider state; never grant access from a historical event body.
async function snapshot(
  api: Backend,
  customer: string,
  context: ObjectMap,
): Promise<ObjectMap | null> {
  const subscriptions = rows(
    await api.stripe(
      `subscriptions?customer=${
        encodeURIComponent(customer)
      }&status=all&limit=100`,
    ),
  );
  const current = subscriptions.filter((s) =>
    !["canceled", "incomplete_expired"].includes(String(s.status))
  );
  if (current.length > 1) throw new Error("review_required");
  const selected = current[0] ??
    subscriptions.sort((a, b) => Number(b.created) - Number(a.created))[0];
  if (!selected) return null;
  if (selected.livemode !== false || id(selected.customer) !== customer) {
    throw new Error("review_required");
  }
  const metadata = object(selected.metadata);
  if (
    metadata.app !== "hocalist" ||
    metadata.membership_id !== context.membership_id
  ) throw new Error("review_required");
  const checkouts = (context.checkouts as unknown[]).map(object);
  const checkout = checkouts.find((c) => c.id === metadata.checkout_id);
  const plans = (context.plans as unknown[]).map(object);
  const items = rows(selected.items);
  const plan = plans.find((p) => p.code === checkout?.plan_code);
  if (!checkout || !plan || items.length !== 1 || items[0].quantity !== 1) {
    throw new Error("review_required");
  }
  const price = object(items[0].price);
  if (
    price.id !== checkout.price_id || price.currency !== "usd" ||
    price.unit_amount !== checkout.amount_minor ||
    object(price.recurring).interval !== "month" ||
    object(price.recurring).interval_count !== 1
  ) throw new Error("review_required");
  let paidUntil: string | null = null;
  if (selected.status === "active" && selected.latest_invoice) {
    const invoice = await api.stripe(
      `invoices/${encodeURIComponent(id(selected.latest_invoice))}`,
    );
    const lines = rows(invoice.lines);
    const periodEnd = Number(selected.current_period_end);
    const paidLine = lines.find((line) =>
      id(line.subscription) === selected.id &&
      id(line.price) === checkout.price_id &&
      object(line.period).end === periodEnd && line.quantity === 1 &&
      line.proration === false
    );
    if (
      invoice.livemode !== false || id(invoice.customer) !== customer ||
      id(invoice.subscription) !== selected.id
    ) throw new Error("review_required");
    if (
      invoice.status === "paid" && invoice.paid === true &&
      invoice.currency === "usd" &&
      typeof invoice.amount_paid === "number" &&
      invoice.amount_paid >= Number(checkout.amount_minor) && paidLine &&
      Number.isSafeInteger(periodEnd) && periodEnd > 0
    ) paidUntil = new Date(periodEnd * 1000).toISOString();
  }
  if (typeof selected.cancel_at_period_end !== "boolean") {
    throw new Error("review_required");
  }
  return {
    subscription_id: selected.id,
    checkout_id: checkout.id,
    plan_code: plan.code,
    status: selected.status,
    paid_until: paidUntil,
    cancel_at_period_end: selected.cancel_at_period_end,
    requires_review: false,
  };
}

// Fail closed for a mapped checkout whose provider session contradicts the
// stored contract: expire the checkout, mark the customer for review and let
// the caller quarantine the receipt. No credit is ever created here.
async function quarantineDeposit(
  api: Backend,
  checkoutId: string,
  customer: string,
  paidAmount: number | null,
): Promise<never> {
  try {
    await api.rpc("stripe_test_deposit_finish", {
      p_checkout: checkoutId,
      p_customer: customer,
      p_paid_amount: paidAmount,
      p_reference: null,
      p_error: "review_required",
    });
  } catch {
    /* The generic finish below still quarantines the receipt and customer. */
  }
  throw new Error("review_required");
}

// Deposit reconciliation: classification comes from the stored session/checkout
// binding, and every provider metadata/mode/customer/amount value is validated
// against that contract before a batch can be created.
async function reconcileDeposit(
  api: Backend,
  session: ObjectMap,
  customer: string,
  context: ObjectMap,
  stored: ObjectMap,
  eventType: string,
): Promise<ObjectMap> {
  const checkoutId = String(stored.id);
  const metadata = object(session.metadata ?? {});
  const contractHolds =
    stored.kind === "credit_deposit" &&
    metadata.app === "hocalist" &&
    metadata.kind === "credit_deposit" &&
    metadata.checkout_id === checkoutId &&
    metadata.membership_id === context.membership_id &&
    session.mode === "payment" &&
    session.livemode === false &&
    id(session.customer) === customer;
  const rawAmount = session.amount_total;
  const amount = typeof rawAmount === "number" && Number.isSafeInteger(rawAmount) && rawAmount > 0
    ? rawAmount
    : null;
  if (!contractHolds) {
    // Missing, altered or contradictory classification (including empty
    // metadata on a bound paid session) is quarantined, never silently
    // processed on the subscription path.
    await quarantineDeposit(api, checkoutId, customer, amount);
  }
  if (session.currency !== "usd" || amount !== stored.amount_minor) {
    await quarantineDeposit(api, checkoutId, customer, amount);
  }
  if (eventType === "checkout.session.async_payment_failed") {
    return { status: "deposit_payment_failed", granted: false };
  }
  // `completed` can still be unpaid for delayed payment methods; the later
  // async_payment_succeeded event carries the grantable state.
  if (session.payment_status !== "paid" || session.status !== "complete") {
    return { status: "deposit_pending", granted: false };
  }
  const result = object(
    await api.rpc("stripe_test_deposit_finish", {
      p_checkout: checkoutId,
      p_customer: customer,
      p_paid_amount: positiveMinor(amount),
      p_reference: paymentReference(session),
    }),
  );
  return {
    status: result.status === "complete" ? "deposit_credited" : "deposit_recorded",
    granted: result.status === "complete",
    checkout_id: checkoutId,
    batch_id: result.batch_id ?? null,
  };
}

export function createReconcileHandler(deps: {
  authorized: (request: Request) => Promise<boolean>;
  api: Backend;
}) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    const { api } = deps;
    let claim: ObjectMap | null = null;
    let customer: string | null = null;
    try {
      if (!await deps.authorized(request)) {
        throw new BillingError("authentication_required", 401);
      }
      await assertAccount(api);
      const work = await api.rpc("stripe_test_claim");
      if (work === null) return json({ status: "idle" });
      claim = object(work);
      const event = await api.stripe(
        `events/${encodeURIComponent(String(claim.event_id))}`,
      );
      const payload = object(object(event.data).object);
      if (
        event.livemode !== false ||
        (event.account && event.account !== ACCOUNT) ||
        event.id !== claim.event_id || event.type !== claim.event_type ||
        payload.id !== claim.object_id
      ) throw new Error("review_required");

      // Retrieve the session itself: an event body may be stale or replayed
      // out of order, and the stored checkout must match the live session.
      let session: ObjectMap | null = null;
      if (String(event.type).startsWith("checkout.session.")) {
        session = await api.stripe(
          `checkout/sessions/${encodeURIComponent(id(payload.id))}`,
        );
        if (session.livemode !== false || session.id !== payload.id) {
          throw new Error("review_required");
        }
        if (payload.customer && id(payload.customer) !== id(session.customer)) {
          throw new Error("review_required");
        }
      }

      if (String(event.type).startsWith("charge.dispute.")) {
        const charge = await api.stripe(
          `charges/${encodeURIComponent(id(payload.charge))}`,
        );
        customer = charge.customer ? id(charge.customer) : null;
      } else {
        customer = payload.customer
          ? id(payload.customer)
          : session?.customer
            ? id(session.customer)
            : null;
      }

      const context = customer
        ? await api.rpc("website_checkout_context", { p_customer: customer })
        : null;
      let state: ObjectMap | null = null;
      if (context !== null && customer) {
        const contextObject = object(context);
        const checkouts = (contextObject.checkouts as unknown[]).map(object);
        const stored = session
          ? checkouts.find((checkout) => checkout.session_id === session?.id)
          : null;
        if (session) {
          // Classification comes from the stored binding, never from provider
          // metadata. A mapped customer's session must be bound to a checkout.
          if (!stored) throw new Error("review_required");
          if (stored.kind === "credit_deposit") {
            const outcome = await reconcileDeposit(
              api,
              session,
              customer,
              contextObject,
              stored,
              String(event.type),
            );
            await api.rpc("stripe_test_finish", {
              p_token: claim.token,
              p_event: claim.event_id,
              p_customer: customer,
              p_snapshot: null,
            });
            return json({ ...outcome, event_id: claim.event_id });
          }
          // A stored subscription checkout advertising deposit metadata is
          // contradictory and must not fall through as a trusted subscription.
          if (isDepositSession(session)) throw new Error("review_required");
        }
        // A refund/dispute needs reviewed policy; do not silently retain or restore paid access.
        if (String(event.type).startsWith("charge.")) {
          throw new Error("review_required");
        }
        state = await snapshot(api, customer, contextObject);
        if (
          state === null &&
          String(event.type).startsWith("customer.subscription.")
        ) throw new Error("review_required");
      }
      await api.rpc("stripe_test_finish", {
        p_token: claim.token,
        p_event: claim.event_id,
        p_customer: customer,
        p_snapshot: state,
      });
      return json({
        status: context === null ? "ignored_unmapped_customer" : "processed",
        event_id: claim.event_id,
      });
    } catch (error) {
      if (claim) {
        try {
          await api.rpc("stripe_test_finish", {
            p_token: claim.token,
            p_event: claim.event_id,
            p_customer: customer,
            p_snapshot: null,
            p_error: error instanceof Error && error.message === "review_required"
              ? "review_required"
              : "provider_or_storage_unavailable",
          });
        } catch {
          /* Lease expiry/storage failure leaves the durable receipt available for recovery. */
        }
      }
      return failure(error);
    }
  };
}

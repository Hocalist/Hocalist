import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { guardFailure, guardMutation, readBoundedJson } from "../../../lib/website-guard";
import {
  classifySiteFailure,
  parseCheckoutBody,
  providerRedirect,
  refreshCookieOptions,
  sessionCookieOptions,
} from "../../../lib/website-rules";
import {
  callBillingFunction,
  REFRESH_COOKIE,
  SESSION_COOKIE,
  siteConfig,
  withSessionRefresh,
} from "../../../lib/website-session";

const CHECKOUT_MESSAGES: Record<string, string> = {
  checkout_pending: "A checkout is already in progress for this account. Finish or cancel it before starting another.",
  checkout_closed: "That checkout is closed. Start a new one.",
  checkout_reconciliation_required: "The previous checkout attempt needs review. Contact support before starting another.",
  subscription_exists: "This account already has an active seller subscription. Manage it instead of starting a new one.",
  invalid_plan_or_key: "That seller plan is not available right now. Refresh and choose again.",
  invalid_option_or_key: "That credit pack is not available right now. Refresh and choose again.",
  billing_review_required: "This account needs a billing review before purchases can continue. Contact support.",
  amount_mismatch: "The payment did not match the selected pack. Nothing was credited twice; contact support.",
};

// Starts a hosted TEST Checkout session for the signed-in seller. The browser
// sends only the plan/pack choice and an opaque retry key; amounts, customer
// and session come from the server function.
export async function POST(request: Request) {
  const guard = guardMutation(request, { policy: "session", maxBytes: 2048 });
  if (!guard.ok) return guardFailure(guard);
  const config = siteConfig();
  if (!config) {
    return NextResponse.json(
      { state: "unconfigured", message: "Seller billing is not configured on this deployment." },
      { status: 503 },
    );
  }
  const parsedBody = await readBoundedJson(request, 2048);
  if (!parsedBody.ok) {
    return NextResponse.json(
      { state: "invalid", message: parsedBody.error === "request_too_large" ? "The checkout request was too large." : "Malformed checkout request." },
      { status: parsedBody.status },
    );
  }
  const parsed = parseCheckoutBody(parsedBody.body);
  if (!parsed.ok) {
    return NextResponse.json({ state: "invalid", message: parsed.message }, { status: 400 });
  }
  const store = await cookies();
  const token = store.get(SESSION_COOKIE)?.value ?? "";
  const refresh = store.get(REFRESH_COOKIE)?.value ?? "";
  if (!token && !refresh) {
    return NextResponse.json({ state: "signed_out" }, { status: 401 });
  }
  const payload = parsed.value.kind === "subscription"
    ? {
      kind: "subscription",
      plan: parsed.value.plan,
      idempotency_key: parsed.value.idempotencyKey,
    }
    : {
      kind: "credit_deposit",
      option_id: parsed.value.optionId,
      idempotency_key: parsed.value.idempotencyKey,
    };

  const { result, refreshed } = await withSessionRefresh(
    config,
    token,
    refresh,
    (value) => callBillingFunction(config, value, "hocalist-stripe-test-checkout", payload),
    (value) => !value.ok && value.status === 401,
  );

  const respond = (body: Record<string, unknown>, status: number) => {
    const response = NextResponse.json(body, { status });
    if (refreshed) {
      const isProduction = process.env.NODE_ENV === "production";
      response.cookies.set(
        SESSION_COOKIE,
        refreshed.accessToken,
        sessionCookieOptions({ expiresIn: refreshed.expiresIn, isProduction }),
      );
      response.cookies.set(
        REFRESH_COOKIE,
        refreshed.refreshToken,
        refreshCookieOptions({ isProduction }),
      );
    }
    return response;
  };

  if (!result.ok) {
    const state = classifySiteFailure(result.status, result.code);
    const status = state === "signed_out"
      ? 401
      : state === "forbidden" || state === "review"
        ? 403
        : result.code && CHECKOUT_MESSAGES[result.code]
          ? 409
          : 503;
    return respond(
      {
        state,
        code: result.code,
        message: result.code && CHECKOUT_MESSAGES[result.code]
          ? CHECKOUT_MESSAGES[result.code]
          : "The billing service could not start checkout. Try again shortly.",
      },
      status,
    );
  }

  const data = (result.data ?? {}) as { checkout_id?: unknown; url?: unknown };
  const url = providerRedirect(data.url, "checkout.stripe.com");
  if (!url || typeof data.checkout_id !== "string" || data.checkout_id.length === 0) {
    return respond(
      { state: "error", message: "The checkout link was refused by this site. No charge was started." },
      502,
    );
  }
  return respond({ state: "ready", checkoutId: data.checkout_id, url }, 200);
}

import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { guardFailure, guardMutation, readBoundedJson } from "../../../lib/website-guard";
import {
  classifySiteFailure,
  parsePortalBody,
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

// Opens the hosted billing portal for the signed-in seller. The provider
// customer is derived inside the function from the verified account; the
// browser only chooses one of the approved return pages.
export async function POST(request: Request) {
  const guard = guardMutation(request, { policy: "session", maxBytes: 1024 });
  if (!guard.ok) return guardFailure(guard);
  const config = siteConfig();
  if (!config) {
    return NextResponse.json(
      { state: "unconfigured", message: "Seller billing is not configured on this deployment." },
      { status: 503 },
    );
  }
  const parsedBody = await readBoundedJson(request, 1024);
  if (!parsedBody.ok) {
    return NextResponse.json(
      { state: "invalid", message: parsedBody.error === "request_too_large" ? "The portal request was too large." : "Malformed portal request." },
      { status: parsedBody.status },
    );
  }
  const parsed = parsePortalBody(parsedBody.body);
  if (!parsed.ok) {
    return NextResponse.json({ state: "invalid", message: parsed.message }, { status: 400 });
  }
  const store = await cookies();
  const token = store.get(SESSION_COOKIE)?.value ?? "";
  const refresh = store.get(REFRESH_COOKIE)?.value ?? "";
  if (!token && !refresh) {
    return NextResponse.json({ state: "signed_out" }, { status: 401 });
  }

  const { result, refreshed } = await withSessionRefresh(
    config,
    token,
    refresh,
    (value) =>
      callBillingFunction(config, value, "hocalist-stripe-test-portal", {
        return_path: parsed.value.returnPath,
      }),
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
    const message = result.code === "customer_unavailable"
      ? "There is no payment method on file yet. Complete a seller purchase first."
      : result.code === "billing_review_required"
        ? "This account needs a billing review before the portal can open. Contact support."
        : state === "signed_out"
          ? "Sign in again to manage billing."
          : state === "forbidden"
            ? "This account is not an active seller account."
            : "The billing portal is unavailable right now. Try again shortly.";
    return respond(
      { state, code: result.code, message },
      state === "signed_out" ? 401 : state === "forbidden" || state === "review" ? 403 : 409,
    );
  }

  const data = (result.data ?? {}) as { url?: unknown };
  const url = providerRedirect(data.url, "billing.stripe.com");
  if (!url) {
    return respond(
      { state: "error", message: "The billing portal link was refused by this site." },
      502,
    );
  }
  return respond({ state: "ready", url }, 200);
}

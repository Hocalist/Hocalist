import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import {
  classifySiteFailure,
  refreshCookieOptions,
  sessionCookieOptions,
  uuidHint,
} from "../../../lib/website-rules";
import { previewEnabled, previewStatus } from "../../../lib/website-preview";
import {
  callRpc,
  REFRESH_COOKIE,
  SESSION_COOKIE,
  siteConfig,
  withSessionRefresh,
} from "../../../lib/website-session";

// Authoritative website billing status. Entitlement, catalogue, exact-checkout
// and credit state come from the database for the signed-in account; a
// `checkout` query value is only a lookup hint and is re-authorized on the
// server. The route repairs one expired access token from the httpOnly refresh
// cookie, then reports the exact signed-out/forbidden/review/error state.
export async function GET(request: Request) {
  const url = new URL(request.url);
  const preview = url.searchParams.get("preview");
  if (preview && previewEnabled()) {
    const result = previewStatus(preview);
    return NextResponse.json(result.body, { status: result.status });
  }
  const checkoutHint = uuidHint(url.searchParams.get("checkout"));
  const config = siteConfig();
  if (!config) {
    return NextResponse.json(
      { state: "unconfigured", message: "Seller billing is not configured on this deployment." },
      { status: 503 },
    );
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
    (value) => callRpc(
      config,
      value,
      "website_purchase_status",
      checkoutHint ? { p_checkout: checkoutHint } : {},
    ),
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
    return respond(
      { state, message: result.message },
      state === "signed_out" ? 401 : state === "forbidden" ? 403 : 503,
    );
  }

  const data = (result.data ?? {}) as Record<string, unknown>;
  return respond(
    {
      state: "ready",
      account: data.account ?? null,
      plans: Array.isArray(data.plans) ? data.plans : [],
      options: Array.isArray(data.options) ? data.options : [],
      subscription: data.subscription ?? null,
      deposits: Array.isArray(data.deposits) ? data.deposits : [],
      selected: data.selected ?? null,
      requires_review: data.requires_review === true,
      checkoutHint,
    },
    200,
  );
}

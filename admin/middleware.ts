import { NextResponse, type NextRequest } from "next/server";

import {
  adminMfaPolicy,
  decodeTokenClaims,
  routeGuardDecision,
  type SessionRouteState,
} from "./app/lib/admin-rules";
import { MFA_PENDING_COOKIE, REFRESH_COOKIE, SESSION_COOKIE } from "./app/lib/admin-session";

const CONFIGURED = Boolean(
  process.env.HOCALIST_SUPABASE_URL && process.env.HOCALIST_SUPABASE_ANON_KEY,
);
const MFA_POLICY = adminMfaPolicy(process.env.HOCALIST_ADMIN_MFA);

function sessionState(token: string | null): SessionRouteState {
  if (!token) return "none";
  const claims = decodeTokenClaims(token);
  if (!claims || !claims.subject || claims.expiresAt === null) return "invalid";
  if (claims.expiresAt <= Math.floor(Date.now() / 1000)) return "invalid";
  if (MFA_POLICY === "required" && claims.aal !== "aal2") return "invalid";
  return "valid";
}

// Redirects stay on the host the browser used; a Next-derived host would make
// the recovery hop cross-origin and fail the bridge's same-origin gate.
function redirectTo(request: NextRequest, pathname: string, search?: string) {
  const host = request.headers.get("host") ?? request.nextUrl.host;
  const forwarded = request.headers.get("x-forwarded-proto");
  const protocol =
    forwarded?.split(",")[0]?.trim() || request.nextUrl.protocol.replace(":", "");
  const url = new URL(`${protocol}://${host}${pathname}`);
  if (search) url.search = search;
  return NextResponse.redirect(url);
}

// Page-route enforcement: a valid local session proceeds, a recoverable
// session (refresh cookie present) is routed through the refresh endpoint, and
// an unusable cookie never blocks the sign-in page. Provider validation and
// assurance enforcement stay on the privileged server paths.
export function middleware(request: NextRequest) {
  const session = request.cookies.get(SESSION_COOKIE)?.value ?? null;
  const hasRefresh = Boolean(request.cookies.get(REFRESH_COOKIE)?.value);
  const hasPending = Boolean(request.cookies.get(MFA_PENDING_COOKIE)?.value);
  const decision = routeGuardDecision({
    pathname: request.nextUrl.pathname,
    configured: CONFIGURED,
    sessionState: sessionState(session),
    hasRefresh,
    hasPending,
  });
  if (decision.action === "redirect-refresh") {
    return redirectTo(
      request,
      "/api/session/refresh",
      `?next=${encodeURIComponent(decision.next)}`,
    );
  }
  if (decision.action === "redirect-login") {
    return redirectTo(request, "/login");
  }
  if (decision.action === "redirect-dashboard") {
    return redirectTo(request, "/dashboard");
  }
  return NextResponse.next();
}

export const config = {
  matcher: [
    "/",
    "/login",
    "/dashboard",
    "/users",
    "/requests",
    "/offers",
    "/catalogue",
    "/locations",
    "/moderation",
    "/reports",
    "/trust",
    "/billing",
    "/billing/config",
    "/withdrawals",
    "/delivery",
    "/settings",
    "/events",
    "/audit",
  ],
};

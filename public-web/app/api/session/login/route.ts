import { NextResponse } from "next/server";
import { guardFailure, guardMutation, readBoundedJson } from "../../../lib/website-guard";
import { classifySiteFailure, parseLoginBody, refreshCookieOptions, sessionCookieOptions } from "../../../lib/website-rules";
import { callRpc, REFRESH_COOKIE, SESSION_COOKIE, signInWithPassword, siteConfig } from "../../../lib/website-session";

// Seller sign-in for the website purchase journey. Mutations are
// same-origin-only and JSON-only before any authentication happens, and the
// browser never receives a Supabase key. A successful sign-in is confirmed
// against the real seller/restriction contract before any session is stored.
export async function POST(request: Request) {
  const guard = guardMutation(request, { policy: "session", maxBytes: 4096 });
  if (!guard.ok) return guardFailure(guard);
  const config = siteConfig();
  if (!config) {
    return NextResponse.json(
      { ok: false, message: "Account sign-in is not configured on this deployment." },
      { status: 503 },
    );
  }
  const parsedBody = await readBoundedJson(request, 4096);
  if (!parsedBody.ok) {
    return NextResponse.json(
      { ok: false, message: parsedBody.error === "request_too_large" ? "The sign-in request was too large." : "Malformed sign-in request." },
      { status: parsedBody.status },
    );
  }
  const parsed = parseLoginBody(parsedBody.body);
  if (!parsed.ok) {
    return NextResponse.json({ ok: false, message: parsed.message }, { status: 400 });
  }
  const signed = await signInWithPassword(config, parsed.value.email, parsed.value.password);
  if (!signed.ok) {
    return NextResponse.json({ ok: false, message: signed.message }, { status: 401 });
  }
  // Full account gate: active seller membership and no restricted or disabled
  // membership in either role.
  const seller = await callRpc(config, signed.accessToken, "website_purchase_status");
  if (!seller.ok) {
    const state = classifySiteFailure(seller.status, seller.code);
    const message = state === "forbidden"
      ? "This account is not an active seller account, or it is currently restricted. Buyer accounts do not purchase seller plans or credits."
      : state === "review"
        ? "This account needs a billing review before purchases can continue. Contact support."
        : "The billing backend is not ready. Try again later.";
    return NextResponse.json({ ok: false, message }, { status: state === "forbidden" ? 403 : 503 });
  }
  const response = NextResponse.json({ ok: true, returnTo: parsed.value.returnTo });
  const isProduction = process.env.NODE_ENV === "production";
  response.cookies.set(
    SESSION_COOKIE,
    signed.accessToken,
    sessionCookieOptions({ expiresIn: signed.expiresIn, isProduction }),
  );
  response.cookies.set(
    REFRESH_COOKIE,
    signed.refreshToken,
    refreshCookieOptions({ isProduction }),
  );
  return response;
}

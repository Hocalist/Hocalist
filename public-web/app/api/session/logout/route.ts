import { NextResponse } from "next/server";
import { guardFailure, guardMutation } from "../../../lib/website-guard";
import { REFRESH_COOKIE, SESSION_COOKIE } from "../../../lib/website-session";

// Clears the httpOnly session cookies. Provider-side token revocation is not
// required for a short-lived access token; the next sign-in issues a new pair.
export async function POST(request: Request) {
  const guard = guardMutation(request, { policy: "session", json: false, maxBytes: 512 });
  if (!guard.ok) return guardFailure(guard);
  const response = NextResponse.json({ ok: true });
  for (const name of [SESSION_COOKIE, REFRESH_COOKIE]) {
    response.cookies.set(name, "", { httpOnly: true, sameSite: "lax", path: "/", maxAge: 0 });
  }
  return response;
}

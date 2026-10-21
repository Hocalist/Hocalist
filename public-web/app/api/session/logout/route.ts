import { NextRequest } from "next/server";
import { revokeSession } from "../../../lib/session-revocation";
import { siteConfig, refreshSession } from "../../../lib/website-session";
import { NextResponse } from "next/server";
import { guardFailure, guardMutation } from "../../../lib/website-guard";
import { REFRESH_COOKIE, SESSION_COOKIE } from "../../../lib/website-session";

// Revoke the provider session before clearing local credentials.
export async function POST(request: Request) {
  const guard = guardMutation(request, { policy: "session", json: false, maxBytes: 512 });
  if (!guard.ok) return guardFailure(guard);
  const store = new NextRequest(request).cookies;
  const config = siteConfig();
  let access = store.get(SESSION_COOKIE)?.value;
  const refresh = store.get(REFRESH_COOKIE)?.value;
  if (refresh) {
    if (!config) return NextResponse.json({ error: 'logout_unavailable' }, { status: 503 });
    const rotated = await refreshSession(config, refresh);
    if (!rotated.ok && rotated.state === 'unavailable') return NextResponse.json({ error: 'logout_unavailable' }, { status: 503 });
    if (rotated.ok) access = rotated.accessToken;
  }
  if (access && (!config || !await revokeSession(config, access))) {
    return NextResponse.json({ error: 'logout_unavailable' }, { status: 503 });
  }
  const response = NextResponse.json({ ok: true });
  for (const name of [SESSION_COOKIE, REFRESH_COOKIE]) {
    response.cookies.set(name, "", { httpOnly: true, sameSite: "lax", path: "/", maxAge: 0 });
  }
  return response;
}

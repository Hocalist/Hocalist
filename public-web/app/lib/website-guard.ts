// Same-origin mutation guard for the website's cookie-authenticated routes.
//
// SameSite cookies alone do not stop login CSRF or same-site sibling-origin
// posts, so every mutation must prove its browser origin before any
// authentication, session or provider work happens:
//   - JSON content type (except body-less logout),
//   - a bounded body,
//   - an exact `Origin` match against the request's own deployment origin
//     (plus the explicitly configured canonical origin), which rejects
//     cross-site and sibling-origin requests,
//   - `Sec-Fetch-Site: same-origin` when the browser sends it.
//
// The public waitlist uses the same boundary under an explicit public-intake
// policy: it holds no cookies, but it must still be posted from this site.

import { NextResponse } from "next/server";

export type MutationPolicy = "session" | "public-intake";

export type GuardOptions = {
  policy: MutationPolicy;
  json?: boolean;
  maxBytes?: number;
};

export type GuardResult =
  | { ok: true; origin: string }
  | { ok: false; status: number; error: string };

const DEFAULT_LIMITS: Record<MutationPolicy, number> = {
  session: 4096,
  "public-intake": 2048,
};

export function requestOrigin(request: Request, isProduction: boolean): string {
  const url = new URL(request.url);
  const forwardedHost = request.headers.get("x-forwarded-host");
  const host = forwardedHost ?? request.headers.get("host") ?? url.host;
  const forwardedProto = request.headers.get("x-forwarded-proto");
  const protocol = forwardedProto ??
    (isProduction ? "https" : url.protocol.replace(":", ""));
  return `${protocol}://${host}`;
}

function configuredOrigin(): string | null {
  const configured = process.env.HOCALIST_WEBSITE_ORIGIN;
  if (!configured) return null;
  try {
    const url = new URL(configured);
    if (
      url.protocol !== "https:" || url.port || url.username || url.password ||
      url.pathname !== "/" || url.search || url.hash
    ) return null;
    return url.origin;
  } catch {
    return null;
  }
}

export function guardMutation(
  request: Request,
  options: GuardOptions,
  isProduction = process.env.NODE_ENV === "production",
): GuardResult {
  const origin = request.headers.get("origin");
  const fetchSite = request.headers.get("sec-fetch-site");
  const expected = requestOrigin(request, isProduction);
  const allowed = new Set<string>([expected]);
  const configured = configuredOrigin();
  if (configured) allowed.add(configured);

  // Origin evidence comes first: a cross-site or sibling-origin mutation is
  // rejected even when its body looks well formed.
  if (!origin || !allowed.has(origin)) {
    return { ok: false, status: 403, error: "cross_origin_rejected" };
  }
  if (fetchSite && fetchSite !== "same-origin") {
    return { ok: false, status: 403, error: "cross_origin_rejected" };
  }
  if (options.json !== false) {
    const contentType = request.headers.get("content-type") ?? "";
    if (!contentType.toLowerCase().startsWith("application/json")) {
      return { ok: false, status: 415, error: "unsupported_media_type" };
    }
  }
  const declared = Number(request.headers.get("content-length") ?? "0");
  const maxBytes = options.maxBytes ?? DEFAULT_LIMITS[options.policy];
  if (Number.isFinite(declared) && declared > maxBytes) {
    return { ok: false, status: 413, error: "request_too_large" };
  }
  return { ok: true, origin };
}

export type BodyResult =
  | { ok: true; body: unknown }
  | { ok: false; status: number; error: string };

export async function readBoundedJson(
  request: Request,
  maxBytes: number,
): Promise<BodyResult> {
  let text: string;
  try {
    text = await request.text();
  } catch {
    return { ok: false, status: 400, error: "invalid_body" };
  }
  if (text.length > maxBytes) {
    return { ok: false, status: 413, error: "request_too_large" };
  }
  try {
    return { ok: true, body: JSON.parse(text) };
  } catch {
    return { ok: false, status: 400, error: "invalid_body" };
  }
}

export function guardFailure(result: { status: number; error: string }) {
  return NextResponse.json({ state: "rejected", error: result.error }, { status: result.status });
}

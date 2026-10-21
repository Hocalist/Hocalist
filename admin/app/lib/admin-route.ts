import { boundedJson } from "./bounded-json";
// Thin Next.js adapter for the tested route cores in admin-http.ts.
import { cookies } from "next/headers";
import { NextResponse } from "next/server";

import {
  handleAdminRpcCore,
  handleEvidenceCore,
  handleLoginCore,
  handleLogoutCore,
  handleMfaCancelCore,
  handleMfaChallengeCore,
  handleMfaPendingCore,
  handleMfaVerifyCore,
  handleSessionRefreshCore,
  type CoreDeps,
  type CoreRequest,
  type CoreResult,
  type AdminEvidenceResolver,
} from "./admin-http";
import { adminMfaPolicy } from "./admin-rules";
import { mediaEvidenceResolver } from "./admin-media-evidence";
import {
  adminConfig,
  MFA_PENDING_COOKIE,
  REFRESH_COOKIE,
  SESSION_COOKIE,
} from "./admin-session";

export async function coreRequest(request: Request): Promise<CoreRequest> {
  const store = await cookies();
  const method = request.method.toUpperCase();
  const hasBody = method !== "GET" && method !== "HEAD";
  const url = new URL(request.url);
  return {
    method,
    origin: request.headers.get("origin"),
    host: request.headers.get("host"),
    secFetchSite: request.headers.get("sec-fetch-site"),
    sessionToken: store.get(SESSION_COOKIE)?.value ?? null,
    refreshToken: store.get(REFRESH_COOKIE)?.value ?? null,
    pendingToken: store.get(MFA_PENDING_COOKIE)?.value ?? null,
    nextPath: url.searchParams.get("next"),
    body: hasBody ? await boundedJson(request, 16384).then(result => result.ok ? result.body : null) : null,
  };
}

export function coreDeps(): CoreDeps {
  return {
    config: adminConfig(),
    isProduction: process.env.NODE_ENV === "production",
    mfaPolicy: adminMfaPolicy(process.env.HOCALIST_ADMIN_MFA),
    evidenceHost: process.env.HOCALIST_EVIDENCE_HOST?.trim() || null,
  };
}

/**
 * Redirects must stay on the host the browser actually used. Next can derive
 * `request.url` from a different host (for example localhost while the request
 * arrived on 127.0.0.1 or a custom domain), which would turn a recovery
 * redirect cross-origin and fail the same-origin gate.
 */
function externalBase(request: Request): string {
  const host = request.headers.get("host");
  const forwarded = request.headers.get("x-forwarded-proto");
  const protocol =
    forwarded?.split(",")[0]?.trim() ||
    new URL(request.url).protocol.replace(":", "");
  return host ? `${protocol}://${host}` : request.url;
}

export function coreResponse(result: CoreResult, request: Request): NextResponse {
  const response = result.image
    ? new NextResponse(new Uint8Array(result.image), {
        status: result.status,
        headers: { "Content-Type": "image/jpeg", "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" },
      })
    : result.redirectTo
    ? NextResponse.redirect(new URL(result.redirectTo, externalBase(request)))
    : NextResponse.json(result.body, { status: result.status });
  for (const cookie of result.cookies ?? []) {
    response.cookies.set(cookie.name, cookie.value, cookie.options);
  }
  return response;
}

export async function loginRoute(request: Request): Promise<NextResponse> {
  return coreResponse(await handleLoginCore(await coreRequest(request), coreDeps()), request);
}

export async function adminRpcRoute(request: Request): Promise<NextResponse> {
  return coreResponse(await handleAdminRpcCore(await coreRequest(request), coreDeps()), request);
}

export async function logoutRoute(request: Request): Promise<NextResponse> {
  return coreResponse(await handleLogoutCore(await coreRequest(request), coreDeps()), request);
}

export async function sessionRefreshRoute(request: Request): Promise<NextResponse> {
  return coreResponse(
    await handleSessionRefreshCore(await coreRequest(request), coreDeps()),
    request,
  );
}

export async function mfaPendingRoute(request: Request): Promise<NextResponse> {
  return coreResponse(await handleMfaPendingCore(await coreRequest(request), coreDeps()), request);
}

export async function mfaChallengeRoute(request: Request): Promise<NextResponse> {
  return coreResponse(await handleMfaChallengeCore(await coreRequest(request), coreDeps()), request);
}

export async function mfaVerifyRoute(request: Request): Promise<NextResponse> {
  return coreResponse(await handleMfaVerifyCore(await coreRequest(request), coreDeps()), request);
}

export async function mfaCancelRoute(request: Request): Promise<NextResponse> {
  return coreResponse(handleMfaCancelCore(await coreRequest(request)), request);
}

/**
 * The integrated resolver reads authorized JPEG bytes through the accounts
 * media gateway. It never publishes a storage URL or uses a service-role key.
 */
export async function evidenceRoute(
  request: Request,
  resolver: AdminEvidenceResolver = mediaEvidenceResolver,
): Promise<NextResponse> {
  return coreResponse(
    await handleEvidenceCore(await coreRequest(request), coreDeps(), resolver),
    request,
  );
}

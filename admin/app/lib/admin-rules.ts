// Pure request/response rules for the admin portal.
//
// Kept free of Next.js and Supabase imports so the validation, allowlist,
// cookie and failure-classification behavior can be tested directly with
// `npm test`.

// Only reviewed admin functions can be forwarded from the browser.
export const ADMIN_RPC_ALLOWLIST = new Set([
  "call_admin_settings",
  "admin_access_list",
  "admin_access_command",
  "support_list",
  "support_command",
  "support_reasons",
  "admin_records",
  "admin_overview",
  "admin_workspace_metrics",
  "admin_moderation_decide",
  "admin_moderation_history",
  "marketplace_admin_command",
  "marketplace_admin_moderation_queue",
  "marketplace_catalogue",
  "marketplace_locations",
  "marketplace_timezones",
  "admin_trust_command",
  "admin_withdrawal_queue",
  "admin_credit_summary",
  "admin_reward_summary",
  "admin_credit_detail",
  "admin_delivery_overview",
  "admin_call_settings_history",
  "credit_admin_command",
  "admin_commercial_config",
  "admin_review_queue",
  "admin_failed_events",
  "admin_failed_event_detail",
  "admin_audit_feed",
]);

export const MAX_EMAIL_LENGTH = 254;
export const MAX_PASSWORD_LENGTH = 200;
export const MAX_RPC_PARAMS_BYTES = 16384;

export type ParseResult<T> =
  | { ok: true; value: T }
  | { ok: false; message: string };

export type LoginCredentials = { email: string; password: string };

export function parseLoginBody(body: unknown): ParseResult<LoginCredentials> {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, message: "Malformed sign-in request." };
  }
  const record = body as Record<string, unknown>;
  const email = typeof record.email === "string" ? record.email.trim() : "";
  const password = typeof record.password === "string" ? record.password : "";
  if (!email || !password) {
    return { ok: false, message: "Email and password are required." };
  }
  if (email.length > MAX_EMAIL_LENGTH || password.length > MAX_PASSWORD_LENGTH) {
    return { ok: false, message: "Email and password are required." };
  }
  return { ok: true, value: { email, password } };
}

export type AdminRpcRequest = {
  functionName: string;
  params: Record<string, unknown>;
};

export function parseAdminRpcBody(body: unknown): ParseResult<AdminRpcRequest> {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, message: "Malformed admin request." };
  }
  const record = body as Record<string, unknown>;
  const functionName =
    typeof record.function === "string" ? record.function.trim() : "";
  if (!functionName || !ADMIN_RPC_ALLOWLIST.has(functionName)) {
    return { ok: false, message: "Unsupported admin operation." };
  }
  const rawParams = record.params;
  if (rawParams !== undefined && (typeof rawParams !== "object" || rawParams === null || Array.isArray(rawParams))) {
    return { ok: false, message: "Malformed admin request." };
  }
  const params = (rawParams ?? {}) as Record<string, unknown>;
  let encoded: string;
  try {
    encoded = JSON.stringify(params);
  } catch {
    return { ok: false, message: "Malformed admin request." };
  }
  if (encoded.length > MAX_RPC_PARAMS_BYTES) {
    return { ok: false, message: "Malformed admin request." };
  }
  return { ok: true, value: { functionName, params } };
}

export type CookieOptions = {
  httpOnly: true;
  sameSite: "lax";
  secure: boolean;
  path: "/";
  maxAge: number;
};

export function sessionCookieOptions({
  expiresIn,
  isProduction,
}: {
  expiresIn: number;
  isProduction: boolean;
}): CookieOptions {
  const bounded = Number.isFinite(expiresIn)
    ? Math.min(Math.max(Math.floor(expiresIn), 120), 86400)
    : 3600;
  return {
    httpOnly: true,
    sameSite: "lax",
    secure: isProduction,
    path: "/",
    maxAge: bounded,
  };
}

export const REFRESH_COOKIE_MAX_AGE = 60 * 60 * 24 * 30;
/** A half-finished second factor is short-lived and never privileged. */
export const MFA_PENDING_COOKIE_MAX_AGE = 600;

/** The refresh token lives longer than the access token and stays httpOnly. */
export function refreshCookieOptions({
  isProduction,
}: {
  isProduction: boolean;
}): CookieOptions {
  return {
    httpOnly: true,
    sameSite: "lax",
    secure: isProduction,
    path: "/",
    maxAge: REFRESH_COOKIE_MAX_AGE,
  };
}

export function pendingCookieOptions({
  isProduction,
  maxAge,
}: {
  isProduction: boolean;
  maxAge: number;
}): CookieOptions {
  const bounded = Number.isFinite(maxAge)
    ? Math.min(Math.max(Math.floor(maxAge), 60), MFA_PENDING_COOKIE_MAX_AGE)
    : MFA_PENDING_COOKIE_MAX_AGE;
  return {
    httpOnly: true,
    sameSite: "lax",
    secure: isProduction,
    path: "/",
    maxAge: bounded,
  };
}

/** Options that delete a cookie in the same path it was set on. */
export function clearedCookieOptions(): CookieOptions {
  return {
    httpOnly: true,
    sameSite: "lax",
    secure: false,
    path: "/",
    maxAge: 0,
  };
}

/**
 * Whether the bridge may retry one admin call after refreshing an expired
 * access token. One retry per request; a definitive provider rejection is not
 * retried and a missing refresh token signs the session out.
 */
export function shouldRefreshSession({
  state,
  hasRefreshToken,
  alreadyRetried,
}: {
  state: AdminFailureState;
  hasRefreshToken: boolean;
  alreadyRetried: boolean;
}): boolean {
  return state === "signed_out" && hasRefreshToken && !alreadyRetried;
}

export type AdminFailureState = "signed_out" | "forbidden" | "error";

export function classifyAdminFailure(
  status: number,
  code: string | null,
): AdminFailureState {
  if (status === 401) return "signed_out";
  if (status === 403 || code === "42501") return "forbidden";
  return "error";
}

// ---------------------------------------------------------------------------
// Request origin (CSRF), MFA assurance and route guard rules
// ---------------------------------------------------------------------------

export type AdminMfaPolicy = "off" | "required";

/** MFA enforcement is opt-in configuration, never an implicit live policy. */
export function adminMfaPolicy(value: string | undefined | null): AdminMfaPolicy {
  return value?.trim().toLowerCase() === "required" ? "required" : "off";
}

export type JwtClaims = {
  subject: string | null;
  aal: string | null;
  expiresAt: number | null;
};

/**
 * Reads the assurance claims Supabase already returns in the access token. The
 * token comes directly from the provider token endpoint over TLS in the same
 * request, so this decodes claims without re-verifying a signature; it never
 * grants access by itself and every privileged call still passes the database
 * `platform_admins` check. Edge-safe: no Node Buffer.
 */
export function decodeTokenClaims(token: string): JwtClaims | null {
  const parts = token.split(".");
  if (parts.length !== 3 || parts[1].length === 0) return null;
  try {
    const binary = atob(parts[1].replace(/-/g, "+").replace(/_/g, "/"));
    const encoded = Array.prototype.map
      .call(binary, (character: string) =>
        `%${character.charCodeAt(0).toString(16).padStart(2, "0")}`,
      )
      .join("");
    const payload = JSON.parse(decodeURIComponent(encoded)) as Record<string, unknown>;
    if (typeof payload !== "object" || payload === null) return null;
    return {
      subject: typeof payload.sub === "string" ? payload.sub : null,
      aal: typeof payload.aal === "string" ? payload.aal : null,
      expiresAt:
        typeof payload.exp === "number" && Number.isSafeInteger(payload.exp)
          ? payload.exp
          : null,
    };
  } catch {
    return null;
  }
}

export type LoginAdmission =
  | { ok: true }
  | { ok: false; state: "mfa_required" | "assurance_unavailable" | "expired"; message: string };

/**
 * Strict assurance shape used whenever the MFA policy is required: a subject,
 * a numeric expiry and the aal2 claim must all be present. A decoded claim set
 * is never treated as a completed second factor by default.
 */
export function requiredAssuranceState(
  claims: JwtClaims | null,
): "valid" | "aal1" | "unverifiable" {
  if (
    claims !== null &&
    claims.subject !== null &&
    claims.subject.length > 0 &&
    claims.expiresAt !== null &&
    claims.aal === "aal2"
  ) {
    return "valid";
  }
  if (claims?.aal === "aal1") return "aal1";
  return "unverifiable";
}

/**
 * Applies the configured MFA assurance policy to a freshly signed-in token. A
 * missing or undecodable assurance claim is refused when the policy is
 * required instead of being treated as satisfied. Recovery is an owner action,
 * never a client bypass.
 */
export function admitLogin({
  policy,
  claims,
  nowSeconds,
}: {
  policy: AdminMfaPolicy;
  claims: JwtClaims | null;
  nowSeconds: number;
}): LoginAdmission {
  if (claims && claims.expiresAt !== null && claims.expiresAt <= nowSeconds) {
    return {
      ok: false,
      state: "expired",
      message: "The provider returned an expired session. Sign in again.",
    };
  }
  if (policy === "off") return { ok: true };
  const assurance = requiredAssuranceState(claims);
  if (assurance === "aal1") {
    return {
      ok: false,
      state: "mfa_required",
      message:
        "This portal requires multi-factor assurance. Complete the second factor to continue. A lost factor is reset by the owner; recovery is never a client action.",
    };
  }
  if (assurance === "unverifiable") {
    return {
      ok: false,
      state: "assurance_unavailable",
      message:
        "This portal requires a verifiable second factor and the sign-in response had no usable assurance claim. Contact the owner before retrying.",
    };
  }
  return { ok: true };
}

/** A stored access token past its own expiry is refreshed before use. */
export function sessionTokenExpired(
  claims: JwtClaims | null,
  nowSeconds: number,
): boolean {
  return claims !== null && claims.expiresAt !== null && claims.expiresAt <= nowSeconds;
}

export type RequestOriginVerdict = "allow" | "reject";

/**
 * Same-origin enforcement for the admin bridge. A cross-site fetch is always
 * rejected. A state-changing request without an Origin header is accepted only
 * when the browser asserts a same-origin fetch metadata context; navigation
 * GETs stay available.
 */
export function evaluateRequestOrigin({
  method,
  origin,
  host,
  secFetchSite,
}: {
  method: string;
  origin: string | null;
  host: string | null;
  secFetchSite: string | null;
}): RequestOriginVerdict {
  const normalized = secFetchSite?.trim().toLowerCase() ?? null;
  if (normalized !== null && normalized !== "same-origin" && normalized !== "none") {
    return "reject";
  }
  // The literal "null" origin (sandboxed or opaque context) is not a usable
  // same-origin proof; fall through to the fetch-metadata check.
  if (origin !== null && origin.length > 0 && origin !== "null") {
    if (host === null || host.length === 0) return "reject";
    try {
      return new URL(origin).host === host ? "allow" : "reject";
    } catch {
      return "reject";
    }
  }
  const upper = method.toUpperCase();
  if (upper === "GET" || upper === "HEAD") {
    return normalized === null || normalized === "same-origin" || normalized === "none"
      ? "allow"
      : "reject";
  }
  return normalized === "same-origin" ? "allow" : "reject";
}

export type RouteGuardDecision =
  | { action: "next" }
  | { action: "redirect-login" }
  | { action: "redirect-dashboard" }
  | { action: "redirect-refresh"; next: string };

export type SessionRouteState = "valid" | "invalid" | "none";

/**
 * Route enforcement for the portal pages. A locally valid session proceeds, a
 * recoverable session (refresh cookie present) is routed through the refresh
 * endpoint instead of the sign-in page, and an unusable cookie never blocks
 * the sign-in page itself. Provider validation and assurance enforcement stay
 * on the privileged server paths; this only routes the navigation.
 */
export function routeGuardDecision({
  pathname,
  configured,
  sessionState,
  hasRefresh,
  hasPending,
}: {
  pathname: string;
  configured: boolean;
  sessionState: SessionRouteState;
  hasRefresh: boolean;
  hasPending: boolean;
}): RouteGuardDecision {
  const recoverable = sessionState !== "valid" && hasRefresh;
  if (pathname === "/") {
    if (!configured) return { action: "redirect-dashboard" };
    if (sessionState === "valid") return { action: "redirect-dashboard" };
    return recoverable
      ? { action: "redirect-refresh", next: "/dashboard" }
      : { action: "redirect-login" };
  }
  if (pathname === "/login") {
    return sessionState === "valid" ? { action: "redirect-dashboard" } : { action: "next" };
  }
  // The recovery-outage page is public by design: it never renders protected
  // data and it must stay reachable while the session cannot be renewed.
  if (pathname === "/session-unavailable") return { action: "next" };
  if (!configured || sessionState === "valid") return { action: "next" };
  if (recoverable) return { action: "redirect-refresh", next: pathname };
  if (hasPending) return { action: "redirect-login" };
  return { action: "redirect-login" };
}

/** A refresh return path stays a same-origin portal content path. */
export function sanitizeNextPath(value: string | null | undefined): string {
  if (typeof value !== "string") return "/dashboard";
  if (value.length === 0 || value.length > 512) return "/dashboard";
  if (!value.startsWith("/") || value.startsWith("//") || value.startsWith("/api")) {
    return "/dashboard";
  }
  if (value === "/login" || value.startsWith("/login?") || value === "/session-unavailable" ||
      value.startsWith("/session-unavailable?")) {
    return "/dashboard";
  }
  if (value.includes("\\") || /[\u0000-\u001f]/.test(value)) return "/dashboard";
  return value;
}

/** Bounded evidence URL gate: HTTPS only, optional exact host allowlist. */
export function evidenceUrlAllowed(url: string, allowedHost: string | null): boolean {
  if (typeof url !== "string" || url.length === 0 || url.length > 2048) return false;
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  if (parsed.protocol !== "https:") return false;
  if (parsed.username.length > 0 || parsed.password.length > 0) return false;
  if (allowedHost !== null && allowedHost.length > 0) {
    return parsed.host === allowedHost;
  }
  return true;
}

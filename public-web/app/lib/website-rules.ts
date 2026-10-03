// Pure request/response rules for the website purchase journey.
//
// Kept free of Next.js and Supabase imports so validation, redirect
// allowlists, cookie options and failure classification can be tested
// directly with `npm test`.

export const MAX_EMAIL_LENGTH = 254;
export const MAX_PASSWORD_LENGTH = 200;

export type ParseResult<T> =
  | { ok: true; value: T }
  | { ok: false; message: string };

export type LoginRequest = {
  email: string;
  password: string;
  returnTo: string;
};

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

// Only account, purchase and waitlist pages may be returned to after sign-in.
const RETURN_PATH_PREFIXES = ["/billing", "/pricing", "/download"];
export const DEFAULT_RETURN_PATH = "/billing";

export function safeReturnPath(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 200) {
    return DEFAULT_RETURN_PATH;
  }
  if (!value.startsWith("/") || value.startsWith("//") || value.includes("\\")) {
    return DEFAULT_RETURN_PATH;
  }
  let url: URL;
  try {
    url = new URL(value, "https://hocalist.com");
  } catch {
    return DEFAULT_RETURN_PATH;
  }
  if (url.origin !== "https://hocalist.com") return DEFAULT_RETURN_PATH;
  if (!RETURN_PATH_PREFIXES.some((prefix) => url.pathname === prefix || url.pathname.startsWith(`${prefix}/`))) {
    return DEFAULT_RETURN_PATH;
  }
  // Only a well-formed checkout hint is preserved across sign-in; every other
  // query or hash value is dropped.
  const hint = uuidHint(url.searchParams.get("checkout"));
  if (
    hint &&
    (url.pathname === "/billing" || url.pathname === "/billing/return" || url.pathname === "/billing/cancel")
  ) {
    return `${url.pathname}?checkout=${hint}`;
  }
  return url.pathname;
}

export function parseLoginBody(body: unknown): ParseResult<LoginRequest> {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, message: "Malformed sign-in request." };
  }
  const record = body as Record<string, unknown>;
  const email = typeof record.email === "string" ? record.email.trim() : "";
  const password = typeof record.password === "string" ? record.password : "";
  if (!email || !password || email.length > MAX_EMAIL_LENGTH || password.length > MAX_PASSWORD_LENGTH) {
    return { ok: false, message: "Email and password are required." };
  }
  if (!EMAIL_PATTERN.test(email)) {
    return { ok: false, message: "Enter a valid email address." };
  }
  return {
    ok: true,
    value: { email, password, returnTo: safeReturnPath(record.returnTo) },
  };
}

export type CheckoutRequest =
  | { kind: "subscription"; plan: "pro" | "elite"; idempotencyKey: string }
  | { kind: "credit_deposit"; optionId: string; idempotencyKey: string };

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// A checkout id from a URL or storage is only a lookup hint: the server
// re-authorizes it against the signed-in account.
export function uuidHint(value: unknown): string | null {
  return typeof value === "string" && UUID_PATTERN.test(value) ? value : null;
}

export function parseCheckoutBody(body: unknown): ParseResult<CheckoutRequest> {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, message: "Malformed checkout request." };
  }
  const record = body as Record<string, unknown>;
  const idempotencyKey = typeof record.idempotencyKey === "string" ? record.idempotencyKey : "";
  if (!UUID_PATTERN.test(idempotencyKey)) {
    return { ok: false, message: "Malformed checkout request." };
  }
  if (record.kind === "credit_deposit") {
    const optionId = typeof record.optionId === "string" ? record.optionId : "";
    if (!UUID_PATTERN.test(optionId)) {
      return { ok: false, message: "Choose a credit pack before continuing." };
    }
    return { ok: true, value: { kind: "credit_deposit", optionId, idempotencyKey } };
  }
  if (record.kind === "subscription") {
    if (record.plan !== "pro" && record.plan !== "elite") {
      return { ok: false, message: "Choose a seller plan before continuing." };
    }
    return { ok: true, value: { kind: "subscription", plan: record.plan, idempotencyKey } };
  }
  return { ok: false, message: "Choose what you want to purchase." };
}

export const PORTAL_RETURN_PATHS = ["/billing", "/billing/return"] as const;

export function parsePortalBody(body: unknown): ParseResult<{ returnPath: string }> {
  if (body === undefined || body === null) {
    return { ok: true, value: { returnPath: PORTAL_RETURN_PATHS[0] } };
  }
  if (typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, message: "Malformed portal request." };
  }
  const record = body as Record<string, unknown>;
  const value = record.returnPath ?? PORTAL_RETURN_PATHS[0];
  if (typeof value !== "string" || !(PORTAL_RETURN_PATHS as readonly string[]).includes(value)) {
    return { ok: false, message: "Unsupported return page." };
  }
  return { ok: true, value: { returnPath: value } };
}

// Provider redirect targets are checked before the browser is sent anywhere.
export function providerRedirect(
  value: unknown,
  host: "checkout.stripe.com" | "billing.stripe.com",
): string | null {
  if (typeof value !== "string" || value.length === 0 || value.length > 2048) return null;
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (
    url.protocol !== "https:" || url.hostname !== host || url.port ||
    url.username || url.password || !value.startsWith(`https://${host}/`)
  ) return null;
  return value;
}

export type SiteFailureState = "signed_out" | "forbidden" | "review" | "error";

export function classifySiteFailure(status: number, code: string | null): SiteFailureState {
  if (status === 401) return "signed_out";
  if (code === "billing_review_required") return "review";
  if (status === 403 || code === "42501" || code === "billing_access_denied") return "forbidden";
  return "error";
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

export function refreshCookieOptions({ isProduction }: { isProduction: boolean }): CookieOptions {
  return {
    httpOnly: true,
    sameSite: "lax",
    secure: isProduction,
    path: "/",
    maxAge: REFRESH_COOKIE_MAX_AGE,
  };
}

export function shouldRefreshSession({
  state,
  hasRefreshToken,
}: {
  state: SiteFailureState;
  hasRefreshToken: boolean;
}): boolean {
  return state === "signed_out" && hasRefreshToken;
}

export const WAITLIST_CONSENT_VERSION = "launch-updates-v1";

export function formatUsdMinor(value: unknown): string {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) return "";
  return `$${(value / 100).toFixed(2)}`;
}

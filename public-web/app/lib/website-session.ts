// Server-only website session and billing helpers.
//
// The browser never receives a Supabase or Stripe secret. Sign-in exchanges
// the seller's Supabase Auth credentials for a short-lived access token that
// is stored in an httpOnly cookie and forwarded to PostgREST as the
// `authenticated` role and to the billing functions as a Bearer token. Every
// privileged decision still happens in the database or the function.
//
// Configuration is read from server environment variables only:
//   HOCALIST_SUPABASE_URL
//   HOCALIST_SUPABASE_ANON_KEY
//   HOCALIST_WEBSITE_FUNCTIONS_URL   (optional override, e.g. local functions)
// When configuration is missing the pages report "not configured" instead of
// pretending a live connection exists.

export const SESSION_COOKIE = "hocalist_site_session";
export const REFRESH_COOKIE = "hocalist_site_refresh";
export const HOCALIST_SCHEMA = "hocalist";

export type SiteConfig = { url: string; anonKey: string };

export function siteConfig(): SiteConfig | null {
  const url = process.env.HOCALIST_SUPABASE_URL?.replace(/\/+$/, "");
  const anonKey = process.env.HOCALIST_SUPABASE_ANON_KEY;
  if (!url || !anonKey) return null;
  return { url, anonKey };
}

export function functionsBase(config: SiteConfig): string {
  const override = process.env.HOCALIST_WEBSITE_FUNCTIONS_URL?.replace(/\/+$/, "");
  return override || `${config.url}/functions/v1`;
}

export type SignInResult =
  | { ok: true; accessToken: string; refreshToken: string; expiresIn: number }
  | { ok: false; message: string };

export async function signInWithPassword(
  config: SiteConfig,
  email: string,
  password: string,
): Promise<SignInResult> {
  let response: Response;
  try {
    response = await fetch(`${config.url}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: config.anonKey, "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
      signal: AbortSignal.timeout(10000),
    });
  } catch {
    return { ok: false, message: "The authentication service is unreachable." };
  }
  const payload = (await response.json().catch(() => null)) as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
  } | null;
  if (!response.ok || !payload?.access_token || !payload.refresh_token) {
    return { ok: false, message: "Sign-in failed. Check the email and password." };
  }
  return {
    ok: true,
    accessToken: payload.access_token,
    refreshToken: payload.refresh_token,
    expiresIn: payload.expires_in ?? 3600,
  };
}

export type RefreshResult =
  | { ok: true; accessToken: string; refreshToken: string; expiresIn: number }
  | { ok: false; state: "expired" | "unavailable" };

export async function refreshSession(
  config: SiteConfig,
  refreshToken: string,
): Promise<RefreshResult> {
  let response: Response;
  try {
    response = await fetch(`${config.url}/auth/v1/token?grant_type=refresh_token`, {
      method: "POST",
      headers: { apikey: config.anonKey, "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: refreshToken }),
      signal: AbortSignal.timeout(10000),
    });
  } catch {
    return { ok: false, state: "unavailable" };
  }
  const payload = (await response.json().catch(() => null)) as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
  } | null;
  if (!response.ok || !payload?.access_token) {
    return { ok: false, state: response.status === 401 ? "expired" : "unavailable" };
  }
  return {
    ok: true,
    accessToken: payload.access_token,
    refreshToken: payload.refresh_token ?? refreshToken,
    expiresIn: payload.expires_in ?? 3600,
  };
}

export type RpcResult =
  | { ok: true; data: unknown }
  | { ok: false; status: number; code: string | null; message: string };

export async function callRpc(
  config: SiteConfig,
  accessToken: string,
  functionName: string,
  params: Record<string, unknown> = {},
): Promise<RpcResult> {
  let response: Response;
  try {
    response = await fetch(`${config.url}/rest/v1/rpc/${functionName}`, {
      method: "POST",
      headers: {
        apikey: config.anonKey,
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Accept-Profile": HOCALIST_SCHEMA,
        "Content-Profile": HOCALIST_SCHEMA,
      },
      body: JSON.stringify(params),
      signal: AbortSignal.timeout(10000),
    });
  } catch {
    return { ok: false, status: 0, code: null, message: "The billing service is unreachable." };
  }
  if (!response.ok) {
    const body = (await response.json().catch(() => null)) as {
      code?: string;
      message?: string;
    } | null;
    return {
      ok: false,
      status: response.status,
      code: body?.code ?? null,
      message: body?.message ?? "The billing service rejected the request.",
    };
  }
  return { ok: true, data: await response.json().catch(() => null) };
}

export type FunctionResult =
  | { ok: true; status: number; data: unknown }
  | { ok: false; status: number; code: string | null };

// Anonymous, server-to-server RPC for the public waitlist. The anon key never
// reaches the browser, and the function itself validates consent and email.
export async function callAnonRpc(
  config: SiteConfig,
  functionName: string,
  params: Record<string, unknown>,
): Promise<RpcResult> {
  let response: Response;
  try {
    response = await fetch(`${config.url}/rest/v1/rpc/${functionName}`, {
      method: "POST",
      headers: {
        apikey: config.anonKey,
        "Content-Type": "application/json",
        "Accept-Profile": HOCALIST_SCHEMA,
        "Content-Profile": HOCALIST_SCHEMA,
      },
      body: JSON.stringify(params),
      signal: AbortSignal.timeout(10000),
    });
  } catch {
    return { ok: false, status: 0, code: null, message: "The waitlist service is unreachable." };
  }
  if (!response.ok) {
    const body = (await response.json().catch(() => null)) as {
      code?: string;
      message?: string;
    } | null;
    return {
      ok: false,
      status: response.status,
      code: body?.code ?? null,
      message: body?.message ?? "The waitlist service rejected the request.",
    };
  }
  return { ok: true, data: await response.json().catch(() => null) };
}

export type SessionRunResult<T> = {
  result: T;
  accessToken: string;
  refreshed: { accessToken: string; refreshToken: string; expiresIn: number } | null;
  refreshFailed: "expired" | "unavailable" | null;
};

// Runs one authenticated call with the current access token. A signed-out
// provider answer is retried exactly once after a refresh; a definitive
// rejection clears the caller's session instead of looping.
export async function withSessionRefresh<T extends { ok: boolean }>(
  config: SiteConfig,
  accessToken: string,
  refreshToken: string,
  run: (token: string) => Promise<T>,
  isSignedOut: (result: T) => boolean,
): Promise<SessionRunResult<T>> {
  const first = await run(accessToken);
  if (first.ok || !isSignedOut(first) || !refreshToken) {
    return { result: first, accessToken, refreshed: null, refreshFailed: null };
  }
  const refreshed = await refreshSession(config, refreshToken);
  if (!refreshed.ok) {
    return { result: first, accessToken, refreshed: null, refreshFailed: refreshed.state };
  }
  const retry = await run(refreshed.accessToken);
  return {
    result: retry,
    accessToken: refreshed.accessToken,
    refreshed: {
      accessToken: refreshed.accessToken,
      refreshToken: refreshed.refreshToken,
      expiresIn: refreshed.expiresIn,
    },
    refreshFailed: null,
  };
}

// Forwards the signed-in user's token to a billing function. The function
// re-verifies the token with Supabase Auth, so this bridge never invents an
// identity or a customer.
export async function callBillingFunction(
  config: SiteConfig,
  accessToken: string,
  name: string,
  body: Record<string, unknown>,
): Promise<FunctionResult> {
  let response: Response;
  try {
    response = await fetch(`${functionsBase(config)}/${name}`, {
      method: "POST",
      headers: {
        apikey: config.anonKey,
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20000),
    });
  } catch {
    return { ok: false, status: 0, code: "billing_unavailable" };
  }
  const payload = (await response.json().catch(() => null)) as
    | { error?: string }
    | null;
  if (!response.ok) {
    return { ok: false, status: response.status, code: payload?.error ?? null };
  }
  return { ok: true, status: response.status, data: payload };
}

// Server-only admin session and Supabase REST helpers.
//
// The admin browser never receives a service-role key. Sign-in exchanges the
// administrator's Supabase Auth credentials for a short-lived access token,
// which is stored in an httpOnly cookie and forwarded to PostgREST as the
// `authenticated` role. Every privileged call still passes through the
// `hocalist` schema's own `platform_admins` authorization check.
//
// Configuration is read from server environment variables only:
//   HOCALIST_SUPABASE_URL
//   HOCALIST_SUPABASE_ANON_KEY
// When either is missing the portal reports "not configured" instead of
// pretending a live connection exists.

export const SESSION_COOKIE = "hocalist_admin_session";
export const REFRESH_COOKIE = "hocalist_admin_refresh";
/** Holds the aal1 token only while a second factor is being completed. */
export const MFA_PENDING_COOKIE = "hocalist_admin_mfa_pending";
export const HOCALIST_SCHEMA = "hocalist";

export type AdminConfig = { url: string; anonKey: string };

export function adminConfig(): AdminConfig | null {
  const url = process.env.HOCALIST_SUPABASE_URL?.replace(/\/+$/, "");
  const anonKey = process.env.HOCALIST_SUPABASE_ANON_KEY;
  if (!url || !anonKey) return null;
  return { url, anonKey };
}

export type SignInResult =
  | { ok: true; accessToken: string; refreshToken: string; expiresIn: number }
  | { ok: false; message: string };

export async function signInWithPassword(
  config: AdminConfig,
  email: string,
  password: string,
  fetchImpl: typeof fetch = fetch,
): Promise<SignInResult> {
  let response: Response;
  try {
    response = await fetchImpl(`${config.url}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: {
        apikey: config.anonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email, password }),
    });
  } catch {
    return { ok: false, message: "The authentication service is unreachable." };
  }
  const payload = (await response.json().catch(() => null)) as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
    error_description?: string;
    msg?: string;
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

/**
 * Exchanges a stored refresh token for a new access token. Called only from
 * the server bridge; the browser never sees either token. A definitive
 * provider rejection clears the session instead of retrying.
 */
export async function refreshSession(
  config: AdminConfig,
  refreshToken: string,
  fetchImpl: typeof fetch = fetch,
): Promise<RefreshResult> {
  let response: Response;
  try {
    response = await fetchImpl(`${config.url}/auth/v1/token?grant_type=refresh_token`, {
      method: "POST",
      headers: {
        apikey: config.anonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ refresh_token: refreshToken }),
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
  config: AdminConfig,
  accessToken: string,
  functionName: string,
  params: Record<string, unknown>,
  fetchImpl: typeof fetch = fetch,
): Promise<RpcResult> {
  let response: Response;
  try {
    response = await fetchImpl(`${config.url}/rest/v1/rpc/${functionName}`, {
      method: "POST",
      headers: {
        apikey: config.anonKey,
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Accept-Profile": HOCALIST_SCHEMA,
        "Content-Profile": HOCALIST_SCHEMA,
      },
      body: JSON.stringify(params),
    });
  } catch {
    return { ok: false, status: 0, code: null, message: "The backend is unreachable." };
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
      message: body?.message ?? "The backend rejected the request.",
    };
  }
  return { ok: true, data: await response.json().catch(() => null) };
}

// ---------------------------------------------------------------------------
// Provider-validated session and second-factor wire contract
// ---------------------------------------------------------------------------

export type MfaFactor = {
  id: string;
  factorType: string;
  status: string;
  friendlyName: string | null;
};

export type ProviderSessionResult =
  | { ok: true; userId: string; factors: MfaFactor[] }
  | { ok: false; state: "signed_out" | "unavailable" };

/**
 * Validates the stored access token with the Auth provider (`GET /auth/v1/user`)
 * and reads the enrolled factors. Used as the provider check when the MFA
 * policy is required; a provider rejection is definitive, an outage is not
 * treated as approval.
 */
export async function providerUserSession(
  config: AdminConfig,
  accessToken: string,
  fetchImpl: typeof fetch = fetch,
): Promise<ProviderSessionResult> {
  let response: Response;
  try {
    response = await fetchImpl(`${config.url}/auth/v1/user`, {
      method: "GET",
      headers: {
        apikey: config.anonKey,
        Authorization: `Bearer ${accessToken}`,
      },
    });
  } catch {
    return { ok: false, state: "unavailable" };
  }
  if (response.status === 401 || response.status === 403) {
    return { ok: false, state: "signed_out" };
  }
  if (!response.ok) return { ok: false, state: "unavailable" };
  const payload = (await response.json().catch(() => null)) as {
    id?: unknown;
    factors?: unknown;
  } | null;
  if (!payload || typeof payload.id !== "string" || payload.id.length === 0) {
    return { ok: false, state: "unavailable" };
  }
  const factors: MfaFactor[] = [];
  if (Array.isArray(payload.factors)) {
    for (const raw of payload.factors.slice(0, 10)) {
      if (!raw || typeof raw !== "object") continue;
      const factor = raw as Record<string, unknown>;
      if (typeof factor.id !== "string" || factor.id.length === 0 || factor.id.length > 64) continue;
      factors.push({
        id: factor.id,
        factorType: typeof factor.factor_type === "string" ? factor.factor_type : "unknown",
        status: typeof factor.status === "string" ? factor.status : "unknown",
        friendlyName: typeof factor.friendly_name === "string" ? factor.friendly_name : null,
      });
    }
  }
  return { ok: true, userId: payload.id, factors };
}

export type ChallengeResult =
  | { ok: true; challengeId: string; expiresAt: number | null }
  | { ok: false; status: number; state: "signed_out" | "invalid_factor" | "unavailable" };

/** Creates a TOTP challenge for one enrolled factor (GoTrue factor contract). */
export async function beginMfaChallenge(
  config: AdminConfig,
  accessToken: string,
  factorId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<ChallengeResult> {
  let response: Response;
  try {
    response = await fetchImpl(
      `${config.url}/auth/v1/factors/${encodeURIComponent(factorId)}/challenge`,
      {
        method: "POST",
        headers: {
          apikey: config.anonKey,
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: "{}",
      },
    );
  } catch {
    return { ok: false, status: 0, state: "unavailable" };
  }
  if (response.status === 401) return { ok: false, status: 401, state: "signed_out" };
  if (response.status === 400 || response.status === 404 || response.status === 422) {
    return { ok: false, status: response.status, state: "invalid_factor" };
  }
  if (!response.ok) return { ok: false, status: response.status, state: "unavailable" };
  const payload = (await response.json().catch(() => null)) as {
    id?: unknown;
    expires_at?: unknown;
  } | null;
  if (!payload || typeof payload.id !== "string" || payload.id.length === 0) {
    return { ok: false, status: response.status, state: "unavailable" };
  }
  return {
    ok: true,
    challengeId: payload.id,
    expiresAt:
      typeof payload.expires_at === "number" && Number.isSafeInteger(payload.expires_at)
        ? payload.expires_at
        : null,
  };
}

export type MfaVerifyResult =
  | { ok: true; accessToken: string; refreshToken: string; expiresIn: number }
  | {
      ok: false;
      status: number;
      state: "signed_out" | "invalid_code" | "rate_limited" | "unavailable";
    };

/** Verifies one factor challenge and returns the upgraded session tokens. */
export async function verifyMfaChallenge(
  config: AdminConfig,
  accessToken: string,
  factorId: string,
  challengeId: string,
  code: string,
  fetchImpl: typeof fetch = fetch,
): Promise<MfaVerifyResult> {
  let response: Response;
  try {
    response = await fetchImpl(
      `${config.url}/auth/v1/factors/${encodeURIComponent(factorId)}/verify`,
      {
        method: "POST",
        headers: {
          apikey: config.anonKey,
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ challenge_id: challengeId, code }),
      },
    );
  } catch {
    return { ok: false, status: 0, state: "unavailable" };
  }
  if (response.status === 401) return { ok: false, status: 401, state: "signed_out" };
  if (response.status === 429) return { ok: false, status: 429, state: "rate_limited" };
  if (response.status === 400 || response.status === 403 || response.status === 422) {
    return { ok: false, status: response.status, state: "invalid_code" };
  }
  if (!response.ok) return { ok: false, status: response.status, state: "unavailable" };
  const payload = (await response.json().catch(() => null)) as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
  } | null;
  if (!payload?.access_token || !payload.refresh_token) {
    return { ok: false, status: response.status, state: "unavailable" };
  }
  return {
    ok: true,
    accessToken: payload.access_token,
    refreshToken: payload.refresh_token,
    expiresIn: payload.expires_in ?? 3600,
  };
}
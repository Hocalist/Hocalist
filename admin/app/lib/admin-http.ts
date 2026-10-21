import { revokeSession } from "./session-revocation";
// Server-route cores for the admin portal bridge.
//
// Kept free of Next.js imports so the HTTP-level behavior can be tested with
// plain request values and an injected fetch:
//   * same-origin/CSRF enforcement,
//   * provider-validated session admission (strict claims + `GET /auth/v1/user`
//     when the MFA policy is required) on every privileged path,
//   * access-missing/expired session recovery through the refresh cookie,
//   * password -> pending -> challenge -> verify second-factor completion,
//   * the evidence gateway reference check.
import {
  admitLogin,
  classifyAdminFailure,
  clearedCookieOptions,
  decodeTokenClaims,
  evaluateRequestOrigin,
  evidenceUrlAllowed,
  parseAdminRpcBody,
  parseLoginBody,
  pendingCookieOptions,
  refreshCookieOptions,
  requiredAssuranceState,
  sanitizeNextPath,
  sessionCookieOptions,
  sessionTokenExpired,
  shouldRefreshSession,
  type AdminMfaPolicy,
  type CookieOptions,
  type JwtClaims,
} from "./admin-rules";
import {
  beginMfaChallenge,
  callRpc,
  providerUserSession,
  refreshSession,
  signInWithPassword,
  verifyMfaChallenge,
  MFA_PENDING_COOKIE,
  REFRESH_COOKIE,
  SESSION_COOKIE,
  type AdminConfig,
  type MfaFactor,
} from "./admin-session";

export type CoreRequest = {
  method: string;
  origin: string | null;
  host: string | null;
  secFetchSite: string | null;
  sessionToken: string | null;
  refreshToken: string | null;
  pendingToken: string | null;
  nextPath: string | null;
  body: unknown;
};

export type CoreCookie = { name: string; value: string; options: CookieOptions };
export type CoreResult = {
  status: number;
  body: Record<string, unknown>;
  image?: Uint8Array;
  cookies?: CoreCookie[];
  redirectTo?: string;
};

export type CoreDeps = {
  config: AdminConfig | null;
  isProduction: boolean;
  mfaPolicy: AdminMfaPolicy;
  evidenceHost: string | null;
  fetchImpl?: typeof fetch;
  nowSeconds?: () => number;
};

export type EvidenceResolverInput = {
  submissionId: string;
  mediaId: string;
  accessToken: string;
  config: AdminConfig;
  fetchImpl: typeof fetch;
};

export type EvidenceResolution =
  | { state: "image"; bytes: Uint8Array }
  | { state: "ready"; url: string; expires_at: string | null }
  | { state: "unavailable"; reason: string; message: string };

/**
 * Accounts-package dependency, injected deliberately. The accounts/media
 * contract enforces that the caller is a platform admin and that the media
 * belongs to the submission. The Next route injects the authenticated byte
 * reader; the isolated core retains an unavailable default for unconfigured
 * callers. Storage paths and service credentials never reach the browser.
 */
export type AdminEvidenceResolver = {
  resolveEvidence(input: EvidenceResolverInput): Promise<EvidenceResolution>;
};

export const unavailableEvidenceResolver: AdminEvidenceResolver = {
  async resolveEvidence() {
    return {
      state: "unavailable",
      reason: "accounts_evidence_gateway_not_integrated",
      message:
        "Evidence preview needs the accounts media gateway. No evidence URL is issued and no bucket is readable from this portal.",
    };
  },
};

const UUID_PATTERN =
  /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

function now(deps: CoreDeps): number {
  return deps.nowSeconds ? deps.nowSeconds() : Math.floor(Date.now() / 1000);
}

function csrfRejected(): CoreResult {
  return {
    status: 403,
    body: {
      ok: false,
      state: "csrf",
      message: "The request origin was rejected.",
    },
  };
}

function unconfigured(): CoreResult {
  return {
    status: 503,
    body: {
      ok: false,
      state: "unconfigured",
      message: "Admin backend is not configured.",
    },
  };
}

function signedOut(): CoreResult {
  return { status: 401, body: { ok: false, state: "signed_out", message: "Sign in again." } };
}

function failureResult(
  result: { status: number; code: string | null; message: string },
  cookies?: CoreCookie[],
): CoreResult {
  const state = classifyAdminFailure(result.status, result.code);
  if (state === "signed_out") return signedOut();
  if (state === "forbidden") {
    return {
      status: 403,
      body: { ok: false, state, message: "Administrator access is required." },
      cookies,
    };
  }
  return { status: 502, body: { ok: false, state, message: result.message }, cookies };
}

function rotatedSessionCookies(
  deps: CoreDeps,
  accessToken: string,
  refreshToken: string,
  expiresIn: number,
): CoreCookie[] {
  return [
    {
      name: SESSION_COOKIE,
      value: accessToken,
      options: sessionCookieOptions({ expiresIn, isProduction: deps.isProduction }),
    },
    {
      name: REFRESH_COOKIE,
      value: refreshToken,
      options: refreshCookieOptions({ isProduction: deps.isProduction }),
    },
  ];
}

function pendingCookie(
  deps: CoreDeps,
  accessToken: string,
  expiresIn: number,
): CoreCookie {
  return {
    name: MFA_PENDING_COOKIE,
    value: accessToken,
    options: pendingCookieOptions({ isProduction: deps.isProduction, maxAge: expiresIn }),
  };
}

export function clearedSessionCookies(): CoreCookie[] {
  return [SESSION_COOKIE, REFRESH_COOKIE].map((name) => ({
    name,
    value: "",
    options: clearedCookieOptions(),
  }));
}

function clearedPendingCookie(): CoreCookie {
  return { name: MFA_PENDING_COOKIE, value: "", options: clearedCookieOptions() };
}

// ---------------------------------------------------------------------------
// Centralized session admission
// ---------------------------------------------------------------------------

export type SessionAdmission =
  | { ok: true; claims: JwtClaims | null }
  | {
      ok: false;
      status: number;
      state: "signed_out" | "mfa_required" | "assurance_unavailable" | "unavailable";
      message: string;
    };

/**
 * Validates one stored access token against the configured policy. With the
 * policy required, the strict assurance shape is enforced and the provider
 * itself is asked to validate the session; a malformed or absent claim set is
 * never treated as a completed second factor. The database
 * `platform_admins` check still runs inside every dispatched RPC.
 */
export async function admitSession({
  config,
  policy,
  accessToken,
  fetchImpl = fetch,
  nowSeconds,
}: {
  config: AdminConfig;
  policy: AdminMfaPolicy;
  accessToken: string;
  fetchImpl?: typeof fetch;
  nowSeconds: number;
}): Promise<SessionAdmission> {
  const claims = decodeTokenClaims(accessToken);
  if (policy === "off") {
    if (sessionTokenExpired(claims, nowSeconds)) {
      return { ok: false, status: 401, state: "signed_out", message: "Sign in again." };
    }
    return { ok: true, claims };
  }
  const assurance = requiredAssuranceState(claims);
  if (assurance === "aal1") {
    return {
      ok: false,
      status: 403,
      state: "mfa_required",
      message: "Multi-factor assurance is required for this session.",
    };
  }
  if (assurance === "unverifiable" || claims === null || claims.expiresAt === null) {
    return {
      ok: false,
      status: 403,
      state: "assurance_unavailable",
      message: "The stored session has no verifiable second-factor assurance. Sign in again.",
    };
  }
  if (claims.expiresAt <= nowSeconds) {
    return { ok: false, status: 401, state: "signed_out", message: "Sign in again." };
  }
  const provider = await providerUserSession(config, accessToken, fetchImpl);
  if (!provider.ok) {
    if (provider.state === "signed_out") {
      return { ok: false, status: 401, state: "signed_out", message: "Sign in again." };
    }
    return {
      ok: false,
      status: 502,
      state: "unavailable",
      message:
        "The authentication provider could not verify the session. No privileged action was run; retry shortly.",
    };
  }
  return { ok: true, claims };
}

// ---------------------------------------------------------------------------
// Login and second factor
// ---------------------------------------------------------------------------

/** POST /api/login behavior, including MFA assurance admission. */
export async function handleLoginCore(
  request: CoreRequest,
  deps: CoreDeps,
): Promise<CoreResult> {
  if (evaluateRequestOrigin(request) === "reject") return csrfRejected();
  if (!deps.config) return unconfigured();
  const parsed = parseLoginBody(request.body);
  if (!parsed.ok) {
    return { status: 400, body: { ok: false, state: "invalid", message: parsed.message } };
  }
  const fetchImpl = deps.fetchImpl ?? fetch;
  const signed = await signInWithPassword(
    deps.config,
    parsed.value.email,
    parsed.value.password,
    fetchImpl,
  );
  if (!signed.ok) {
    return {
      status: 401,
      body: { ok: false, state: "signed_out", message: signed.message },
    };
  }
  const claims = decodeTokenClaims(signed.accessToken);
  const admission = admitLogin({
    policy: deps.mfaPolicy,
    claims,
    nowSeconds: now(deps),
  });
  if (!admission.ok) {
    if (admission.state === "expired") {
      return {
        status: 401,
        body: { ok: false, state: "signed_out", message: admission.message },
      };
    }
    if (admission.state === "mfa_required") {
      // A half-finished factor lives in a short-lived pending cookie only.
      const pending = pendingCookie(deps, signed.accessToken, signed.expiresIn);
      const provider = await providerUserSession(deps.config, signed.accessToken, fetchImpl);
      if (provider.ok) {
        const factors = provider.factors.filter((factor) => factor.status === "verified");
        if (factors.length === 0) {
          const eligible = await callRpc(deps.config, signed.accessToken, "admin_mfa_enrollment_eligible", {}, fetchImpl);
          if (!eligible.ok || eligible.data !== true) return {
            status: 403, body: { ok: false, state: "forbidden", message: "This account is not authorised for administrator setup." },
          };
          return {
            status: 403,
            body: { ok: false, state: "mfa_setup_required", message: "Set up your authenticator to finish administrator sign-in." },
            cookies: [pending, ...clearedSessionCookies()],
          };
        }
        return {
          status: 403,
          body: {
            ok: false,
            state: "mfa_required",
            message: admission.message,
            factors,
          },
          cookies: [pending],
        };
      }
      if (provider.state === "unavailable") {
        return {
          status: 502,
          body: {
            ok: false,
            state: "assurance_unavailable",
            message:
              "The second-factor directory is unreachable. Retry shortly; no privileged session was issued.",
          },
          cookies: [pending],
        };
      }
      return {
        status: 401,
        body: { ok: false, state: "signed_out", message: "Sign in again." },
      };
    }
    return {
      status: 403,
      body: { ok: false, state: admission.state, message: admission.message },
    };
  }
  // Confirm the account is a platform administrator before storing a session.
  const adminCheck = await callRpc(
    deps.config,
    signed.accessToken,
    "marketplace_admin_moderation_queue",
    { p_limit: 1, p_cursor: null },
    fetchImpl,
  );
  if (!adminCheck.ok) {
    const state = classifyAdminFailure(adminCheck.status, adminCheck.code);
    const notAdmin = state === "signed_out" || state === "forbidden";
    return {
      status: notAdmin ? 403 : 502,
      body: {
        ok: false,
        state: notAdmin ? "forbidden" : "error",
        message: notAdmin
          ? "This account is not a platform administrator."
          : "The administrator check could not be completed. Try again.",
      },
    };
  }
  return {
    status: 200,
    body: { ok: true },
    cookies: rotatedSessionCookies(
      deps,
      signed.accessToken,
      signed.refreshToken,
      signed.expiresIn,
    ),
  };
}

async function readPendingSession(
  request: CoreRequest,
  deps: CoreDeps,
): Promise<{ ok: true } | { ok: false; result: CoreResult }> {
  if (!request.pendingToken) {
    return {
      ok: false,
      result: {
        status: 401,
        body: {
          ok: false,
          state: "pending_expired",
          message: "The second-factor step expired. Sign in again.",
        },
      },
    };
  }
  const claims = decodeTokenClaims(request.pendingToken);
  if (
    !claims?.subject ||
    claims.expiresAt === null ||
    claims.expiresAt <= now(deps)
  ) {
    return {
      ok: false,
      result: {
        status: 401,
        body: {
          ok: false,
          state: "pending_expired",
          message: "The second-factor step expired. Sign in again.",
        },
        cookies: [clearedPendingCookie()],
      },
    };
  }
  return { ok: true };
}

/** POST /api/mfa/pending: list the enrolled factors for the pending session. */
export async function handleMfaPendingCore(
  request: CoreRequest,
  deps: CoreDeps,
): Promise<CoreResult> {
  if (evaluateRequestOrigin(request) === "reject") return csrfRejected();
  if (!deps.config) return unconfigured();
  if (deps.mfaPolicy !== "required") {
    return {
      status: 409,
      body: { ok: false, state: "mfa_disabled", message: "Second-factor enforcement is not configured." },
    };
  }
  const pending = await readPendingSession(request, deps);
  if (!pending.ok) return pending.result;
  const provider = await providerUserSession(
    deps.config,
    request.pendingToken as string,
    deps.fetchImpl ?? fetch,
  );
  if (!provider.ok) {
    if (provider.state === "signed_out") {
      return {
        status: 401,
        body: { ok: false, state: "pending_expired", message: "Sign in again." },
        cookies: [clearedPendingCookie()],
      };
    }
    return {
      status: 502,
      body: {
        ok: false,
        state: "assurance_unavailable",
        message: "The second-factor directory is unreachable. Retry shortly.",
      },
    };
  }
  const factors = provider.factors.filter((factor) => factor.status === "verified");
  if (factors.length === 0) {
    return {
      status: 409,
      body: {
        ok: false,
        state: "mfa_unconfigured",
        message:
          "No enrolled second factor is available for this account. Owner enrollment is required.",
      },
    };
  }
  return { status: 200, body: { ok: true, factors } };
}

/** POST /api/mfa/challenge: start one factor challenge. */
export async function handleMfaChallengeCore(
  request: CoreRequest,
  deps: CoreDeps,
): Promise<CoreResult> {
  if (evaluateRequestOrigin(request) === "reject") return csrfRejected();
  if (!deps.config) return unconfigured();
  if (deps.mfaPolicy !== "required") {
    return {
      status: 409,
      body: { ok: false, state: "mfa_disabled", message: "Second-factor enforcement is not configured." },
    };
  }
  const pending = await readPendingSession(request, deps);
  if (!pending.ok) return pending.result;
  const body = request.body;
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { status: 400, body: { ok: false, state: "invalid", message: "Malformed challenge request." } };
  }
  const factorId = (body as Record<string, unknown>).factor_id;
  if (typeof factorId !== "string" || !UUID_PATTERN.test(factorId.trim())) {
    return { status: 400, body: { ok: false, state: "invalid", message: "Malformed challenge request." } };
  }
  const challenge = await beginMfaChallenge(
    deps.config,
    request.pendingToken as string,
    factorId.trim(),
    deps.fetchImpl ?? fetch,
  );
  if (!challenge.ok) {
    if (challenge.state === "signed_out") {
      return {
        status: 401,
        body: { ok: false, state: "pending_expired", message: "Sign in again." },
        cookies: [clearedPendingCookie()],
      };
    }
    if (challenge.state === "invalid_factor") {
      return {
        status: 404,
        body: {
          ok: false,
          state: "invalid_factor",
          message: "That second factor is not available for this account.",
        },
      };
    }
    return {
      status: 502,
      body: {
        ok: false,
        state: "assurance_unavailable",
        message: "The second-factor directory is unreachable. Retry shortly.",
      },
    };
  }
  return {
    status: 200,
    body: { ok: true, challenge_id: challenge.challengeId, expires_at: challenge.expiresAt },
  };
}

/** POST /api/mfa/verify: complete the factor and issue the privileged session. */
export async function handleMfaVerifyCore(
  request: CoreRequest,
  deps: CoreDeps,
): Promise<CoreResult> {
  if (evaluateRequestOrigin(request) === "reject") return csrfRejected();
  if (!deps.config) return unconfigured();
  if (deps.mfaPolicy !== "required") {
    return {
      status: 409,
      body: { ok: false, state: "mfa_disabled", message: "Second-factor enforcement is not configured." },
    };
  }
  const pending = await readPendingSession(request, deps);
  if (!pending.ok) return pending.result;
  const body = request.body;
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { status: 400, body: { ok: false, state: "invalid", message: "Malformed verification request." } };
  }
  const record = body as Record<string, unknown>;
  const factorId = typeof record.factor_id === "string" ? record.factor_id.trim() : "";
  const challengeId = typeof record.challenge_id === "string" ? record.challenge_id.trim() : "";
  const code = typeof record.code === "string" ? record.code.trim() : "";
  if (!UUID_PATTERN.test(factorId) || !UUID_PATTERN.test(challengeId) || !/^\d{6}$/.test(code)) {
    return { status: 400, body: { ok: false, state: "invalid", message: "Malformed verification request." } };
  }
  const fetchImpl = deps.fetchImpl ?? fetch;
  const verified = await verifyMfaChallenge(
    deps.config,
    request.pendingToken as string,
    factorId,
    challengeId,
    code,
    fetchImpl,
  );
  if (!verified.ok) {
    if (verified.state === "signed_out") {
      return {
        status: 401,
        body: { ok: false, state: "pending_expired", message: "Sign in again." },
        cookies: [clearedPendingCookie()],
      };
    }
    if (verified.state === "invalid_code") {
      return {
        status: 400,
        body: {
          ok: false,
          state: "invalid_code",
          message: "That code was rejected or the challenge expired. Request a new code and try again.",
        },
      };
    }
    if (verified.state === "rate_limited") {
      return {
        status: 429,
        body: {
          ok: false,
          state: "rate_limited",
          message: "Too many attempts. Wait before requesting another code.",
        },
      };
    }
    return {
      status: 502,
      body: {
        ok: false,
        state: "assurance_unavailable",
        message: "The second-factor check could not be completed. Retry shortly.",
      },
    };
  }
  // The upgraded session must still pass strict admission, and the account
  // must still be a platform administrator, before any cookie is issued.
  const admission = await admitSession({
    config: deps.config,
    policy: deps.mfaPolicy,
    accessToken: verified.accessToken,
    fetchImpl,
    nowSeconds: now(deps),
  });
  if (!admission.ok) {
    return {
      status: admission.status,
      body: { ok: false, state: admission.state, message: admission.message },
      cookies: [clearedPendingCookie(), ...clearedSessionCookies()],
    };
  }
  const adminCheck = await callRpc(
    deps.config,
    verified.accessToken,
    "marketplace_admin_moderation_queue",
    { p_limit: 1, p_cursor: null },
    fetchImpl,
  );
  if (!adminCheck.ok) {
    const state = classifyAdminFailure(adminCheck.status, adminCheck.code);
    const notAdmin = state === "signed_out" || state === "forbidden";
    return {
      status: notAdmin ? 403 : 502,
      body: {
        ok: false,
        state: notAdmin ? "forbidden" : "error",
        message: notAdmin
          ? "This account is not a platform administrator."
          : "The administrator check could not be completed. Try again.",
      },
      cookies: [clearedPendingCookie()],
    };
  }
  return {
    status: 200,
    body: { ok: true },
    cookies: [
      ...rotatedSessionCookies(
        deps,
        verified.accessToken,
        verified.refreshToken,
        verified.expiresIn,
      ),
      clearedPendingCookie(),
    ],
  };
}

/** POST /api/mfa/cancel: abandon an unfinished second factor. */
export function handleMfaCancelCore(request: CoreRequest): CoreResult {
  if (evaluateRequestOrigin(request) === "reject") return csrfRejected();
  return { status: 200, body: { ok: true }, cookies: [clearedPendingCookie()] };
}

/** POST/GET /api/logout behavior with same-origin enforcement. */
export async function handleLogoutCore(request: CoreRequest, deps?: CoreDeps): Promise<CoreResult> {
  if (evaluateRequestOrigin(request) === "reject") return csrfRejected();
  let access = request.sessionToken || request.pendingToken;
  if (request.refreshToken) {
    if (!deps?.config) return { status: 503, body: { error: 'logout_unavailable' } };
    const rotated = await refreshSession(deps.config, request.refreshToken, deps.fetchImpl);
    if (!rotated.ok && rotated.state === 'unavailable') return { status: 503, body: { error: 'logout_unavailable' } };
    if (rotated.ok) access = rotated.accessToken;
  }
  if (access && (!deps?.config || !await revokeSession(deps.config, access, deps.fetchImpl))) {
    return { status: 503, body: { error: 'logout_unavailable' } };
  }
  return {
    status: 200,
    body: { ok: true },
    cookies: [...clearedSessionCookies(), clearedPendingCookie()],
    redirectTo: request.method.toUpperCase() === "GET" ? "/login" : undefined,
  };
}

// ---------------------------------------------------------------------------
// Privileged dispatch with session recovery
// ---------------------------------------------------------------------------

type ResolvedSession =
  | { ok: true; token: string; cookies?: CoreCookie[]; rotated: boolean }
  | { ok: false; result: CoreResult };

function admissionFailure(
  admission: Extract<SessionAdmission, { ok: false }>,
  rotated: CoreCookie[] | undefined,
): CoreResult {
  const result: CoreResult = {
    status: admission.status,
    body: { ok: false, state: admission.state, message: admission.message },
  };
  if (
    admission.state === "signed_out" ||
    admission.state === "mfa_required" ||
    admission.state === "assurance_unavailable"
  ) {
    result.cookies = [...(rotated ?? []), ...clearedSessionCookies()];
  } else if (rotated) {
    result.cookies = rotated;
  }
  return result;
}

/**
 * Resolves the privileged session for a request: refreshes an absent or
 * expired access cookie when a refresh cookie exists, then applies provider
 * admission. Rotation is returned as cookie directives and enforced once.
 * A transient provider failure is never treated as a definitive rejection:
 * no privileged work is dispatched, the recoverable cookies are preserved and
 * the caller receives a retryable unavailable outcome.
 */
async function resolveSession(request: CoreRequest, deps: CoreDeps): Promise<ResolvedSession> {
  const fetchImpl = deps.fetchImpl ?? fetch;
  const token = request.sessionToken;
  const refreshToken = request.refreshToken ?? "";
  let cookies: CoreCookie[] | undefined;
  let rotated = false;

  const claims = token ? decodeTokenClaims(token) : null;
  if (!token || sessionTokenExpired(claims, now(deps))) {
    if (!refreshToken) {
      return token
        ? { ok: false, result: { ...signedOut(), cookies: clearedSessionCookies() } }
        : { ok: false, result: signedOut() };
    }
    const refreshed = await refreshSession(deps.config as AdminConfig, refreshToken, fetchImpl);
    if (refreshed.ok) {
      return await admitRefreshedSession(refreshed, deps, fetchImpl);
    }
    if (refreshed.state === "expired") {
      return { ok: false, result: { ...signedOut(), cookies: clearedSessionCookies() } };
    }
    return { ok: false, result: unavailableResult() };
  }

  const admission = await admitSession({
    config: deps.config as AdminConfig,
    policy: deps.mfaPolicy,
    accessToken: token as string,
    fetchImpl,
    nowSeconds: now(deps),
  });
  if (!admission.ok) return { ok: false, result: admissionFailure(admission, cookies) };
  return { ok: true, token: token as string, cookies, rotated };
}

function unavailableResult(rotated?: CoreCookie[]): CoreResult {
  return {
    status: 502,
    body: {
      ok: false,
      state: "unavailable",
      message:
        "The authentication provider is unavailable, so the session could not be renewed. No privileged action was run; retry shortly.",
    },
    cookies: rotated,
  };
}

/** Applies admission to freshly rotated tokens and returns the session. */
async function admitRefreshedSession(
  refreshed: Extract<Awaited<ReturnType<typeof refreshSession>>, { ok: true }>,
  deps: CoreDeps,
  fetchImpl: typeof fetch,
): Promise<ResolvedSession> {
  const rotated = rotatedSessionCookies(
    deps,
    refreshed.accessToken,
    refreshed.refreshToken,
    refreshed.expiresIn,
  );
  const admission = await admitSession({
    config: deps.config as AdminConfig,
    policy: deps.mfaPolicy,
    accessToken: refreshed.accessToken,
    fetchImpl,
    nowSeconds: now(deps),
  });
  if (!admission.ok) return { ok: false, result: admissionFailure(admission, rotated) };
  return { ok: true, token: refreshed.accessToken, cookies: rotated, rotated: true };
}

/** POST /api/admin-rpc behavior: admission, refresh recovery, one retry. */
export async function handleAdminRpcCore(
  request: CoreRequest,
  deps: CoreDeps,
): Promise<CoreResult> {
  if (evaluateRequestOrigin(request) === "reject") return csrfRejected();
  if (!deps.config) return unconfigured();
  const parsed = parseAdminRpcBody(request.body);
  if (!parsed.ok) {
    return { status: 400, body: { ok: false, state: "invalid", message: parsed.message } };
  }
  const resolved = await resolveSession(request, deps);
  if (!resolved.ok) return resolved.result;
  const fetchImpl = deps.fetchImpl ?? fetch;

  const first = await callRpc(
    deps.config,
    resolved.token,
    parsed.value.functionName,
    parsed.value.params,
    fetchImpl,
  );
  if (first.ok) {
    return { status: 200, body: { ok: true, data: first.data }, cookies: resolved.cookies };
  }

  const firstState = classifyAdminFailure(first.status, first.code);
  if (
    shouldRefreshSession({
      state: firstState,
      hasRefreshToken: (request.refreshToken ?? "").length > 0,
      alreadyRetried: resolved.rotated,
    })
  ) {
    const refreshed = await refreshSession(
      deps.config,
      request.refreshToken as string,
      fetchImpl,
    );
    if (refreshed.ok) {
      const rotated = rotatedSessionCookies(
        deps,
        refreshed.accessToken,
        refreshed.refreshToken,
        refreshed.expiresIn,
      );
      const admission = await admitSession({
        config: deps.config,
        policy: deps.mfaPolicy,
        accessToken: refreshed.accessToken,
        fetchImpl,
        nowSeconds: now(deps),
      });
      if (!admission.ok) return admissionFailure(admission, rotated);
      const retry = await callRpc(
        deps.config,
        refreshed.accessToken,
        parsed.value.functionName,
        parsed.value.params,
        fetchImpl,
      );
      if (retry.ok) {
        return { status: 200, body: { ok: true, data: retry.data }, cookies: rotated };
      }
      return failureResult(retry, retry.status === 401 ? undefined : rotated);
    }
    if (refreshed.state === "expired") {
      return { ...signedOut(), cookies: clearedSessionCookies() };
    }
    // Transient refresh failure after a rejected access token: retryable, and
    // the recoverable cookies are preserved for a later attempt.
    return unavailableResult();
  }

  return failureResult(first, first.status === 401 ? undefined : resolved.cookies);
}

// ---------------------------------------------------------------------------
// Session refresh route
// ---------------------------------------------------------------------------

/**
 * GET /api/session/refresh?next=...: consistent recovery for an absent or
 * expired access cookie with a refresh cookie present. Rotation is persisted
 * once; a definitively rejected refresh clears the cookies and returns to the
 * reachable sign-in page.
 */
export async function handleSessionRefreshCore(
  request: CoreRequest,
  deps: CoreDeps,
): Promise<CoreResult> {
  if (evaluateRequestOrigin(request) === "reject") return csrfRejected();
  if (!deps.config) return unconfigured();
  const next = sanitizeNextPath(request.nextPath);
  const fetchImpl = deps.fetchImpl ?? fetch;
  const nowSeconds = now(deps);

  const claims = request.sessionToken ? decodeTokenClaims(request.sessionToken) : null;
  if (request.sessionToken && !sessionTokenExpired(claims, nowSeconds)) {
    const admission = await admitSession({
      config: deps.config,
      policy: deps.mfaPolicy,
      accessToken: request.sessionToken,
      fetchImpl,
      nowSeconds,
    });
    if (admission.ok || admission.state === "unavailable") {
      return { status: 200, body: { ok: true }, redirectTo: next };
    }
  }

  if (!request.refreshToken) {
    return {
      status: 200,
      body: { ok: true },
      cookies: clearedSessionCookies(),
      redirectTo: "/login",
    };
  }
  const refreshed = await refreshSession(deps.config, request.refreshToken, fetchImpl);
  if (!refreshed.ok) {
    if (refreshed.state === "expired") {
      return {
        status: 200,
        body: { ok: true },
        cookies: clearedSessionCookies(),
        redirectTo: "/login",
      };
    }
    // Provider outage: preserve the cookies and terminate the navigation on a
    // reachable retry page instead of redirecting back into the guard.
    return {
      status: 200,
      body: { ok: true },
      redirectTo: `/session-unavailable?next=${encodeURIComponent(next)}`,
    };
  }
  const rotated = rotatedSessionCookies(
    deps,
    refreshed.accessToken,
    refreshed.refreshToken,
    refreshed.expiresIn,
  );
  const admission = await admitSession({
    config: deps.config,
    policy: deps.mfaPolicy,
    accessToken: refreshed.accessToken,
    fetchImpl,
    nowSeconds,
  });
  if (!admission.ok) {
    if (admission.state === "unavailable") {
      return { status: 200, body: { ok: true }, cookies: rotated, redirectTo: next };
    }
    return {
      status: 200,
      body: { ok: true },
      cookies: [...rotated, ...clearedSessionCookies()],
      redirectTo: "/login",
    };
  }
  return { status: 200, body: { ok: true }, cookies: rotated, redirectTo: next };
}

// ---------------------------------------------------------------------------
// Evidence gateway
// ---------------------------------------------------------------------------

/** POST /api/admin-evidence behavior: narrow admin-checked evidence gateway. */
export async function handleEvidenceCore(
  request: CoreRequest,
  deps: CoreDeps,
  resolver: AdminEvidenceResolver = unavailableEvidenceResolver,
): Promise<CoreResult> {
  if (evaluateRequestOrigin(request) === "reject") return csrfRejected();
  if (!deps.config) return unconfigured();
  const resolved = await resolveSession(request, deps);
  if (!resolved.ok) return resolved.result;
  const body = request.body;
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { status: 400, body: { ok: false, state: "invalid", message: "Malformed evidence request." } };
  }
  const record = body as Record<string, unknown>;
  const submissionId =
    typeof record.submission_id === "string" ? record.submission_id.trim() : "";
  const mediaId = typeof record.media_id === "string" ? record.media_id.trim() : "";
  if (!UUID_PATTERN.test(submissionId) || !UUID_PATTERN.test(mediaId)) {
    return { status: 400, body: { ok: false, state: "invalid", message: "Malformed evidence request." } };
  }
  const fetchImpl = deps.fetchImpl ?? fetch;
  const reference = await callRpc(
    deps.config,
    resolved.token,
    "admin_evidence_reference",
    { p_submission: submissionId, p_media: mediaId },
    fetchImpl,
  );
  if (!reference.ok) {
    const state = classifyAdminFailure(reference.status, reference.code);
    if (state === "signed_out") {
      return { ...signedOut(), cookies: resolved.cookies };
    }
    if (state === "forbidden") {
      return {
        status: 403,
        body: { ok: false, state, message: "Administrator access is required." },
        cookies: resolved.cookies,
      };
    }
    if (reference.code === "P0002") {
      return {
        status: 404,
        body: {
          ok: false,
          state: "not_found",
          message: "That submission is no longer available for review.",
        },
        cookies: resolved.cookies,
      };
    }
    return {
      status: 502,
      body: { ok: false, state: "error", message: "The evidence reference could not be checked." },
      cookies: resolved.cookies,
    };
  }
  const referenceData = reference.data as { reference_ok?: unknown } | null;
  if (!referenceData || referenceData.reference_ok !== true) {
    return {
      status: 404,
      body: {
        ok: false,
        state: "not_found",
        message: "That evidence reference does not belong to the selected submission.",
      },
      cookies: resolved.cookies,
    };
  }
  const resolution = await resolver.resolveEvidence({
    submissionId,
    mediaId,
    accessToken: resolved.token,
    config: deps.config,
    fetchImpl,
  });
  if (resolution.state === "unavailable") {
    return {
      status: 501,
      body: {
        ok: false,
        state: "unavailable",
        reason: resolution.reason,
        message: resolution.message,
      },
      cookies: resolved.cookies,
    };
  }
  if (resolution.state === "image") {
    return { status: 200, body: {}, image: resolution.bytes, cookies: resolved.cookies };
  }
  if (!evidenceUrlAllowed(resolution.url, deps.evidenceHost)) {
    return {
      status: 502,
      body: {
        ok: false,
        state: "error",
        message: "The evidence gateway returned a URL that this portal will not open.",
      },
      cookies: resolved.cookies,
    };
  }
  return {
    status: 200,
    body: { ok: true, url: resolution.url, expires_at: resolution.expires_at },
    cookies: resolved.cookies,
  };
}

// ---------------------------------------------------------------------------
// Server-rendered loader admission
// ---------------------------------------------------------------------------

export type SessionLoad<T> =
  | { state: "ok"; data: T }
  | { state: "unconfigured" }
  | { state: "signed_out" }
  | { state: "forbidden" }
  | { state: "error"; message: string };

/**
 * Server-rendered load path. It enforces the same policy as the API bridge, so
 * a stored aal1 or malformed session cannot read data through a page loader
 * even when the API rejects it. Rotation is intentionally not attempted here:
 * a server render cannot persist rotated cookies, and a single-use refresh
 * token must not be consumed without persisting its replacement.
 */
export async function loadAdminDataCore<T>({
  config,
  policy,
  accessToken,
  functionName,
  params,
  fetchImpl = fetch,
  nowSeconds,
}: {
  config: AdminConfig | null;
  policy: AdminMfaPolicy;
  accessToken: string | null;
  functionName: string;
  params: Record<string, unknown>;
  fetchImpl?: typeof fetch;
  nowSeconds: number;
}): Promise<SessionLoad<T>> {
  if (!config) return { state: "unconfigured" };
  if (!accessToken) return { state: "signed_out" };
  const admission = await admitSession({
    config,
    policy,
    accessToken,
    fetchImpl,
    nowSeconds,
  });
  if (!admission.ok) {
    if (
      admission.state === "signed_out" ||
      admission.state === "mfa_required" ||
      admission.state === "assurance_unavailable"
    ) {
      return { state: "signed_out" };
    }
    return { state: "error", message: admission.message };
  }
  const result = await callRpc(config, accessToken, functionName, params, fetchImpl);
  if (!result.ok) {
    if (result.status === 401) return { state: "signed_out" };
    if (result.status === 403 || result.code === "42501") return { state: "forbidden" };
    return { state: "error", message: result.message };
  }
  return { state: "ok", data: result.data as T };
}

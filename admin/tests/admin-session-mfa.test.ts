// HTTP-level regression tests for the session/MFA corrections:
//   * required MFA is enforced on every privileged path (not login only),
//   * the password -> pending -> challenge -> verify second-factor journey,
//   * absent/expired access cookie recovery through the refresh cookie.
// Real request values, injected fetch, no live provider.
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  admitSession,
  handleAdminRpcCore,
  handleEvidenceCore,
  handleLoginCore,
  handleMfaCancelCore,
  handleMfaChallengeCore,
  handleMfaPendingCore,
  handleMfaVerifyCore,
  handleSessionRefreshCore,
  loadAdminDataCore,
  type AdminEvidenceResolver,
  type CoreCookie,
  type CoreDeps,
  type CoreRequest,
} from "../app/lib/admin-http";
import { MFA_PENDING_COOKIE, REFRESH_COOKIE, SESSION_COOKIE } from "../app/lib/admin-session";

const CONFIG = { url: "https://project.supabase.co", anonKey: "anon-key" };
const SUBMISSION = "90000000-0000-4000-8000-000000000001";
const MEDIA = "90000000-0000-4000-8000-00000000000a";
const FACTOR = "95000000-0000-4000-8000-000000000001";
const CHALLENGE = "96000000-0000-4000-8000-000000000001";

function base64url(value: string): string {
  return Buffer.from(value, "utf8")
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function token(payload: Record<string, unknown>): string {
  return `${base64url(JSON.stringify({ alg: "HS256" }))}.${base64url(JSON.stringify(payload))}.sig`;
}

const aal1 = (exp = 5000) => token({ sub: "user-1", aal: "aal1", exp });
const aal2 = (exp = 9000) => token({ sub: "user-1", aal: "aal2", exp });

type Route = (url: URL) => { status: number; body: unknown } | undefined;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function fakeFetch(routes: Route[]) {
  const calls: string[] = [];
  const fetchImpl = (async (input: string | URL | Request) => {
    const url = new URL(typeof input === "string" ? input : input.toString());
    calls.push(`${url.pathname}${url.search}`);
    for (const route of routes) {
      const result = route(url);
      if (result) return json(result.status, result.body);
    }
    return json(500, { message: "unexpected" });
  }) as typeof fetch;
  return { fetchImpl, calls };
}

const authRoute =
  (status: number, body: unknown): Route =>
  (url) =>
    url.pathname === "/auth/v1/token" ? { status, body } : undefined;

const rpcRoute =
  (name: string, status: number, body: unknown): Route =>
  (url) =>
    url.pathname === `/rest/v1/rpc/${name}` ? { status, body } : undefined;

const providerRoutes = (
  overrides: {
    userStatus?: number;
    factors?: unknown[];
    challengeStatus?: number;
    verifyStatus?: number;
    access?: string;
    refresh?: string;
  } = {},
): Route[] => [
  (url) =>
    url.pathname === "/auth/v1/user"
      ? {
          status: overrides.userStatus ?? 200,
          body:
            overrides.userStatus && overrides.userStatus !== 200
              ? { message: "rejected" }
              : {
                  id: "user-1",
                  factors:
                    overrides.factors ??
                    [
                      {
                        id: FACTOR,
                        factor_type: "totp",
                        status: "verified",
                        friendly_name: "Phone",
                      },
                    ],
                },
        }
      : undefined,
  (url) =>
    url.pathname === `/auth/v1/factors/${FACTOR}/challenge`
      ? {
          status: overrides.challengeStatus ?? 200,
          body:
            overrides.challengeStatus && overrides.challengeStatus !== 200
              ? {}
              : { id: CHALLENGE, expires_at: 2000000000 },
        }
      : undefined,
  (url) =>
    url.pathname === `/auth/v1/factors/${FACTOR}/verify`
      ? {
          status: overrides.verifyStatus ?? 200,
          body:
            overrides.verifyStatus && overrides.verifyStatus !== 200
              ? {}
              : {
                  access_token: overrides.access ?? aal2(),
                  refresh_token: overrides.refresh ?? "refresh-2",
                  expires_in: 3600,
                },
        }
      : undefined,
];

function deps(overrides: Partial<CoreDeps> = {}): CoreDeps {
  return {
    config: CONFIG,
    isProduction: false,
    mfaPolicy: "off",
    evidenceHost: null,
    nowSeconds: () => 1000,
    ...overrides,
  };
}

function request(overrides: Partial<CoreRequest> = {}): CoreRequest {
  return {
    method: "POST",
    origin: "https://admin.hocalist.com",
    host: "admin.hocalist.com",
    secFetchSite: "same-origin",
    sessionToken: null,
    refreshToken: null,
    pendingToken: null,
    nextPath: null,
    body: null,
    ...overrides,
  };
}

const cookie = (cookies: CoreCookie[] | undefined, name: string) =>
  cookies?.find((entry) => entry.name === name);

test("required session admission is strict and provider-validated", async () => {
  const { fetchImpl, calls } = fakeFetch(providerRoutes());
  const ok = await admitSession({
    config: CONFIG,
    policy: "required",
    accessToken: aal2(),
    fetchImpl,
    nowSeconds: 1000,
  });
  assert.equal(ok.ok, true);
  assert.equal(calls.filter((call) => call.startsWith("/auth/v1/user")).length, 1);

  const before = calls.length;
  const denied = await admitSession({
    config: CONFIG,
    policy: "required",
    accessToken: aal1(),
    fetchImpl,
    nowSeconds: 1000,
  });
  assert.equal(denied.ok === false ? denied.state : null, "mfa_required");
  assert.equal(calls.length, before, "an aal1 denial must not call the provider");

  for (const malformed of [
    token({ sub: "user-1", aal: "aal2" }),
    token({ aal: "aal2", exp: 5000 }),
    token({ sub: "user-1", aal: "aal2", exp: null }),
    "opaque-token",
  ]) {
    const result = await admitSession({
      config: CONFIG,
      policy: "required",
      accessToken: malformed,
      fetchImpl,
      nowSeconds: 1000,
    });
    assert.equal(result.ok === false ? result.state : null, "assurance_unavailable");
  }

  const rejected = await admitSession({
    config: CONFIG,
    policy: "required",
    accessToken: aal2(),
    fetchImpl: fakeFetch(providerRoutes({ userStatus: 401 })).fetchImpl,
    nowSeconds: 1000,
  });
  assert.equal(rejected.ok === false ? rejected.state : null, "signed_out");

  const outage = await admitSession({
    config: CONFIG,
    policy: "required",
    accessToken: aal2(),
    fetchImpl: fakeFetch([]).fetchImpl,
    nowSeconds: 1000,
  });
  assert.equal(outage.ok === false ? outage.state : null, "unavailable");

  const policyOff = await admitSession({
    config: CONFIG,
    policy: "off",
    accessToken: aal1(),
    fetchImpl,
    nowSeconds: 1000,
  });
  assert.equal(policyOff.ok, true);
});

test("an existing aal1 cookie cannot dispatch privileged work under required MFA", async () => {
  const { fetchImpl, calls } = fakeFetch([
    rpcRoute("admin_overview", 200, { active_memberships: 99 }),
  ]);
  const result = await handleAdminRpcCore(
    request({ sessionToken: aal1(), body: { function: "admin_overview", params: {} } }),
    deps({ fetchImpl, mfaPolicy: "required" }),
  );
  assert.equal(result.status, 403);
  assert.equal(result.body.state, "mfa_required");
  assert.equal(calls.length, 0, "no privileged dispatch for a denied session");
  assert.equal(cookie(result.cookies, SESSION_COOKIE)?.value, "");
  assert.equal(cookie(result.cookies, REFRESH_COOKIE)?.value, "");
});

test("evidence resolution is never invoked for a denied session", async () => {
  let invoked = false;
  const resolver: AdminEvidenceResolver = {
    async resolveEvidence() {
      invoked = true;
      return { state: "ready", url: "https://media.hocalist.com/a.png", expires_at: null };
    },
  };
  const result = await handleEvidenceCore(
    request({
      sessionToken: aal1(),
      body: { submission_id: SUBMISSION, media_id: MEDIA },
    }),
    deps({ mfaPolicy: "required", fetchImpl: fakeFetch([]).fetchImpl }),
    resolver,
  );
  assert.equal(result.status, 403);
  assert.equal(invoked, false);
});

test("server-rendered loaders enforce the same policy as the API bridge", async () => {
  const blocked = fakeFetch([rpcRoute("admin_overview", 200, { active_memberships: 1 })]);
  const denied = await loadAdminDataCore({
    config: CONFIG,
    policy: "required",
    accessToken: aal1(),
    functionName: "admin_overview",
    params: {},
    fetchImpl: blocked.fetchImpl,
    nowSeconds: 1000,
  });
  assert.equal(denied.state, "signed_out");
  assert.equal(blocked.calls.length, 0);

  const allowed = fakeFetch([
    ...providerRoutes(),
    rpcRoute("admin_overview", 200, { active_memberships: 1 }),
  ]);
  const loaded = await loadAdminDataCore({
    config: CONFIG,
    policy: "required",
    accessToken: aal2(),
    functionName: "admin_overview",
    params: {},
    fetchImpl: allowed.fetchImpl,
    nowSeconds: 1000,
  });
  assert.equal(loaded.state, "ok");
  assert.deepEqual(loaded.state === "ok" ? loaded.data : null, { active_memberships: 1 });

  const outage = await loadAdminDataCore({
    config: CONFIG,
    policy: "required",
    accessToken: aal2(),
    functionName: "admin_overview",
    params: {},
    fetchImpl: fakeFetch([]).fetchImpl,
    nowSeconds: 1000,
  });
  assert.equal(outage.state, "error");
});

test("an absent access cookie is recovered from the refresh cookie before dispatch", async () => {
  const { fetchImpl, calls } = fakeFetch([
    authRoute(200, { access_token: aal2(), refresh_token: "refresh-2", expires_in: 3600 }),
    rpcRoute("admin_overview", 200, { active_memberships: 2 }),
  ]);
  const result = await handleAdminRpcCore(
    request({ refreshToken: "refresh-1", body: { function: "admin_overview", params: {} } }),
    deps({ fetchImpl }),
  );
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.data, { active_memberships: 2 });
  assert.equal(cookie(result.cookies, REFRESH_COOKIE)?.value, "refresh-2");
  assert.equal(calls.filter((call) => call.startsWith("/rest/v1/rpc/")).length, 1);
});

test("a definitively rejected refresh clears the session cookies", async () => {
  const { fetchImpl } = fakeFetch([authRoute(401, { error_description: "expired" })]);
  const result = await handleAdminRpcCore(
    request({ refreshToken: "refresh-1", body: { function: "admin_overview", params: {} } }),
    deps({ fetchImpl }),
  );
  assert.equal(result.status, 401);
  assert.equal(result.body.state, "signed_out");
  assert.equal(cookie(result.cookies, SESSION_COOKIE)?.value, "");
  assert.equal(cookie(result.cookies, REFRESH_COOKIE)?.value, "");
});

test("two concurrent recoveries with one refresh token never both succeed", async () => {
  let refreshCalls = 0;
  const routed = (async (input: string | URL | Request) => {
    const url = new URL(typeof input === "string" ? input : input.toString());
    if (url.pathname === "/auth/v1/token") {
      refreshCalls += 1;
      if (refreshCalls === 1) {
        return json(200, { access_token: aal2(), refresh_token: "refresh-2", expires_in: 3600 });
      }
      return json(401, { error_description: "already used" });
    }
    if (url.pathname === "/rest/v1/rpc/admin_overview") {
      return json(200, { active_memberships: 1 });
    }
    return json(500, {});
  }) as typeof fetch;
  const body = { function: "admin_overview", params: {} };
  const [first, second] = await Promise.all([
    handleAdminRpcCore(request({ refreshToken: "refresh-1", body }), deps({ fetchImpl: routed })),
    handleAdminRpcCore(request({ refreshToken: "refresh-1", body }), deps({ fetchImpl: routed })),
  ]);
  const statuses = [first.status, second.status].sort();
  assert.deepEqual(statuses, [200, 401]);
  const winner = first.status === 200 ? first : second;
  const loser = first.status === 401 ? first : second;
  assert.equal(cookie(winner.cookies, REFRESH_COOKIE)?.value, "refresh-2");
  assert.equal(cookie(loser.cookies, SESSION_COOKIE)?.value, "");
  assert.equal(refreshCalls, 2);
});

test("the refresh route recovers, preserves and terminates sessions correctly", async () => {
  const valid = await handleSessionRefreshCore(
    request({ sessionToken: aal2(), nextPath: "/trust" }),
    deps({ fetchImpl: fakeFetch([]).fetchImpl }),
  );
  assert.equal(valid.status, 200);
  assert.equal(valid.redirectTo, "/trust");
  assert.equal(valid.cookies, undefined);

  const recoveredFetch = fakeFetch([
    authRoute(200, { access_token: aal2(), refresh_token: "r2", expires_in: 3600 }),
  ]);
  const recovered = await handleSessionRefreshCore(
    request({ sessionToken: aal2(100), refreshToken: "r1", nextPath: "/events" }),
    deps({ fetchImpl: recoveredFetch.fetchImpl }),
  );
  assert.equal(recovered.redirectTo, "/events");
  assert.equal(cookie(recovered.cookies, REFRESH_COOKIE)?.value, "r2");
  assert.equal(recoveredFetch.calls.length, 1);

  const dead = await handleSessionRefreshCore(
    request({ sessionToken: aal2(100), refreshToken: "r1", nextPath: "/audit" }),
    deps({ fetchImpl: fakeFetch([authRoute(401, {})]).fetchImpl }),
  );
  assert.equal(dead.redirectTo, "/login");
  assert.equal(cookie(dead.cookies, SESSION_COOKIE)?.value, "");

  const outage = await handleSessionRefreshCore(
    request({ refreshToken: "r1", nextPath: "/billing" }),
    deps({ fetchImpl: fakeFetch([]).fetchImpl }),
  );
  // A transient provider failure must not bounce back into the guard.
  assert.equal(outage.redirectTo, "/session-unavailable?next=%2Fbilling");
  assert.equal(outage.cookies, undefined);

  const hostile = await handleSessionRefreshCore(
    request({ sessionToken: aal2(), nextPath: "https://evil.example" }),
    deps({ fetchImpl: fakeFetch([]).fetchImpl }),
  );
  assert.equal(hostile.redirectTo, "/dashboard");

  const unknown = await handleSessionRefreshCore(
    request({ nextPath: "/settings" }),
    deps({ fetchImpl: fakeFetch([]).fetchImpl }),
  );
  assert.equal(unknown.redirectTo, "/login");
  assert.equal(cookie(unknown.cookies, SESSION_COOKIE)?.value, "");

  const csrf = await handleSessionRefreshCore(
    request({ origin: "https://evil.example" }),
    deps(),
  );
  assert.equal(csrf.status, 403);
});

test("password -> pending -> challenge -> verify completes the required second factor", async () => {
  const login = await handleLoginCore(
    request({ body: { email: "admin@x.test", password: "secret" } }),
    deps({
      mfaPolicy: "required",
      fetchImpl: fakeFetch([
        authRoute(200, { access_token: aal1(), refresh_token: "r1", expires_in: 3600 }),
        ...providerRoutes(),
      ]).fetchImpl,
    }),
  );
  assert.equal(login.status, 403);
  assert.equal(login.body.state, "mfa_required");
  assert.equal(cookie(login.cookies, SESSION_COOKIE), undefined);
  assert.equal(cookie(login.cookies, REFRESH_COOKIE), undefined);
  const pending = cookie(login.cookies, MFA_PENDING_COOKIE);
  assert.ok(pending);

  // The pending cookie is not a privileged session.
  const ignored = await handleAdminRpcCore(
    request({ pendingToken: aal1(), body: { function: "admin_overview", params: {} } }),
    deps({ mfaPolicy: "required" }),
  );
  assert.equal(ignored.status, 401);

  const factors = await handleMfaPendingCore(
    request({ pendingToken: aal1() }),
    deps({ mfaPolicy: "required", fetchImpl: fakeFetch(providerRoutes()).fetchImpl }),
  );
  assert.equal(factors.status, 200);
  assert.equal((factors.body.factors as unknown[]).length, 1);

  const challenge = await handleMfaChallengeCore(
    request({ pendingToken: aal1(), body: { factor_id: FACTOR } }),
    deps({ mfaPolicy: "required", fetchImpl: fakeFetch(providerRoutes()).fetchImpl }),
  );
  assert.equal(challenge.status, 200);
  assert.equal(challenge.body.challenge_id, CHALLENGE);

  const wrong = await handleMfaVerifyCore(
    request({
      pendingToken: aal1(),
      body: { factor_id: FACTOR, challenge_id: CHALLENGE, code: "000000" },
    }),
    deps({ mfaPolicy: "required", fetchImpl: fakeFetch(providerRoutes({ verifyStatus: 422 })).fetchImpl }),
  );
  assert.equal(wrong.status, 400);
  assert.equal(wrong.body.state, "invalid_code");
  assert.equal(cookie(wrong.cookies, SESSION_COOKIE), undefined);

  const replayed = await handleMfaVerifyCore(
    request({
      pendingToken: aal1(),
      body: { factor_id: FACTOR, challenge_id: CHALLENGE, code: "123456" },
    }),
    deps({ mfaPolicy: "required", fetchImpl: fakeFetch(providerRoutes({ verifyStatus: 422 })).fetchImpl }),
  );
  assert.equal(replayed.status, 400);
  assert.equal(replayed.body.state, "invalid_code");

  const verified = await handleMfaVerifyCore(
    request({
      pendingToken: aal1(),
      body: { factor_id: FACTOR, challenge_id: CHALLENGE, code: "123456" },
    }),
    deps({
      mfaPolicy: "required",
      fetchImpl: fakeFetch([
        ...providerRoutes(),
        rpcRoute("marketplace_admin_moderation_queue", 200, { items: [] }),
      ]).fetchImpl,
    }),
  );
  assert.equal(verified.status, 200);
  assert.ok(cookie(verified.cookies, SESSION_COOKIE));
  assert.equal(cookie(verified.cookies, REFRESH_COOKIE)?.value, "refresh-2");
  assert.equal(cookie(verified.cookies, MFA_PENDING_COOKIE)?.value, "");
});

test("second-factor failure and cancellation paths stay closed", async () => {
  const expired = await handleMfaPendingCore(
    request({ pendingToken: aal1(100) }),
    deps({ mfaPolicy: "required", nowSeconds: () => 1000 }),
  );
  assert.equal(expired.status, 401);
  assert.equal(expired.body.state, "pending_expired");
  assert.equal(cookie(expired.cookies, MFA_PENDING_COOKIE)?.value, "");

  const disabled = await handleMfaPendingCore(
    request({ pendingToken: aal1() }),
    deps({ mfaPolicy: "off" }),
  );
  assert.equal(disabled.status, 409);
  assert.equal(disabled.body.state, "mfa_disabled");

  const noPending = await handleMfaChallengeCore(
    request({ body: { factor_id: FACTOR } }),
    deps({ mfaPolicy: "required" }),
  );
  assert.equal(noPending.status, 401);

  const badFactor = await handleMfaChallengeCore(
    request({ pendingToken: aal1(), body: { factor_id: "not-a-uuid" } }),
    deps({ mfaPolicy: "required" }),
  );
  assert.equal(badFactor.status, 400);

  const nonAdmin = await handleMfaVerifyCore(
    request({
      pendingToken: aal1(),
      body: { factor_id: FACTOR, challenge_id: CHALLENGE, code: "123456" },
    }),
    deps({
      mfaPolicy: "required",
      fetchImpl: fakeFetch([
        ...providerRoutes(),
        rpcRoute("marketplace_admin_moderation_queue", 403, { code: "42501" }),
      ]).fetchImpl,
    }),
  );
  assert.equal(nonAdmin.status, 403);
  assert.equal(cookie(nonAdmin.cookies, SESSION_COOKIE), undefined);
  assert.equal(cookie(nonAdmin.cookies, MFA_PENDING_COOKIE)?.value, "");

  const cancelled = handleMfaCancelCore(request({ pendingToken: aal1() }));
  assert.equal(cancelled.status, 200);
  assert.equal(cookie(cancelled.cookies, MFA_PENDING_COOKIE)?.value, "");
});

test("sign-in creates and verifies a fresh challenge within one request, ignoring the earlier browser challenge", async () => {
  const fresh = "96000000-0000-4000-8000-000000000099";
  const calls: string[] = [];
  let verifiedChallenge = "";
  const fallback = fakeFetch([...providerRoutes(), rpcRoute("marketplace_admin_moderation_queue", 200, { items: [] })]).fetchImpl;
  const transport = (async (input, init) => {
    const path = new URL(String(input)).pathname;
    calls.push(path);
    if (path.endsWith("/challenge")) return json(200, { id: fresh });
    if (path.endsWith("/verify")) verifiedChallenge = JSON.parse(String(init?.body)).challenge_id;
    return fallback(input, init);
  }) as typeof fetch;
  const result = await handleMfaVerifyCore(request({ pendingToken: aal1(), body: { factor_id: FACTOR, challenge_id: CHALLENGE, code: "123456" } }), deps({ mfaPolicy: "required", fetchImpl: transport }));
  assert.equal(result.status, 200);
  assert.equal(verifiedChallenge, fresh);
  assert.ok(calls.indexOf(`/auth/v1/factors/${FACTOR}/challenge`) < calls.indexOf(`/auth/v1/factors/${FACTOR}/verify`));
});

test("fresh-challenge failure never verifies the code or issues an admin session", async () => {
  const transport = fakeFetch(providerRoutes({ challengeStatus: 500 }));
  const result = await handleMfaVerifyCore(request({ pendingToken: aal1(), body: { factor_id: FACTOR, code: "123456" } }), deps({ mfaPolicy: "required", fetchImpl: transport.fetchImpl }));
  assert.equal(result.status, 502);
  assert.ok(!transport.calls.some(path => path.endsWith("/verify")));
  assert.equal(cookie(result.cookies, SESSION_COOKIE), undefined);
});

test("provider IP mismatch reports a server failure without blaming the authenticator code", async () => {
  const fallback = fakeFetch(providerRoutes()).fetchImpl;
  const transport = (async (input, init) => String(input).endsWith("/verify") ? json(422, { code: "mfa_ip_address_mismatch" }) : fallback(input, init)) as typeof fetch;
  const result = await handleMfaVerifyCore(request({ pendingToken: aal1(), body: { factor_id: FACTOR, code: "123456" } }), deps({ mfaPolicy: "required", fetchImpl: transport }));
  assert.equal(result.status, 502);
  assert.equal(result.body.state, "assurance_unavailable");
  assert.equal(cookie(result.cookies, SESSION_COOKIE), undefined);
});

// HTTP-level tests for the admin bridge cores: same-origin/CSRF, MFA
// assurance admission, session refresh/expiry/logout and the evidence gateway.
// These exercise real request values and response status/cookie behavior with
// an injected fetch; they are not live provider proof.
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  handleAdminRpcCore,
  handleEvidenceCore,
  handleLoginCore,
  handleLogoutCore,
  unavailableEvidenceResolver,
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

type Route = (url: URL) => { status: number; body: unknown } | undefined;

function fakeFetch(routes: Route[]) {
  const calls: string[] = [];
  const fetchImpl = (async (input: string | URL | Request) => {
    const url = new URL(typeof input === "string" ? input : input.toString());
    calls.push(url.toString());
    for (const route of routes) {
      const result = route(url);
      if (result) {
        return new Response(JSON.stringify(result.body), {
          status: result.status,
          headers: { "Content-Type": "application/json" },
        });
      }
    }
    return new Response(JSON.stringify({ message: "unexpected" }), { status: 500 });
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

test("login rejects cross-site requests before any provider call", async () => {
  const { fetchImpl, calls } = fakeFetch([]);
  const result = await handleLoginCore(
    request({ origin: "https://evil.example" }),
    deps({ fetchImpl }),
  );
  assert.equal(result.status, 403);
  assert.equal(result.body.state, "csrf");
  assert.equal(calls.length, 0);
});

test("login stays unconfigured without server variables", async () => {
  const result = await handleLoginCore(request(), deps({ config: null }));
  assert.equal(result.status, 503);
  assert.equal(result.body.state, "unconfigured");
});

test("login rejects malformed and oversized credentials", async () => {
  const result = await handleLoginCore(
    request({ body: { email: "", password: "x" } }),
    deps(),
  );
  assert.equal(result.status, 400);
  assert.equal(result.body.state, "invalid");
});

test("a failed sign-in never propagates provider detail or a cookie", async () => {
  const { fetchImpl } = fakeFetch([
    authRoute(400, { error_description: "invalid grant for admin@x.test" }),
  ]);
  const result = await handleLoginCore(
    request({ body: { email: "admin@x.test", password: "nope" } }),
    deps({ fetchImpl }),
  );
  assert.equal(result.status, 401);
  assert.equal(result.body.state, "signed_out");
  assert.doesNotMatch(String(result.body.message), /invalid grant|admin@x\.test/);
  assert.equal(result.cookies, undefined);
});

test("required MFA refuses an aal1 session, keeps a pending cookie only, and never checks membership", async () => {
  const access = token({ sub: "user-1", aal: "aal1", exp: 5000 });
  const { fetchImpl, calls } = fakeFetch([
    authRoute(200, { access_token: access, refresh_token: "refresh-1", expires_in: 3600 }),
    (url) =>
      url.pathname === "/auth/v1/user"
        ? {
            status: 200,
            body: {
              id: "user-1",
              factors: [
                { id: FACTOR, factor_type: "totp", status: "verified", friendly_name: "Phone" },
              ],
            },
          }
        : undefined,
  ]);
  const result = await handleLoginCore(
    request({ body: { email: "admin@x.test", password: "secret" } }),
    deps({ fetchImpl, mfaPolicy: "required" }),
  );
  assert.equal(result.status, 403);
  assert.equal(result.body.state, "mfa_required");
  assert.equal(
    (result.body.factors as { id: string }[])[0].id,
    FACTOR,
  );
  assert.equal(cookie(result.cookies, SESSION_COOKIE), undefined);
  assert.equal(cookie(result.cookies, REFRESH_COOKIE), undefined);
  const pending = cookie(result.cookies, MFA_PENDING_COOKIE);
  assert.ok(pending);
  assert.equal(pending.value, access);
  assert.equal(pending.options.maxAge, 600);
  assert.equal(pending.options.httpOnly, true);
  assert.equal(calls.some((call) => call.includes("/rest/v1/rpc/")), false);
});

test("required MFA without enrolled factor or bootstrap eligibility refuses access", async () => {
  const access = token({ sub: "user-1", aal: "aal1", exp: 5000 });
  const { fetchImpl } = fakeFetch([
    authRoute(200, { access_token: access, refresh_token: "refresh-1", expires_in: 3600 }),
    (url) => (url.pathname === "/auth/v1/user" ? { status: 200, body: { id: "user-1", factors: [] } } : undefined),
  ]);
  const result = await handleLoginCore(
    request({ body: { email: "admin@x.test", password: "secret" } }),
    deps({ fetchImpl, mfaPolicy: "required" }),
  );
  assert.equal(result.status, 403);
  assert.equal(result.body.state, "forbidden");
  assert.equal(result.cookies, undefined);
});

test("required MFA with an undecodable token refuses instead of assuming assurance", async () => {
  const { fetchImpl } = fakeFetch([
    authRoute(200, { access_token: "opaque-token", refresh_token: "refresh-1", expires_in: 3600 }),
  ]);
  const result = await handleLoginCore(
    request({ body: { email: "admin@x.test", password: "secret" } }),
    deps({ fetchImpl, mfaPolicy: "required" }),
  );
  assert.equal(result.status, 403);
  assert.equal(result.body.state, "assurance_unavailable");
});

test("an aal2 admin receives hardened httpOnly cookies", async () => {
  const access = token({ sub: "user-1", aal: "aal2", exp: 5000 });
  const { fetchImpl, calls } = fakeFetch([
    authRoute(200, { access_token: access, refresh_token: "refresh-1", expires_in: 7200 }),
    rpcRoute("marketplace_admin_moderation_queue", 200, { items: [] }),
  ]);
  const result = await handleLoginCore(
    request({ body: { email: "admin@x.test", password: "secret" } }),
    deps({ fetchImpl, mfaPolicy: "required" }),
  );
  assert.equal(result.status, 200);
  const session = cookie(result.cookies, SESSION_COOKIE);
  const refresh = cookie(result.cookies, REFRESH_COOKIE);
  assert.ok(session && refresh);
  assert.equal(session.options.httpOnly, true);
  assert.equal(session.options.sameSite, "lax");
  assert.equal(session.options.maxAge, 7200);
  assert.match(calls[1], /marketplace_admin_moderation_queue/);
});

test("a non-admin account is refused after a valid sign-in", async () => {
  const access = token({ sub: "user-1", aal: "aal2", exp: 5000 });
  const { fetchImpl } = fakeFetch([
    authRoute(200, { access_token: access, refresh_token: "refresh-1", expires_in: 3600 }),
    rpcRoute("marketplace_admin_moderation_queue", 403, { code: "42501", message: "denied" }),
  ]);
  const result = await handleLoginCore(
    request({ body: { email: "admin@x.test", password: "secret" } }),
    deps({ fetchImpl }),
  );
  assert.equal(result.status, 403);
  assert.equal(result.body.state, "forbidden");
  assert.equal(result.cookies, undefined);
});

test("rpc bridge rejects cross-site and unknown operations", async () => {
  const csrf = await handleAdminRpcCore(
    request({ origin: "https://evil.example", sessionToken: "t" }),
    deps(),
  );
  assert.equal(csrf.status, 403);
  const unsupported = await handleAdminRpcCore(
    request({ sessionToken: "t", body: { function: "delete_everything", params: {} } }),
    deps(),
  );
  assert.equal(unsupported.status, 400);
  assert.equal(unsupported.body.state, "invalid");
});

test("rpc bridge requires a session cookie", async () => {
  const result = await handleAdminRpcCore(
    request({ body: { function: "admin_overview", params: {} } }),
    deps(),
  );
  assert.equal(result.status, 401);
  assert.equal(result.body.state, "signed_out");
});

test("rpc success forwards the reviewed function with schema profile headers", async () => {
  const seen: RequestInit[] = [];
  const fetchImpl = (async (input: string | URL | Request, init: RequestInit = {}) => {
    seen.push(init);
    return new Response(JSON.stringify({ items: [] }), { status: 200 });
  }) as typeof fetch;
  const result = await handleAdminRpcCore(
    request({
      sessionToken: token({ sub: "user-1", aal: "aal2", exp: 5000 }),
      body: { function: "admin_review_queue", params: { p_limit: 50 } },
    }),
    deps({ fetchImpl }),
  );
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.data, { items: [] });
  const headers = seen[0]?.headers as Record<string, string>;
  assert.equal(headers["Accept-Profile"], "hocalist");
  assert.equal(headers["Content-Profile"], "hocalist");
});

test("rpc bridge refreshes once on an expired session and rotates cookies", async () => {
  // First rpc attempt must 401; the refresh and retry then succeed.
  let attempts = 0;
  const routed = (async (input: string | URL | Request, init: RequestInit = {}) => {
    const url = new URL(typeof input === "string" ? input : input.toString());
    if (url.pathname === "/rest/v1/rpc/admin_overview") {
      attempts += 1;
      if (attempts === 1) {
        return new Response(JSON.stringify({ message: "jwt expired" }), { status: 401 });
      }
      return new Response(JSON.stringify({ active_memberships: 1 }), { status: 200 });
    }
    if (url.pathname === "/auth/v1/token") {
      return new Response(
        JSON.stringify({
          access_token: token({ sub: "user-1", aal: "aal2", exp: 9000 }),
          refresh_token: "refresh-2",
          expires_in: 3600,
        }),
        { status: 200 },
      );
    }
    return new Response("{}", { status: 500 });
  }) as typeof fetch;
  const result = await handleAdminRpcCore(
    request({
      sessionToken: token({ sub: "user-1", aal: "aal2", exp: 5000 }),
      refreshToken: "refresh-1",
      body: { function: "admin_overview", params: {} },
    }),
    deps({ fetchImpl: routed }),
  );
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.data, { active_memberships: 1 });
  assert.equal(cookie(result.cookies, SESSION_COOKIE)?.value.includes("."), true);
  assert.equal(cookie(result.cookies, REFRESH_COOKIE)?.value, "refresh-2");
  assert.equal(attempts, 2);
});

test("a proactively expired stored token is refreshed before the first call", async () => {
  let rpcAttempts = 0;
  const routed = (async (input: string | URL | Request) => {
    const url = new URL(typeof input === "string" ? input : input.toString());
    if (url.pathname === "/rest/v1/rpc/admin_overview") {
      rpcAttempts += 1;
      return new Response(JSON.stringify({ active_memberships: 3 }), { status: 200 });
    }
    if (url.pathname === "/auth/v1/token") {
      return new Response(
        JSON.stringify({
          access_token: token({ sub: "user-1", aal: "aal2", exp: 2000 }),
          refresh_token: "refresh-2",
          expires_in: 3600,
        }),
        { status: 200 },
      );
    }
    return new Response("{}", { status: 500 });
  }) as typeof fetch;
  const result = await handleAdminRpcCore(
    request({
      sessionToken: token({ sub: "user-1", aal: "aal2", exp: 100 }),
      refreshToken: "refresh-1",
      body: { function: "admin_overview", params: {} },
    }),
    deps({ fetchImpl: routed, nowSeconds: () => 1000 }),
  );
  assert.equal(result.status, 200);
  assert.equal(rpcAttempts, 1);
  assert.ok(cookie(result.cookies, REFRESH_COOKIE));
});

test("a definitively expired refresh signs the session out", async () => {
  const routed = (async (input: string | URL | Request) => {
    const url = new URL(typeof input === "string" ? input : input.toString());
    if (url.pathname === "/rest/v1/rpc/admin_overview") {
      return new Response(JSON.stringify({ message: "jwt expired" }), { status: 401 });
    }
    return new Response(JSON.stringify({ error_description: "refresh expired" }), { status: 401 });
  }) as typeof fetch;
  const result = await handleAdminRpcCore(
    request({
      sessionToken: token({ sub: "user-1", aal: "aal2", exp: 5000 }),
      refreshToken: "refresh-1",
      body: { function: "admin_overview", params: {} },
    }),
    deps({ fetchImpl: routed }),
  );
  assert.equal(result.status, 401);
  assert.equal(result.body.state, "signed_out");
});

test("a forbidden rpc is not retried through refresh", async () => {
  const { fetchImpl, calls } = fakeFetch([
    rpcRoute("admin_overview", 403, { code: "42501", message: "denied" }),
    authRoute(200, { access_token: "x.y.z", refresh_token: "r", expires_in: 60 }),
  ]);
  const result = await handleAdminRpcCore(
    request({
      sessionToken: token({ sub: "user-1", aal: "aal2", exp: 9000 }),
      refreshToken: "refresh-1",
      body: { function: "admin_overview", params: {} },
    }),
    deps({ fetchImpl }),
  );
  assert.equal(result.status, 403);
  assert.equal(result.body.state, "forbidden");
  assert.equal(calls.length, 1);
});

test("logout clears both cookies and enforces origin", async () => {
  const result = await handleLogoutCore(request());
  assert.equal(result.status, 200);
  for (const name of [SESSION_COOKIE, REFRESH_COOKIE]) {
    const cleared = cookie(result.cookies, name);
    assert.ok(cleared, name);
    assert.equal(cleared.value, "");
    assert.equal(cleared.options.maxAge, 0);
    assert.equal(cleared.options.path, "/");
  }
  assert.equal(result.redirectTo, undefined);
  const navigation = await handleLogoutCore(request({ method: "GET", secFetchSite: "same-origin" }));
  assert.equal(navigation.redirectTo, "/login");
  const csrf = await handleLogoutCore(request({ origin: "https://evil.example" }));
  assert.equal(csrf.status, 403);
  assert.equal(csrf.cookies, undefined);
});

test("evidence gateway requires a session, validates references and defaults to unavailable", async () => {
  const csrf = await handleEvidenceCore(
    request({ origin: "https://evil.example", sessionToken: "t", body: {} }),
    deps(),
  );
  assert.equal(csrf.status, 403);

  const signedOut = await handleEvidenceCore(request({ body: {} }), deps());
  assert.equal(signedOut.status, 401);

  const invalid = await handleEvidenceCore(
    request({ sessionToken: "t", body: { submission_id: "nope", media_id: MEDIA } }),
    deps(),
  );
  assert.equal(invalid.status, 400);

  const { fetchImpl } = fakeFetch([
    rpcRoute("admin_evidence_reference", 200, { reference_ok: false }),
  ]);
  const notFound = await handleEvidenceCore(
    request({
      sessionToken: "t",
      body: { submission_id: SUBMISSION, media_id: MEDIA },
    }),
    deps({ fetchImpl }),
  );
  assert.equal(notFound.status, 404);
  assert.equal(notFound.body.state, "not_found");

  const { fetchImpl: allowedFetch } = fakeFetch([
    rpcRoute("admin_evidence_reference", 200, { reference_ok: true }),
  ]);
  const unavailable = await handleEvidenceCore(
    request({
      sessionToken: "t",
      body: { submission_id: SUBMISSION, media_id: MEDIA },
    }),
    deps({ fetchImpl: allowedFetch }),
    unavailableEvidenceResolver,
  );
  assert.equal(unavailable.status, 501);
  assert.equal(unavailable.body.state, "unavailable");
  assert.match(String(unavailable.body.message), /accounts media gateway/);
  assert.doesNotMatch(JSON.stringify(unavailable.body), /https?:\/\//);
});

test("a registered evidence resolver is bounded by the URL gate", async () => {
  const ready: AdminEvidenceResolver = {
    async resolveEvidence() {
      return { state: "ready", url: "https://media.hocalist.com/evidence/a.png", expires_at: null };
    },
  };
  const { fetchImpl } = fakeFetch([
    rpcRoute("admin_evidence_reference", 200, { reference_ok: true }),
  ]);
  const allowed = await handleEvidenceCore(
    request({ sessionToken: "t", body: { submission_id: SUBMISSION, media_id: MEDIA } }),
    deps({ fetchImpl, evidenceHost: "media.hocalist.com" }),
    ready,
  );
  assert.equal(allowed.status, 200);
  assert.equal(allowed.body.url, "https://media.hocalist.com/evidence/a.png");

  const blocked = await handleEvidenceCore(
    request({ sessionToken: "t", body: { submission_id: SUBMISSION, media_id: MEDIA } }),
    deps({ fetchImpl, evidenceHost: "other.hocalist.com" }),
    ready,
  );
  assert.equal(blocked.status, 502);
  assert.equal(blocked.body.state, "error");
});

test('logout revokes the provider session and preserves recovery on transport failure', async () => {
  const calls: string[] = [];
  const transport = (async (input: unknown) => { calls.push(String(input)); return new Response(null, { status: 204 }); }) as typeof fetch;
  const success = await handleLogoutCore(request({ sessionToken: 'synthetic' }), { ...deps(), fetchImpl: transport });
  assert.equal(success.status, 200);
  assert.ok(calls[0].endsWith('/auth/v1/logout?scope=local'));
  const failed = await handleLogoutCore(request({ sessionToken: 'synthetic' }), { ...deps(), fetchImpl: (async () => { throw new Error('offline'); }) as typeof fetch });
  assert.equal(failed.status, 503);
  assert.equal(failed.cookies, undefined);
});

test('eligible unenrolled administrator receives only a bootstrap pending cookie', async () => {
 const access=token({sub:'user-1',aal:'aal1',exp:5000});
 const {fetchImpl}=fakeFetch([authRoute(200,{access_token:access,refresh_token:'synthetic-refresh',expires_in:3600}),
 url=>url.pathname==='/auth/v1/user'?{status:200,body:{id:'user-1',factors:[]}}:undefined,
 rpcRoute('admin_mfa_enrollment_eligible',200,true)]);
 const result=await handleLoginCore(request({body:{email:'admin@example.test',password:'synthetic'}}),deps({fetchImpl,mfaPolicy:'required'}));
 assert.equal(result.body.state,'mfa_setup_required');assert.ok(cookie(result.cookies,MFA_PENDING_COOKIE)?.value);
 assert.ok(!cookie(result.cookies,SESSION_COOKIE)?.value);assert.ok(!cookie(result.cookies,REFRESH_COOKIE)?.value);
});

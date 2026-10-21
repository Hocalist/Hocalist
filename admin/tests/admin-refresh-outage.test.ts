// Regression tests for transient provider-outage recovery:
//   * a missing or expired access cookie plus a temporary refresh failure must
//     dispatch no privileged work, preserve recoverable cookies and return a
//     retryable unavailable outcome (API and evidence),
//   * navigation must terminate on the reachable /session-unavailable page
//     instead of looping through the refresh guard,
//   * a definitive rejection still clears and returns to sign-in, and a later
//     successful refresh persists rotation before the destination.
// Real core functions with injected fetch; no network or credentials.
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  handleAdminRpcCore,
  handleEvidenceCore,
  handleSessionRefreshCore,
  type AdminEvidenceResolver,
  type CoreCookie,
  type CoreDeps,
  type CoreRequest,
} from "../app/lib/admin-http";
import { routeGuardDecision } from "../app/lib/admin-rules";
import { REFRESH_COOKIE, SESSION_COOKIE } from "../app/lib/admin-session";

const CONFIG = { url: "https://project.supabase.co", anonKey: "anon-key" };
const SUBMISSION = "90000000-0000-4000-8000-000000000001";
const MEDIA = "90000000-0000-4000-8000-00000000000a";

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

const expiredAal2 = () => token({ sub: "user-1", aal: "aal2", exp: 100 });
const freshAal2 = () => token({ sub: "user-1", aal: "aal2", exp: 9000 });

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

/** Provider outage in two shapes: thrown network error and HTTP 503. */
function outageFetch(
  mode: "network" | "status",
  track?: { rpc: number; provider: number },
): typeof fetch {
  return (async (input: string | URL | Request) => {
    const url = new URL(typeof input === "string" ? input : input.toString());
    if (url.pathname.startsWith("/rest/v1/rpc/")) {
      if (track) track.rpc += 1;
      return json(200, { unexpected: true });
    }
    if (track) track.provider += 1;
    if (mode === "network") throw new TypeError("fetch failed");
    return json(503, { message: "service unavailable" });
  }) as typeof fetch;
}

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

const clearedRecoverableCookies = (cookies: CoreCookie[] | undefined) =>
  (cookies ?? []).filter(
    (entry) =>
      entry.value === "" && (entry.name === SESSION_COOKIE || entry.name === REFRESH_COOKIE),
  );

test("a transient refresh failure preserves the session and dispatches nothing", async (t) => {
  const accessVariants = [
    ["expired", expiredAal2()],
    ["missing", null],
  ] as const;
  for (const [label, accessToken] of accessVariants) {
    for (const mode of ["network", "status"] as const) {
      await t.test(`${label} access / ${mode} failure`, async () => {
        const track = { rpc: 0, provider: 0 };
        const result = await handleAdminRpcCore(
          request({
            sessionToken: accessToken,
            refreshToken: "refresh-1",
            body: { function: "admin_overview", params: {} },
          }),
          deps({ fetchImpl: outageFetch(mode, track) }),
        );
        assert.equal(result.status, 502);
        assert.equal(result.body.state, "unavailable");
        assert.match(String(result.body.message), /retry/i);
        assert.equal(track.rpc, 0, "no privileged dispatch during a provider outage");
        assert.equal(track.provider, 1, "exactly one refresh attempt");
        assert.equal(
          clearedRecoverableCookies(result.cookies).length,
          0,
          "recoverable cookies must be preserved",
        );
      });
    }
  }
});

test("evidence resolution is not invoked during a transient refresh failure", async () => {
  let invoked = false;
  const resolver: AdminEvidenceResolver = {
    async resolveEvidence() {
      invoked = true;
      return { state: "ready", url: "https://media.hocalist.com/a.png", expires_at: null };
    },
  };
  const track = { rpc: 0, provider: 0 };
  const result = await handleEvidenceCore(
    request({
      refreshToken: "refresh-1",
      body: { submission_id: SUBMISSION, media_id: MEDIA },
    }),
    deps({ fetchImpl: outageFetch("status", track) }),
    resolver,
  );
  assert.equal(result.status, 502);
  assert.equal(result.body.state, "unavailable");
  assert.equal(invoked, false);
  assert.equal(track.rpc, 0);
});

test("a later successful retry recovers the retained refresh cookie", async () => {
  const { fetchImpl, calls } = fakeFetch([
    authRoute(200, { access_token: freshAal2(), refresh_token: "refresh-2", expires_in: 3600 }),
    rpcRoute("admin_overview", 200, { active_memberships: 7 }),
  ]);
  const result = await handleAdminRpcCore(
    request({
      sessionToken: expiredAal2(),
      refreshToken: "refresh-1",
      body: { function: "admin_overview", params: {} },
    }),
    deps({ fetchImpl }),
  );
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.data, { active_memberships: 7 });
  assert.equal(cookie(result.cookies, REFRESH_COOKIE)?.value, "refresh-2");
  assert.equal(calls.filter((call) => call.startsWith("/rest/v1/rpc/")).length, 1);
});

test("a rejected access token followed by a provider outage stays retryable", async () => {
  const track = { rpc: 0, provider: 0 };
  const impl = (async (input: string | URL | Request) => {
    const url = new URL(typeof input === "string" ? input : input.toString());
    if (url.pathname.startsWith("/rest/v1/rpc/")) {
      track.rpc += 1;
      return json(401, { message: "expired" });
    }
    track.provider += 1;
    return json(503, {});
  }) as typeof fetch;
  const result = await handleAdminRpcCore(
    request({
      sessionToken: freshAal2(),
      refreshToken: "refresh-1",
      body: { function: "admin_overview", params: {} },
    }),
    deps({ fetchImpl: impl }),
  );
  assert.equal(result.status, 502);
  assert.equal(result.body.state, "unavailable");
  assert.equal(track.rpc, 1, "the original attempt only; no retry dispatch");
  assert.equal(track.provider, 1);
  assert.equal(clearedRecoverableCookies(result.cookies).length, 0);
});

test("navigation terminates on the retry page for missing and expired access", async (t) => {
  const accessVariants = [
    ["expired", expiredAal2()],
    ["missing", null],
  ] as const;
  for (const [label, accessToken] of accessVariants) {
    await t.test(label, async () => {
      const track = { rpc: 0, provider: 0 };
      let pathname = "/trust";
      let redirects = 0;
      const history: string[] = [];
      for (let step = 0; step < 4; step += 1) {
        const decision = routeGuardDecision({
          pathname,
          configured: true,
          sessionState: accessToken ? "invalid" : "none",
          hasRefresh: true,
          hasPending: false,
        });
        history.push(`${pathname}:${decision.action}`);
        if (decision.action !== "redirect-refresh") break;
        const core = await handleSessionRefreshCore(
          request({ sessionToken: accessToken, refreshToken: "refresh-1", nextPath: decision.next }),
          deps({ fetchImpl: outageFetch("status", track) }),
        );
        assert.equal(core.cookies, undefined, "cookies preserved during outage");
        assert.notEqual(core.redirectTo, "/trust", "must not bounce into the guard destination");
        redirects += 1;
        pathname = String(core.redirectTo).split("?")[0];
      }
      assert.equal(redirects, 1);
      assert.equal(pathname, "/session-unavailable");
      assert.equal(history.filter((entry) => entry === "/trust:redirect-refresh").length, 1);
      assert.deepEqual(
        routeGuardDecision({
          pathname,
          configured: true,
          sessionState: "none",
          hasRefresh: true,
          hasPending: false,
        }),
        { action: "next" },
      );
      assert.equal(track.rpc, 0);
    });
  }
});

test("definitive rejection still clears; success persists rotation before the destination", async () => {
  const dead = await handleSessionRefreshCore(
    request({ sessionToken: expiredAal2(), refreshToken: "refresh-1", nextPath: "/audit" }),
    deps({ fetchImpl: fakeFetch([authRoute(401, {})]).fetchImpl }),
  );
  assert.equal(dead.redirectTo, "/login");
  assert.equal(cookie(dead.cookies, SESSION_COOKIE)?.value, "");
  assert.equal(cookie(dead.cookies, REFRESH_COOKIE)?.value, "");

  const healthy = fakeFetch([
    authRoute(200, { access_token: freshAal2(), refresh_token: "refresh-2", expires_in: 3600 }),
  ]);
  const ok = await handleSessionRefreshCore(
    request({ refreshToken: "refresh-1", nextPath: "/events" }),
    deps({ fetchImpl: healthy.fetchImpl }),
  );
  assert.equal(ok.redirectTo, "/events");
  assert.equal(cookie(ok.cookies, SESSION_COOKIE)?.value.includes("."), true);
  assert.equal(cookie(ok.cookies, REFRESH_COOKIE)?.value, "refresh-2");
});

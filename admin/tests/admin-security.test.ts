import { test } from "node:test";
import assert from "node:assert/strict";

import {
  ADMIN_RPC_ALLOWLIST,
  admitLogin,
  adminMfaPolicy,
  clearedCookieOptions,
  decodeTokenClaims,
  evaluateRequestOrigin,
  evidenceUrlAllowed,
  pendingCookieOptions,
  requiredAssuranceState,
  routeGuardDecision,
  sanitizeNextPath,
  sessionTokenExpired,
} from "../app/lib/admin-rules";

function base64url(value: string): string {
  return Buffer.from(value, "utf8")
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function token(payload: Record<string, unknown>): string {
  return `${base64url(JSON.stringify({ alg: "HS256", typ: "JWT" }))}.${base64url(
    JSON.stringify(payload),
  )}.signature`;
}

test("the reviewed allowlist includes the new read and command contracts", () => {
  for (const name of [
    "admin_commercial_config",
    "credit_admin_command",
    "admin_review_queue",
    "admin_failed_events",
    "admin_failed_event_detail",
    "admin_audit_feed",
    "admin_credit_summary",
    "admin_reward_summary",
    "admin_credit_detail",
    "admin_delivery_overview",
    "admin_call_settings_history",
    "marketplace_timezones",
  ]) {
    assert.equal(ADMIN_RPC_ALLOWLIST.has(name), true, name);
  }
  assert.equal(ADMIN_RPC_ALLOWLIST.has("admin_trust_queue"), false);
  assert.equal(ADMIN_RPC_ALLOWLIST.has("admin_evidence_reference"), false);
  assert.equal(ADMIN_RPC_ALLOWLIST.has("receive_stripe_test_event"), false);
});

test("MFA policy is opt-in configuration", () => {
  assert.equal(adminMfaPolicy(undefined), "off");
  assert.equal(adminMfaPolicy(""), "off");
  assert.equal(adminMfaPolicy("false"), "off");
  assert.equal(adminMfaPolicy(" required "), "required");
});

test("token claims decode without a Node Buffer and never throw", () => {
  const claims = decodeTokenClaims(token({ sub: "user-1", aal: "aal2", exp: 1234 }));
  assert.deepEqual(claims, { subject: "user-1", aal: "aal2", expiresAt: 1234 });
  assert.equal(decodeTokenClaims("not-a-token"), null);
  assert.equal(decodeTokenClaims("a.b"), null);
  assert.equal(decodeTokenClaims(`a.${base64url("not json")}.c`), null);
  assert.deepEqual(decodeTokenClaims(token({})), { subject: null, aal: null, expiresAt: null });
});

test("login admission enforces the configured assurance policy", () => {
  const aal1 = { subject: "u", aal: "aal1", expiresAt: 9999 };
  const aal2 = { subject: "u", aal: "aal2", expiresAt: 9999 };
  assert.equal(admitLogin({ policy: "off", claims: aal1, nowSeconds: 1 }).ok, true);
  assert.equal(admitLogin({ policy: "off", claims: null, nowSeconds: 1 }).ok, true);
  const required = admitLogin({ policy: "required", claims: aal1, nowSeconds: 1 });
  assert.equal(required.ok, false);
  assert.equal(required.ok === false ? required.state : null, "mfa_required");
  const satisfied = admitLogin({ policy: "required", claims: aal2, nowSeconds: 1 });
  assert.equal(satisfied.ok, true);
  const unavailable = admitLogin({ policy: "required", claims: null, nowSeconds: 1 });
  assert.equal(unavailable.ok === false ? unavailable.state : null, "assurance_unavailable");
  // A decoded claim set without subject/expiry is not a completed factor.
  const spoofed = admitLogin({
    policy: "required",
    claims: { subject: "synthetic", aal: "aal2", expiresAt: null },
    nowSeconds: 1,
  });
  assert.equal(spoofed.ok === false ? spoofed.state : null, "assurance_unavailable");
  const noSubject = admitLogin({
    policy: "required",
    claims: { subject: null, aal: "aal2", expiresAt: 9999 },
    nowSeconds: 1,
  });
  assert.equal(noSubject.ok === false ? noSubject.state : null, "assurance_unavailable");
  // An expired provider token is never stored even with MFA satisfied.
  const expired = admitLogin({
    policy: "required",
    claims: { ...aal2, expiresAt: 100 },
    nowSeconds: 200,
  });
  assert.equal(expired.ok === false ? expired.state : null, "expired");
});

test("required assurance is strict for stored sessions as well", () => {
  assert.equal(requiredAssuranceState({ subject: "u", aal: "aal2", expiresAt: 9 }), "valid");
  assert.equal(requiredAssuranceState({ subject: "u", aal: "aal1", expiresAt: 9 }), "aal1");
  assert.equal(requiredAssuranceState({ subject: "u", aal: "aal2", expiresAt: null }), "unverifiable");
  assert.equal(requiredAssuranceState({ subject: "", aal: "aal2", expiresAt: 9 }), "unverifiable");
  assert.equal(requiredAssuranceState({ subject: null, aal: null, expiresAt: 9 }), "unverifiable");
  assert.equal(requiredAssuranceState(null), "unverifiable");
});

test("stored token expiry is explicit", () => {
  assert.equal(sessionTokenExpired({ subject: "u", aal: "aal2", expiresAt: 100 }, 100), true);
  assert.equal(sessionTokenExpired({ subject: "u", aal: "aal2", expiresAt: 101 }, 100), false);
  assert.equal(sessionTokenExpired(null, 100), false);
  assert.equal(sessionTokenExpired({ subject: "u", aal: null, expiresAt: null }, 100), false);
});

test("same-origin enforcement rejects cross-site state changes", () => {
  const base = { method: "POST", origin: "https://admin.hocalist.com", host: "admin.hocalist.com", secFetchSite: "same-origin" };
  assert.equal(evaluateRequestOrigin(base), "allow");
  assert.equal(evaluateRequestOrigin({ ...base, origin: "https://evil.example" }), "reject");
  assert.equal(evaluateRequestOrigin({ ...base, secFetchSite: "cross-site" }), "reject");
  assert.equal(evaluateRequestOrigin({ ...base, origin: null }), "allow");
  assert.equal(
    evaluateRequestOrigin({ method: "POST", origin: null, host: "admin.hocalist.com", secFetchSite: null }),
    "reject",
  );
  assert.equal(
    evaluateRequestOrigin({ method: "GET", origin: null, host: "admin.hocalist.com", secFetchSite: null }),
    "allow",
  );
  assert.equal(
    evaluateRequestOrigin({ method: "GET", origin: "https://other.example", host: "admin.hocalist.com", secFetchSite: null }),
    "reject",
  );
  assert.equal(
    evaluateRequestOrigin({ ...base, origin: "not a url" }),
    "reject",
  );
  // A literal "null" origin is not a same-origin proof; GET navigation stays
  // allowed, a state-changing request still needs the fetch-metadata signal.
  assert.equal(
    evaluateRequestOrigin({ method: "GET", origin: "null", host: "admin.hocalist.com", secFetchSite: null }),
    "allow",
  );
  assert.equal(
    evaluateRequestOrigin({ method: "POST", origin: "null", host: "admin.hocalist.com", secFetchSite: null }),
    "reject",
  );
  assert.equal(
    evaluateRequestOrigin({ method: "POST", origin: "null", host: "admin.hocalist.com", secFetchSite: "same-origin" }),
    "allow",
  );
  // A user-initiated navigation reports sec-fetch-site "none"; a state change
  // still requires same-origin.
  assert.equal(
    evaluateRequestOrigin({ method: "GET", origin: null, host: "admin.hocalist.com", secFetchSite: "none" }),
    "allow",
  );
  assert.equal(
    evaluateRequestOrigin({ method: "POST", origin: null, host: "admin.hocalist.com", secFetchSite: "none" }),
    "reject",
  );
});

test("route guard routes recoverable and unusable sessions without trapping login", () => {
  const configured = { configured: true };
  // A valid session proceeds; an invalid cookie without refresh goes to login.
  assert.deepEqual(
    routeGuardDecision({
      pathname: "/dashboard",
      ...configured,
      sessionState: "valid",
      hasRefresh: false,
      hasPending: false,
    }),
    { action: "next" },
  );
  assert.deepEqual(
    routeGuardDecision({
      pathname: "/dashboard",
      ...configured,
      sessionState: "invalid",
      hasRefresh: false,
      hasPending: false,
    }),
    { action: "redirect-login" },
  );
  // A missing/expired access cookie with a refresh cookie recovers instead of
  // bouncing through the sign-in page.
  assert.deepEqual(
    routeGuardDecision({
      pathname: "/trust",
      ...configured,
      sessionState: "invalid",
      hasRefresh: true,
      hasPending: false,
    }),
    { action: "redirect-refresh", next: "/trust" },
  );
  assert.deepEqual(
    routeGuardDecision({
      pathname: "/",
      ...configured,
      sessionState: "none",
      hasRefresh: true,
      hasPending: false,
    }),
    { action: "redirect-refresh", next: "/dashboard" },
  );
  // A half-finished second factor cannot reach a page.
  assert.deepEqual(
    routeGuardDecision({
      pathname: "/events",
      ...configured,
      sessionState: "none",
      hasRefresh: false,
      hasPending: true,
    }),
    { action: "redirect-login" },
  );
  // An unusable cookie never blocks the sign-in page itself.
  assert.deepEqual(
    routeGuardDecision({
      pathname: "/login",
      ...configured,
      sessionState: "invalid",
      hasRefresh: false,
      hasPending: true,
    }),
    { action: "next" },
  );
  assert.deepEqual(
    routeGuardDecision({
      pathname: "/login",
      ...configured,
      sessionState: "valid",
      hasRefresh: false,
      hasPending: false,
    }),
    { action: "redirect-dashboard" },
  );
  // Unconfigured deployments stay reviewable.
  assert.deepEqual(
    routeGuardDecision({
      pathname: "/dashboard",
      configured: false,
      sessionState: "none",
      hasRefresh: false,
      hasPending: false,
    }),
    { action: "next" },
  );
  // The recovery-outage page is public and can never bounce back into the
  // refresh guard, even with a recoverable-looking session.
  for (const sessionState of ["none", "invalid"] as const) {
    assert.deepEqual(
      routeGuardDecision({
        pathname: "/session-unavailable",
        ...configured,
        sessionState,
        hasRefresh: true,
        hasPending: false,
      }),
      { action: "next" },
    );
  }
});

test("refresh return paths stay same-origin portal paths", () => {
  assert.equal(sanitizeNextPath("/trust"), "/trust");
  assert.equal(sanitizeNextPath("/billing/config"), "/billing/config");
  assert.equal(sanitizeNextPath(null), "/dashboard");
  assert.equal(sanitizeNextPath("https://evil.example"), "/dashboard");
  assert.equal(sanitizeNextPath("//evil.example"), "/dashboard");
  assert.equal(sanitizeNextPath("/api/session/refresh"), "/dashboard");
  assert.equal(sanitizeNextPath("/login"), "/dashboard");
  assert.equal(sanitizeNextPath("/login?next=/x"), "/dashboard");
  assert.equal(sanitizeNextPath("/session-unavailable"), "/dashboard");
  assert.equal(sanitizeNextPath("/session-unavailable?next=/trust"), "/dashboard");
  assert.equal(sanitizeNextPath("/trust\\..\\evil"), "/dashboard");
  assert.equal(sanitizeNextPath(`/${"a".repeat(600)}`), "/dashboard");
});

test("pending and cleared cookie options are hardened", () => {
  assert.deepEqual(pendingCookieOptions({ isProduction: true, maxAge: 900 }), {
    httpOnly: true,
    sameSite: "lax",
    secure: true,
    path: "/",
    maxAge: 600,
  });
  assert.equal(pendingCookieOptions({ isProduction: false, maxAge: 5 }).maxAge, 60);
  assert.deepEqual(clearedCookieOptions(), {
    httpOnly: true,
    sameSite: "lax",
    secure: false,
    path: "/",
    maxAge: 0,
  });
});

test("evidence URLs are HTTPS-only and optionally host-locked", () => {
  assert.equal(evidenceUrlAllowed("https://evidence.hocalist.com/a.png?sig=1", null), true);
  assert.equal(evidenceUrlAllowed("https://evidence.hocalist.com/a.png", "evidence.hocalist.com"), true);
  assert.equal(evidenceUrlAllowed("https://evil.example/a.png", "evidence.hocalist.com"), false);
  assert.equal(evidenceUrlAllowed("http://evidence.hocalist.com/a.png", null), false);
  assert.equal(evidenceUrlAllowed("https://user:pass@evidence.hocalist.com/a.png", null), false);
  assert.equal(evidenceUrlAllowed("not a url", null), false);
  assert.equal(evidenceUrlAllowed(`https://x.example/${"a".repeat(2100)}`, null), false);
});

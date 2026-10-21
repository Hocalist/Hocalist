import assert from "node:assert/strict";
import test from "node:test";

import {
  ADMIN_RPC_ALLOWLIST,
  MAX_RPC_PARAMS_BYTES,
  REFRESH_COOKIE_MAX_AGE,
  classifyAdminFailure,
  parseAdminRpcBody,
  parseLoginBody,
  refreshCookieOptions,
  sessionCookieOptions,
  shouldRefreshSession,
} from "../app/lib/admin-rules";

test("admin rpc allowlist rejects unknown functions", () => {
  assert.equal(ADMIN_RPC_ALLOWLIST.has("marketplace_admin_command"), true);
  assert.equal(ADMIN_RPC_ALLOWLIST.has("marketplace_catalogue"), true);
  assert.equal(ADMIN_RPC_ALLOWLIST.has("chat_send"), false);
  assert.equal(ADMIN_RPC_ALLOWLIST.has("account_command"), false);
});

test("login body validation rejects malformed and oversized input", () => {
  assert.equal(parseLoginBody(null).ok, false);
  assert.equal(parseLoginBody([]).ok, false);
  assert.equal(parseLoginBody("admin").ok, false);
  assert.equal(parseLoginBody({ email: 5, password: "x" }).ok, false);
  assert.equal(parseLoginBody({ email: "a@b.test" }).ok, false);
  assert.equal(parseLoginBody({ email: "", password: "x" }).ok, false);
  assert.equal(parseLoginBody({ email: "a@b.test", password: "x".repeat(201) }).ok, false);
  assert.equal(parseLoginBody({ email: `${"a".repeat(255)}@b.test`, password: "x" }).ok, false);
  assert.deepEqual(parseLoginBody({ email: "  admin@hocalist.com ", password: "secret" }), {
    ok: true,
    value: { email: "admin@hocalist.com", password: "secret" },
  });
});

test("admin rpc body validation enforces the allowlist and bounds", () => {
  assert.equal(parseAdminRpcBody(null).ok, false);
  assert.equal(parseAdminRpcBody({ function: "delete_everything", params: {} }).ok, false);
  assert.equal(parseAdminRpcBody({ function: "marketplace_admin_command", params: [] }).ok, false);
  assert.equal(
    parseAdminRpcBody({
      function: "marketplace_admin_command",
      params: { blob: "x".repeat(MAX_RPC_PARAMS_BYTES + 1) },
    }).ok,
    false,
  );
  const ok = parseAdminRpcBody({
    function: "marketplace_admin_command",
    params: { p_operation: "category.create" },
  });
  assert.equal(ok.ok, true);
  assert.deepEqual(parseAdminRpcBody({ function: "marketplace_catalogue" }), {
    ok: true,
    value: { functionName: "marketplace_catalogue", params: {} },
  });
});

test("session cookie options are hardened and bounded", () => {
  assert.deepEqual(sessionCookieOptions({ expiresIn: 3600, isProduction: true }), {
    httpOnly: true,
    sameSite: "lax",
    secure: true,
    path: "/",
    maxAge: 3600,
  });
  const development = sessionCookieOptions({ expiresIn: 10, isProduction: false });
  assert.equal(development.secure, false);
  assert.equal(development.maxAge, 120);
  assert.equal(sessionCookieOptions({ expiresIn: 999999, isProduction: false }).maxAge, 86400);
  assert.equal(sessionCookieOptions({ expiresIn: Number.NaN, isProduction: false }).maxAge, 3600);
});

test("admin failure classification maps status and code", () => {
  assert.equal(classifyAdminFailure(401, null), "signed_out");
  assert.equal(classifyAdminFailure(403, null), "forbidden");
  assert.equal(classifyAdminFailure(400, "42501"), "forbidden");
  assert.equal(classifyAdminFailure(500, null), "error");
  assert.equal(classifyAdminFailure(0, null), "error");
});

test("refresh cookie stays httpOnly with a bounded lifetime", () => {
  assert.deepEqual(refreshCookieOptions({ isProduction: true }), {
    httpOnly: true,
    sameSite: "lax",
    secure: true,
    path: "/",
    maxAge: REFRESH_COOKIE_MAX_AGE,
  });
  assert.equal(refreshCookieOptions({ isProduction: false }).secure, false);
});

test("session refresh is attempted once for an expired token only", () => {
  assert.equal(
    shouldRefreshSession({
      state: "signed_out",
      hasRefreshToken: true,
      alreadyRetried: false,
    }),
    true,
  );
  assert.equal(
    shouldRefreshSession({
      state: "signed_out",
      hasRefreshToken: false,
      alreadyRetried: false,
    }),
    false,
  );
  assert.equal(
    shouldRefreshSession({
      state: "signed_out",
      hasRefreshToken: true,
      alreadyRetried: true,
    }),
    false,
  );
  assert.equal(
    shouldRefreshSession({
      state: "forbidden",
      hasRefreshToken: true,
      alreadyRetried: false,
    }),
    false,
  );
  assert.equal(
    shouldRefreshSession({
      state: "error",
      hasRefreshToken: true,
      alreadyRetried: false,
    }),
    false,
  );
});

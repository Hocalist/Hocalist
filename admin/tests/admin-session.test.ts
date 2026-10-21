import assert from "node:assert/strict";
import test, { afterEach, beforeEach } from "node:test";

import {
  adminConfig,
  callRpc,
  refreshSession,
  signInWithPassword,
} from "../app/lib/admin-session";

const originalFetch = globalThis.fetch;
const originalUrl = process.env.HOCALIST_SUPABASE_URL;
const originalKey = process.env.HOCALIST_SUPABASE_ANON_KEY;

beforeEach(() => {
  delete process.env.HOCALIST_SUPABASE_URL;
  delete process.env.HOCALIST_SUPABASE_ANON_KEY;
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  if (originalUrl === undefined) delete process.env.HOCALIST_SUPABASE_URL;
  else process.env.HOCALIST_SUPABASE_URL = originalUrl;
  if (originalKey === undefined) delete process.env.HOCALIST_SUPABASE_ANON_KEY;
  else process.env.HOCALIST_SUPABASE_ANON_KEY = originalKey;
});

test("adminConfig stays null until both server variables exist", () => {
  assert.equal(adminConfig(), null);
  process.env.HOCALIST_SUPABASE_URL = "https://example.test/";
  assert.equal(adminConfig(), null);
  process.env.HOCALIST_SUPABASE_ANON_KEY = "anon-key";
  assert.deepEqual(adminConfig(), {
    url: "https://example.test",
    anonKey: "anon-key",
  });
});

test("sign-in posts credentials and returns both tokens without echoing the password", async () => {
  let captured: { url: string; init?: Parameters<typeof fetch>[1] } | undefined;
  globalThis.fetch = (async (input: unknown, init?: Parameters<typeof fetch>[1]) => {
    captured = { url: String(input), init };
    return new Response(
      JSON.stringify({
        access_token: "access",
        refresh_token: "refresh",
        expires_in: 1800,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }) as typeof fetch;

  const result = await signInWithPassword(
    { url: "https://example.test", anonKey: "anon-key" },
    "admin@hocalist.com",
    "synthetic-password",
  );
  assert.deepEqual(result, {
    ok: true,
    accessToken: "access",
    refreshToken: "refresh",
    expiresIn: 1800,
  });
  assert.equal(captured?.url, "https://example.test/auth/v1/token?grant_type=password");
  const headers = captured?.init?.headers as Record<string, string>;
  assert.equal(headers.apikey, "anon-key");
  assert.equal(headers.Authorization, undefined);
  assert.match(String(captured?.init?.body), /"email":"admin@hocalist\.com"/);
});

test("sign-in without a refresh token is rejected instead of half-authenticated", async () => {
  globalThis.fetch = (async () =>
    new Response(JSON.stringify({ access_token: "access", expires_in: 1800 }), {
      status: 200,
    })) as typeof fetch;
  const result = await signInWithPassword(
    { url: "https://example.test", anonKey: "anon-key" },
    "admin@hocalist.com",
    "pw",
  );
  assert.equal(result.ok, false);
});

test("sign-in failure never propagates provider detail", async () => {
  globalThis.fetch = (async () =>
    new Response(
      JSON.stringify({
        error_description: "Invalid login credentials for admin@hocalist.com",
      }),
      { status: 400 },
    )) as typeof fetch;

  const result = await signInWithPassword(
    { url: "https://example.test", anonKey: "anon-key" },
    "admin@hocalist.com",
    "wrong",
  );
  assert.equal(result.ok, false);
  if (!result.ok) {
    assert.equal(result.message, "Sign-in failed. Check the email and password.");
    assert.equal(result.message.includes("admin@hocalist.com"), false);
  }
});

test("sign-in surfaces an unreachable provider safely", async () => {
  globalThis.fetch = (async () => {
    throw new Error("ECONNREFUSED");
  }) as unknown as typeof fetch;
  const result = await signInWithPassword(
    { url: "https://example.test", anonKey: "anon-key" },
    "admin@hocalist.com",
    "pw",
  );
  assert.deepEqual(result, {
    ok: false,
    message: "The authentication service is unreachable.",
  });
});

test("refresh exchanges the stored token and rotates it", async () => {
  let captured: { url: string; init?: Parameters<typeof fetch>[1] } | undefined;
  globalThis.fetch = (async (input: unknown, init?: Parameters<typeof fetch>[1]) => {
    captured = { url: String(input), init };
    return new Response(
      JSON.stringify({
        access_token: "new-access",
        refresh_token: "new-refresh",
        expires_in: 3600,
      }),
      { status: 200 },
    );
  }) as typeof fetch;
  const result = await refreshSession(
    { url: "https://example.test", anonKey: "anon-key" },
    "stored-refresh",
  );
  assert.deepEqual(result, {
    ok: true,
    accessToken: "new-access",
    refreshToken: "new-refresh",
    expiresIn: 3600,
  });
  assert.equal(
    captured?.url,
    "https://example.test/auth/v1/token?grant_type=refresh_token",
  );
  assert.match(String(captured?.init?.body), /"refresh_token":"stored-refresh"/);
});

test("refresh keeps the previous token when the provider omits a rotation", async () => {
  globalThis.fetch = (async () =>
    new Response(JSON.stringify({ access_token: "new-access" }), {
      status: 200,
    })) as typeof fetch;
  const result = await refreshSession(
    { url: "https://example.test", anonKey: "anon-key" },
    "stored-refresh",
  );
  assert.deepEqual(result, {
    ok: true,
    accessToken: "new-access",
    refreshToken: "stored-refresh",
    expiresIn: 3600,
  });
});

test("a rejected refresh reports expired and an unreachable one reports unavailable", async () => {
  globalThis.fetch = (async () =>
    new Response(JSON.stringify({ error: "invalid_grant" }), {
      status: 401,
    })) as typeof fetch;
  assert.deepEqual(
    await refreshSession(
      { url: "https://example.test", anonKey: "anon-key" },
      "stale",
    ),
    { ok: false, state: "expired" },
  );

  globalThis.fetch = (async () => {
    throw new Error("ECONNREFUSED");
  }) as unknown as typeof fetch;
  assert.deepEqual(
    await refreshSession(
      { url: "https://example.test", anonKey: "anon-key" },
      "stale",
    ),
    { ok: false, state: "unavailable" },
  );
});

test("rpc failure maps status and code without leaking the body", async () => {
  globalThis.fetch = (async () =>
    new Response(JSON.stringify({ code: "42501", message: "admin_required" }), {
      status: 403,
    })) as typeof fetch;
  const result = await callRpc(
    { url: "https://example.test", anonKey: "anon-key" },
    "token",
    "marketplace_admin_command",
    { p_operation: "category.create" },
  );
  assert.deepEqual(result, {
    ok: false,
    status: 403,
    code: "42501",
    message: "admin_required",
  });
});

test("rpc success returns the payload and sends the schema profile", async () => {
  let captured: { url: string; init?: Parameters<typeof fetch>[1] } | undefined;
  globalThis.fetch = (async (input: unknown, init?: Parameters<typeof fetch>[1]) => {
    captured = { url: String(input), init };
    return new Response(JSON.stringify({ items: [] }), { status: 200 });
  }) as typeof fetch;
  const result = await callRpc(
    { url: "https://example.test", anonKey: "anon-key" },
    "token",
    "marketplace_admin_moderation_queue",
    { p_limit: 1, p_cursor: null },
  );
  assert.deepEqual(result, { ok: true, data: { items: [] } });
  const headers = captured?.init?.headers as Record<string, string>;
  assert.equal(headers.Authorization, "Bearer token");
  assert.equal(headers["Accept-Profile"], "hocalist");
  assert.equal(headers["Content-Profile"], "hocalist");
});

import assert from "node:assert/strict";
import { createPlacesAuthVerifier } from "./auth.ts";

const userId = "00000000-0000-4000-8000-000000000001";

Deno.test("Places Auth forwards credentials only to the fixed Auth endpoint and rejects redirects", async () => {
  const verify = createPlacesAuthVerifier(
    "https://example.supabase.co",
    "test-key",
    (url, init) => {
      assert.equal(url, "https://example.supabase.co/auth/v1/user");
      assert.deepEqual(init.headers, {
        apikey: "test-key",
        Authorization: "Bearer test-token",
      });
      assert.equal(init.redirect, "error");
      assert.ok(init.signal);
      return Promise.resolve(
        Response.json({ id: userId, is_anonymous: false }),
      );
    },
  );
  assert.deepEqual(await verify("Bearer test-token"), { userId });
});

Deno.test("Places Auth distinguishes rejected identity from throttling and outages", async () => {
  for (const status of [401, 403, 429, 500, 503]) {
    const verify = createPlacesAuthVerifier(
      "https://example.supabase.co",
      "test-key",
      () => Promise.resolve(new Response("private upstream error", { status })),
    );
    assert.deepEqual(await verify("Bearer test-token"), {
      error: status === 401 || status === 403 ? "unauthorized" : "unavailable",
    });
  }
});

Deno.test("Places Auth fails closed on malformed success, anonymous users and network errors", async () => {
  for (const data of [null, [], {}, { id: "" }, { id: "not-a-uuid" }]) {
    const verify = createPlacesAuthVerifier(
      "https://example.supabase.co",
      "test-key",
      () => Promise.resolve(Response.json(data)),
    );
    assert.deepEqual(await verify("Bearer test-token"), {
      error: "unavailable",
    });
  }
  const anonymous = createPlacesAuthVerifier(
    "https://example.supabase.co",
    "test-key",
    () => Promise.resolve(Response.json({ id: userId, is_anonymous: true })),
  );
  assert.deepEqual(await anonymous("Bearer test-token"), {
    error: "unauthorized",
  });
  const broken = createPlacesAuthVerifier(
    "https://example.supabase.co",
    "test-key",
    () => Promise.reject(new Error("private network details")),
  );
  assert.deepEqual(await broken("Bearer test-token"), { error: "unavailable" });
});

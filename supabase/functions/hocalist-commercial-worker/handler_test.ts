// HTTP contract proof for the commercial worker handler using an injected
// fetch: shared-secret authorization, Hocalist schema headers, RPC path/body
// and the honest provider-unavailable states. No network is used.
import { deepStrictEqual, rejects, strictEqual } from "node:assert/strict";
import { createHandler, HOCALIST_SCHEMA, serviceRpc } from "./handler.ts";

const SECRET = "test-secret-0123456789-0123456789-0123";
const URL_BASE = "https://project.supabase.co";
const SERVICE_KEY = "service-role-key";

interface CapturedCall {
  url: string;
  init: RequestInit;
}

function capturedFetcher(body: unknown = { status: "ok", items: [] }): {
  fetcher: typeof fetch;
  calls: CapturedCall[];
} {
  const calls: CapturedCall[] = [];
  const fetcher = ((url: string | URL, init?: RequestInit) => {
    calls.push({ url: String(url), init: init ?? {} });
    return Promise.resolve(
      new Response(JSON.stringify(body), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
  }) as unknown as typeof fetch;
  return { fetcher, calls };
}

const env = (values: Record<string, string>) => (name: string) => values[name];

Deno.test("handler: missing or wrong secret is rejected before any call", async () => {
  const { fetcher, calls } = capturedFetcher();
  const handler = createHandler({
    fetcher,
    env: env({ HOCALIST_COMMERCIAL_WORKER_SECRET: SECRET }),
  });
  const missing = await handler(new Request("https://worker/", { method: "POST" }));
  strictEqual(missing.status, 401);
  const wrong = await handler(new Request("https://worker/", {
    method: "POST",
    headers: { Authorization: "Bearer not-the-secret" },
  }));
  strictEqual(wrong.status, 401);
  strictEqual(calls.length, 0);
});

Deno.test("handler: provider configuration is reported honestly", async () => {
  const { fetcher, calls } = capturedFetcher();
  const handler = createHandler({
    fetcher,
    env: env({
      HOCALIST_COMMERCIAL_WORKER_SECRET: SECRET,
      SUPABASE_URL: URL_BASE,
      SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY,
    }),
  });
  const unconfigured = await handler(new Request("https://worker/", {
    method: "POST",
    headers: { Authorization: `Bearer ${SECRET}` },
  }));
  strictEqual(unconfigured.status, 200);
  deepStrictEqual(await unconfigured.json(), { status: "provider_not_configured" });

  const adapterMissing = createHandler({
    fetcher,
    env: env({
      HOCALIST_COMMERCIAL_WORKER_SECRET: SECRET,
      SUPABASE_URL: URL_BASE,
      SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY,
      HOCALIST_PAYOUT_PROVIDER_KEY: "fake_payout",
    }),
  });
  const adapterResponse = await adapterMissing(new Request("https://worker/", {
    method: "POST",
    headers: { Authorization: `Bearer ${SECRET}` },
  }));
  strictEqual(adapterResponse.status, 200);
  deepStrictEqual(await adapterResponse.json(), { status: "provider_adapter_unavailable" });
  strictEqual(calls.length, 0);
});

Deno.test("handler: non-POST methods are refused", async () => {
  const { fetcher } = capturedFetcher();
  const handler = createHandler({
    fetcher,
    env: env({ HOCALIST_COMMERCIAL_WORKER_SECRET: SECRET }),
  });
  const response = await handler(new Request("https://worker/", { method: "GET" }));
  strictEqual(response.status, 405);
});

Deno.test("serviceRpc: explicit hocalist schema, path, auth and body", async () => {
  const { fetcher, calls } = capturedFetcher({ status: "ok", items: [] });
  const rpc = serviceRpc({
    fetcher,
    env: env({
      SUPABASE_URL: `${URL_BASE}/`,
      SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY,
    }),
  });
  const data = await rpc("payout_claim_internal", {
    p_limit: 5,
    p_runner: "commercial-worker",
  });
  deepStrictEqual(data, { status: "ok", items: [] });
  strictEqual(calls.length, 1);
  strictEqual(
    calls[0].url,
    `${URL_BASE}/rest/v1/rpc/payout_claim_internal`,
  );
  strictEqual(calls[0].init.method, "POST");
  const headers = calls[0].init.headers as Record<string, string>;
  strictEqual(headers["Content-Profile"], HOCALIST_SCHEMA);
  strictEqual(headers["Accept-Profile"], HOCALIST_SCHEMA);
  strictEqual(headers["apikey"], SERVICE_KEY);
  strictEqual(headers["Authorization"], `Bearer ${SERVICE_KEY}`);
  strictEqual(headers["Content-Type"], "application/json");
  deepStrictEqual(JSON.parse(String(calls[0].init.body)), {
    p_limit: 5,
    p_runner: "commercial-worker",
  });
});

Deno.test("serviceRpc: missing configuration and transport failures are typed", async () => {
  const { fetcher } = capturedFetcher();
  await rejects(
    async () =>
      serviceRpc({ fetcher, env: env({}) })("payout_claim_internal", {}),
    { message: "configuration_error" },
  );
  const failing = ((_url: string | URL, _init?: RequestInit) =>
    Promise.resolve(new Response("nope", { status: 500 }))) as unknown as typeof fetch;
  await rejects(
    async () =>
      serviceRpc({
        fetcher: failing,
        env: env({ SUPABASE_URL: URL_BASE, SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY }),
      })("payout_poll_batch_internal", { p_limit: 1 }),
    { message: "provider_or_storage_unavailable" },
  );
});

// No-network security tests for the secured hocalist-places handler.
//
// They prove the request contract: authentication before anything else, the
// gate before the provider, bounded bodies/responses, typed decision mapping,
// server-side suggestion recording and sanitized provider failures. Real JWT,
// PostgREST, Google and device behavior stay unproven here.
import assert from "node:assert/strict";
import { createPlacesHandler } from "./handler.ts";
import type { AuthorizationResult, PlacesRpcResult } from "./handler.ts";
import { PlacesFailure } from "../_shared/hocalist-places.ts";
import type { PlacesResult } from "../_shared/hocalist-places.ts";

const USER = "00000000-0000-4000-8000-00000000000a";
const OTHER = "00000000-0000-4000-8000-00000000000b";
const SESSION = "b01c240d-a7af-4eab-984c-123456789012";
const PLACE = "ChIJ_fixture";

type Call = { name: string; params: Record<string, unknown> };

function harness(options: {
  identity?: AuthorizationResult;
  gate?: Record<string, unknown> | null;
  gateResult?: PlacesRpcResult;
  provider?: (raw: unknown) => Promise<PlacesResult>;
  record?: unknown;
  recordFails?: boolean;
  resolveFails?: boolean;
} = {}) {
  const calls: Call[] = [];
  let providerCalls = 0;
  const handler = createPlacesHandler({
    verifyAuthorization: () =>
      Promise.resolve(options.identity ?? { userId: USER }),
    provider: (raw) => {
      providerCalls++;
      return options.provider
        ? options.provider(raw)
        : Promise.resolve({
          suggestions: [{ placeId: PLACE, label: "Public Library" }],
        });
    },
    rpc: async (name, params): Promise<PlacesRpcResult> => {
      calls.push({ name, params });
      if (name === "places_gate" || name === 'places_coordinates_gate') {
        if (options.gateResult) return options.gateResult;
        if (options.gate === null) {
          return { ok: false, status: 500, data: null };
        }
        return {
          ok: true,
          status: 200,
          data: options.gate ?? { decision: "allowed", user_id: USER },
        };
      }
      if (name === "places_record_suggestions") {
        if (options.recordFails) {
          return { ok: false, status: 500, data: null };
        }
        return {
          ok: true,
          status: 200,
          data: options.record ?? { recorded: true },
        };
      }
      if (name === "places_resolve_session") {
        return options.resolveFails
          ? { ok: false, status: 500, data: null }
          : { ok: true, status: 200, data: { resolved: true } };
      }
      return { ok: true, status: 200, data: { released: true } };
    },
  });
  return { handler, calls, providerCalls: () => providerCalls };
}

const post = (
  body: unknown,
  {
    authorization = "Bearer user-token",
    contentType = "application/json",
  }: { authorization?: string | null; contentType?: string } = {},
) =>
  new Request("https://project.supabase.co/functions/v1/hocalist-places", {
    method: "POST",
    headers: {
      "Content-Type": contentType,
      ...(authorization === null ? {} : { Authorization: authorization }),
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

const autocomplete = { operation: "autocomplete", input: "library", sessionToken: SESSION };
const details = { operation: "details", placeId: PLACE, sessionToken: SESSION };

const bodyOf = async (response: Response) => await response.json();

Deno.test('coordinate provider is gated by verified identity and shared ceilings', async()=>{
  const query={operation:'coordinates',latitude:40,longitude:-74,sessionToken:SESSION};
  for(const gate of [{decision:'membership_required'},{decision:'rate_limited'},{decision:'allowed',user_id:OTHER}]) {
    const h=harness({gate});
    assert.notEqual((await h.handler(post(query))).status,200);
    assert.equal(h.providerCalls(),0);
  }
  const denied=harness({identity:{error:'unauthorized'}});
  assert.equal((await denied.handler(post(query))).status,401); assert.equal(denied.calls.length,0);
  const h=harness({provider:async()=>({placeId:PLACE,address:'Synthetic',latitude:40,longitude:-74,timezoneId:'America/New_York',attributions:[]})});
  assert.equal((await h.handler(post(query))).status,200);
  assert.deepEqual(h.calls,[{name:'places_coordinates_gate',params:{p_user:USER}}]);
});

Deno.test("non-POST, wrong content type and missing bearer are refused before any RPC", async () => {
  const { handler, calls, providerCalls } = harness();
  const get = await handler(
    new Request("https://project.supabase.co/functions/v1/hocalist-places", {
      method: "GET",
    }),
  );
  assert.equal(get.status, 405);
  const wrongType = await handler(post(autocomplete, { contentType: "text/plain" }));
  assert.equal(wrongType.status, 415);
  const noAuth = await handler(post(autocomplete, { authorization: null }));
  assert.equal(noAuth.status, 401);
  const malformed = await handler(post(autocomplete, { authorization: "Token x" }));
  assert.equal(malformed.status, 401);
  assert.equal(calls.length, 0);
  assert.equal(providerCalls(), 0);
});

Deno.test("authentication rejection and unavailability are distinct", async () => {
  const rejected = harness({ identity: { error: "unauthorized" } });
  assert.equal((await rejected.handler(post(autocomplete))).status, 401);
  const unavailable = harness({ identity: { error: "unavailable" } });
  assert.equal((await unavailable.handler(post(autocomplete))).status, 503);
  assert.equal(rejected.calls.length, 0);
  assert.equal(unavailable.calls.length, 0);
  assert.equal(rejected.providerCalls(), 0);
  assert.equal(unavailable.providerCalls(), 0);
});

Deno.test("invalid payloads and oversized bodies are refused before the gate", async () => {
  const { handler, calls, providerCalls } = harness();
  assert.equal((await handler(post("not json"))).status, 400);
  assert.equal(
    (await handler(post({ ...autocomplete, url: "https://attacker.invalid" }))).status,
    400,
  );
  assert.equal(
    (await handler(post({ ...autocomplete, sessionToken: "not-a-uuid" }))).status,
    400,
  );
  assert.equal(
    (await handler(post({ ...autocomplete, input: "x".repeat(201) }))).status,
    400,
  );
  const oversized = await handler(post({ ...autocomplete, input: "x".repeat(5000) }));
  assert.equal(oversized.status, 413);
  assert.equal(calls.length, 0);
  assert.equal(providerCalls(), 0);
});

Deno.test("gate decisions map to stable statuses and never reach the provider", async () => {
  const cases: [string, number][] = [
    ["membership_required", 403],
    ["invalid_input", 400],
    ["rate_limited", 429],
    ["session_invalid", 400],
    ["session_expired", 400],
    ["session_exhausted", 400],
    ["suggestion_required", 400],
    ["session_busy", 409],
    ["unexpected_decision", 503],
  ];
  for (const [decision, status] of cases) {
    const { handler, providerCalls, calls } = harness({
      gate: { decision, user_id: USER },
    });
    const response = await handler(post(autocomplete));
    assert.equal(response.status, status, decision);
    const body = await bodyOf(response) as Record<string, unknown>;
    assert.equal(typeof body.error, "string");
    assert.ok(!JSON.stringify(body).includes("library"));
    assert.equal(providerCalls(), 0, `${decision} must not reach the provider`);
    assert.equal(calls.length, 1);
  }
});

Deno.test("gate transport failure and mismatched user are unavailable", async () => {
  const failed = harness({ gate: null });
  assert.equal((await failed.handler(post(autocomplete))).status, 503);
  assert.equal(failed.providerCalls(), 0);
  const mismatched = harness({ gate: { decision: "allowed", user_id: OTHER } });
  assert.equal((await mismatched.handler(post(autocomplete))).status, 503);
  assert.equal(mismatched.providerCalls(), 0);
});

Deno.test("autocomplete sends only contract fields, records suggestions and returns the bounded projection", async () => {
  const { handler, calls, providerCalls } = harness();
  const response = await handler(post(autocomplete));
  assert.equal(response.status, 200);
  assert.deepEqual(await bodyOf(response), {
    suggestions: [{ placeId: PLACE, label: "Public Library" }],
  });
  assert.deepEqual(calls[0], {
    name: "places_gate",
    params: {
      p_user: USER,
      p_operation: "autocomplete",
      p_session_token: SESSION,
      p_input: "library",
      p_place_id: null,
    },
  });
  assert.deepEqual(calls[1], {
    name: "places_record_suggestions",
    params: { p_session: SESSION, p_user: USER, p_place_ids: [PLACE] },
  });
  assert.equal(calls.length, 2);
  assert.equal(providerCalls(), 1);
});

Deno.test("autocomplete with no suggestions records nothing", async () => {
  const { handler, calls } = harness({
    provider: () => Promise.resolve({ suggestions: [] }),
  });
  const response = await handler(post(autocomplete));
  assert.equal(response.status, 200);
  assert.deepEqual(await bodyOf(response), { suggestions: [] });
  assert.equal(calls.filter((call) => call.name === "places_record_suggestions").length, 0);
});

Deno.test("failed suggestion recording hides the suggestions", async () => {
  const { handler } = harness({ recordFails: true });
  const response = await handler(post(autocomplete));
  assert.equal(response.status, 503);
  assert.ok(!JSON.stringify(await bodyOf(response)).includes("Public Library"));
});

Deno.test("details resolves the recorded session and returns the validated result", async () => {
  const resolved = {
    placeId: PLACE,
    address: "1 Library Way",
    latitude: 40,
    longitude: -73,
    attributions: [{ provider: "Example", uri: "https://example.com" }],
  };
  const { handler, calls } = harness({
    provider: () => Promise.resolve(resolved),
  });
  const response = await handler(post(details));
  assert.equal(response.status, 200);
  assert.deepEqual(await bodyOf(response), resolved);
  assert.deepEqual(calls[0], {
    name: "places_gate",
    params: {
      p_user: USER,
      p_operation: "details",
      p_session_token: SESSION,
      p_input: null,
      p_place_id: PLACE,
    },
  });
  assert.deepEqual(calls[1], {
    name: "places_resolve_session",
    params: { p_session: SESSION, p_user: USER },
  });
});

Deno.test("details provider failures release the session and stay sanitized", async () => {
  for (
    const [code, status] of [
      ["maps_rate_limited", 429],
      ["maps_unavailable", 503],
      ["maps_invalid_response", 502],
      ["maps_unconfigured", 404],
    ] as const
  ) {
    const { handler, calls } = harness({
      provider: () => Promise.reject(new PlacesFailure(code)),
    });
    const response = await handler(post(details));
    assert.equal(response.status, status, code);
    const text = JSON.stringify(await bodyOf(response));
    assert.ok(!text.includes(code));
    assert.ok(!text.includes("library"));
    assert.equal(
      calls.filter((call) => call.name === "places_release_session").length,
      1,
      `${code} must release the details reservation`,
    );
  }
  const unknown = harness({
    provider: () => Promise.reject(new Error("synthetic-key private-query")),
  });
  const response = await unknown.handler(post(details));
  assert.equal(response.status, 503);
  const text = JSON.stringify(await bodyOf(response));
  assert.ok(!text.includes("synthetic-key"));
  assert.ok(!text.includes("private-query"));
});

Deno.test("a failed resolve does not hide a successful details result", async () => {
  const resolved = {
    placeId: PLACE,
    address: "1 Library Way",
    latitude: 40,
    longitude: -73,
    attributions: [],
  };
  const { handler } = harness({
    provider: () => Promise.resolve(resolved),
    resolveFails: true,
  });
  const response = await handler(post(details));
  assert.equal(response.status, 200);
  assert.deepEqual(await bodyOf(response), resolved);
});

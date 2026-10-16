import {
  createPlacesProvider,
  parsePlacesQuery,
  PlacesFailure,
} from "./hocalist-places.ts";
import type { PlacesFetch } from "./hocalist-places.ts";
import assert from "node:assert/strict";
const sessionToken = "b01c240d-a7af-4eab-984c-123456789012";
const query = {
  operation: "autocomplete",
  input: "public library",
  sessionToken,
};
const details = { operation: "details", placeId: "ChIJ_fixture", sessionToken };
const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.test("US preference does not restrict international suggestions", async () => {
  const run = createPlacesProvider({
    apiKey: "synthetic-key",
    regionCodes: [],
    regionCode: "us",
    fetcher: (_url, init) => {
      const body = JSON.parse(init.body as string);
      assert.equal(body.regionCode, "us");
      assert.equal("includedRegionCodes" in body, false);
      assert.equal("locationRestriction" in body, false);
      return Promise.resolve(json({
        suggestions: [{
          placePrediction: {
            placeId: "ChIJ_international",
            text: { text: "Toronto, Canada" },
          },
        }],
      }));
    },
  });
  assert.deepEqual(await run(query), {
    suggestions: [{
      placeId: "ChIJ_international",
      label: "Toronto, Canada",
    }],
  });
});
const provider = (fetcher: PlacesFetch, timeoutMs?: number) =>
  createPlacesProvider({
    apiKey: "synthetic-key",
    regionCodes: ["us"],
    fetcher,
    timeoutMs,
  });
async function fails(action: () => Promise<unknown>, code: string) {
  await assert.rejects(
    action,
    (error: unknown) => error instanceof PlacesFailure && error.code === code,
  );
}
Deno.test("rejects arbitrary URLs, fields, invalid sessions and place path injection before network", async () => {
  let calls = 0;
  const run = provider(() => {
    calls++;
    throw new Error("unexpected");
  });
  for (
    const input of [
      { ...query, url: "https://attacker.invalid" },
      { ...query, fieldMask: "*" },
      { ...query, sessionToken: "bad" },
      { ...details, placeId: "../secret" },
      { ...query, input: "x".repeat(201) },
      { ...query, operation: "geocode" },
    ]
  ) await fails(() => run(input), "invalid_input");
  assert.equal(calls, 0);
});
Deno.test("autocomplete uses fixed endpoint, server region, narrow mask and session; returns public projection only", async () => {
  const run = provider(async (url, init) => {
    assert.equal(url, "https://places.googleapis.com/v1/places:autocomplete");
    assert.equal(init?.redirect, "error");
    assert.equal(init?.method, "POST");
    assert.deepEqual(JSON.parse(init?.body as string), {
      input: query.input,
      sessionToken,
      includedRegionCodes: ["us"],
      includeQueryPredictions: false,
    });
    const headers = new Headers(init?.headers);
    assert.equal(headers.get("X-Goog-Api-Key"), "synthetic-key");
    assert.equal(
      headers.get("X-Goog-FieldMask"),
      "suggestions.placePrediction.placeId,suggestions.placePrediction.text.text",
    );
    return json({
      suggestions: [{
        placePrediction: {
          placeId: "ChIJ_fixture",
          text: { text: "Library" },
          privateData: "excluded",
        },
      }],
      secret: "excluded",
    });
  });
  assert.deepEqual(await run(query), {
    suggestions: [{ placeId: "ChIJ_fixture", label: "Library" }],
  });
});
Deno.test("details preserves session and attribution without extra billed fields", async () => {
  const run = provider(async (url, init) => {
    assert.equal(
      String(url),
      `https://places.googleapis.com/v1/places/ChIJ_fixture?sessionToken=${sessionToken}`,
    );
    assert.equal(
      new Headers(init?.headers).get("X-Goog-FieldMask"),
      "id,formattedAddress,location,attributions",
    );
    return json({
      id: "ChIJ_fixture",
      formattedAddress: "Public library",
      location: { latitude: 40, longitude: -73 },
      attributions: [{
        provider: "Example",
        providerUri: "https://example.com",
      }],
      displayName: "excluded",
    });
  });
  assert.deepEqual(await run(details), {
    placeId: "ChIJ_fixture",
    address: "Public library",
    latitude: 40,
    longitude: -73,
    attributions: [{ provider: "Example", uri: "https://example.com" }],
  });
});
Deno.test("rejects wrong place identity, malformed coordinates, unsafe attribution and invalid payloads", async () => {
  for (
    const value of [{ id: "wrong", location: {} }, {
      id: "ChIJ_fixture",
      formattedAddress: "x",
      location: { latitude: 91, longitude: 0 },
    }, {
      id: "ChIJ_fixture",
      formattedAddress: "x",
      location: { latitude: 0, longitude: 0 },
      attributions: [{ provider: "x", providerUri: "javascript:alert(1)" }],
    }, []]
  ) {
    await fails(
      () => provider(async () => json(value))(details),
      "maps_invalid_response",
    );
  }
  await fails(
    () => provider(async () => json({ suggestions: Array(6).fill({}) }))(query),
    "maps_invalid_response",
  );
  await fails(
    () =>
      provider(async () =>
        new Response("not json", {
          headers: { "content-type": "application/json" },
        })
      )(query),
    "maps_invalid_response",
  );
});
Deno.test("oversized body and non-JSON fail safely", async () => {
  await fails(
    () => provider(async () => json({ oversized: "x".repeat(65536) }))(query),
    "maps_invalid_response",
  );
  await fails(
    () => provider(async () => new Response("private raw error"))(query),
    "maps_invalid_response",
  );
});
Deno.test("provider failures are sanitized and never automatically retried", async () => {
  for (const status of [400, 401, 403, 429, 500]) {
    let calls = 0;
    await fails(() =>
      provider(async () => {
        calls++;
        return json({ key: "synthetic-key", address: "private" }, status);
      })(query), status === 429 ? "maps_rate_limited" : "maps_unavailable");
    assert.equal(calls, 1);
  }
  await fails(() =>
    provider(() => {
      throw new Error("synthetic-key private-query");
    })(query), "maps_unavailable");
});
Deno.test("timeout aborts outgoing request", async () => {
  await fails(() =>
    provider((_url, init) =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener(
          "abort",
          () => reject(new Error("aborted")),
          { once: true },
        );
      }), 5)(query), "maps_unavailable");
});
Deno.test("empty predictions valid; unsafe deployment config rejected", async () => {
  assert.deepEqual(await provider(async () => json({}))(query), {
    suggestions: [],
  });
  assert.throws(() =>
    createPlacesProvider({ apiKey: "", regionCodes: ["us"] })
  );
  assert.throws(() => createPlacesProvider({ apiKey: "x", regionCodes: [] }));
  assert.equal(parsePlacesQuery(query).operation, "autocomplete");
});

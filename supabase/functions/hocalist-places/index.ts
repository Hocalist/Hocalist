// Authenticated, cost-bounded Places proxy for the Hocalist app.
//
// The Google server credential and the service role never reach the app. The
// function verifies the caller through Supabase Auth /user, then enforces
// membership, identity-bound search sessions, selected-suggestion validation
// and shared request ceilings through the service-only gateway RPCs before any
// provider call. It is disabled until HOCALIST_PLACES_ENABLED is set as part
// of a separately reviewed activation.
import { createPlacesHandler } from "./handler.ts";
import type { PlacesRpcResult } from "./handler.ts";
import { createPlacesProvider } from "../_shared/hocalist-places.ts";
import { createCoordinatePlaceProvider, createAddressPlaceProvider } from "../_shared/hocalist-coordinate-place.ts";
import { createPlacesAuthVerifier } from "./auth.ts";
import { placesPreflight, withPlacesCors } from "./cors.ts";

const PROJECT = "https://icqwbzswokoulatomgql.supabase.co";

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return placesPreflight(request);
  if (request.method !== "POST") {
    return withPlacesCors(request, json({ error: "method_not_allowed" }, 405));
  }
  // Disabled by default. Enabling live provider traffic is a separate
  // reviewed deployment/configuration action.
  if (Deno.env.get("HOCALIST_PLACES_ENABLED") !== "true") {
    return withPlacesCors(request, json({ error: "unconfigured" }, 404));
  }
  try {
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const apiKey = Deno.env.get("HOCALIST_GOOGLE_PLACES_SERVER_API_KEY") ?? "";
    // Owner decision: prefer US results without excluding other countries.
    // Do not reinterpret the former REGION_CODES restriction as a preference.
    if (
      Deno.env.get("SUPABASE_URL") !== PROJECT || !service || !apiKey
    ) {
      return withPlacesCors(request, json({ error: "unconfigured" }, 404));
    }
    const rpc = async (
      name: string,
      params: Record<string, unknown>,
    ): Promise<PlacesRpcResult> => {
      const response = await fetch(`${PROJECT}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
          apikey: service,
          Authorization: `Bearer ${service}`,
          "Content-Type": "application/json",
          "Content-Profile": "hocalist",
        },
        body: JSON.stringify(params),
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) {
        await response.body?.cancel();
        return { ok: false, status: response.status, data: null };
      }
      return { ok: true, status: response.status, data: await response.json() };
    };
    const handler = createPlacesHandler({
      verifyAuthorization: createPlacesAuthVerifier(PROJECT, service),
      provider: createPlacesProvider({
        apiKey,
        regionCodes: [],
        regionCode: "us",
        // Separate reviewed activation/key for the two billed pin lookups.
        ...(Deno.env.get('HOCALIST_COORDINATE_LOOKUP_ENABLED') === 'true' &&
            Deno.env.get('HOCALIST_GOOGLE_LOCATION_SERVER_API_KEY')
          ? {coordinateProvider:createCoordinatePlaceProvider({apiKey:Deno.env.get('HOCALIST_GOOGLE_LOCATION_SERVER_API_KEY')!}),
             addressProvider:createAddressPlaceProvider({apiKey:Deno.env.get('HOCALIST_GOOGLE_LOCATION_SERVER_API_KEY')!})}
          : {}),
      }),
      rpc,
    });
    return withPlacesCors(request, await handler(request));
  } catch {
    return withPlacesCors(request, json({ error: "unavailable" }, 503));
  }
});

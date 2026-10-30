// Pure request handler for the secured hocalist-places Edge Function.
//
// Every provider-bound request must pass: bearer authentication (verified by
// the caller-supplied verifier), the service-only `places_gate` RPC (active
// membership, identity-bound session, selected-suggestion validation, shared
// request ceilings) and bounded request/response handling. Autocomplete
// suggestions are recorded server-side before they are returned; details
// resolution is released if the provider call fails.
import {
  parsePlacesQuery,
  PlacesFailure,
} from "../_shared/hocalist-places.ts";
import type { PlacesResult } from "../_shared/hocalist-places.ts";

export const DEFAULT_MAX_BODY_BYTES = 4096;

export type AuthorizationResult =
  | { userId: string }
  | { error: "unauthorized" | "unavailable" };

export type PlacesRpcResult = {
  ok: boolean;
  status: number;
  data: unknown;
};

export type PlacesRpc = (
  name: string,
  params: Record<string, unknown>,
) => Promise<PlacesRpcResult>;

export type PlacesHandlerConfig = {
  /** Verifies the caller's bearer token with Supabase Auth and returns its id. */
  verifyAuthorization: (authorization: string) => Promise<AuthorizationResult>;
  /** Provider transport; never called before the gate allows the operation. */
  provider: (raw: unknown) => Promise<PlacesResult>;
  /** Service-role PostgREST RPC caller for the hocalist schema. */
  rpc: PlacesRpc;
  maxBodyBytes?: number;
};

class RequestFailure extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function readJsonBody(request: Request, limit: number): Promise<unknown> {
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(declared) && declared > limit) {
    throw new RequestFailure(413, "payload_too_large");
  }
  const reader = request.body?.getReader();
  if (!reader) throw new RequestFailure(400, "invalid_input");
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.length;
      if (size > limit) {
        await reader.cancel();
        throw new RequestFailure(413, "payload_too_large");
      }
      chunks.push(part.value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new RequestFailure(400, "invalid_input");
  }
}

function deniedResponse(decision: string): Response | null {
  switch (decision) {
    case "membership_required":
      return json({ error: "membership_required" }, 403);
    case "invalid_input":
      return json({ error: "invalid_input" }, 400);
    case "rate_limited":
      return json({ error: "rate_limited" }, 429);
    case "session_invalid":
    case "session_expired":
    case "session_exhausted":
    case "suggestion_required":
      return json({ error: decision }, 400);
    case "session_busy":
      return json({ error: "session_busy" }, 409);
    default:
      return null;
  }
}

function providerFailureResponse(error: unknown): Response {
  if (error instanceof PlacesFailure) {
    if (error.code === "maps_unconfigured") {
      return json({ error: "unconfigured" }, 404);
    }
    if (error.code === "maps_rate_limited") {
      return json({ error: "rate_limited" }, 429);
    }
    if (error.code === "maps_invalid_response") {
      return json({ error: "invalid_response" }, 502);
    }
  }
  return json({ error: "unavailable" }, 503);
}

export function createPlacesHandler(
  config: PlacesHandlerConfig,
): (request: Request) => Promise<Response> {
  const maxBodyBytes = config.maxBodyBytes ?? DEFAULT_MAX_BODY_BYTES;
  return async (request) => {
    try {
      if (request.method !== "POST") {
        return json({ error: "method_not_allowed" }, 405);
      }
      if (!(request.headers.get("Content-Type") ?? "").includes("application/json")) {
        return json({ error: "unsupported_media_type" }, 415);
      }
      const authorization = request.headers.get("Authorization") ?? "";
      if (!/^Bearer \S+$/.test(authorization)) {
        return json({ error: "unauthorized" }, 401);
      }
      const identity = await config.verifyAuthorization(authorization);
      if ("error" in identity) {
        return json(
          { error: identity.error },
          identity.error === "unauthorized" ? 401 : 503,
        );
      }

      const raw = await readJsonBody(request, maxBodyBytes);
      let query;
      try {
        query = parsePlacesQuery(raw);
      } catch {
        return json({ error: "invalid_input" }, 400);
      }

      const locationLookup = query.operation === 'coordinates' || query.operation === 'address';
      const gate = await config.rpc(locationLookup ? 'places_coordinates_gate' : "places_gate", locationLookup ? {
        p_user: identity.userId,
      } : {
        p_user: identity.userId,
        p_operation: query.operation,
        p_session_token: query.sessionToken,
        p_input: query.operation === "autocomplete" ? query.input : null,
        p_place_id: query.operation === "details" ? query.placeId : null,
      });
      if (!gate.ok || !isRecord(gate.data)) {
        return json({ error: "unavailable" }, 503);
      }
      const decision = gate.data.decision;
      if (decision !== "allowed") {
        if (typeof decision === "string") {
          const denied = deniedResponse(decision);
          if (denied) return denied;
        }
        return json({ error: "unavailable" }, 503);
      }
      if (gate.data.user_id !== identity.userId) {
        return json({ error: "unavailable" }, 503);
      }

      try {
        const result = await config.provider(raw);
        if (locationLookup) return json(result);
        if ("suggestions" in result) {
          const placeIds = result.suggestions.map((item) => item.placeId);
          if (placeIds.length > 0) {
            const recorded = await config.rpc("places_record_suggestions", {
              p_session: query.sessionToken,
              p_user: identity.userId,
              p_place_ids: placeIds,
            });
            if (!recorded.ok || !isRecord(recorded.data) || recorded.data.recorded !== true) {
              return json({ error: "unavailable" }, 503);
            }
          }
          return json({ suggestions: result.suggestions });
        }
        // The details result is authoritative; closing the session is
        // best-effort so a storage hiccup cannot hide a paid result.
        await config.rpc("places_resolve_session", {
          p_session: query.sessionToken,
          p_user: identity.userId,
        }).catch(() => undefined);
        return json(result);
      } catch (error) {
        if (query.operation === "details") {
          await config.rpc("places_release_session", {
            p_session: query.sessionToken,
            p_user: identity.userId,
          }).catch(() => undefined);
        }
        return providerFailureResponse(error);
      }
    } catch (error) {
      if (error instanceof RequestFailure) {
        return json({ error: error.code }, error.status);
      }
      return json({ error: "unavailable" }, 503);
    }
  };
}

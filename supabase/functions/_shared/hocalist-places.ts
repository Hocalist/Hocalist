// Provider transport only. Call behind verified membership, shared rate limits
// and server-owned search sessions. This module is not a public endpoint.
export class PlacesFailure extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}
type ObjectValue = Record<string, unknown>;
export type PlacesFetch = (url: string, init: RequestInit) => Promise<Response>;
function object(value: unknown): ObjectValue {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new PlacesFailure("invalid_input");
  }
  return value as ObjectValue;
}
function text(value: unknown, max: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > max) {
    throw new PlacesFailure("invalid_input");
  }
  return value.trim();
}
function token(value: unknown): string {
  const result = text(value, 36);
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(result)
  ) throw new PlacesFailure("invalid_input");
  return result;
}
function placeId(value: unknown): string {
  const result = text(value, 256);
  if (!/^[A-Za-z0-9_-]+$/.test(result)) {
    throw new PlacesFailure("invalid_input");
  }
  return result;
}
export type PlacesQuery =
  | { operation: "autocomplete"; input: string; sessionToken: string }
  | { operation: "details"; placeId: string; sessionToken: string };
export function parsePlacesQuery(value: unknown): PlacesQuery {
  const input = object(value);
  const allowed = input.operation === "autocomplete"
    ? ["operation", "input", "sessionToken"]
    : ["operation", "placeId", "sessionToken"];
  if (Object.keys(input).some((key) => !allowed.includes(key))) {
    throw new PlacesFailure("invalid_input");
  }
  const sessionToken = token(input.sessionToken);
  if (input.operation === "autocomplete") {
    return {
      operation: "autocomplete",
      input: text(input.input, 200),
      sessionToken,
    };
  }
  if (input.operation === "details") {
    return {
      operation: "details",
      placeId: placeId(input.placeId),
      sessionToken,
    };
  }
  throw new PlacesFailure("invalid_input");
}
export function structuredAddress(value: unknown) {
  if (value == null) return undefined;
  if (!Array.isArray(value) || value.length > 40) throw new PlacesFailure('maps_invalid_response');
  const components = value.map(object);
  const field = (type: string, short = false): string | undefined => {
    const component = components.find(c => Array.isArray(c.types) && c.types.includes(type));
    if (!component) return undefined;
    const raw = short ? component.shortText : component.longText;
    return typeof raw === 'string' && raw.trim() ? text(raw, 300) : undefined;
  };
  const street = [field('street_number'), field('route')].filter(Boolean).join(' ');
  return {
    line1: street || field('premise'),
    line2: field('subpremise'),
    city: field('locality') ?? field('postal_town') ?? field('administrative_area_level_2'),
    state: field('administrative_area_level_1', true),
    postalCode: field('postal_code'),
    country: field('country', true),
  };
}

export type PlacesResult =
  | { suggestions: { placeId: string; label: string }[] }
  | {
    placeId: string;
    address: string;
    postalAddress?: {line1?: string; line2?: string; city?: string; state?: string; postalCode?: string; country?: string};
    latitude: number;
    longitude: number;
    attributions: { provider: string; uri: string }[];
  };

export function createPlacesProvider(config: {
  apiKey: string;
  // Deployment/admin configuration, never arbitrary client input.
  regionCodes: string[];
  // Regional preference, distinct from the optional country restriction.
  regionCode?: string;
  fetcher?: PlacesFetch;
  timeoutMs?: number;
}) {
  if (
    !config.apiKey.trim() ||
    (config.regionCodes.length < 1 && !config.regionCode) ||
    (config.regionCode !== undefined &&
      !/^[a-z]{2}$/.test(config.regionCode)) ||
    config.regionCodes.length > 15 ||
    config.regionCodes.some((code) => !/^[a-z]{2}$/.test(code))
  ) throw new PlacesFailure("maps_unconfigured");
  const apiKey = config.apiKey;
  const regionCodes = [...config.regionCodes];
  const fetcher = config.fetcher ?? fetch;
  const timeoutMs = config.timeoutMs ?? 5000;
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 10000) {
    throw new PlacesFailure("maps_unconfigured");
  }
  return async (raw: unknown): Promise<PlacesResult> => {
    const query = parsePlacesQuery(raw);
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), timeoutMs);
    try {
      const autocomplete = query.operation === "autocomplete";
      const url = autocomplete
        ? "https://places.googleapis.com/v1/places:autocomplete"
        : `https://places.googleapis.com/v1/places/${
          encodeURIComponent(query.placeId)
        }?sessionToken=${encodeURIComponent(query.sessionToken)}`;
      const response = await fetcher(url, {
        method: autocomplete ? "POST" : "GET",
        redirect: "error",
        signal: abort.signal,
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": apiKey,
          "X-Goog-FieldMask": autocomplete
            ? "suggestions.placePrediction.placeId,suggestions.placePrediction.text.text"
            : "id,formattedAddress,addressComponents,location,attributions",
        },
        ...(autocomplete
          ? {
            body: JSON.stringify({
              input: query.input,
              sessionToken: query.sessionToken,
              ...(regionCodes.length
                ? { includedRegionCodes: regionCodes }
                : {}),
              ...(config.regionCode ? { regionCode: config.regionCode } : {}),
              includeQueryPredictions: false,
            }),
          }
          : {}),
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new PlacesFailure(
          response.status === 429 ? "maps_rate_limited" : "maps_unavailable",
        );
      }
      if (!response.headers.get("content-type")?.includes("application/json")) {
        await response.body?.cancel();
        throw new PlacesFailure("maps_invalid_response");
      }
      const reader = response.body?.getReader();
      if (!reader) throw new PlacesFailure("maps_invalid_response");
      const chunks: Uint8Array[] = [];
      let size = 0;
      try {
        while (true) {
          const part = await reader.read();
          if (part.done) break;
          size += part.value.length;
          if (size > 65536) {
            await reader.cancel();
            throw new PlacesFailure("maps_invalid_response");
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
      const data = object(JSON.parse(new TextDecoder().decode(bytes)));
      if (query.operation === "autocomplete") {
        const suggestions = data.suggestions ?? [];
        if (!Array.isArray(suggestions) || suggestions.length > 5) {
          throw new PlacesFailure("maps_invalid_response");
        }
        return {
          suggestions: suggestions.map((entry) => {
            const prediction = object(object(entry).placePrediction);
            return {
              placeId: placeId(prediction.placeId),
              label: text(object(prediction.text).text, 1000),
            };
          }),
        };
      }
      const location = object(data.location);
      const latitude = location.latitude;
      const longitude = location.longitude;
      if (
        data.id !== query.placeId || typeof latitude !== "number" ||
        typeof longitude !== "number" ||
        !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
        Math.abs(latitude) > 90 || Math.abs(longitude) > 180
      ) throw new PlacesFailure("maps_invalid_response");
      const attributions = data.attributions ?? [];
      if (!Array.isArray(attributions) || attributions.length > 20) {
        throw new PlacesFailure("maps_invalid_response");
      }
      return {
        placeId: query.placeId,
        address: text(data.formattedAddress, 1000),
        postalAddress: structuredAddress(data.addressComponents),
        latitude,
        longitude,
        attributions: attributions.map((item) => {
          const entry = object(item);
          const uri = text(entry.providerUri, 2000);
          if (new URL(uri).protocol !== "https:") {
            throw new PlacesFailure("maps_invalid_response");
          }
          return { provider: text(entry.provider, 300), uri };
        }),
      };
    } catch (error) {
      if (
        error instanceof PlacesFailure &&
        ["maps_rate_limited", "maps_unavailable", "maps_invalid_response"]
          .includes(error.code)
      ) throw error;
      // Never return Google bodies, request URLs, keys, queries or addresses in errors.
      throw new PlacesFailure(
        error instanceof PlacesFailure || error instanceof SyntaxError
          ? "maps_invalid_response"
          : "maps_unavailable",
      );
    } finally {
      clearTimeout(timer);
    }
  };
}

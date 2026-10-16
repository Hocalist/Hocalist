// Browser access is limited to the approved local Hocalist test preview.
// Native apps do not send Origin and continue through the normal Auth check.
const localOrigins = new Set(['http://127.0.0.1:7359']);

const allowedHeaders =
  'authorization, apikey, x-client-info, content-type, x-retry-count, ' +
  'traceparent, tracestate, baggage';

function originHeaders(request: Request): Headers {
  const headers = new Headers({ Vary: 'Origin' });
  const origin = request.headers.get('Origin');
  if (origin != null && localOrigins.has(origin)) {
    headers.set('Access-Control-Allow-Origin', origin);
    headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    headers.set('Access-Control-Allow-Headers', allowedHeaders);
  }
  return headers;
}

export function placesPreflight(request: Request): Response {
  const origin = request.headers.get('Origin');
  if (origin == null || !localOrigins.has(origin)) {
    return new Response(null, { status: 403, headers: { Vary: 'Origin' } });
  }
  return new Response(null, { status: 204, headers: originHeaders(request) });
}

export function withPlacesCors(request: Request, response: Response): Response {
  const headers = new Headers(response.headers);
  originHeaders(request).forEach((value, key) => headers.set(key, value));
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

const origins = new Set([
  'http://127.0.0.1:7359',
  'https://score-constantly-packing-lonely.trycloudflare.com',
]);
export const mediaOriginAllowed = (origin: string | null) => origin == null || origins.has(origin);
export function mediaCors(request: Request, response?: Response): Response {
  const source = request.headers.get('Origin');
  if (!mediaOriginAllowed(source)) {
    return new Response(null, {status: 403, headers: {Vary: 'Origin'}});
  }
  const headers = new Headers(response?.headers);
  headers.set('Vary', 'Origin');
  if (source != null && origins.has(source)) {
    headers.set('Access-Control-Allow-Origin', source);
    headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    headers.set('Access-Control-Allow-Headers',
      'authorization, content-type, apikey, x-client-info, x-upload-key, x-media-purpose');
  }
  return new Response(response?.body ?? null, {
    status: response?.status ?? (source != null && origins.has(source) ? 204 : 403), headers,
  });
}

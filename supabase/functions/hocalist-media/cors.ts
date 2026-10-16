const origin = 'http://127.0.0.1:7359';
export function mediaCors(request: Request, response?: Response): Response {
  const source = request.headers.get('Origin');
  if (source != null && source !== origin) {
    return new Response(null, {status: 403, headers: {Vary: 'Origin'}});
  }
  const headers = new Headers(response?.headers);
  headers.set('Vary', 'Origin');
  if (source === origin) {
    headers.set('Access-Control-Allow-Origin', origin);
    headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    headers.set('Access-Control-Allow-Headers',
      'authorization, content-type, apikey, x-client-info, x-upload-key, x-media-purpose');
  }
  return new Response(response?.body ?? null, {
    status: response?.status ?? (source === origin ? 204 : 403), headers,
  });
}

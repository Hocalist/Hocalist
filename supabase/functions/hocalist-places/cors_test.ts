import { placesPreflight, withPlacesCors } from './cors.ts';

Deno.test('approved localhost preflight allows Supabase SDK headers', () => {
  const request = new Request('https://example.test/functions/v1/hocalist-places', {
    method: 'OPTIONS',
    headers: {
      Origin: 'http://127.0.0.1:7359',
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers': 'authorization,apikey,x-client-info,content-type',
    },
  });
  const response = placesPreflight(request);
  if (response.status !== 204) throw new Error('preflight was not accepted');
  if (response.headers.get('Access-Control-Allow-Origin') !== 'http://127.0.0.1:7359') {
    throw new Error('approved origin was not returned');
  }
  for (const name of ['authorization', 'apikey', 'x-client-info', 'content-type']) {
    if (!response.headers.get('Access-Control-Allow-Headers')?.includes(name)) {
      throw new Error(`missing ${name}`);
    }
  }
});

Deno.test('unapproved browser origin cannot pass preflight', () => {
  const request = new Request('https://example.test/functions/v1/hocalist-places', {
    method: 'OPTIONS',
    headers: { Origin: 'https://unapproved.example' },
  });
  const response = placesPreflight(request);
  if (response.status !== 403 || response.headers.has('Access-Control-Allow-Origin')) {
    throw new Error('unapproved origin passed preflight');
  }
});

Deno.test('approved response includes CORS headers without changing status', () => {
  const request = new Request('https://example.test/functions/v1/hocalist-places', {
    method: 'POST',
    headers: { Origin: 'http://127.0.0.1:7359' },
  });
  const response = withPlacesCors(request, Response.json({ error: 'unauthorized' }, { status: 401 }));
  if (response.status !== 401 || response.headers.get('Access-Control-Allow-Origin') !== 'http://127.0.0.1:7359') {
    throw new Error('CORS response changed status or omitted the origin');
  }
});

Deno.test('HTTPS preview is exact; lookalike hosts remain refused', () => {
  const origin = 'https://onto-warranties-cork-snow.trycloudflare.com';
  for (const [candidate, status] of [[origin,204],[origin+'.evil.example',403],['https://other.trycloudflare.com',403],['https://catalog-bishop-mere-workers.trycloudflare.com',403],['http://onto-warranties-cork-snow.trycloudflare.com',403]] as const) {
    const response=placesPreflight(new Request('https://example.test', {method:'OPTIONS',headers:{Origin:candidate}}));
    if(response.status!==status)throw new Error('origin boundary failed');
    if(status===204 && response.headers.get('Access-Control-Allow-Origin')!==origin)throw new Error('missing exact origin');
  }
});

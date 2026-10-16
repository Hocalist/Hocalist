import {mediaCors} from './cors.ts';
function assert(value: unknown) {if (!value) throw Error('assertion_failed');}
Deno.test('media preflight is localhost-only and includes upload headers', () => {
  const allowed = mediaCors(new Request('https://endpoint.test', {method:'OPTIONS',
    headers:{Origin:'http://127.0.0.1:7359'}}));
  assert(allowed.status === 204);
  assert(allowed.headers.get('Access-Control-Allow-Headers')?.includes('x-media-purpose'));
  assert(mediaCors(new Request('https://endpoint.test',{method:'OPTIONS',headers:{Origin:'https://evil.test'}})).status === 403);
});
Deno.test('media auth failures retain CORS without exposing other origins', () => {
  const request = new Request('https://endpoint.test',{headers:{Origin:'http://127.0.0.1:7359'}});
  const response = mediaCors(request,new Response(null,{status:401}));
  assert(response.status === 401 && response.headers.get('Access-Control-Allow-Origin') === 'http://127.0.0.1:7359');
  assert(mediaCors(new Request('https://endpoint.test'), new Response(null,{status:200})).status === 200);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boundedJson } from '../app/lib/bounded-json';
import { revokeSession } from '../app/lib/session-revocation';
test('body limit counts UTF-8 bytes and stops a chunked stream early', async () => {
  let cancelled = false;
  const body = new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode('"ééé"')); }, cancel() { cancelled = true; } });
  const request = new Request('https://example.com', { method: 'POST', body, duplex: 'half' } as RequestInit);
  const result = await boundedJson(request, 5);
  assert.equal(result.ok, false);
  if (!result.ok) assert.equal(result.status, 413);
  assert.equal(cancelled, true);
});
test('session revocation uses local scope and reports provider failure', async () => {
  const config = { url: 'https://example.supabase.co', anonKey: 'public' };
  const transport = (async (input: unknown, init: RequestInit) => {
    assert.equal(input, config.url + '/auth/v1/logout?scope=local');
    assert.equal((init.headers as Record<string,string>).Authorization, 'Bearer synthetic');
    return new Response(null, { status: 204 });
  }) as typeof fetch;
  assert.equal(await revokeSession(config, 'synthetic', transport), true);
  assert.equal(await revokeSession(config, 'synthetic', (async () => new Response(null, { status: 500 })) as typeof fetch), false);
});

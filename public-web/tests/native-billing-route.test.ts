import { test } from 'node:test';
import assert from 'node:assert/strict';
import { POST } from '../app/api/session/native/route';

test('native admission verifies auth and seller, consumes once, rejects cross-origin and never exposes tokens', async () => {
  const saved = { ...process.env }, originalFetch = globalThis.fetch;
  const user = '00000000-0000-4000-8000-000000000001';
  const token = `header.${Buffer.from(JSON.stringify({ sub: user, exp: Math.floor(Date.now()/1000)+3600 })).toString('base64url')}.signature`;
  let digest = '', used = false, seller = true;
  try {
    process.env.HOCALIST_SUPABASE_URL = 'https://auth.example';
    process.env.HOCALIST_SUPABASE_ANON_KEY = 'public-test';
    process.env.HOCALIST_NATIVE_BILLING_KEY = 'ab'.repeat(32);
    globalThis.fetch = async(input, init) => {
      const url = String(input);
      assert.equal((init?.headers as Record<string,string>).Authorization, `Bearer ${token}`);
      if (url.endsWith('/auth/v1/user')) return Response.json({id:user});
      if (url.endsWith('/website_purchase_status')) return Response.json(seller?{}:{}, {status:seller?200:403});
      assert(url.endsWith('/native_billing_receipt'));
      const body = JSON.parse(String(init?.body));
      if (body.p_action === 'register') { digest = body.p_digest; used = false; return Response.json(true); }
      const allowed = body.p_digest === digest && !used; used = true; return Response.json(allowed);
    };
    const issue = () => POST(new Request('https://www.hocalist.com/api/session/native', {method:'POST', headers:{Authorization:`Bearer ${token}`}}));
    const issued = await issue(); assert.equal(issued.status,200);
    const body = await issued.json(); assert.deepEqual(Object.keys(body),['ticket']);
    assert(!body.ticket.includes(token)); assert.equal(issued.cookies.get('hocalist_site_session'),undefined);
    const redeem = (origin='https://www.hocalist.com') => POST(new Request('https://www.hocalist.com/api/session/native', {
      method:'POST', headers:{origin,'content-type':'application/json'}, body:JSON.stringify(body),
    }));
    assert.equal((await redeem('https://evil.example')).status,403);
    const admitted = await redeem(); assert.equal(admitted.status,200);
    assert.equal(admitted.cookies.get('hocalist_site_session')?.value,token);
    assert.equal(admitted.cookies.get('hocalist_app_return')?.value,'com.hocalist.app://billing-return/');
    assert.equal(admitted.headers.get('cache-control'),'no-store');
    assert(!(await admitted.text()).includes(token));
    assert.equal((await redeem()).status,401);
    seller = false; assert.equal((await issue()).status,403);
  } finally {
    globalThis.fetch = originalFetch;
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env,saved);
  }
});

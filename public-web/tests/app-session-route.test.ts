import { test } from 'node:test';
import assert from 'node:assert/strict';
import { POST } from '../app/api/session/app/route';
import { allowedAppOrigin } from '../app/lib/app-billing-return';

test('app billing admission verifies identity and seller, rejects unapproved origins and never rotates app refresh credentials', async () => {
  const saved = { ...process.env };
  const originalFetch = globalThis.fetch;
  const app = 'https://phone.example';
  const user = '00000000-0000-4000-8000-000000000001';
  const token = (sub = user, exp = Math.floor(Date.now()/1000)+300) =>
    `eyJhbGciOiJIUzI1NiJ9.${Buffer.from(JSON.stringify({sub,exp})).toString('base64url')}.synthetic`;
  let calls: string[] = [];
  let identity = user;
  let sellerAllowed = true;
  try {
    process.env.HOCALIST_SUPABASE_URL = 'https://auth.example';
    process.env.HOCALIST_SUPABASE_ANON_KEY = 'synthetic-public-key';
    process.env.HOCALIST_BILLING_APP_ORIGINS = app;
    globalThis.fetch = async(input, init) => {
      const url = String(input); calls.push(url);
      assert.match((init?.headers as Record<string,string>).Authorization, /^Bearer /);
      if (url.endsWith('/auth/v1/user')) return Response.json({id:identity,is_anonymous:false});
      assert.equal(url, 'https://auth.example/rest/v1/rpc/website_purchase_status');
      return Response.json(sellerAllowed ? {subscription:null} : {code:'42501'}, {status:sellerAllowed?200:403});
    };
    const request = (origin: string | null, access = token(), extra = '') => new Request('https://www.hocalist.com/api/session/app', {
      method:'POST', headers:{...(origin?{origin}:{}),'content-type':'application/x-www-form-urlencoded'},
      body:new URLSearchParams({access_token:access,user_id:user}).toString()+extra,
    });
    for (const origin of [null,'https://evil.example',`${app}/path`]) {
      assert.equal((await POST(request(origin))).status,403);
    }
    assert.deepEqual(calls,[]);
    assert.equal(allowedAppOrigin('https://phone.example@evil.example'),null);
    assert.equal(allowedAppOrigin(`${app}#ignored`),null);
    assert.equal((await POST(request(app,token(),'&user_id=other'))).status,400);
    assert.equal((await POST(request(app,'x'.repeat(17000)))).status,413);
    assert.deepEqual(calls,[]);
    const response = await POST(request(app));
    assert.equal(response.status,303);
    assert.equal(response.headers.get('location'),'/billing');
    assert.equal(response.cookies.get('hocalist_site_session')?.value, token());
    assert.equal(response.cookies.get('hocalist_site_refresh')?.value,'');
    assert.equal(response.cookies.get('hocalist_app_return')?.value,app);
    assert.match(response.headers.get('set-cookie')??'',/HttpOnly/);
    assert.equal(await response.text(),'');
    assert.equal(calls.length,2);
    calls=[]; identity='different-user';
    assert.equal((await POST(request(app))).status,401);
    assert.equal(calls.length,1);
    identity=user; calls=[]; sellerAllowed=false;
    assert.equal((await POST(request(app))).status,403);
    sellerAllowed=true;
    assert.equal((await POST(request(app,token(user,1)))).status,401);
    delete process.env.HOCALIST_BILLING_APP_ORIGINS;
    calls=[];
    assert.equal((await POST(request(app))).status,403);
    assert.deepEqual(calls,[]);
  } finally {
    globalThis.fetch=originalFetch;
    for(const key of ['HOCALIST_SUPABASE_URL','HOCALIST_SUPABASE_ANON_KEY','HOCALIST_BILLING_APP_ORIGINS']) {
      if(saved[key]===undefined) delete process.env[key]; else process.env[key]=saved[key];
    }
  }
});

import {test} from 'node:test';
import assert from 'node:assert/strict';

test('payment setup entry point enforces session, origin, provider URL and revocation boundaries',async()=>{
 const modulePath=require.resolve('next/headers');require(modulePath);
 const headersModule=require.cache[modulePath]!,originalHeaders=headersModule.exports;
 const originalFetch=globalThis.fetch;
 const names=['HOCALIST_SUPABASE_URL','HOCALIST_SUPABASE_ANON_KEY','HOCALIST_PAYGO_TEST_ENABLED'] as const;
 const saved=names.map(name=>process.env[name]);let signedIn=true;
 const calls:string[]=[];
 const request=(body:unknown,origin='http://localhost')=>new Request('http://localhost/api/billing/paygo',{method:'POST',headers:{'Origin':origin,'Content-Type':'application/json'},body:JSON.stringify(body)});
 try{
  process.env.HOCALIST_SUPABASE_URL='https://billing-test.example';process.env.HOCALIST_SUPABASE_ANON_KEY='synthetic-key';
  headersModule.exports={cookies:async()=>({get:(name:string)=>signedIn&&name==='hocalist_site_session'?{value:'synthetic-session'}:undefined})};
  const {GET,POST}=require('../app/api/billing/paygo/route') as typeof import('../app/api/billing/paygo/route');
  globalThis.fetch=async(input,init)=>{
   calls.push(String(input));assert.equal((init?.headers as Record<string,string>).Authorization,'Bearer synthetic-session');
   if(String(input).endsWith('paygo_payment_status'))return Response.json({authorised:true,customer_id:'never-expose',payment_method_id:'never-expose'});
   if(String(input).endsWith('paygo_payment_revoke'))return Response.json(null);
   return Response.json({setup_id:'10000000-0000-4000-8000-000000000001',url:'https://attacker.example/checkout'});
  };
  delete process.env.HOCALIST_PAYGO_TEST_ENABLED;
  assert.equal((await GET(new Request('http://localhost/api/billing/paygo'))).status,503);assert.equal(calls.length,0);
  process.env.HOCALIST_PAYGO_TEST_ENABLED='true';signedIn=false;
  assert.equal((await GET(new Request('http://localhost/api/billing/paygo'))).status,401);assert.equal(calls.length,0);
  signedIn=true;
  assert.deepEqual(await (await GET(new Request('http://localhost/api/billing/paygo'))).json(),{state:'ready',authorised:true,charges:[]});
  const count=calls.length;
  assert.equal((await POST(request({operation:'revoke'},'https://attacker.example'))).status,403);assert.equal(calls.length,count);
  assert.equal((await POST(request({operation:'begin',consent_version:'paygo-v1',idempotency_key:'10000000-0000-4000-8000-000000000002'}))).status,502);
  assert.deepEqual(await (await POST(request({operation:'revoke'}))).json(),{state:'revoked'});
  assert.ok(calls.at(-1)?.endsWith('paygo_payment_revoke'));
  const before=calls.length;assert.equal((await POST(request({operation:'revoke',user_id:'foreign'}))).status,400);assert.equal(calls.length,before);
 }finally{
  headersModule.exports=originalHeaders;globalThis.fetch=originalFetch;
  names.forEach((name,i)=>{if(saved[i]===undefined)delete process.env[name];else process.env[name]=saved[i];});
 }
});

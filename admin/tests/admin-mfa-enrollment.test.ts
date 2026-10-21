import { test } from 'node:test';
import assert from 'node:assert/strict';
import { enrollAdminMfa } from '../app/lib/admin-mfa-enrollment';
import { type CoreRequest, type CoreDeps } from '../app/lib/admin-http';
const user='00000000-0000-4000-8000-000000000001';
const factor='00000000-0000-4000-8000-000000000002';
const challenge='00000000-0000-4000-8000-000000000003';
const jwt=(aal:string)=>'e30.'+Buffer.from(JSON.stringify({sub:user,aal,exp:2000000000})).toString('base64url')+'.synthetic';
function fixture(options: { nonAdmin?:boolean; mismatch?:boolean; enrolled?:boolean }={}) {
 const calls:string[]=[];
 const transport=(async(input:unknown,init:RequestInit)=>{
  const url=String(input); calls.push(url);
  if(url.includes('/auth/v1/user')) {
   const bearer=(init.headers as Record<string,string>).Authorization;
   return Response.json({id:options.mismatch && bearer === 'Bearer '+jwt('aal1') ? 'different' : user,factors:options.enrolled ? [{id:factor,factor_type:'totp',status:'verified'}] : bearer==='Bearer '+jwt('aal1') ? [{id:factor,factor_type:'totp',status:'unverified'}] : []});
  }
  if(url.includes('/rpc/')) return Response.json(options.nonAdmin?{code:'42501'}:url.includes('admin_mfa_enrollment_eligible')?true:[],{status:options.nonAdmin?403:200});
  if(url.includes('/token')) return Response.json({access_token:jwt('aal1'),refresh_token:'synthetic-refresh',expires_in:300});
  if(url.endsWith('/factors')) return Response.json({id:factor,totp:{qr_code:'<svg xmlns="http://www.w3.org/2000/svg"></svg>'}});
  if(url.endsWith('/challenge')) return Response.json({id:challenge});
  if(url.endsWith('/verify')) return Response.json({access_token:jwt('aal2'),refresh_token:'upgraded-refresh',expires_in:300});
  throw new Error('unexpected request');
 }) as typeof fetch;
 const deps:CoreDeps={config:{url:'https://example.supabase.co',anonKey:'public'},isProduction:true,mfaPolicy:'off',evidenceHost:null,fetchImpl:transport,nowSeconds:()=>1800000000};
 const request:CoreRequest={method:'POST',origin:'https://admin.example',host:'admin.example',secFetchSite:'same-origin',sessionToken:'current',refreshToken:null,pendingToken:null,nextPath:null,body:{action:'start',email:'admin@example.com',password:'synthetic-password'}};
 return {calls,deps,request};
}
test('enrollment rejects foreign origin before any provider request',async()=>{const f=fixture();const r=await enrollAdminMfa({...f.request,origin:'https://evil.example'},f.deps);assert.equal(r.status,403);assert.equal(f.calls.length,0);});
test('enrollment rejects non-admins without creating a factor',async()=>{const f=fixture({nonAdmin:true});assert.equal((await enrollAdminMfa(f.request,f.deps)).status,403);assert.ok(!f.calls.some(x=>x.endsWith('/factors')));});
test('fresh password must belong to the same signed-in identity',async()=>{const f=fixture({mismatch:true});assert.equal((await enrollAdminMfa(f.request,f.deps)).status,403);assert.ok(!f.calls.some(x=>x.endsWith('/factors')));});
test('existing verified factor cannot be replaced by password-only setup',async()=>{const f=fixture({enrolled:true});assert.equal((await enrollAdminMfa(f.request,f.deps)).status,409);assert.ok(!f.calls.some(x=>x.includes('/token')));});
test('setup returns private QR with short HttpOnly cookie, never bearer credentials',async()=>{const f=fixture();const r=await enrollAdminMfa(f.request,f.deps);assert.equal(r.status,200);assert.equal(r.body.factor_id,factor);assert.ok(r.cookies?.[0].options.httpOnly);assert.equal(r.cookies?.[0].options.maxAge,300);assert.ok(!JSON.stringify(r.body).includes('synthetic-refresh'));assert.ok(!JSON.stringify(r.body).includes(jwt('aal1')));});
test('verification upgrades the same account and issues AAL2 cookies',async()=>{const f=fixture();const r=await enrollAdminMfa({...f.request,pendingToken:jwt('aal1'),body:{action:'verify',factor_id:factor,code:'123456'}},f.deps);assert.equal(r.status,200);assert.ok(r.cookies?.some(c=>c.value===jwt('aal2')));});
test('verification rejects an unknown factor before challenging',async()=>{const f=fixture();const r=await enrollAdminMfa({...f.request,pendingToken:jwt('aal1'),body:{action:'verify',factor_id:challenge,code:'123456'}},f.deps);assert.equal(r.status,403);assert.ok(!f.calls.some(x=>x.endsWith('/challenge')));});

test('recent provider-validated password sign-in starts setup without a second password exchange',async()=>{
 const f=fixture();const token='e30.'+Buffer.from(JSON.stringify({sub:user,exp:1800000300,amr:[{method:'password',timestamp:1800000000}]})).toString('base64url')+'.synthetic';
 const r=await enrollAdminMfa({...f.request,pendingToken:token,body:{action:'start'}},f.deps);
 assert.equal(r.status,200);assert.ok(!f.calls.some(x=>x.includes('/token')));assert.equal(r.cookies?.[0].value,token);
});
test('pending setup rejects stale password proof and email-only proof',async()=>{
 for(const entry of [{method:'password',timestamp:1799999600},{method:'otp',timestamp:1800000000}]){
 const f=fixture();const token='e30.'+Buffer.from(JSON.stringify({sub:user,exp:1800000300,amr:[entry]})).toString('base64url')+'.synthetic';
 assert.equal((await enrollAdminMfa({...f.request,pendingToken:token,body:{action:'start'}},f.deps)).status,401);assert.ok(!f.calls.some(x=>x.endsWith('/factors')));
 }
});
test('provider SVG data URL is accepted without rejecting successful enrollment',async()=>{
 const f=fixture();const original=f.deps.fetchImpl!;
 f.deps.fetchImpl=(async(input,init)=>String(input).endsWith('/factors')?Response.json({id:factor,totp:{qr_code:'data:image/svg+xml;utf-8,%3Csvg%3E%3C/svg%3E'}}):original(input,init)) as typeof fetch;
 assert.equal((await enrollAdminMfa(f.request,f.deps)).status,200);
});

test('setup attempts use distinct friendly names to avoid abandoned-factor conflicts',async()=>{
 const f=fixture();const original=f.deps.fetchImpl!,names:string[]=[];
 f.deps.fetchImpl=(async(input,init)=>{if(String(input).endsWith('/factors'))names.push(JSON.parse(init!.body as string).friendly_name);return original(input,init);}) as typeof fetch;
 assert.equal((await enrollAdminMfa(f.request,f.deps)).status,200);assert.equal((await enrollAdminMfa(f.request,f.deps)).status,200);assert.notEqual(names[0],names[1]);
});
test('factor provider errors have safe specific messages without leaking secrets',async()=>{
 for(const [code,pattern] of [['mfa_factor_name_conflict',/unfinished setup/],['too_many_enrolled_mfa_factors',/Too many unfinished/],['mfa_totp_enroll_not_enabled',/disabled/]] as const){
 const f=fixture(),original=f.deps.fetchImpl!;f.deps.fetchImpl=(async(input,init)=>String(input).endsWith('/factors')?Response.json({code,secret:'never-return-this'},{status:422}):original(input,init)) as typeof fetch;
 const r=await enrollAdminMfa(f.request,f.deps);assert.equal(r.status,409);assert.match(r.body.message as string,pattern);assert.ok(!JSON.stringify(r).includes('never-return-this'));
 }
});

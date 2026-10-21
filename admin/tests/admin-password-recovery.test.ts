import { test } from 'node:test';
import assert from 'node:assert/strict';
import { passwordRecovery,ADMIN_RESET_URL } from '../app/lib/admin-password-recovery';
import { recoveryFragment } from '../app/lib/recovery-fragment';
import type { CoreRequest,CoreDeps } from '../app/lib/admin-http';
const user='00000000-0000-4000-8000-000000000001',now=1800000000;
const jwt=(method='otp',timestamp=now,sub=user)=>'e30.'+Buffer.from(JSON.stringify({sub,exp:now+300,amr:[{method,timestamp}]})).toString('base64url')+'.synthetic';
function fixture(options:{invalid?:boolean;nonAdmin?:boolean;rateLimit?:boolean;updateCode?:string}={}){
 const calls:{url:string;init:RequestInit}[]=[];
 const deps:CoreDeps={config:{url:'https://example.supabase.co',anonKey:'public'},isProduction:true,mfaPolicy:'required',evidenceHost:null,nowSeconds:()=>now,fetchImpl:(async(input:unknown,init:RequestInit)=>{
  const url=String(input);calls.push({url,init});
  if(url.includes('/recover?'))return Response.json({}, {status:options.rateLimit?429:200});
  if(url.endsWith('/auth/v1/user')&&init.method==='GET')return Response.json({id:user},{status:options.invalid?401:200});
  if(url.includes('/rpc/'))return Response.json(!options.nonAdmin);
  if(url.endsWith('/auth/v1/user')&&init.method==='PUT')return Response.json(options.updateCode?{code:options.updateCode}:{id:user},{status:options.updateCode?422:200});
  throw Error('Unexpected request');
 }) as typeof fetch};
 const request:CoreRequest={method:'POST',origin:'https://admin.hocalist.com',host:'admin.hocalist.com',secFetchSite:'same-origin',sessionToken:null,refreshToken:null,pendingToken:null,nextPath:null,body:{action:'request',email:'admin@example.test',redirectTo:'https://evil.invalid'}};
 return {deps,request,calls};
}
test('reset email has a fixed approved destination and no account enumeration',async()=>{const f=fixture();const r=await passwordRecovery(f.request,f.deps);assert.equal(r.status,200);assert.equal(new URL(f.calls[0].url).searchParams.get('redirect_to'),ADMIN_RESET_URL);assert.deepEqual(JSON.parse(f.calls[0].init.body as string),{email:'admin@example.test'});assert.match(r.body.message as string,/If this account/);assert.equal(r.cookies,undefined);});
test('foreign origin is rejected before sending mail or changing credentials',async()=>{const f=fixture();assert.equal((await passwordRecovery({...f.request,origin:'https://evil.invalid'},f.deps)).status,403);assert.equal(f.calls.length,0);});
test('malformed email and provider throttling are handled without another request',async()=>{const f=fixture({rateLimit:true});assert.equal((await passwordRecovery({...f.request,body:{action:'request',email:'bad'}},f.deps)).status,400);assert.equal(f.calls.length,0);assert.equal((await passwordRecovery(f.request,f.deps)).status,429);});
test('missing or invalid bearer cannot update a password',async()=>{const f=fixture({invalid:true});assert.equal((await passwordRecovery({...f.request,body:{action:'update',password:'synthetic-password'}},f.deps)).status,401);assert.equal((await passwordRecovery({...f.request,body:{action:'update',password:'synthetic-password',access_token:jwt()}},f.deps)).status,401);assert.ok(!f.calls.some(x=>x.init.method==='PUT'));});
test('ordinary, stale, future and mismatched sessions cannot use email recovery',async()=>{for(const token of [jwt('password'),jwt('otp',now-601),jwt('otp',now+31),jwt('otp',now,'different')]){const f=fixture();assert.equal((await passwordRecovery({...f.request,body:{action:'update',password:'synthetic-password',access_token:token}},f.deps)).status,401);assert.ok(!f.calls.some(x=>x.init.method==='PUT'));}});
test('non-admin email session cannot enter the admin recovery flow',async()=>{const f=fixture({nonAdmin:true});assert.equal((await passwordRecovery({...f.request,body:{action:'update',password:'synthetic-password',access_token:jwt()}},f.deps)).status,403);assert.ok(!f.calls.some(x=>x.init.method==='PUT'));});
test('verified recent email proof updates only the token owner, without privileged cookies or credentials in response',async()=>{const f=fixture();const r=await passwordRecovery({...f.request,body:{action:'update',password:'synthetic-password',access_token:jwt(),user_id:'different'}},f.deps);assert.equal(r.status,200);assert.equal(r.cookies,undefined);const update=f.calls.find(x=>x.init.method==='PUT');assert.deepEqual(JSON.parse(update!.init.body as string),{password:'synthetic-password'});assert.equal((update!.init.headers as Record<string,string>).Authorization,'Bearer '+jwt());assert.ok(!JSON.stringify(r).includes('synthetic-password'));assert.ok(!JSON.stringify(r).includes(jwt()));});
test('provider password policy is preserved',async()=>{const f=fixture({updateCode:'weak_password'});const r=await passwordRecovery({...f.request,body:{action:'update',password:'synthetic-password',access_token:jwt()}},f.deps);assert.equal(r.status,400);assert.match(r.body.message as string,/stronger/);});
test('recovery fragment accepts only recovery links and handles expiry',()=>{assert.deepEqual(recoveryFragment('#access_token=synthetic&type=recovery'),{token:'synthetic',error:false});assert.deepEqual(recoveryFragment('#error=access_denied&error_code=otp_expired'),{token:'',error:true});assert.equal(recoveryFragment('#access_token=synthetic&type=signup').token,'');assert.deepEqual(recoveryFragment(''),{token:'',error:false});});

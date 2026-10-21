import { evaluateRequestOrigin } from './admin-rules';
import { callRpc, providerUserSession } from './admin-session';
import type { CoreRequest, CoreDeps, CoreResult } from './admin-http';

export const ADMIN_RESET_URL = 'https://admin.hocalist.com/reset-password';
const fail = (status:number,message:string):CoreResult => ({status,body:{ok:false,message}});

// Called only after Auth has validated the bearer. Decoding is not verification.
export function recentEmailProof(token:string,userId:string,now:number):boolean {
  try {
    const claims=JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString('utf8'));
    return claims.sub===userId && Number.isFinite(claims.exp) && claims.exp>now &&
      Array.isArray(claims.amr) && claims.amr.some((entry:{method?:unknown;timestamp?:unknown})=>
        entry?.method==='otp' && typeof entry.timestamp==='number' && entry.timestamp<=now+30 && entry.timestamp>=now-600);
  } catch { return false; }
}

export async function passwordRecovery(request:CoreRequest,deps:CoreDeps):Promise<CoreResult> {
  if(request.method!=='POST'||evaluateRequestOrigin(request)==='reject')return fail(403,'Use the Hocalist administrator portal.');
  if(!deps.config)return fail(503,'Password recovery is unavailable. Please retry later.');
  const body=request.body as Record<string,unknown>|null;
  const config=deps.config, transport=deps.fetchImpl??fetch;
  const headers={apikey:config.anonKey,'Content-Type':'application/json'};
  try {
    if(body?.action==='request') {
      const email=typeof body.email==='string'?body.email.trim():'';
      if(email.length>254||!/^\S+@\S+\.\S+$/.test(email))return fail(400,'Enter your Hocalist account email.');
      const response=await transport(config.url+'/auth/v1/recover?redirect_to='+encodeURIComponent(ADMIN_RESET_URL),{
        method:'POST',headers,body:JSON.stringify({email}),signal:AbortSignal.timeout(10000),
      });
      if(response.status===429)return fail(429,'Please wait before requesting another reset email.');
      if(!response.ok)return fail(502,'The reset email could not be requested. Please retry later.');
      return {status:200,body:{ok:true,message:'If this account can receive recovery emails, a new link is on its way. Use only the newest email.'}};
    }
    if(body?.action!=='update')return fail(400,'Choose a password recovery action.');
    const token=typeof body.access_token==='string'?body.access_token:'';
    const password=typeof body.password==='string'?body.password:'';
    if(password.length<8||password.length>200)return fail(400,'Use a password between 8 and 200 characters.');
    if(!token||token.length>8000)return fail(401,'Open a fresh password-reset email first.');
    const provider=await providerUserSession(config,token,transport);
    if(!provider.ok)return fail(provider.state==='signed_out'?401:502,'This reset session could not be verified. Request a new email.');
    if(!recentEmailProof(token,provider.userId,(deps.nowSeconds??(()=>Math.floor(Date.now()/1000)))()))return fail(401,'This reset session has expired. Request a new email.');
    const eligible=await callRpc(config,token,'admin_mfa_enrollment_eligible',{},transport);
    if(!eligible.ok||eligible.data!==true)return fail(403,'This account cannot use administrator password recovery.');
    const response=await transport(config.url+'/auth/v1/user',{
      method:'PUT',headers:{...headers,Authorization:'Bearer '+token},body:JSON.stringify({password}),signal:AbortSignal.timeout(10000),
    });
    if(!response.ok){
      const result=await response.json().catch(()=>null) as {code?:string}|null;
      if(result?.code==='same_password')return fail(400,'Choose a password different from the previous password.');
      if(result?.code==='weak_password')return fail(400,'Choose a stronger password and try again.');
      return fail(response.status===401||response.status===403?401:502,'The password could not be updated. Request a fresh link if needed.');
    }
    // Never issue administrator or pending-MFA cookies from password recovery.
    return {status:200,body:{ok:true,message:'Password updated. Sign in and complete your authenticator step.'}};
  } catch {return fail(502,'Password recovery is temporarily unavailable. Please retry.');}
}

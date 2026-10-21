import { boundedJson } from './bounded-json';
import { randomUUID } from 'node:crypto';
import { evaluateRequestOrigin, parseLoginBody, pendingCookieOptions } from './admin-rules';
import { providerUserSession, signInWithPassword, callRpc, beginMfaChallenge, MFA_PENDING_COOKIE } from './admin-session';
import { handleMfaVerifyCore, type CoreRequest, type CoreDeps, type CoreResult } from './admin-http';
const failure = (status: number, message: string): CoreResult => ({ status, body: { ok: false, message } });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function enrollAdminMfa(request: CoreRequest, deps: CoreDeps): Promise<CoreResult> {
  if (request.method !== 'POST' || evaluateRequestOrigin(request) === 'reject') return failure(403, 'Use this administrator portal to set up your authenticator.');
  if (!deps.config || !(request.pendingToken || request.sessionToken)) return failure(401, 'Sign into the administrator account first.');
  const config = deps.config;
  const transport = deps.fetchImpl ?? fetch;
  const currentToken = (request.pendingToken || request.sessionToken) as string;
  const current = await providerUserSession(config, currentToken, transport);
  if (!current.ok) return failure(current.state === 'signed_out' ? 401 : 502, 'Your session could not be verified. Sign in again.');
  const admin = await callRpc(config, currentToken, 'admin_mfa_enrollment_eligible', {}, transport);
  if (!admin.ok || admin.data !== true) return failure(admin.ok || admin.status === 403 ? 403 : 502, 'Administrator access is required.');
  const body = request.body as Record<string, unknown> | null;
  if (body?.action === 'verify') {
    const factorId = typeof body.factor_id === 'string' ? body.factor_id : '';
    const code = typeof body.code === 'string' ? body.code : '';
    if (!uuid.test(factorId) || !/^\d{6}$/.test(code) || !request.pendingToken) return failure(400, 'Enter the six-digit code from your authenticator.');
    const pending = await providerUserSession(config, request.pendingToken, transport);
    if (!pending.ok || pending.userId !== current.userId || !pending.factors.some(f => f.id === factorId && f.factorType === 'totp')) return failure(403, 'Restart authenticator setup for this account.');
    const challenge = await beginMfaChallenge(config, request.pendingToken, factorId, transport);
    if (!challenge.ok) return failure(502, 'The code check could not start. Please retry.');
    return handleMfaVerifyCore({ ...request, body: { factor_id: factorId, challenge_id: challenge.challengeId, code } }, { ...deps, mfaPolicy: 'required' });
  }
  if (body?.action !== 'start') return failure(400, 'Choose an authenticator setup action.');
  if (current.factors.some(f => f.status === 'verified')) return failure(409, 'An authenticator is already configured. Use it when signing in.');
  let enrollmentToken=currentToken;
  if(request.pendingToken) {
    // The provider validates the token above; only a recent password login may bootstrap.
    let recent=false;
    try {const claims=JSON.parse(Buffer.from(currentToken.split('.')[1],'base64url').toString('utf8'));
      const now=(deps.nowSeconds??(()=>Math.floor(Date.now()/1000)))();
      recent=claims.sub===current.userId && claims.exp>now && Array.isArray(claims.amr) && claims.amr.some((v:{method?:string;timestamp?:number})=>v.method==='password' && typeof v.timestamp==='number' && v.timestamp>=now-300 && v.timestamp<=now+30);
    }catch{}
    if(!recent)return failure(401,'Your sign-in step expired. Return to sign-in to restart authenticator setup.');
  } else {
    const credentials=parseLoginBody(body);
    if(!credentials.ok)return failure(400,credentials.message);
    const fresh=await signInWithPassword(config,credentials.value.email,credentials.value.password,transport);
    if(!fresh.ok)return failure(401,'Re-enter your administrator email and password.');
    const confirmed=await providerUserSession(config,fresh.accessToken,transport);
    if(!confirmed.ok||confirmed.userId!==current.userId)return failure(403,'Use the same administrator account that is currently signed in.');
    enrollmentToken=fresh.accessToken;
  }
  let response: Response;
  try {
    response = await transport(config.url + '/auth/v1/factors', {
      method: 'POST', headers: { apikey: config.anonKey, Authorization: 'Bearer ' + enrollmentToken, 'Content-Type': 'application/json' },
      body: JSON.stringify({ factor_type: 'totp', friendly_name: 'Hocalist administrator '+randomUUID().slice(0,8), issuer: 'Hocalist' }), signal: AbortSignal.timeout(10000),
    });
  } catch { return failure(502, 'Authenticator setup is unavailable. Please retry.'); }
  const parsed=await boundedJson(response as unknown as Request,1024*1024);
  const payload = (parsed.ok?parsed.body:null) as { id?: string; code?: string; error_code?: string; totp?: { qr_code?: string } } | null;
  if(!response.ok){
    const code=payload?.code??payload?.error_code;
    if(code==='mfa_factor_name_conflict')return failure(409,'An unfinished setup already uses this name. Start setup again.');
    if(code==='too_many_enrolled_mfa_factors')return failure(409,'Too many unfinished authenticator setups exist. Contact the owner to review them.');
    if(code==='mfa_totp_enroll_not_enabled')return failure(409,'Authenticator enrollment is disabled in the authentication service. Contact the owner.');
    if(response.status===401||response.status===403)return failure(401,'Your sign-in step expired. Return to sign-in to restart authenticator setup.');
    if(response.status===429)return failure(429,'Too many setup attempts. Wait a moment before retrying.');
    return failure(502,'The authentication service could not create the authenticator. Please retry.');
  }
  const qr = payload?.totp?.qr_code;
  if (!payload?.id || !uuid.test(payload.id) || typeof qr !== 'string' || qr.length > 900000 || !(qr.includes('<svg') || qr.startsWith('data:image/svg+xml;'))) return failure(502, 'Authenticator setup could not be prepared. Please retry.');
  return { status: 200, body: { ok: true, factor_id: payload.id, qr_code: qr }, cookies: [{ name: MFA_PENDING_COOKIE, value: enrollmentToken, options: pendingCookieOptions({ isProduction: deps.isProduction, maxAge: 300 }) }] };
}

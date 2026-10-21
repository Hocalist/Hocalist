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
  const credentials = parseLoginBody(body);
  if (!credentials.ok) return failure(400, credentials.message);
  const fresh = await signInWithPassword(config, credentials.value.email, credentials.value.password, transport);
  if (!fresh.ok) return failure(401, 'Re-enter your administrator email and password.');
  const confirmed = await providerUserSession(config, fresh.accessToken, transport);
  if (!confirmed.ok || confirmed.userId !== current.userId) return failure(403, 'Use the same administrator account that is currently signed in.');
  let response: Response;
  try {
    response = await transport(config.url + '/auth/v1/factors', {
      method: 'POST', headers: { apikey: config.anonKey, Authorization: 'Bearer ' + fresh.accessToken, 'Content-Type': 'application/json' },
      body: JSON.stringify({ factor_type: 'totp', friendly_name: 'Hocalist administrator', issuer: 'Hocalist' }), signal: AbortSignal.timeout(10000),
    });
  } catch { return failure(502, 'Authenticator setup is unavailable. Please retry.'); }
  const payload = await response.json().catch(() => null) as { id?: string; totp?: { qr_code?: string } } | null;
  const qr = payload?.totp?.qr_code;
  if (!response.ok || !payload?.id || !uuid.test(payload.id) || typeof qr !== 'string' || qr.length > 100000 || !qr.includes('<svg')) return failure(502, 'Authenticator setup could not be prepared. Please retry.');
  return { status: 200, body: { ok: true, factor_id: payload.id, qr_code: qr }, cookies: [{ name: MFA_PENDING_COOKIE, value: fresh.accessToken, options: pendingCookieOptions({ isProduction: deps.isProduction, maxAge: 300 }) }] };
}

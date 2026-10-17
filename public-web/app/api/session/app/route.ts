import { NextResponse } from 'next/server';
import { allowedAppOrigin, APP_RETURN_COOKIE } from '../../../lib/app-billing-return';
import { callRpc, siteConfig, SESSION_COOKIE, REFRESH_COOKIE } from '../../../lib/website-session';
import { sessionCookieOptions, refreshCookieOptions } from '../../../lib/website-rules';

// A top-level POST from the explicitly configured app establishes a short-lived
// website session. Tokens never enter URLs; no app refresh token is transferred
// or rotated. Admission is independently checked against Auth and the seller RPC.
export async function POST(request: Request) {
  const deny = (status: number) => NextResponse.json({ error: 'app_billing_sign_in_unavailable' }, { status });
  const origin = allowedAppOrigin(request.headers.get('origin'));
  if (!origin) return deny(403);
  if (!(request.headers.get('content-type') ?? '').startsWith('application/x-www-form-urlencoded')) return deny(415);
  if (Number(request.headers.get('content-length') ?? 0) > 16384) return deny(413);
  const config = siteConfig();
  if (!config) return deny(503);
  let text = '';
  try {
    const reader = request.body?.getReader();
    if (!reader) return deny(400);
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.byteLength;
      if (size > 16384) { await reader.cancel(); return deny(413); }
      chunks.push(part.value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch { return deny(400); }
  const body = new URLSearchParams(text);
  if ([...body.keys()].sort().join(',') !== 'access_token,user_id') return deny(400);
  const token = body.get('access_token') ?? '';
  const expectedUser = body.get('user_id');
  if (!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token) || !expectedUser) return deny(400);
  let identity: { id?: string; is_anonymous?: boolean };
  try {
    const result = await fetch(`${config.url}/auth/v1/user`, {
      headers: { apikey: config.anonKey, Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(10000), cache: 'no-store',
    });
    if (!result.ok) return deny(result.status >= 500 ? 503 : 401);
    identity = await result.json();
  } catch { return deny(503); }
  if (identity.id !== expectedUser || identity.is_anonymous) return deny(401);
  let expiresIn: number;
  try {
    const claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
    if (claims.sub !== expectedUser || !Number.isInteger(claims.exp)) return deny(401);
    expiresIn = Math.min(3600, claims.exp - Math.floor(Date.now() / 1000));
    if (expiresIn < 30) return deny(401);
  } catch { return deny(401); }
  const seller = await callRpc(config, token, 'website_purchase_status');
  if (!seller.ok) return deny(seller.status === 403 ? 403 : 503);
  const response = new NextResponse(null, { status: 303, headers: { Location: '/billing' } });
  const isProduction = process.env.NODE_ENV === 'production';
  response.headers.set('Cache-Control', 'no-store');
  response.headers.set('Referrer-Policy', 'no-referrer');
  response.cookies.set(SESSION_COOKIE, token, { ...sessionCookieOptions({ expiresIn, isProduction }), maxAge: expiresIn });
  // An older website account's refresh token must never replace this identity.
  response.cookies.set(REFRESH_COOKIE, '', { ...refreshCookieOptions({ isProduction }), maxAge: 0 });
  response.cookies.set(APP_RETURN_COOKIE, origin, {
    httpOnly: true, secure: isProduction, sameSite: 'lax', path: '/', maxAge: expiresIn,
  });
  return response;
}

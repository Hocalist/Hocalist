import { NextResponse } from 'next/server';
import { callRpc, siteConfig, SESSION_COOKIE, REFRESH_COOKIE } from '../../../lib/website-session';
import { sessionCookieOptions, refreshCookieOptions } from '../../../lib/website-rules';
import { APP_RETURN_COOKIE } from '../../../lib/app-billing-return';
import { openNativeBillingTicket, receiptDigest, sealNativeBillingTicket } from '../../../lib/native-billing-ticket';

export const runtime = 'nodejs';
const deny = (status: number) => NextResponse.json({ error: 'native_billing_unavailable' }, {
  status, headers: { 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' },
});

export async function POST(request: Request) {
  const config = siteConfig();
  if (!config) return deny(503);
  const issuance = request.headers.has('authorization');
  let token = '', expectedUser: string | undefined, digest: string | undefined;
  if (issuance) {
    // Native clients authenticate explicitly; browser cookie authentication is never accepted.
    if (request.headers.get('origin')) return deny(403);
    token = (request.headers.get('authorization') ?? '').replace(/^Bearer /, '');
  } else {
    if (request.headers.get('origin') !== new URL(request.url).origin ||
        !request.headers.get('content-type')?.startsWith('application/json')) return deny(403);
    try {
      // Bound the stream, even when content-length is missing or forged.
      const reader = request.body?.getReader();
      if (!reader) return deny(400);
      let bytes = new Uint8Array();
      while (true) {
        const part = await reader.read(); if (part.done) break;
        if (bytes.length + part.value.length > 10_000) { await reader.cancel(); return deny(413); }
        const next = new Uint8Array(bytes.length + part.value.length); next.set(bytes); next.set(part.value, bytes.length); bytes = next;
      }
      const body = JSON.parse(new TextDecoder().decode(bytes));
      if (Object.keys(body).join(',') !== 'ticket') return deny(400);
      const receipt = openNativeBillingTicket(body.ticket);
      token = receipt.token; expectedUser = receipt.user; digest = receiptDigest(receipt.nonce);
    } catch { return deny(401); }
  }
  if (!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token) || token.length > 7000) return deny(401);
  let user: string, expiresIn: number;
  try {
    const auth = await fetch(`${config.url}/auth/v1/user`, {
      headers: { apikey: config.anonKey, Authorization: `Bearer ${token}` },
      cache: 'no-store', signal: AbortSignal.timeout(10_000),
    });
    if (!auth.ok) return deny(auth.status >= 500 ? 503 : 401);
    const identity = await auth.json(); user = identity.id;
    if (!user || identity.is_anonymous || (expectedUser && expectedUser !== user)) return deny(401);
    const claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
    expiresIn = Math.min(3600, claims.exp - Math.floor(Date.now() / 1000));
    if (claims.sub !== user || !Number.isFinite(expiresIn) || expiresIn < 120) return deny(401);
    const seller = await callRpc(config, token, 'website_purchase_status');
    if (!seller.ok) return deny(seller.status === 403 ? 403 : 503);
    if (issuance) {
      const sealed = sealNativeBillingTicket(token, user);
      const registered = await callRpc(config, token, 'native_billing_receipt', {
        p_action: 'register', p_digest: receiptDigest(sealed.receipt.nonce),
      });
      if (!registered.ok || registered.data !== true) return deny(503);
      return NextResponse.json({ ticket: sealed.ticket }, { headers: { 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' } });
    }
    const consumed = await callRpc(config, token, 'native_billing_receipt', { p_action: 'consume', p_digest: digest });
    if (!consumed.ok || consumed.data !== true) return deny(401);
  } catch { return deny(503); }
  const production = process.env.NODE_ENV === 'production';
  const response = NextResponse.json({ ready: true }, { headers: { 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' } });
  response.cookies.set(SESSION_COOKIE, token, { ...sessionCookieOptions({ expiresIn, isProduction: production }), maxAge: expiresIn });
  response.cookies.set(REFRESH_COOKIE, '', { ...refreshCookieOptions({ isProduction: production }), maxAge: 0 });
  response.cookies.set(APP_RETURN_COOKIE, 'com.hocalist.app://billing-return/', {
    httpOnly: true, secure: production, sameSite: 'lax', path: '/', maxAge: expiresIn,
  });
  return response;
}

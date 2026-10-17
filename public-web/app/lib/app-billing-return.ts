// Explicit app origins only. Never accept an arbitrary return URL or a wildcard.
export const APP_RETURN_COOKIE = 'hocalist_app_return';
export function allowedAppOrigin(value: string | null): string | null {
  if (!value) return null;
  const configured = (process.env.HOCALIST_BILLING_APP_ORIGINS ?? '').split(',').map(x => x.trim()).filter(Boolean);
  try {
    const url = new URL(value);
    if (url.origin !== value || url.username || url.password) return null;
    if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(url.hostname))) return null;
    return configured.includes(value) ? value : null;
  } catch { return null; }
}

import { cookies } from 'next/headers';
import { allowedAppOrigin, APP_RETURN_COOKIE } from '../lib/app-billing-return';

export async function ReturnToApp() {
  const saved = (await cookies()).get(APP_RETURN_COOKIE)?.value ?? null;
  if (saved === 'com.hocalist.app://billing-return/') {
    return <div className="billing-actions"><a className="button secondary" href={saved}>Return to app</a></div>;
  }
  const origin = allowedAppOrigin(saved);
  if (!origin) return null;
  return <div className="billing-actions"><a className="button secondary" href={`${origin}/`}>Return to app</a></div>;
}

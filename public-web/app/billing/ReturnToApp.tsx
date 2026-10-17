import { cookies } from 'next/headers';
import { allowedAppOrigin, APP_RETURN_COOKIE } from '../lib/app-billing-return';

export async function ReturnToApp() {
  const origin = allowedAppOrigin((await cookies()).get(APP_RETURN_COOKIE)?.value ?? null);
  if (!origin) return null;
  return <div className="billing-actions"><a className="button secondary" href={`${origin}/`}>Return to app</a></div>;
}

import { cookies } from 'next/headers';
import { allowedAppOrigin, APP_RETURN_COOKIE } from '../lib/app-billing-return';
import styles from './ReturnToApp.module.css';

function ReturnLink({ href }: { href: string }) {
  return <div className={styles.container}>
    <a className={styles.link} href={href}>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="m12 5-7 7 7 7M5 12h14" /></svg>
      <span>Return to app</span>
    </a>
  </div>;
}

export async function ReturnToApp() {
  const saved = (await cookies()).get(APP_RETURN_COOKIE)?.value ?? null;
  if (saved === 'com.hocalist.app://billing-return/') {
    return <ReturnLink href={saved} />;
  }
  const origin = allowedAppOrigin(saved);
  if (!origin) return null;
  return <ReturnLink href={`${origin}/`} />;
}

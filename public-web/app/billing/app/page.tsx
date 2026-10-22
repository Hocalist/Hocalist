'use client';
import { BrandLoading } from '../../brand-loading';
import { useEffect, useRef, useState } from 'react';
import { subscribeNativeBillingReentry } from '../../lib/native-billing-reentry';

export default function NativeBillingAdmission() {
  const [failed, setFailed] = useState(false);
  const started = useRef(false);
  useEffect(() => {
    const stopReentry = subscribeNativeBillingReentry(
      window, () => window.location.hash, () => window.location.reload(),
    );
    if (started.current) return stopReentry;
    started.current = true;
    const ticket = new URLSearchParams(window.location.hash.slice(1)).get('ticket');
    // Remove the one-use credential before any network call or navigation.
    window.history.replaceState(null, '', '/billing/app');
    if (!ticket) { setFailed(true); return stopReentry; }
    const controller = new AbortController();
    const timer = window.setTimeout(() => controller.abort(), 15_000);
    void fetch('/api/session/native', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ticket }), credentials: 'same-origin',
      cache: 'no-store', referrerPolicy: 'no-referrer', signal: controller.signal,
    }).then(response => {
      if (!response.ok) throw new Error('billing_admission_failed');
      window.location.replace('/billing');
    }).catch(() => setFailed(true)).finally(() => window.clearTimeout(timer));
    // Do not abort on React's development effect replay: this ticket is one use.
    return stopReentry;
  }, []);
  return <main className="page-shell"><section className="card" aria-live="polite">
    {failed ? <><h1>Billing could not be opened</h1><p>Return to Hocalist and try opening billing again.</p></> : <BrandLoading label="Opening your billing account…" />}
    <a className="button secondary" href="com.hocalist.app://billing-return/">Return to app</a>
  </section></main>;
}

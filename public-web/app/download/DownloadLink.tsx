'use client';
export function DownloadLink({ href, platform, children }: { href: string; platform: 'android' | 'ios'; children: React.ReactNode }) {
  function record() {
    // Count a click, never claim it proves a completed install. No cross-site ID.
    void fetch('/api/waitlist', { method: 'POST', keepalive: true,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ event: 'download_click', platform, source: 'download-page', eventId: crypto.randomUUID() }),
    }).catch(() => {});
  }
  return <a className="button primary small" href={href} onClick={record}>{children}</a>;
}

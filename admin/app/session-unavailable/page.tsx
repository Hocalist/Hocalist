import Link from "next/link";

import { sanitizeNextPath } from "../lib/admin-rules";

export const dynamic = "force-dynamic";

// Reachable terminus for a navigation that could not renew its session because
// the authentication provider is temporarily unavailable. It is public by
// design and renders no protected data; the destination is retried only from
// an explicit user action.
export default async function SessionUnavailable({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const raw = Array.isArray(params.next) ? params.next[0] : params.next;
  const next = sanitizeNextPath(raw ?? null);
  return (
    <main className="login">
      <section className="login-brand">
        <span className="brandmark large">H</span>
        <p>Hocalist operations</p>
        <h1>Your session is safe, the provider is not answering.</h1>
        <p>
          The authentication service did not respond while renewing this
          session. Nothing protected was loaded and no action was taken.
        </p>
        <div className="login-note">
          <strong>Retryable</strong>
          <span>
            Your refresh session is preserved. Try again when the provider
            responds, or sign in again if the problem continues.
          </span>
        </div>
      </section>
      <section className="login-panel">
        <div className="login-card">
          <div>
            <p className="eyebrow">Session recovery</p>
            <h2>Session not renewed</h2>
            <p>
              This page is shown instead of the requested screen so an
              unreachable provider cannot loop the portal or expose protected
              data.
            </p>
          </div>
          <Link className="primary login-button" href={next}>
            Try again
          </Link>
          <small>
            <Link href="/login">Sign in instead</Link> · No privileged request
            was dispatched for this attempt.
          </small>
        </div>
      </section>
    </main>
  );
}

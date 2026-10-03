import { WAITLIST_CONSENT_VERSION } from "../../lib/website-rules";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export type WaitlistSubmission = {
  email: string;
  consent: boolean;
  market?: string;
  source?: string;
};

export function validateWaitlistSubmission(
  value: unknown
):
  | { ok: true; submission: WaitlistSubmission }
  | { ok: false; error: string } {
  if (!value || typeof value !== 'object') {
    return { ok: false, error: 'invalid_body' };
  }
  const record = value as Record<string, unknown>;
  const email = typeof record.email === 'string' ? record.email.trim() : '';
  if (email.length === 0 || email.length > 254 || !EMAIL_PATTERN.test(email)) {
    return { ok: false, error: 'invalid_email' };
  }
  if (record.consent !== true) {
    return { ok: false, error: 'consent_required' };
  }
  const market =
    typeof record.market === 'string' ? record.market.trim().slice(0, 80) : undefined;
  const source =
    typeof record.source === "string" ? record.source.trim().slice(0, 80) : undefined;
  return { ok: true, submission: { email, consent: true, market, source } };
}

// Server-selected parameters for the consented waitlist RPC. The consent
// version, the salted client fingerprint and the deployment intake token are
// never taken from request JSON.
export function waitlistRpcParams(
  submission: WaitlistSubmission,
  clientHash: string,
  intakeToken: string
): Record<string, unknown> {
  return {
    p_email: submission.email,
    p_consent_version: WAITLIST_CONSENT_VERSION,
    p_source: submission.source ?? submission.market ?? "website",
    p_client_hash: clientHash,
    p_intake_token: intakeToken,
  };
}

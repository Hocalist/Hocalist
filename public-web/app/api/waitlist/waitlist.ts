import { WAITLIST_CONSENT_VERSION } from "../../lib/website-rules";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export type WaitlistSubmission = {
  email: string;
  consent: boolean;
  market?: string;
  source?: string;
  lead?: { name: string; city: string; interest: string };
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
  let lead: WaitlistSubmission['lead'];
  if (record.lead !== undefined) {
    if (!record.lead || typeof record.lead !== 'object') return { ok: false, error: 'invalid_lead' };
    const input = record.lead as Record<string, unknown>;
    if (typeof input.name !== 'string' || input.name.trim().length > 100 ||
        typeof input.city !== 'string' || input.city.trim().length > 100 ||
        !['buyer', 'seller', 'both'].includes(String(input.interest))) return { ok: false, error: 'invalid_lead' };
    lead = { name: input.name.trim(), city: input.city.trim(), interest: String(input.interest) };
  }
  return { ok: true, submission: { email, consent: true, market, source, ...(lead ? { lead } : {}) } };
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
    ...(submission.lead ? { p_lead: submission.lead } : {}),
  };
}

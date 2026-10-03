import { createHash } from "node:crypto";
import { NextResponse } from "next/server";
import { guardFailure, guardMutation, readBoundedJson } from "../../lib/website-guard";
import { callAnonRpc, siteConfig } from "../../lib/website-session";
import { validateWaitlistSubmission, waitlistRpcParams } from "./waitlist";

// Consented launch-waitlist intake.
//
// Public-intake policy: same-origin, JSON-only and bounded, with no cookies
// involved. The database function is a server-controlled boundary (it requires
// the deployment intake secret and enforces atomic caps), so a public caller
// cannot invent fingerprints or enumerate the list. The public response is one
// generic acknowledgement for new and existing addresses alike; marketing
// sends, public launch and retention automation stay gated outside this route.

const WINDOW_MS = 60 * 60 * 1000;
const MAX_PER_WINDOW = 10;
const attempts = new Map<string, number[]>();

function intakeSecret(): string | null {
  const secret = process.env.HOCALIST_WAITLIST_INTAKE_SECRET ?? "";
  return secret.length >= 32 && secret.length <= 200 ? secret : null;
}

// Trusted deployment metadata. Vercel writes the connecting client address to
// these headers; a forged forwarded header only changes an opaque fingerprint,
// while the database's global hourly cap remains the hard backstop.
function clientFingerprint(request: Request, secret: string): string {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const address = request.headers.get("x-real-ip")?.trim() || forwarded || "unknown";
  return createHash("sha256").update(`${address}|${secret}`).digest("hex");
}

function withinRouteLimit(fingerprint: string): boolean {
  const now = Date.now();
  const recent = (attempts.get(fingerprint) ?? []).filter((time) => now - time < WINDOW_MS);
  if (recent.length >= MAX_PER_WINDOW) {
    attempts.set(fingerprint, recent);
    return false;
  }
  recent.push(now);
  attempts.set(fingerprint, recent);
  return true;
}

const unavailable = () =>
  NextResponse.json(
    {
      error: "waitlist_not_configured",
      message: "The launch list is not open yet, so nothing was stored. Use the email updates option instead.",
    },
    { status: 503 },
  );

export async function POST(request: Request) {
  const guard = guardMutation(request, { policy: "public-intake", maxBytes: 2048 });
  if (!guard.ok) return guardFailure(guard);
  const config = siteConfig();
  const secret = intakeSecret();
  if (!config || !secret) return unavailable();
  const parsedBody = await readBoundedJson(request, 2048);
  if (!parsedBody.ok) {
    return NextResponse.json({ error: "invalid_body" }, { status: parsedBody.status });
  }
  const result = validateWaitlistSubmission(parsedBody.body);
  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: 400 });
  }
  const fingerprint = clientFingerprint(request, secret);
  if (!withinRouteLimit(fingerprint)) {
    return NextResponse.json(
      { error: "rate_limited", message: "Too many launch-list requests. Try again later." },
      { status: 429 },
    );
  }
  const stored = await callAnonRpc(
    config,
    "website_waitlist_join",
    waitlistRpcParams(result.submission, fingerprint, secret),
  );
  if (!stored.ok) {
    const code = stored.code ?? "";
    const message = stored.message ?? "";
    if (code === "rate_limited" || message === "rate_limited") {
      return NextResponse.json(
        { error: "rate_limited", message: "Too many launch-list requests. Try again later." },
        { status: 429 },
      );
    }
    if (
      message === "invalid_email" || message === "consent_required" ||
      message === "invalid_source" || message === "invalid_client" || code === "22023"
    ) {
      return NextResponse.json({ error: "invalid_email" }, { status: 400 });
    }
    // Missing configuration, an unknown intake token or any storage failure
    // is reported exactly like an unconfigured backend: nothing was stored and
    // no internal state is disclosed.
    return unavailable();
  }
  return NextResponse.json({
    status: "accepted",
    message: "Thanks — you are on the launch update list. You can unsubscribe at any time.",
  });
}

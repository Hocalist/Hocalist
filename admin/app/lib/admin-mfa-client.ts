// Browser helper for the second-factor completion flow. The pending session
// lives only in an httpOnly cookie; this module never persists or exposes a
// token and it never receives a privileged session cookie.
export type MfaFactorView = {
  id: string;
  factorType: string;
  friendlyName: string | null;
};

export type MfaOutcome<T> = { ok: true; value: T } | { ok: false; state: string; message: string };

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

async function post(path: string, body: Record<string, unknown>): Promise<MfaOutcome<Record<string, unknown>>> {
  let response: Response;
  try {
    response = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    return { ok: false, state: "unreachable", message: "The admin backend is unreachable." };
  }
  const payload = (await response.json().catch(() => null)) as
    | (Record<string, unknown> & { ok?: boolean; state?: string; message?: string })
    | null;
  if (!payload || typeof payload !== "object") {
    return { ok: false, state: "error", message: "The admin backend returned an invalid response." };
  }
  if (payload.ok === true) return { ok: true, value: payload };
  if (typeof payload.state !== "string" || typeof payload.message !== "string") {
    return { ok: false, state: "error", message: "The admin backend returned an invalid response." };
  }
  return { ok: false, state: payload.state, message: payload.message };
}

export function decodeFactors(value: unknown): MfaFactorView[] | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > 10) return null;
  const factors: MfaFactorView[] = [];
  for (const raw of value) {
    if (!raw || typeof raw !== "object") return null;
    const factor = raw as Record<string, unknown>;
    if (
      typeof factor.id !== "string" ||
      !UUID.test(factor.id) ||
      factor.id.length > 64 ||
      (factor.friendlyName !== null && typeof factor.friendlyName !== "string")
    ) {
      return null;
    }
    factors.push({
      id: factor.id,
      factorType: typeof factor.factorType === "string" ? factor.factorType : "unknown",
      friendlyName: factor.friendlyName as string | null,
    });
  }
  return factors;
}

export async function fetchPendingFactors(): Promise<MfaOutcome<MfaFactorView[]>> {
  const result = await post("/api/mfa/pending", {});
  if (!result.ok) return result;
  const factors = decodeFactors(result.value.factors);
  if (!factors) {
    return { ok: false, state: "error", message: "The backend returned an invalid factor list." };
  }
  return { ok: true, value: factors };
}

export async function requestMfaChallenge(
  factorId: string,
): Promise<MfaOutcome<{ challengeId: string }>> {
  const result = await post("/api/mfa/challenge", { factor_id: factorId });
  if (!result.ok) return result;
  const challengeId = result.value.challenge_id;
  if (typeof challengeId !== "string" || challengeId.length === 0 || challengeId.length > 64) {
    return { ok: false, state: "error", message: "The backend returned an invalid challenge." };
  }
  return { ok: true, value: { challengeId } };
}

export async function verifyMfa(
  factorId: string,
  challengeId: string,
  code: string,
): Promise<MfaOutcome<Record<string, never>>> {
  const result = await post("/api/mfa/verify", {
    factor_id: factorId,
    challenge_id: challengeId,
    code,
  });
  if (!result.ok) return result;
  return { ok: true, value: {} };
}

export async function cancelMfa(): Promise<void> {
  await post("/api/mfa/cancel", {});
}

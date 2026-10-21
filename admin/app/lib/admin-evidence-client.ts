// Browser helper for the narrow evidence gateway. The server decides whether a
// URL may be issued; this only validates the response shape before display.
export type EvidenceClientResult =
  | { ok: true; url: string; expiresAt: string | null }
  | { ok: false; state: string; message: string };

const HTTPS_URL = /^https:\/\/[\w.-]+(:\d+)?(\/[^\s"']*)?$/;

export function decodeEvidenceResponse(value: unknown): EvidenceClientResult | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (record.ok !== true) {
    if (typeof record.state !== "string" || typeof record.message !== "string") return null;
    return { ok: false, state: record.state, message: record.message };
  }
  if (typeof record.url !== "string" || record.url.length > 2048 || !HTTPS_URL.test(record.url)) {
    return null;
  }
  const expiresAt = record.expires_at;
  if (expiresAt !== null && (typeof expiresAt !== "string" || expiresAt.length > 40)) {
    return null;
  }
  return { ok: true, url: record.url, expiresAt: expiresAt as string | null };
}

export async function requestEvidence(
  submissionId: string,
  mediaId: string,
): Promise<EvidenceClientResult> {
  let response: Response;
  try {
    response = await fetch("/api/admin-evidence", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ submission_id: submissionId, media_id: mediaId }),
    });
  } catch {
    return { ok: false, state: "unreachable", message: "The evidence gateway is unreachable." };
  }
  if (response.ok && response.headers.get("content-type")?.split(";")[0] === "image/jpeg") {
    const image = await response.blob();
    if (image.size > 0 && image.size <= 4 * 1024 * 1024) {
      return { ok: true, url: URL.createObjectURL(image), expiresAt: null };
    }
    return { ok: false, state: "error", message: "The evidence image was invalid." };
  }
  const decoded = decodeEvidenceResponse(await response.json().catch(() => null));
  if (!decoded) {
    return {
      ok: false,
      state: "error",
      message: "The evidence gateway returned an invalid response.",
    };
  }
  return decoded;
}

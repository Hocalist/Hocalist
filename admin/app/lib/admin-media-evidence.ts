import type { AdminEvidenceResolver } from "./admin-http";

const MAX_IMAGE_BYTES = 4 * 1024 * 1024;

/** Reads authorized bytes with the admitted admin session; never uses a service key. */
export const mediaEvidenceResolver: AdminEvidenceResolver = {
  async resolveEvidence({ mediaId, accessToken, config, fetchImpl }) {
    const unavailable = {
      state: "unavailable" as const,
      reason: "evidence_read_unavailable",
      message: "Evidence could not be loaded. Refresh the review and try again.",
    };
    try {
      const endpoint = new URL(`${config.url}/functions/v1/hocalist-media`);
      endpoint.searchParams.set("action", "read");
      endpoint.searchParams.set("id", mediaId);
      const response = await fetchImpl(endpoint, {
        method: "POST", redirect: "error",
        headers: { apikey: config.anonKey, Authorization: `Bearer ${accessToken}`, "Cache-Control": "no-store" },
        signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok || response.headers.get("content-type")?.split(";")[0] !== "image/jpeg" || !response.body) return unavailable;
      const reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let total = 0;
      while (true) {
        const next = await reader.read();
        if (next.done) break;
        total += next.value.length;
        if (total > MAX_IMAGE_BYTES) { await reader.cancel(); return unavailable; }
        chunks.push(next.value);
      }
      const bytes = Buffer.concat(chunks, total);
      if (bytes.length < 3 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) return unavailable;
      return { state: "image", bytes };
    } catch { return unavailable; }
  },
};

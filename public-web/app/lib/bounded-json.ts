// Limit incoming bytes before decoding or parsing untrusted JSON.
export async function boundedJson(request: Request, maxBytes: number): Promise<
  { ok: true; body: unknown } | { ok: false; status: number; error: string }
> {
  const reader = request.body?.getReader();
  if (!reader) return { ok: false, status: 400, error: "invalid_body" };
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        await reader.cancel().catch(() => undefined);
        return { ok: false, status: 413, error: "request_too_large" };
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return { ok: true, body: JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) };
  } catch {
    return { ok: false, status: 400, error: "invalid_body" };
  } finally { reader.releaseLock(); }
}

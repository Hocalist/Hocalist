export type RequestPostingSettings = { maximum_active_requests: number; revision: number };
export function parseRequestPostingSettings(value: unknown): RequestPostingSettings | null {
  if (!value || typeof value !== "object") return null;
  const v = value as Record<string, unknown>;
  return Number.isSafeInteger(v.maximum_active_requests) && Number(v.maximum_active_requests) >= 1 && Number(v.maximum_active_requests) <= 100
    && Number.isSafeInteger(v.revision) && Number(v.revision) > 0
    ? { maximum_active_requests: Number(v.maximum_active_requests), revision: Number(v.revision) } : null;
}
export function parseActiveRequestLimit(value: string): number | null {
  if (!/^[1-9][0-9]*$/.test(value)) return null;
  const limit = Number(value);
  return Number.isSafeInteger(limit) && limit <= 100 ? limit : null;
}

const uuid = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

const isCount = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0;

const isTimestamp = (value: unknown): value is string | null =>
  value === null || (typeof value === "string" && value.length <= 40);

export type DeliveryFailure = {
  id: string;
  kind: string;
  user_id: string;
  attempts: number;
  last_error: string;
  available_at: string;
};

export type DeliveryOverview = {
  pending: number;
  sending: number;
  accepted: number;
  skipped: number;
  failed: number;
  failed_last_24h: number;
  oldest_pending_at: string | null;
  recent_failures: DeliveryFailure[];
};

export function decodeDeliveryOverview(value: unknown): DeliveryOverview | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  for (const field of ["pending", "sending", "accepted", "skipped", "failed", "failed_last_24h"]) {
    if (!isCount(record[field])) return null;
  }
  if (!isTimestamp(record.oldest_pending_at)) return null;
  if (!Array.isArray(record.recent_failures) || record.recent_failures.length > 20) return null;
  const failures: DeliveryFailure[] = [];
  const ids = new Set<string>();
  for (const raw of record.recent_failures) {
    if (!raw || typeof raw !== "object") return null;
    const row = raw as Record<string, unknown>;
    if (
      typeof row.id !== "string" ||
      !uuid.test(row.id) ||
      ids.has(row.id) ||
      typeof row.kind !== "string" ||
      row.kind.length === 0 ||
      row.kind.length > 60 ||
      typeof row.user_id !== "string" ||
      !uuid.test(row.user_id) ||
      !isCount(row.attempts) ||
      typeof row.last_error !== "string" ||
      row.last_error.length > 200 ||
      typeof row.available_at !== "string" ||
      row.available_at.length > 40
    ) {
      return null;
    }
    ids.add(row.id);
    failures.push({
      id: row.id,
      kind: row.kind,
      user_id: row.user_id,
      attempts: row.attempts,
      last_error: row.last_error,
      available_at: row.available_at,
    });
  }
  return {
    pending: record.pending as number,
    sending: record.sending as number,
    accepted: record.accepted as number,
    skipped: record.skipped as number,
    failed: record.failed as number,
    failed_last_24h: record.failed_last_24h as number,
    oldest_pending_at: record.oldest_pending_at as string | null,
    recent_failures: failures,
  };
}

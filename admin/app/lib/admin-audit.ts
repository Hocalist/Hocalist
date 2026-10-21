// Decoder for the cross-feature administrator audit feed. Sources are a fixed
// server-reviewed allowlist; the client can only filter by them.
export const AUDIT_SOURCES = [
  "moderation",
  "configuration",
  "commercial",
  "support",
  "trust",
  "calls",
  "withdrawals",
] as const;

export type AuditSource = (typeof AUDIT_SOURCES)[number];

const CURSOR = /^\d{1,20}\|[0-9a-f]{32}$/;

const isCount = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0;

const isText = (value: unknown, max: number): value is string =>
  typeof value === "string" && value.length <= max;

export type AuditRow = {
  id: string;
  occurred_at: string;
  source: AuditSource;
  action: string;
  actor: string;
  target: string;
  summary: string;
  detail: string | null;
};

export type AuditFeed = {
  items: AuditRow[];
  next_cursor: string | null;
  sources: AuditSource[];
};

export function decodeAuditFeed(value: unknown): AuditFeed | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (
    !Array.isArray(record.items) ||
    record.items.length > 100 ||
    !(record.next_cursor === null || (typeof record.next_cursor === "string" && CURSOR.test(record.next_cursor))) ||
    !Array.isArray(record.sources) ||
    record.sources.some((source) => !(AUDIT_SOURCES as readonly unknown[]).includes(source))
  ) {
    return null;
  }
  const items: AuditRow[] = [];
  const ids = new Set<string>();
  for (const raw of record.items) {
    if (!raw || typeof raw !== "object") return null;
    const row = raw as Record<string, unknown>;
    if (
      typeof row.id !== "string" ||
      !/^[0-9a-f]{32}$/.test(row.id) ||
      ids.has(row.id) ||
      typeof row.occurred_at !== "string" ||
      row.occurred_at.length > 40 ||
      !(AUDIT_SOURCES as readonly unknown[]).includes(row.source) ||
      !isText(row.action, 80) ||
      row.action.length === 0 ||
      !isText(row.actor, 80) ||
      !isText(row.target, 80) ||
      !isText(row.summary, 200) ||
      (row.detail !== null && !isText(row.detail, 500))
    ) {
      return null;
    }
    ids.add(row.id);
    items.push({
      id: row.id,
      occurred_at: row.occurred_at,
      source: row.source as AuditSource,
      action: row.action as string,
      actor: row.actor as string,
      target: row.target as string,
      summary: row.summary as string,
      detail: row.detail as string | null,
    });
  }
  if (record.next_cursor !== null && items.length === 0) return null;
  return {
    items,
    next_cursor: record.next_cursor as string | null,
    sources: record.sources as AuditSource[],
  };
}

export function isAuditSource(value: string): value is AuditSource {
  return (AUDIT_SOURCES as readonly string[]).includes(value);
}

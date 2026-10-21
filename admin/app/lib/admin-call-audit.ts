const uuid = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

export type CallAuditEntry = {
  revision: number;
  enabled: boolean;
  changed_by: string;
  changed_at: string;
};

export type CallAuditHistory = {
  current_enabled: boolean;
  items: CallAuditEntry[];
};

export function decodeCallAuditHistory(value: unknown): CallAuditHistory | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  if (typeof record.current_enabled !== "boolean") return null;
  if (!Array.isArray(record.items) || record.items.length > 20) return null;
  const items: CallAuditEntry[] = [];
  const revisions = new Set<number>();
  for (const raw of record.items) {
    if (!raw || typeof raw !== "object") return null;
    const row = raw as Record<string, unknown>;
    if (
      typeof row.revision !== "number" ||
      !Number.isSafeInteger(row.revision) ||
      row.revision < 1 ||
      revisions.has(row.revision) ||
      typeof row.enabled !== "boolean" ||
      typeof row.changed_by !== "string" ||
      !uuid.test(row.changed_by) ||
      typeof row.changed_at !== "string" ||
      row.changed_at.length > 40
    ) {
      return null;
    }
    revisions.add(row.revision);
    items.push({
      revision: row.revision,
      enabled: row.enabled,
      changed_by: row.changed_by,
      changed_at: row.changed_at,
    });
  }
  return { current_enabled: record.current_enabled, items };
}

const uuid = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

const isCount = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0;

const isText = (value: unknown, max: number): value is string =>
  typeof value === "string" && value.length <= max;

export type TrustVerification = {
  id: string;
  user_id: string;
  kind: string;
  note: string;
  evidence_media_ids: string[];
  evidence_count: number;
  status: string;
  revision: number;
  created_at: string;
  decision_reason: string | null;
};

export type TrustHealthReview = {
  case_id: string;
  reason_code: string;
  status: string;
  body: string;
  created_at: string;
  decision: string | null;
  decision_reason: string | null;
};

export type TrustRestriction = {
  id: string;
  user_id: string;
  scope: string;
  reason: string;
  source: string;
  status: string;
  revision: number;
  created_at: string;
  appeal_id: string | null;
  appeal_status: string | null;
  appeal_revision: number | null;
};

export type ReviewSection<T> = { items: T[]; next_cursor: string | null };

export type ReviewQueue = {
  verifications: ReviewSection<TrustVerification>;
  health_reviews: ReviewSection<TrustHealthReview>;
  restrictions: ReviewSection<TrustRestriction>;
  single_report_penalty: boolean;
};

const CURSOR = /^\d{1,20}\|[0-9a-f-]{36}$/;

function decodeSection<T>(
  value: unknown,
  decodeRow: (row: Record<string, unknown>) => T | null,
): ReviewSection<T> | null {
  if (!value || typeof value !== "object") return null;
  const section = value as Record<string, unknown>;
  if (
    !Array.isArray(section.items) ||
    section.items.length > 100 ||
    !(section.next_cursor === null ||
      (typeof section.next_cursor === "string" && CURSOR.test(section.next_cursor)))
  ) {
    return null;
  }
  const items: T[] = [];
  for (const raw of section.items) {
    if (!raw || typeof raw !== "object") return null;
    const decoded = decodeRow(raw as Record<string, unknown>);
    if (decoded === null) return null;
    items.push(decoded);
  }
  if (section.next_cursor !== null && items.length === 0) return null;
  return { items, next_cursor: section.next_cursor as string | null };
}

/**
 * Decodes the 161 review queue. Every row carries the committed revision a
 * decision must send back, evidence is exposed only as bounded media
 * references (never a URL), and each section has its own keyset cursor.
 */
export function decodeReviewQueue(value: unknown): ReviewQueue | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  const verifications = decodeSection<TrustVerification>(record.verifications, (row) => {
    if (
      typeof row.id !== "string" ||
      !uuid.test(row.id) ||
      typeof row.user_id !== "string" ||
      !uuid.test(row.user_id) ||
      !isText(row.kind, 20) ||
      !isText(row.note, 2000) ||
      !Array.isArray(row.evidence_media_ids) ||
      row.evidence_media_ids.length > 8 ||
      row.evidence_media_ids.some((media) => typeof media !== "string" || !uuid.test(media)) ||
      !isCount(row.evidence_count) ||
      row.evidence_count !== row.evidence_media_ids.length ||
      !isText(row.status, 20) ||
      !isCount(row.revision) ||
      row.revision < 1 ||
      !isText(row.created_at, 40) ||
      (row.decision_reason !== null && !isText(row.decision_reason, 500))
    ) {
      return null;
    }
    return {
      id: row.id,
      user_id: row.user_id,
      kind: row.kind as string,
      note: row.note as string,
      evidence_media_ids: row.evidence_media_ids as string[],
      evidence_count: row.evidence_count,
      status: row.status as string,
      revision: row.revision,
      created_at: row.created_at as string,
      decision_reason: row.decision_reason as string | null,
    };
  });
  const health = decodeSection<TrustHealthReview>(record.health_reviews, (row) => {
    if (
      typeof row.case_id !== "string" ||
      !uuid.test(row.case_id) ||
      !isText(row.reason_code, 40) ||
      !isText(row.status, 20) ||
      !isText(row.body, 4000) ||
      !isText(row.created_at, 40) ||
      (row.decision !== null && !isText(row.decision, 40)) ||
      (row.decision_reason !== null && !isText(row.decision_reason, 500))
    ) {
      return null;
    }
    return {
      case_id: row.case_id,
      reason_code: row.reason_code as string,
      status: row.status as string,
      body: row.body as string,
      created_at: row.created_at as string,
      decision: row.decision as string | null,
      decision_reason: row.decision_reason as string | null,
    };
  });
  const restrictions = decodeSection<TrustRestriction>(record.restrictions, (row) => {
    if (
      typeof row.id !== "string" ||
      !uuid.test(row.id) ||
      typeof row.user_id !== "string" ||
      !uuid.test(row.user_id) ||
      !isText(row.scope, 20) ||
      !isText(row.reason, 500) ||
      !isText(row.source, 20) ||
      !isText(row.status, 20) ||
      !isCount(row.revision) ||
      row.revision < 1 ||
      !isText(row.created_at, 40) ||
      (row.appeal_id !== null && !isText(row.appeal_id, 40)) ||
      (row.appeal_status !== null && !isText(row.appeal_status, 20)) ||
      (row.appeal_revision !== null &&
        (!isCount(row.appeal_revision) || row.appeal_revision < 1)) ||
      (row.appeal_id === null) !== (row.appeal_status === null) ||
      (row.appeal_id === null) !== (row.appeal_revision === null)
    ) {
      return null;
    }
    return {
      id: row.id,
      user_id: row.user_id,
      scope: row.scope as string,
      reason: row.reason as string,
      source: row.source as string,
      status: row.status as string,
      revision: row.revision,
      created_at: row.created_at as string,
      appeal_id: row.appeal_id as string | null,
      appeal_status: row.appeal_status as string | null,
      appeal_revision: row.appeal_revision as number | null,
    };
  });
  if (!verifications || !health || !restrictions) return null;
  return {
    verifications,
    health_reviews: health,
    restrictions,
    single_report_penalty: record.single_report_penalty === true,
  };
}

export type ReviewSectionKey = "verifications" | "health_reviews" | "restrictions";

const sectionKey = (row: { id?: string; case_id?: string }): string =>
  row.id ?? row.case_id ?? "";

/**
 * Appends one loaded page of a section while dropping anything already shown;
 * only the requested section's cursor advances. Used by the queue's
 * "Load more" controls.
 */
export function mergeReviewSection(
  previous: ReviewQueue,
  incoming: ReviewQueue,
  section: ReviewSectionKey,
): ReviewQueue {
  const seen = new Set(previous[section].items.map(sectionKey));
  const merged = {
    ...previous,
    [section]: {
      items: [
        ...previous[section].items,
        ...incoming[section].items.filter((row) => !seen.has(sectionKey(row))),
      ],
      next_cursor: incoming[section].next_cursor,
    },
  };
  return merged as ReviewQueue;
}

/** Safe, specific messages for the reviewed trust command. */
export function trustErrorMessage(message: string, state?: string): string {
  if (state === "signed_out") return "Sign in again to record a review decision.";
  if (state === "forbidden") return "Administrator access is required.";
  if (state === "unconfigured") return "The admin backend is not configured.";
  const normalized = message.toLowerCase();
  if (normalized.includes("revision_conflict")) {
    return "Another reviewer changed this record. Refresh and review the current state before deciding.";
  }
  if (normalized.includes("idempotency_conflict")) {
    return "This decision key was already used for a different change. Refresh before deciding again.";
  }
  if (normalized.includes("invalid_")) {
    return "The backend rejected this decision. Check the reason and selected status.";
  }
  return "The decision was not confirmed. Retry the same decision or refresh and check the recorded state.";
}

export type WithdrawalQueueRow = {
  id: string;
  user_id: string;
  display_name: string;
  amount_minor: number;
  fee_minor: number;
  net_minor: number;
  status: string;
  provider: string | null;
  provider_reference: string | null;
  failure_reason: string | null;
  created_at: string;
  updated_at: string;
};

export type WithdrawalQueue = {
  items: WithdrawalQueueRow[];
  next_cursor: string | null;
  processing_minor: number;
};

export function decodeWithdrawalQueue(value: unknown): WithdrawalQueue | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  if (!Array.isArray(record.items) || !isCount(record.processing_minor)) {
    return null;
  }
  if (record.next_cursor !== null && typeof record.next_cursor !== "string") {
    return null;
  }
  const items: WithdrawalQueueRow[] = [];
  for (const raw of record.items) {
    if (!raw || typeof raw !== "object") return null;
    const row = raw as Record<string, unknown>;
    if (
      typeof row.id !== "string" ||
      !uuid.test(row.id) ||
      typeof row.user_id !== "string" ||
      !uuid.test(row.user_id) ||
      !isText(row.display_name, 200) ||
      !isCount(row.amount_minor) ||
      !isCount(row.fee_minor) ||
      !isCount(row.net_minor) ||
      !isText(row.status, 20) ||
      !isText(row.created_at, 40) ||
      !isText(row.updated_at, 40) ||
      (row.provider !== null && !isText(row.provider, 60)) ||
      (row.provider_reference !== null && !isText(row.provider_reference, 200)) ||
      (row.failure_reason !== null && !isText(row.failure_reason, 500))
    ) {
      return null;
    }
    items.push({
      id: row.id,
      user_id: row.user_id,
      display_name: row.display_name as string,
      amount_minor: row.amount_minor,
      fee_minor: row.fee_minor,
      net_minor: row.net_minor,
      status: row.status as string,
      provider: row.provider as string | null,
      provider_reference: row.provider_reference as string | null,
      failure_reason: row.failure_reason as string | null,
      created_at: row.created_at as string,
      updated_at: row.updated_at as string,
    });
  }
  return {
    items,
    next_cursor: (record.next_cursor as string | null) ?? null,
    processing_minor: record.processing_minor,
  };
}

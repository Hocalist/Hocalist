// Decoders for the read-only failed-event operations view. The Stripe TEST
// receipt inbox is the only live source; email events stay explicitly
// unavailable until an ingestion contract exists.
const isCount = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0;

const isEventId = (value: unknown): value is string =>
  typeof value === "string" && /^evt_[A-Za-z0-9]{1,251}$/.test(value);

const CURSOR = /^\d{1,20}\|[A-Za-z0-9_]{5,255}$/;

export const FAILED_EVENT_STATUSES = ["pending", "quarantined", "processed"] as const;
export type FailedEventStatus = (typeof FAILED_EVENT_STATUSES)[number];

export const FAILED_EVENT_TYPES = [
  "checkout.session.completed",
  "checkout.session.async_payment_succeeded",
  "checkout.session.async_payment_failed",
  "customer.subscription.created",
  "customer.subscription.updated",
  "customer.subscription.deleted",
  "invoice.paid",
  "invoice.payment_failed",
  "charge.refunded",
  "charge.dispute.created",
  "charge.dispute.closed",
] as const;

export type FailedEventRow = {
  event_id: string;
  event_type: string;
  status: string;
  attempts: number;
  available_at: string;
  received_at: string;
  error_class: string;
};

export type FailedEventPage = {
  items: FailedEventRow[];
  next_cursor: string | null;
  email_events_available: boolean;
  retry_available: boolean;
};

export function decodeFailedEvents(value: unknown): FailedEventPage | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (
    !Array.isArray(record.items) ||
    record.items.length > 100 ||
    !(record.next_cursor === null || (typeof record.next_cursor === "string" && CURSOR.test(record.next_cursor))) ||
    typeof record.email_events_available !== "boolean" ||
    typeof record.retry_available !== "boolean"
  ) {
    return null;
  }
  const items: FailedEventRow[] = [];
  const ids = new Set<string>();
  for (const raw of record.items) {
    if (!raw || typeof raw !== "object") return null;
    const row = raw as Record<string, unknown>;
    if (
      !isEventId(row.event_id) ||
      ids.has(row.event_id) ||
      typeof row.event_type !== "string" ||
      !(FAILED_EVENT_TYPES as readonly string[]).includes(row.event_type) ||
      typeof row.status !== "string" ||
      !(FAILED_EVENT_STATUSES as readonly string[]).includes(row.status) ||
      !isCount(row.attempts) ||
      typeof row.available_at !== "string" ||
      row.available_at.length > 40 ||
      typeof row.received_at !== "string" ||
      row.received_at.length > 40 ||
      typeof row.error_class !== "string" ||
      row.error_class.length > 80
    ) {
      return null;
    }
    ids.add(row.event_id);
    items.push({
      event_id: row.event_id,
      event_type: row.event_type,
      status: row.status,
      attempts: row.attempts,
      available_at: row.available_at,
      received_at: row.received_at,
      error_class: row.error_class,
    });
  }
  return {
    items,
    next_cursor: record.next_cursor as string | null,
    email_events_available: record.email_events_available,
    retry_available: record.retry_available,
  };
}

export type FailedEventDetail = {
  event_id: string;
  event_type: string;
  status: string;
  attempts: number;
  available_at: string;
  received_at: string;
  event_created: number;
  object_kind: string;
  error_class: string;
  livemode: boolean;
};

export function decodeFailedEventDetail(value: unknown): FailedEventDetail | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const row = value as Record<string, unknown>;
  if (
    !isEventId(row.event_id) ||
    typeof row.event_type !== "string" ||
    !(FAILED_EVENT_TYPES as readonly string[]).includes(row.event_type) ||
    typeof row.status !== "string" ||
    !(FAILED_EVENT_STATUSES as readonly string[]).includes(row.status) ||
    !isCount(row.attempts) ||
    typeof row.available_at !== "string" ||
    row.available_at.length > 40 ||
    typeof row.received_at !== "string" ||
    row.received_at.length > 40 ||
    !isCount(row.event_created) ||
    row.event_created === 0 ||
    typeof row.object_kind !== "string" ||
    row.object_kind.length === 0 ||
    row.object_kind.length > 40 ||
    typeof row.error_class !== "string" ||
    row.error_class.length > 80 ||
    typeof row.livemode !== "boolean"
  ) {
    return null;
  }
  return {
    event_id: row.event_id,
    event_type: row.event_type,
    status: row.status,
    attempts: row.attempts,
    available_at: row.available_at,
    received_at: row.received_at,
    event_created: row.event_created,
    object_kind: row.object_kind,
    error_class: row.error_class,
    livemode: row.livemode,
  };
}

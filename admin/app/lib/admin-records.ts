export const RECORDS = {
  users: { title: "Users", description: "Buyer and seller memberships, current access state and profile names.", columns: ["Membership", "Name", "Role", "Status", "Area", "Joined"], statusIndex: 3, statuses: ["pending", "active", "restricted", "disabled"] },
  requests: { title: "Buyer requests", description: "Requests and their current marketplace state. Exact addresses stay private.", columns: ["Request", "Title", "Buyer membership", "Category", "Status", "Created"], statusIndex: 4, statuses: ["draft", "active", "closed", "expired", "cancelled"] },
  offers: { title: "Offers & deals", description: "Offer state and selected-revision pricing. Item payments remain offline.", columns: ["Offer", "Request", "Seller membership", "Price", "Status", "Updated"], statusIndex: 4, statuses: ["submitted", "selected", "withdrawn", "declined", "completed", "cancelled", "expired"] },
  billing: { title: "Seller billing — TEST", description: "Stripe test subscription records only. These are not live revenue or item payments.", columns: ["Membership", "Plan", "Provider status", "Paid through", "Renewal", "Review"], statusIndex: 2, statuses: ["active", "trialing", "past_due", "canceled", "unpaid", "incomplete", "incomplete_expired", "paused"] },
} as const;
export type RecordResource = keyof typeof RECORDS;
export type RecordPage = { items: { id: string; cells: string[] }[]; next_cursor: string | null };
const uuid = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;
export function decodeRecordPage(value: unknown): RecordPage | null {
  if (!value || typeof value !== "object") return null;
  const page = value as Record<string, unknown>;
  if (!Array.isArray(page.items) || page.items.length > 100 ||
      !(page.next_cursor === null || (typeof page.next_cursor === "string" && uuid.test(page.next_cursor)))) return null;
  const ids = new Set<string>();
  for (const row of page.items) {
    if (!row || typeof row !== "object" || typeof row.id !== "string" || !uuid.test(row.id) || ids.has(row.id) ||
        !Array.isArray(row.cells) || row.cells.length !== 6 || row.cells.some((cell: unknown) => typeof cell !== "string" || cell.length > 2000)) return null;
    ids.add(row.id);
  }
  if (page.next_cursor !== null && (!page.items.length || page.items.at(-1).id !== page.next_cursor)) return null;
  return page as RecordPage;
}
export const OVERVIEW_LABELS = {
  active_memberships: "Active memberships", open_requests: "Open requests",
  submitted_offers: "Submitted offers", listings_in_review: "Listings in review",
  test_subscriptions: "TEST subscriptions",
} as const;
export function decodeOverview(value: unknown): Record<keyof typeof OVERVIEW_LABELS, number> | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  if (Object.keys(OVERVIEW_LABELS).some(key => typeof record[key] !== "number" || !Number.isSafeInteger(record[key]) || (record[key] as number) < 0)) return null;
  return record as Record<keyof typeof OVERVIEW_LABELS, number>;
}

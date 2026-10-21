import { test } from "node:test";
import assert from "node:assert/strict";
import { decodeDeliveryOverview } from "../app/lib/admin-delivery";

const failureId = "82000000-0000-4000-8000-00000000000a";
const userId = "00000000-0000-4000-8000-000000000002";

const valid = {
  pending: 1,
  sending: 0,
  accepted: 1,
  skipped: 0,
  failed: 1,
  failed_last_24h: 1,
  oldest_pending_at: "2026-09-25T10:00:00Z",
  recent_failures: [
    {
      id: failureId,
      kind: "new_offer",
      user_id: userId,
      attempts: 3,
      last_error: "provider_timeout",
      available_at: "2026-09-25T09:00:00Z",
    },
  ],
};

test("delivery decoder accepts bounded queue health", () => {
  const decoded = decodeDeliveryOverview(valid);
  assert.equal(decoded?.failed, 1);
  assert.equal(decoded?.recent_failures.length, 1);
  assert.equal(decoded?.recent_failures[0].kind, "new_offer");
});

test("delivery decoder refuses malformed or unbounded payloads", () => {
  for (const payload of [
    null,
    {},
    { ...valid, pending: -1 },
    { ...valid, failed: "1" },
    { ...valid, oldest_pending_at: 5 },
    { ...valid, recent_failures: [{ ...valid.recent_failures[0], id: "other" }] },
    { ...valid, recent_failures: [{ ...valid.recent_failures[0], user_id: 5 }] },
    { ...valid, recent_failures: [{ ...valid.recent_failures[0], last_error: "x".repeat(201) }] },
    { ...valid, recent_failures: [valid.recent_failures[0], valid.recent_failures[0]] },
    { ...valid, recent_failures: Array.from({ length: 21 }, (_, i) => ({ ...valid.recent_failures[0], id: `82000000-0000-4000-8000-${String(i).padStart(12, "0")}` })) },
  ]) {
    assert.equal(decodeDeliveryOverview(payload), null);
  }
});

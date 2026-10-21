import { test } from "node:test";
import assert from "node:assert/strict";

import { decodeFailedEventDetail, decodeFailedEvents } from "../app/lib/admin-events";

const validRow = {
  event_id: "evt_PendingTwo",
  event_type: "invoice.payment_failed",
  status: "pending",
  attempts: 2,
  available_at: "2026-09-26T11:05:00+00:00",
  received_at: "2026-09-26T11:00:00+00:00",
  error_class: "provider_or_storage_unavailable",
};

const validPage = {
  items: [validRow],
  next_cursor: "1790438454695000|evt_PendingTwo",
  email_events_available: false,
  retry_available: false,
};

test("decodes a bounded failed-event page with honest capability flags", () => {
  const decoded = decodeFailedEvents(validPage);
  assert.ok(decoded);
  assert.equal(decoded.items[0].attempts, 2);
  assert.equal(decoded.email_events_available, false);
  assert.equal(decoded.retry_available, false);
});

test("refuses malformed, duplicated or unbounded event rows", () => {
  assert.equal(
    decodeFailedEvents({ ...validPage, items: [{ ...validRow, event_id: "nope" }] }),
    null,
  );
  assert.equal(
    decodeFailedEvents({ ...validPage, items: [validRow, validRow] }),
    null,
  );
  assert.equal(
    decodeFailedEvents({ ...validPage, items: [{ ...validRow, status: "lost" }] }),
    null,
  );
  assert.equal(
    decodeFailedEvents({ ...validPage, items: [{ ...validRow, event_type: "made.up" }] }),
    null,
  );
  assert.equal(
    decodeFailedEvents({ ...validPage, next_cursor: "not-a-cursor" }),
    null,
  );
  assert.equal(decodeFailedEvents({ ...validPage, email_events_available: "no" }), null);
});

test("detail exposes sanitized metadata only", () => {
  const decoded = decodeFailedEventDetail({
    event_id: validRow.event_id,
    event_type: validRow.event_type,
    status: "quarantined",
    attempts: 10,
    available_at: validRow.available_at,
    received_at: validRow.received_at,
    event_created: 1700000001,
    object_kind: "invoice",
    error_class: "provider_or_storage_unavailable",
    livemode: false,
  });
  assert.ok(decoded);
  assert.equal(decoded.object_kind, "invoice");
  assert.equal(decoded.livemode, false);
  assert.doesNotMatch(JSON.stringify(decoded), /cus_|in_Private|card|token/);
  assert.equal(
    decodeFailedEventDetail({
      event_id: validRow.event_id,
      event_type: validRow.event_type,
      status: "pending",
      attempts: 0,
      available_at: validRow.available_at,
      received_at: validRow.received_at,
      event_created: 0,
      object_kind: "invoice",
      error_class: "",
      livemode: false,
    }),
    null,
  );
});

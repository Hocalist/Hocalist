import { test } from "node:test";
import assert from "node:assert/strict";

import { decodeAuditFeed, isAuditSource } from "../app/lib/admin-audit";

const row = {
  id: "d48628b40f9e388762db1cf07d57d9ba",
  occurred_at: "2026-09-26T12:00:00+00:00",
  source: "trust",
  action: "appeal.decide",
  actor: "00000000-0000-4000-8000-00000000000e",
  target: "30000000-0000-4000-8000-0000000000b2",
  summary: "upheld",
  detail: "Appeal upheld reason.",
};

const validFeed = {
  items: [row],
  next_cursor: "1790438454695000|d48628b40f9e388762db1cf07d57d9ba",
  sources: ["moderation", "configuration", "commercial", "support", "trust", "calls", "withdrawals"],
};

test("decodes the audit feed with fixed sources", () => {
  const decoded = decodeAuditFeed(validFeed);
  assert.ok(decoded);
  assert.equal(decoded.items[0].detail, "Appeal upheld reason.");
  assert.equal(decoded.sources.length, 7);
});

test("an empty filtered page is valid and no cursor is trusted loosely", () => {
  const decoded = decodeAuditFeed({ items: [], next_cursor: null, sources: validFeed.sources });
  assert.ok(decoded);
  assert.deepEqual(decoded.items, []);
  assert.equal(decodeAuditFeed({ ...validFeed, next_cursor: "bad" }), null);
  assert.equal(decodeAuditFeed({ ...validFeed, items: [], next_cursor: validFeed.next_cursor }), null);
});

test("refuses unknown sources, malformed ids and oversized detail", () => {
  assert.equal(
    decodeAuditFeed({ ...validFeed, items: [{ ...row, source: "secrets" }] }),
    null,
  );
  assert.equal(
    decodeAuditFeed({ ...validFeed, items: [{ ...row, id: "not-a-hash" }] }),
    null,
  );
  assert.equal(
    decodeAuditFeed({ ...validFeed, items: [{ ...row, detail: "x".repeat(501) }] }),
    null,
  );
  assert.equal(
    decodeAuditFeed({ ...validFeed, sources: ["moderation", "unknown"] }),
    null,
  );
  assert.equal(isAuditSource("support"), true);
  assert.equal(isAuditSource("users"), false);
});

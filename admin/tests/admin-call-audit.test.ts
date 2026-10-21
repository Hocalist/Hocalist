import { test } from "node:test";
import assert from "node:assert/strict";
import { decodeCallAuditHistory } from "../app/lib/admin-call-audit";

const admin = "00000000-0000-4000-8000-000000000001";

const entry = {
  revision: 2,
  enabled: true,
  changed_by: admin,
  changed_at: "2026-09-25T10:00:00Z",
};

test("call audit decoder accepts a bounded history", () => {
  const decoded = decodeCallAuditHistory({
    current_enabled: true,
    items: [entry],
  });
  assert.equal(decoded?.current_enabled, true);
  assert.equal(decoded?.items[0].changed_by, admin);
});

test("call audit decoder refuses malformed or duplicate revisions", () => {
  for (const payload of [
    null,
    {},
    { current_enabled: "yes", items: [] },
    { current_enabled: false, items: [{ ...entry, revision: 0 }] },
    { current_enabled: false, items: [{ ...entry, changed_by: "other" }] },
    { current_enabled: false, items: [{ ...entry, enabled: "on" }] },
    { current_enabled: false, items: [entry, entry] },
    { current_enabled: false, items: Array.from({ length: 21 }, (_, i) => ({ ...entry, revision: i + 1 })) },
  ]) {
    assert.equal(decodeCallAuditHistory(payload), null, JSON.stringify(payload));
  }
});

import { test } from "node:test";
import assert from "node:assert/strict";

import { decodeEvidenceResponse } from "../app/lib/admin-evidence-client";

test("evidence responses accept only HTTPS URLs", () => {
  const decoded = decodeEvidenceResponse({
    ok: true,
    url: "https://media.hocalist.com/evidence/a.png?sig=1",
    expires_at: "2026-09-26T13:00:00+00:00",
  });
  assert.ok(decoded);
  assert.equal(decoded.ok, true);
  assert.equal(
    decodeEvidenceResponse({ ok: true, url: "http://media.hocalist.com/a.png", expires_at: null }),
    null,
  );
  assert.equal(
    decodeEvidenceResponse({ ok: true, url: "javascript:alert(1)", expires_at: null }),
    null,
  );
  assert.equal(decodeEvidenceResponse({ ok: true, url: "x".repeat(2100), expires_at: null }), null);
});

test("unavailable evidence keeps its explicit state", () => {
  const decoded = decodeEvidenceResponse({
    ok: false,
    state: "unavailable",
    reason: "accounts_evidence_gateway_not_integrated",
    message: "Evidence preview needs the accounts media gateway.",
  });
  assert.ok(decoded);
  assert.equal(decoded.ok, false);
  assert.equal(decoded.ok === false ? decoded.state : null, "unavailable");
  assert.equal(decodeEvidenceResponse({ ok: false }), null);
  assert.equal(decodeEvidenceResponse(null), null);
});

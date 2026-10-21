import { test } from "node:test";
import assert from "node:assert/strict";
import {
  decodeReviewQueue,
  decodeWithdrawalQueue,
  mergeReviewSection,
  trustErrorMessage,
} from "../app/lib/admin-trust";

const userId = "00000000-0000-4000-8000-000000000002";
const submissionId = "90000000-0000-4000-8000-000000000001";
const mediaId = "90000000-0000-4000-8000-00000000000a";
const caseId = "93000000-0000-4000-8000-000000000001";
const restrictionId = "91000000-0000-4000-8000-000000000001";
const appealId = "92000000-0000-4000-8000-000000000001";
const withdrawalId = "94000000-0000-4000-8000-000000000001";

const validTrust = {
  verifications: {
    items: [
      {
        id: submissionId,
        user_id: userId,
        kind: "business",
        note: "Licence attached",
        evidence_media_ids: [mediaId],
        evidence_count: 1,
        status: "pending",
        revision: 3,
        created_at: "2026-09-26T00:00:00+00:00",
        decision_reason: null,
      },
    ],
    next_cursor: "1790438454695000|90000000-0000-4000-8000-000000000001",
  },
  health_reviews: {
    items: [
      {
        case_id: caseId,
        reason_code: "safety",
        status: "open",
        body: "No-show report",
        created_at: "2026-09-26T00:00:00+00:00",
        decision: null,
        decision_reason: null,
      },
    ],
    next_cursor: null,
  },
  restrictions: {
    items: [
      {
        id: restrictionId,
        user_id: userId,
        scope: "seller",
        reason: "Repeated no-shows",
        source: "health",
        status: "active",
        revision: 2,
        created_at: "2026-09-26T00:00:00+00:00",
        appeal_id: appealId,
        appeal_status: "submitted",
        appeal_revision: 1,
      },
    ],
    next_cursor: null,
  },
  single_report_penalty: false,
};

test("decodes a valid review queue with carried revisions and cursors", () => {
  const decoded = decodeReviewQueue(validTrust);
  assert.ok(decoded);
  assert.equal(decoded.verifications.items[0].revision, 3);
  assert.equal(decoded.verifications.next_cursor, validTrust.verifications.next_cursor);
  assert.deepEqual(decoded.verifications.items[0].evidence_media_ids, [mediaId]);
  assert.equal(decoded.health_reviews.items[0].decision, null);
  assert.equal(decoded.restrictions.items[0].revision, 2);
  assert.equal(decoded.restrictions.items[0].appeal_revision, 1);
  assert.equal(decoded.single_report_penalty, false);
});

test("rejects malformed review rows instead of defaulting", () => {
  assert.equal(
    decodeReviewQueue({
      ...validTrust,
      verifications: { ...validTrust.verifications, items: [{ ...validTrust.verifications.items[0], id: "not-a-uuid" }] },
    }),
    null,
  );
  // A count that disagrees with the bounded reference list is refused.
  assert.equal(
    decodeReviewQueue({
      ...validTrust,
      verifications: {
        ...validTrust.verifications,
        items: [{ ...validTrust.verifications.items[0], evidence_count: 4 }],
      },
    }),
    null,
  );
  // A media reference must be an id, never a URL or storage path.
  assert.equal(
    decodeReviewQueue({
      ...validTrust,
      verifications: {
        ...validTrust.verifications,
        items: [
          { ...validTrust.verifications.items[0], evidence_media_ids: ["https://bucket/x.png"] },
        ],
      },
    }),
    null,
  );
  assert.equal(
    decodeReviewQueue({
      ...validTrust,
      restrictions: {
        ...validTrust.restrictions,
        items: [{ ...validTrust.restrictions.items[0], reason: undefined }],
      },
    }),
    null,
  );
  assert.equal(
    decodeReviewQueue({
      ...validTrust,
      restrictions: {
        ...validTrust.restrictions,
        items: [{ ...validTrust.restrictions.items[0], appeal_revision: null }],
      },
    }),
    null,
  );
  // A cursor is a keyset token, not arbitrary text.
  assert.equal(
    decodeReviewQueue({
      ...validTrust,
      verifications: { ...validTrust.verifications, next_cursor: "not-a-cursor" },
    }),
    null,
  );
  assert.equal(decodeReviewQueue({ verifications: { items: [] } }), null);
});

test("trust failures map to safe reviewer messages", () => {
  assert.match(trustErrorMessage("revision_conflict"), /Refresh/);
  assert.match(trustErrorMessage("idempotency_conflict"), /decision key/);
  assert.match(trustErrorMessage("anything", "forbidden"), /Administrator/);
  assert.doesNotMatch(trustErrorMessage("invalid_decision"), /invalid_/);
});

test("load-more merges one section without duplicates and advances only its cursor", () => {
  const previous = decodeReviewQueue(validTrust);
  assert.ok(previous);
  const secondVerification = {
    ...validTrust.verifications.items[0],
    id: "90000000-0000-4000-8000-000000000002",
  };
  const incoming = decodeReviewQueue({
    ...validTrust,
    verifications: {
      items: [validTrust.verifications.items[0], secondVerification],
      next_cursor: null,
    },
    health_reviews: {
      items: [
        { ...validTrust.health_reviews.items[0], case_id: "93000000-0000-4000-8000-000000000002" },
      ],
      next_cursor: "1790438454695000|93000000-0000-4000-8000-000000000002",
    },
  });
  assert.ok(incoming);
  const merged = mergeReviewSection(previous, incoming, "verifications");
  // The already-shown row is not duplicated; the new one is appended.
  assert.deepEqual(
    merged.verifications.items.map((row) => row.id),
    [validTrust.verifications.items[0].id, secondVerification.id],
  );
  assert.equal(merged.verifications.next_cursor, null);
  // Other sections are untouched by a section-scoped load-more.
  assert.equal(merged.health_reviews.items.length, 1);
  assert.equal(merged.health_reviews.next_cursor, null);
  assert.equal(merged.restrictions.items.length, 1);
});

const validWithdrawals = {
  items: [
    {
      id: withdrawalId,
      user_id: userId,
      display_name: "Buyer A",
      amount_minor: 3000,
      fee_minor: 250,
      net_minor: 2750,
      status: "processing",
      provider: null,
      provider_reference: null,
      failure_reason: null,
      created_at: "2026-09-26T00:00:00+00:00",
      updated_at: "2026-09-26T00:00:00+00:00",
    },
  ],
  next_cursor: null,
  processing_minor: 3000,
};

test("decodes a valid withdrawal queue", () => {
  const decoded = decodeWithdrawalQueue(validWithdrawals);
  assert.ok(decoded);
  assert.equal(decoded.items[0].net_minor, 2750);
  assert.equal(decoded.processing_minor, 3000);
});

test("rejects an invalid withdrawal queue", () => {
  assert.equal(
    decodeWithdrawalQueue({
      ...validWithdrawals,
      items: [{ ...validWithdrawals.items[0], net_minor: -1 }],
    }),
    null,
  );
  assert.equal(decodeWithdrawalQueue({ items: [], processing_minor: -1 }), null);
});

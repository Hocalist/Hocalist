import { test } from "node:test";
import assert from "node:assert/strict";
import {
  decodeCreditDetail,
  decodeCreditSummary,
  decodeRewardSummary,
  formatHc,
  formatUsd,
} from "../app/lib/admin-ledger";

const seller = "00000000-0000-4000-8000-000000000003";
const buyer = "00000000-0000-4000-8000-000000000002";

const creditRow = {
  user_id: seller,
  batch_count: 2,
  original_minor: 6000,
  remaining_minor: 5550,
  reserved_minor: 375,
  available_minor: 5175,
  spent_percent: 8,
  target_count: 2,
  won_count: 1,
  released_count: 1,
  last_deposit_at: "2026-09-21T10:00:00Z",
};

const rewardRow = {
  buyer_user_id: buyer,
  reward_count: 2,
  total_minor: 180,
  last_reward_at: null,
};

test("credit summary decoder accepts bounded aggregate pages", () => {
  assert.deepEqual(decodeCreditSummary({ items: [], next_cursor: null }), {
    items: [],
    next_cursor: null,
  });
  const page = decodeCreditSummary({ items: [creditRow], next_cursor: seller });
  assert.equal(page?.items[0].available_minor, 5175);
  assert.equal(page?.items[0].spent_percent, 8);
});

test("credit summary decoder refuses impossible or malformed aggregates", () => {
  for (const payload of [
    null,
    {},
    { items: [{ ...creditRow, remaining_minor: 9000 }], next_cursor: null },
    { items: [{ ...creditRow, reserved_minor: 9999 }], next_cursor: null },
    { items: [{ ...creditRow, spent_percent: 101 }], next_cursor: null },
    { items: [{ ...creditRow, user_id: "other" }], next_cursor: null },
    { items: [creditRow, creditRow], next_cursor: null },
    { items: [creditRow], next_cursor: "invalid" },
    { items: [], next_cursor: seller },
  ]) {
    assert.equal(decodeCreditSummary(payload), null);
  }
});

test("reward summary decoder keeps the buyer ledger separate", () => {
  const page = decodeRewardSummary({ items: [rewardRow], next_cursor: null });
  assert.equal(page?.items[0].total_minor, 180);
  for (const payload of [
    null,
    { items: [{ ...rewardRow, total_minor: -1 }], next_cursor: null },
    { items: [{ ...rewardRow, reward_count: 1.5 }], next_cursor: null },
    { items: [{ ...rewardRow, buyer_user_id: 5 }], next_cursor: null },
  ]) {
    assert.equal(decodeRewardSummary(payload), null);
  }
});

test("ledger amounts format without implying a target count", () => {
  assert.equal(formatHc(5175), "51.75 HC");
  assert.equal(formatUsd(180), "$1.80");
});

const batch = {
  id: "70000000-0000-4000-8000-00000000000a",
  original_minor: 2000,
  balance_minor: 1550,
  reserved_minor: 375,
  initial_fee_minor: 155,
  winning_total_minor: 375,
  rate_version: "elite-v1",
  created_at: "2026-09-21T10:00:00Z",
};

const target = {
  id: "71000000-0000-4000-8000-00000000000a",
  request_id: "73000000-0000-4000-8000-00000000000a",
  batch_id: batch.id,
  status: "won",
  charged_minor: 375,
  reserved_minor: 0,
  week_start: "2026-09-21",
  created_at: "2026-09-21T10:05:00Z",
};

test("credit detail decoder accepts one seller's bounded drill-down", () => {
  const decoded = decodeCreditDetail({
    user_id: seller,
    available_minor: 5175,
    batches: [batch],
    targets: [target],
  });
  assert.equal(decoded?.batches.length, 1);
  assert.equal(decoded?.targets[0].status, "won");
  assert.equal(decoded?.user_id, seller);
});

test("credit detail decoder refuses impossible accounting or unknown status", () => {
  for (const payload of [
    null,
    { user_id: "other", available_minor: 1, batches: [], targets: [] },
    { user_id: seller, available_minor: -1, batches: [], targets: [] },
    {
      user_id: seller,
      available_minor: 1,
      batches: [{ ...batch, balance_minor: 9000 }],
      targets: [],
    },
    {
      user_id: seller,
      available_minor: 1,
      batches: [{ ...batch, winning_total_minor: 100 }],
      targets: [],
    },
    {
      user_id: seller,
      available_minor: 1,
      batches: [],
      targets: [{ ...target, status: "captured" }],
    },
    {
      user_id: seller,
      available_minor: 1,
      batches: [],
      targets: [{ ...target, batch_id: 5 }],
    },
  ]) {
    assert.equal(decodeCreditDetail(payload), null, JSON.stringify(payload));
  }
});

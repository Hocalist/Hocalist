import { test } from "node:test";
import assert from "node:assert/strict";

import {
  beginDepositOptionEdit,
  beginRewardPolicyDraft,
  commercialErrorMessage,
  decodeCommercialConfig,
  depositOptionStale,
  newDepositOptionDraft,
  parseMinorAmount,
  rebaseDepositOptionDraft,
  rebaseRewardPolicyDraft,
  rewardPolicyStale,
  validateDepositOptionDraft,
  validateRewardPolicyDraft,
} from "../app/lib/admin-commercial";

const OPTION_ID = "70000000-0000-4000-8000-00000000000a";
test('standard rate configuration is complete, unique and compatible with card minimums',()=>{
 const rows=['free','pro','elite'].map(plan_code=>({plan_code,initial_minor:200,winning_minor:500,revision:1}));
 const base={deposit_options:[],reward_policy:null,paygo_plan_rates:rows};
 assert.equal(decodeCommercialConfig(base)?.paygo_plan_rates?.length,3);
 assert.equal(decodeCommercialConfig({...base,paygo_plan_rates:[rows[0],rows[0],rows[2]]}),null);
 assert.equal(decodeCommercialConfig({...base,paygo_plan_rates:rows.map(r=>({...r,winning_minor:220}))}),null);
 assert.equal(decodeCommercialConfig({...base,paygo_plan_rates:rows.map(r=>({...r,initial_minor:20}))}),null);
});

test("plan rates reject duplicate or incomplete pack matrices", () => {
  const rows = ["free", "pro", "elite"].flatMap(plan_code => [2000,4000].map(amount_minor => ({
    plan_code, amount_minor, initial_fee_minor:150, winning_total_minor:300, rate_version:"test", revision:1,
  })));
  const base={deposit_options:[],reward_policy:null,plan_deposit_rates:rows};
  assert.equal(decodeCommercialConfig(base)?.plan_deposit_rates?.length,6);
  assert.equal(decodeCommercialConfig({...base,plan_deposit_rates:rows.slice(1)}),null);
  assert.equal(decodeCommercialConfig({...base,plan_deposit_rates:[...rows.slice(1),rows[1]]}),null);
});

const validConfig = {
  deposit_options: [
    {
      id: OPTION_ID,
      amount_minor: 2000,
      initial_fee_minor: 155,
      winning_total_minor: 375,
      rate_version: "elite-v1",
      active: true,
      sort_order: 0,
      revision: 2,
      updated_at: "2026-09-26T00:00:00+00:00",
    },
  ],
  reward_policy: {
    normal_minor: 15,
    late_minor: 30,
    late_window_hours: 12,
    rule_version: "reward-v1",
    revision: 3,
    updated_at: "2026-09-26T00:00:00+00:00",
  },
};

test("decodes configured options and policy with revisions", () => {
  const decoded = decodeCommercialConfig(validConfig);
  assert.ok(decoded);
  assert.equal(decoded.deposit_options[0].revision, 2);
  assert.equal(decoded.reward_policy?.revision, 3);
  assert.equal(decoded.reward_policy?.late_window_hours, 12);
});

test("an empty catalogue is a valid explicit state, not a default", () => {
  const decoded = decodeCommercialConfig({ deposit_options: [], reward_policy: null });
  assert.ok(decoded);
  assert.deepEqual(decoded.deposit_options, []);
  assert.equal(decoded.reward_policy, null);
});

test("refuses impossible or unbounded commercial rows", () => {
  assert.equal(
    decodeCommercialConfig({
      ...validConfig,
      deposit_options: [{ ...validConfig.deposit_options[0], winning_total_minor: 9999 }],
    }),
    null,
  );
  assert.equal(
    decodeCommercialConfig({
      ...validConfig,
      deposit_options: [{ ...validConfig.deposit_options[0], winning_total_minor: 100 }],
    }),
    null,
  );
  assert.equal(
    decodeCommercialConfig({
      ...validConfig,
      deposit_options: [{ ...validConfig.deposit_options[0], rate_version: "" }],
    }),
    null,
  );
  assert.equal(
    decodeCommercialConfig({
      ...validConfig,
      reward_policy: { ...validConfig.reward_policy, late_minor: 10 },
    }),
    null,
  );
  assert.equal(
    decodeCommercialConfig({
      ...validConfig,
      reward_policy: { ...validConfig.reward_policy, late_window_hours: 200 },
    }),
    null,
  );
  assert.equal(decodeCommercialConfig(null), null);
});

test("amounts parse to minor units without float drift", () => {
  assert.equal(parseMinorAmount("20"), 2000);
  assert.equal(parseMinorAmount("20.00"), 2000);
  assert.equal(parseMinorAmount("1.55"), 155);
  assert.equal(parseMinorAmount("0.15"), 15);
  assert.equal(parseMinorAmount("3.7"), 370);
  assert.equal(parseMinorAmount("-1"), null);
  assert.equal(parseMinorAmount("1.555"), null);
  assert.equal(parseMinorAmount("abc"), null);
  assert.equal(parseMinorAmount(""), null);
  const huge = "9".repeat(14);
  assert.equal(parseMinorAmount(huge), null);
});

test("a new deposit draft sends no revision", () => {
  const created = validateDepositOptionDraft({
    ...newDepositOptionDraft(),
    amount: "20",
    initialFee: "1.55",
    winningTotal: "3.75",
    rateVersion: "elite-v1",
  });
  assert.equal(created.ok, true);
  assert.deepEqual(created.ok ? created.value : null, {
    amount_minor: 2000,
    initial_fee_minor: 155,
    winning_total_minor: 375,
    rate_version: "elite-v1",
    active: true,
    sort_order: 0,
  });
});

test("an edited deposit draft carries the revision captured at edit start", () => {
  const decoded = decodeCommercialConfig(validConfig);
  assert.ok(decoded);
  const draft = beginDepositOptionEdit(decoded.deposit_options[0]);
  assert.equal(draft.revision, 2);
  const saved = validateDepositOptionDraft({ ...draft, winningTotal: "3.50" });
  assert.equal(saved.ok, true);
  assert.equal(saved.ok ? saved.value.expected_revision : null, 2);
  // An id without a captured revision is refused rather than guessed.
  assert.equal(validateDepositOptionDraft({ ...draft, revision: null }).ok, false);
});

test("deposit draft validation still rejects impossible values", () => {
  const decoded = decodeCommercialConfig(validConfig);
  assert.ok(decoded);
  const draft = beginDepositOptionEdit(decoded.deposit_options[0]);
  assert.equal(validateDepositOptionDraft({ ...draft, winningTotal: "1.00" }).ok, false);
  assert.equal(validateDepositOptionDraft({ ...draft, winningTotal: "25" }).ok, false);
  assert.equal(validateDepositOptionDraft({ ...draft, amount: "0" }).ok, false);
  assert.equal(validateDepositOptionDraft({ ...draft, rateVersion: "  " }).ok, false);
  assert.equal(validateDepositOptionDraft({ ...draft, sortOrder: "-1" }).ok, false);
});

test("a background reload marks the draft stale and rebase adopts the new revision", () => {
  const decoded = decodeCommercialConfig(validConfig);
  assert.ok(decoded);
  const draft = beginDepositOptionEdit(decoded.deposit_options[0]);
  assert.equal(depositOptionStale(draft, decoded), false);

  const movedOn = decodeCommercialConfig({
    ...validConfig,
    deposit_options: [{ ...validConfig.deposit_options[0], revision: 5, amount_minor: 4000 }],
  });
  assert.ok(movedOn);
  assert.equal(depositOptionStale(draft, movedOn), true);

  const rebased = rebaseDepositOptionDraft(draft, movedOn);
  assert.ok(rebased);
  assert.equal(rebased.revision, 5);
  // The typed values are preserved; only the revision is adopted explicitly.
  assert.equal(rebased.amount, draft.amount);
  const saved = validateDepositOptionDraft(rebased);
  assert.equal(saved.ok ? saved.value.expected_revision : null, 5);

  // A removed row is stale and offers no silent rebase.
  const removed = decodeCommercialConfig({ deposit_options: [], reward_policy: null });
  assert.ok(removed);
  assert.equal(depositOptionStale(draft, removed), true);
  assert.equal(rebaseDepositOptionDraft(draft, removed), null);
});

test("a reward draft captures its revision and detects background changes", () => {
  const decoded = decodeCommercialConfig(validConfig);
  assert.ok(decoded);
  const draft = beginRewardPolicyDraft(decoded.reward_policy);
  assert.equal(draft.revision, 3);
  assert.equal(rewardPolicyStale(draft, decoded), false);

  const movedOn = decodeCommercialConfig({
    ...validConfig,
    reward_policy: { ...validConfig.reward_policy, revision: 4, normal_minor: 20 },
  });
  assert.ok(movedOn);
  assert.equal(rewardPolicyStale(draft, movedOn), true);

  const rebased = rebaseRewardPolicyDraft(draft, movedOn);
  assert.equal(rebased.revision, 4);
  assert.equal(rebased.normal, draft.normal);
  const saved = validateRewardPolicyDraft(rebased);
  assert.equal(saved.ok ? saved.value.expected_revision : null, 4);

  // Creating an absent policy sends no revision; an unconfigured policy after
  // a configured draft is stale.
  const created = beginRewardPolicyDraft(null);
  assert.equal(created.revision, null);
  assert.equal(rewardPolicyStale(created, decoded), true);
  const unconfigured = decodeCommercialConfig({ deposit_options: [], reward_policy: null });
  assert.ok(unconfigured);
  assert.equal(rewardPolicyStale(created, unconfigured), false);
});

test("reward policy drafts carry an optional window", () => {
  const policy = { ...beginRewardPolicyDraft(null), normal: "0.15", late: "0.30", ruleVersion: "reward-v1" };
  const created = validateRewardPolicyDraft(policy);
  assert.equal(created.ok, true);
  assert.equal(created.ok ? created.value.late_window_hours : "x", null);
  assert.equal(validateRewardPolicyDraft({ ...policy, late: "0.10" }).ok, false);
  assert.equal(validateRewardPolicyDraft({ ...policy, lateWindowHours: "0" }).ok, false);
  assert.equal(validateRewardPolicyDraft({ ...policy, lateWindowHours: "169" }).ok, false);
  const updated = validateRewardPolicyDraft({ ...policy, revision: 5, lateWindowHours: "24" });
  assert.equal(updated.ok ? updated.value.expected_revision : null, 5);
});

test("commercial failures map to safe administrator messages", () => {
  assert.match(
    commercialErrorMessage({ ok: false, state: "error", message: "revision_conflict" }),
    /Refresh/,
  );
  assert.match(
    commercialErrorMessage({ ok: false, state: "error", message: "idempotency_conflict" }),
    /operation key/,
  );
  assert.match(
    commercialErrorMessage({ ok: false, state: "forbidden", message: "42501" }),
    /Administrator/,
  );
  assert.doesNotMatch(
    commercialErrorMessage({ ok: false, state: "error", message: "invalid_option" }),
    /invalid_option/,
  );
});

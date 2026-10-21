// Decoders and validated drafts for the administrator commercial
// configuration. Pure functions only: the reviewed `credit_admin_command`
// remains the single write path, and this module never invents a rate.
import type { AdminRpcResponse } from "./admin-client";

const uuid = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

const isMinor = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0;

const isCount = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0;

const isText = (value: unknown, max: number): value is string =>
  typeof value === "string" && value.length > 0 && value.length <= max;

export type DepositOptionRow = {
  id: string;
  amount_minor: number;
  initial_fee_minor: number;
  winning_total_minor: number;
  rate_version: string;
  active: boolean;
  sort_order: number;
  revision: number;
  updated_at: string;
};

export type RewardPolicy = {
  normal_minor: number;
  late_minor: number;
  late_window_hours: number | null;
  rule_version: string;
  revision: number;
  updated_at: string;
};

export type CommercialConfig = {
  deposit_options: DepositOptionRow[];
  reward_policy: RewardPolicy | null;
};

export function decodeCommercialConfig(value: unknown): CommercialConfig | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (!Array.isArray(record.deposit_options) || record.deposit_options.length > 50) {
    return null;
  }
  const options: DepositOptionRow[] = [];
  const ids = new Set<string>();
  for (const raw of record.deposit_options) {
    if (!raw || typeof raw !== "object") return null;
    const row = raw as Record<string, unknown>;
    if (
      typeof row.id !== "string" ||
      !uuid.test(row.id) ||
      ids.has(row.id) ||
      !isMinor(row.amount_minor) ||
      row.amount_minor === 0 ||
      !isMinor(row.initial_fee_minor) ||
      !isMinor(row.winning_total_minor) ||
      row.winning_total_minor < row.initial_fee_minor ||
      row.winning_total_minor > row.amount_minor ||
      !isText(row.rate_version, 100) ||
      typeof row.active !== "boolean" ||
      !isCount(row.sort_order) ||
      !isCount(row.revision) ||
      row.revision < 1 ||
      typeof row.updated_at !== "string" ||
      row.updated_at.length > 40
    ) {
      return null;
    }
    ids.add(row.id);
    options.push({
      id: row.id,
      amount_minor: row.amount_minor,
      initial_fee_minor: row.initial_fee_minor,
      winning_total_minor: row.winning_total_minor,
      rate_version: row.rate_version,
      active: row.active,
      sort_order: row.sort_order,
      revision: row.revision,
      updated_at: row.updated_at,
    });
  }
  let policy: RewardPolicy | null = null;
  if (record.reward_policy !== null) {
    if (!record.reward_policy || typeof record.reward_policy !== "object") return null;
    const row = record.reward_policy as Record<string, unknown>;
    const hours = row.late_window_hours;
    if (
      !isMinor(row.normal_minor) ||
      row.normal_minor === 0 ||
      !isMinor(row.late_minor) ||
      row.late_minor < row.normal_minor ||
      (hours !== null && (!isCount(hours) || hours < 1 || hours > 168)) ||
      !isText(row.rule_version, 100) ||
      !isCount(row.revision) ||
      row.revision < 1 ||
      typeof row.updated_at !== "string" ||
      row.updated_at.length > 40
    ) {
      return null;
    }
    policy = {
      normal_minor: row.normal_minor,
      late_minor: row.late_minor,
      late_window_hours: hours,
      rule_version: row.rule_version,
      revision: row.revision,
      updated_at: row.updated_at,
    };
  }
  return { deposit_options: options, reward_policy: policy };
}

// Structural input guard, not a business limit: rejects sizes that would
// overflow minor-unit arithmetic. No fee table is inferred here.
export const MAX_MINOR = 1_000_000_000_000;
const AMOUNT = /^(\d{1,13})(?:[.](\d{1,2}))?$/;

export function parseMinorAmount(raw: string): number | null {
  const trimmed = raw.trim();
  const match = AMOUNT.exec(trimmed);
  if (!match) return null;
  const whole = Number(match[1]);
  const fraction = (match[2] ?? "").padEnd(2, "0");
  const minor = whole * 100 + Number(fraction);
  if (!Number.isSafeInteger(minor) || minor > MAX_MINOR) return null;
  return minor;
}

export type DepositOptionDraft = {
  id: string | null;
  revision: number | null;
  amount: string;
  initialFee: string;
  winningTotal: string;
  rateVersion: string;
  active: boolean;
  sortOrder: string;
};

export type DepositOptionInput = {
  id?: string;
  amount_minor: number;
  initial_fee_minor: number;
  winning_total_minor: number;
  rate_version: string;
  active: boolean;
  sort_order: number;
  expected_revision?: number;
};

export type Validation<T> = { ok: true; value: T } | { ok: false; message: string };

export function formatMinorInput(minor: number): string {
  return `${Math.floor(minor / 100)}.${String(minor % 100).padStart(2, "0")}`;
}

export function newDepositOptionDraft(): DepositOptionDraft {
  return {
    id: null,
    revision: null,
    amount: "",
    initialFee: "",
    winningTotal: "",
    rateVersion: "",
    active: true,
    sortOrder: "0",
  };
}

export function beginDepositOptionEdit(option: DepositOptionRow): DepositOptionDraft {
  return {
    id: option.id,
    revision: option.revision,
    amount: formatMinorInput(option.amount_minor),
    initialFee: formatMinorInput(option.initial_fee_minor),
    winningTotal: formatMinorInput(option.winning_total_minor),
    rateVersion: option.rate_version,
    active: option.active,
    sortOrder: String(option.sort_order),
  };
}

/** The exact revision captured when editing began; a reload never upgrades it. */
export function validateDepositOptionDraft(
  draft: DepositOptionDraft,
): Validation<DepositOptionInput> {
  const amount = parseMinorAmount(draft.amount);
  if (amount === null || amount === 0) {
    return { ok: false, message: "Enter the deposit amount as a positive number with up to two decimals." };
  }
  const initial = parseMinorAmount(draft.initialFee);
  if (initial === null) {
    return { ok: false, message: "Enter the initial fee as a number with up to two decimals." };
  }
  const winning = parseMinorAmount(draft.winningTotal);
  if (winning === null) {
    return { ok: false, message: "Enter the winning total as a number with up to two decimals." };
  }
  if (winning < initial) {
    return { ok: false, message: "The winning total cannot be smaller than the initial fee." };
  }
  if (winning > amount) {
    return { ok: false, message: "The winning total cannot exceed the deposit amount." };
  }
  const rateVersion = draft.rateVersion.trim();
  if (rateVersion.length === 0 || rateVersion.length > 100) {
    return { ok: false, message: "A rate version label of 1 to 100 characters is required." };
  }
  const sortOrder = Number(draft.sortOrder.trim());
  if (!Number.isSafeInteger(sortOrder) || sortOrder < 0 || sortOrder > 100000) {
    return { ok: false, message: "Sort order must be a whole number between 0 and 100000." };
  }
  if (draft.id !== null && draft.revision === null) {
    return {
      ok: false,
      message: "This entry has no captured revision. Refresh and reopen it before editing.",
    };
  }
  return {
    ok: true,
    value: {
      ...(draft.id !== null ? { id: draft.id } : {}),
      amount_minor: amount,
      initial_fee_minor: initial,
      winning_total_minor: winning,
      rate_version: rateVersion,
      active: draft.active,
      sort_order: sortOrder,
      ...(draft.revision !== null ? { expected_revision: draft.revision } : {}),
    },
  };
}

/** True when the server row moved on after this draft was opened. */
export function depositOptionStale(
  draft: DepositOptionDraft,
  config: CommercialConfig,
): boolean {
  if (draft.id === null || draft.revision === null) return false;
  const current = config.deposit_options.find((option) => option.id === draft.id);
  return current === undefined || current.revision !== draft.revision;
}

/** Rebase keeps the typed values but adopts the current server revision. */
export function rebaseDepositOptionDraft(
  draft: DepositOptionDraft,
  config: CommercialConfig,
): DepositOptionDraft | null {
  if (draft.id === null) return draft;
  const current = config.deposit_options.find((option) => option.id === draft.id);
  if (!current) return null;
  return { ...draft, revision: current.revision };
}

export type RewardPolicyDraft = {
  revision: number | null;
  normal: string;
  late: string;
  lateWindowHours: string;
  ruleVersion: string;
};

export type RewardPolicyInput = {
  normal_minor: number;
  late_minor: number;
  late_window_hours: number | null;
  rule_version: string;
  expected_revision?: number;
};

export function beginRewardPolicyDraft(policy: RewardPolicy | null): RewardPolicyDraft {
  return {
    revision: policy?.revision ?? null,
    normal: policy ? formatMinorInput(policy.normal_minor) : "",
    late: policy ? formatMinorInput(policy.late_minor) : "",
    lateWindowHours: policy?.late_window_hours != null ? String(policy.late_window_hours) : "",
    ruleVersion: policy?.rule_version ?? "",
  };
}

export function rewardPolicyStale(
  draft: RewardPolicyDraft,
  config: CommercialConfig,
): boolean {
  const current = config.reward_policy;
  if (draft.revision === null) return current !== null;
  return current === null || current.revision !== draft.revision;
}

export function rebaseRewardPolicyDraft(
  draft: RewardPolicyDraft,
  config: CommercialConfig,
): RewardPolicyDraft {
  return { ...draft, revision: config.reward_policy?.revision ?? null };
}

export function validateRewardPolicyDraft(
  draft: RewardPolicyDraft,
): Validation<RewardPolicyInput> {
  const normal = parseMinorAmount(draft.normal);
  if (normal === null || normal === 0) {
    return { ok: false, message: "Enter the normal reward as a positive number with up to two decimals." };
  }
  const late = parseMinorAmount(draft.late);
  if (late === null) {
    return { ok: false, message: "Enter the late-window reward as a number with up to two decimals." };
  }
  if (late < normal) {
    return { ok: false, message: "The late-window reward cannot be smaller than the normal reward." };
  }
  let lateWindow: number | null = null;
  const hours = draft.lateWindowHours.trim();
  if (hours.length > 0) {
    lateWindow = Number(hours);
    if (!Number.isSafeInteger(lateWindow) || lateWindow < 1 || lateWindow > 168) {
      return { ok: false, message: "The late window must be a whole number of hours between 1 and 168, or empty." };
    }
  }
  const ruleVersion = draft.ruleVersion.trim();
  if (ruleVersion.length === 0 || ruleVersion.length > 100) {
    return { ok: false, message: "A rule version label of 1 to 100 characters is required." };
  }
  return {
    ok: true,
    value: {
      normal_minor: normal,
      late_minor: late,
      late_window_hours: lateWindow,
      rule_version: ruleVersion,
      ...(draft.revision !== null ? { expected_revision: draft.revision } : {}),
    },
  };
}

/** Safe, specific messages for the reviewed commercial command. */
export function commercialErrorMessage(result: Extract<AdminRpcResponse, { ok: false }>): string {
  if (result.state === "signed_out") return "Sign in again to save configuration.";
  if (result.state === "forbidden") return "Administrator access is required.";
  if (result.state === "unconfigured") return "The admin backend is not configured.";
  const message = result.message.toLowerCase();
  if (message.includes("revision_conflict")) {
    return "Another administrator changed this entry. Refresh and review the current values before saving.";
  }
  if (message.includes("idempotency_conflict")) {
    return "This operation key was already used for a different change. The saved configuration was not altered.";
  }
  if (message.includes("invalid_option") || message.includes("invalid_policy") || message.includes("invalid_field")) {
    return "The backend rejected these values. Check the amounts and version label.";
  }
  return "The change was not confirmed. Retry the same change or refresh and check the saved value.";
}

const uuid = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

const isMinor = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0;

const isCount = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0;

const isTimestamp = (value: unknown): value is string | null =>
  value === null || (typeof value === "string" && value.length <= 40);

export type CreditSummaryRow = {
  user_id: string;
  batch_count: number;
  original_minor: number;
  remaining_minor: number;
  reserved_minor: number;
  available_minor: number;
  spent_percent: number;
  target_count: number;
  won_count: number;
  released_count: number;
  last_deposit_at: string | null;
};

export type RewardSummaryRow = {
  buyer_user_id: string;
  reward_count: number;
  total_minor: number;
  last_reward_at: string | null;
};

export type LedgerPage<T> = { items: T[]; next_cursor: string | null };

function decodePage<T>(
  value: unknown,
  decodeRow: (row: Record<string, unknown>) => T | null,
): LedgerPage<T> | null {
  if (!value || typeof value !== "object") return null;
  const page = value as Record<string, unknown>;
  if (
    !Array.isArray(page.items) ||
    page.items.length > 100 ||
    !(page.next_cursor === null || (typeof page.next_cursor === "string" && uuid.test(page.next_cursor)))
  ) {
    return null;
  }
  const items: T[] = [];
  const ids = new Set<string>();
  for (const raw of page.items) {
    if (!raw || typeof raw !== "object") return null;
    const row = raw as Record<string, unknown>;
    const id = row.user_id ?? row.buyer_user_id;
    if (typeof id !== "string" || !uuid.test(id) || ids.has(id)) return null;
    const decoded = decodeRow(row);
    if (decoded === null) return null;
    ids.add(id);
    items.push(decoded);
  }
  if (page.next_cursor !== null && items.length === 0) {
    return null;
  }
  return { items, next_cursor: page.next_cursor as string | null };
}

export function decodeCreditSummary(value: unknown): LedgerPage<CreditSummaryRow> | null {
  return decodePage(value, (row) => {
    if (
      !isCount(row.batch_count) ||
      !isMinor(row.original_minor) ||
      !isMinor(row.remaining_minor) ||
      !isMinor(row.reserved_minor) ||
      !isMinor(row.available_minor) ||
      !isCount(row.spent_percent) ||
      row.spent_percent > 100 ||
      !isCount(row.target_count) ||
      !isCount(row.won_count) ||
      !isCount(row.released_count) ||
      !isTimestamp(row.last_deposit_at) ||
      row.remaining_minor > row.original_minor ||
      row.reserved_minor > row.remaining_minor
    ) {
      return null;
    }
    return {
      user_id: row.user_id as string,
      batch_count: row.batch_count,
      original_minor: row.original_minor,
      remaining_minor: row.remaining_minor,
      reserved_minor: row.reserved_minor,
      available_minor: row.available_minor,
      spent_percent: row.spent_percent,
      target_count: row.target_count,
      won_count: row.won_count,
      released_count: row.released_count,
      last_deposit_at: row.last_deposit_at,
    };
  });
}

export function decodeRewardSummary(value: unknown): LedgerPage<RewardSummaryRow> | null {
  return decodePage(value, (row) => {
    if (
      !isCount(row.reward_count) ||
      !isMinor(row.total_minor) ||
      !isTimestamp(row.last_reward_at)
    ) {
      return null;
    }
    return {
      buyer_user_id: row.buyer_user_id as string,
      reward_count: row.reward_count,
      total_minor: row.total_minor,
      last_reward_at: row.last_reward_at,
    };
  });
}

export function formatHc(minor: number): string {
  return `${(minor / 100).toFixed(2)} HC`;
}

export function formatUsd(minor: number): string {
  return `$${(minor / 100).toFixed(2)}`;
}

const TARGET_STATUSES = new Set([
  "reserved",
  "initial_charged",
  "won",
  "released",
  "refunded",
]);

export type CreditBatchRow = {
  id: string;
  original_minor: number;
  balance_minor: number;
  reserved_minor: number;
  initial_fee_minor: number;
  winning_total_minor: number;
  rate_version: string;
  created_at: string;
};

export type CreditTargetRow = {
  id: string;
  request_id: string;
  batch_id: string;
  status: string;
  charged_minor: number;
  reserved_minor: number;
  week_start: string;
  created_at: string;
};

export type CreditDetail = {
  user_id: string;
  available_minor: number;
  batches: CreditBatchRow[];
  targets: CreditTargetRow[];
};

export function decodeCreditDetail(value: unknown): CreditDetail | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  if (
    typeof record.user_id !== "string" ||
    !uuid.test(record.user_id) ||
    !isMinor(record.available_minor) ||
    !Array.isArray(record.batches) ||
    !Array.isArray(record.targets) ||
    record.targets.length > 20
  ) {
    return null;
  }
  const batches: CreditBatchRow[] = [];
  for (const raw of record.batches) {
    if (!raw || typeof raw !== "object") return null;
    const row = raw as Record<string, unknown>;
    if (
      typeof row.id !== "string" ||
      !uuid.test(row.id) ||
      !isMinor(row.original_minor) ||
      !isMinor(row.balance_minor) ||
      !isMinor(row.reserved_minor) ||
      !isMinor(row.initial_fee_minor) ||
      !isMinor(row.winning_total_minor) ||
      typeof row.rate_version !== "string" ||
      row.rate_version.length === 0 ||
      row.rate_version.length > 100 ||
      typeof row.created_at !== "string" ||
      row.created_at.length > 40 ||
      row.balance_minor > row.original_minor ||
      row.reserved_minor > row.balance_minor ||
      row.winning_total_minor < row.initial_fee_minor
    ) {
      return null;
    }
    batches.push({
      id: row.id,
      original_minor: row.original_minor,
      balance_minor: row.balance_minor,
      reserved_minor: row.reserved_minor,
      initial_fee_minor: row.initial_fee_minor,
      winning_total_minor: row.winning_total_minor,
      rate_version: row.rate_version,
      created_at: row.created_at,
    });
  }
  const targets: CreditTargetRow[] = [];
  for (const raw of record.targets) {
    if (!raw || typeof raw !== "object") return null;
    const row = raw as Record<string, unknown>;
    if (
      typeof row.id !== "string" ||
      !uuid.test(row.id) ||
      typeof row.request_id !== "string" ||
      !uuid.test(row.request_id) ||
      typeof row.batch_id !== "string" ||
      !uuid.test(row.batch_id) ||
      typeof row.status !== "string" ||
      !TARGET_STATUSES.has(row.status) ||
      !isMinor(row.charged_minor) ||
      !isMinor(row.reserved_minor) ||
      typeof row.week_start !== "string" ||
      row.week_start.length > 20 ||
      typeof row.created_at !== "string" ||
      row.created_at.length > 40
    ) {
      return null;
    }
    targets.push({
      id: row.id,
      request_id: row.request_id,
      batch_id: row.batch_id,
      status: row.status,
      charged_minor: row.charged_minor,
      reserved_minor: row.reserved_minor,
      week_start: row.week_start,
      created_at: row.created_at,
    });
  }
  return {
    user_id: record.user_id,
    available_minor: record.available_minor,
    batches,
    targets,
  };
}

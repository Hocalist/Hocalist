// Pure checkout-return and retained-intent rules.
//
// A checkout id is a lookup hint, never proof: the server re-authorizes it and
// returns the exact row. These helpers only decide how that authoritative row
// is presented and when a client-retained retry key may be discarded.

export type CheckoutRow = {
  id: string;
  kind: "subscription" | "credit_deposit" | string;
  state: string;
  amount_minor: number;
  currency?: string;
  created_at?: string;
  expires_at?: string;
  credited_at?: string | null;
  batch_id?: string | null;
  option_id?: string | null;
  plan_code?: string | null;
};

export type CheckoutViewMode =
  | "verifying"
  | "verified-deposit"
  | "verified-subscription"
  | "pending"
  | "expired"
  | "missing"
  | "unconfirmed"
  | "idle";

export type CheckoutView = {
  mode: CheckoutViewMode;
  checkout: CheckoutRow | null;
};

export function resolveCheckoutView(
  payload: { selected?: CheckoutRow | null; deposits?: CheckoutRow[] | null },
  options: { cancelled?: boolean; hintProvided?: boolean } = {},
): CheckoutView {
  const selected = payload.selected ?? null;
  const deposits = Array.isArray(payload.deposits) ? payload.deposits : [];
  if (selected) {
    if (selected.state === "complete") {
      return {
        mode: selected.kind === "subscription" ? "verified-subscription" : "verified-deposit",
        checkout: selected,
      };
    }
    if (selected.state === "open" || selected.state === "creating") {
      return { mode: "pending", checkout: selected };
    }
    return { mode: "expired", checkout: selected };
  }
  if (options.hintProvided) {
    // The hint named a checkout this account does not own, or one that no
    // longer exists: never fall back to an older completion.
    return { mode: "missing", checkout: null };
  }
  const open = deposits.find((checkout) => checkout.state === "open" || checkout.state === "creating");
  if (open) return { mode: "pending", checkout: open };
  if (options.cancelled) return { mode: "unconfirmed", checkout: null };
  return { mode: "idle", checkout: null };
}

export type CheckoutIntent = {
  kind: "subscription" | "credit_deposit";
  value: string;
  key: string;
  checkoutId?: string | null;
};

export type IntentStorage = {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
};

export const INTENT_PREFIX = "hocalist.siteCheckoutIntent.";

export function intentKey(membershipId: string): string {
  return `${INTENT_PREFIX}${membershipId}`;
}

export function readIntent(
  storage: IntentStorage,
  membershipId: string | null | undefined,
): CheckoutIntent | null {
  if (!membershipId) return null;
  try {
    const raw = storage.getItem(intentKey(membershipId));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as CheckoutIntent;
    if (
      (parsed.kind === "subscription" || parsed.kind === "credit_deposit") &&
      typeof parsed.value === "string" && typeof parsed.key === "string"
    ) {
      return parsed;
    }
  } catch {
    /* Malformed local state is ignored. */
  }
  return null;
}

export function writeIntent(
  storage: IntentStorage,
  membershipId: string | null | undefined,
  intent: CheckoutIntent | null,
): void {
  if (!membershipId) return;
  try {
    if (intent) storage.setItem(intentKey(membershipId), JSON.stringify(intent));
    else storage.removeItem(intentKey(membershipId));
  } catch {
    /* Storage can be unavailable; checkout still works in this tab. */
  }
}

// A retained retry key survives reloads and sign-ins until the exact checkout
// it started is confirmed complete or has definitively expired. An unrelated
// completed deposit never clears it, and an intent without a recorded checkout
// id is kept so a lost response can be retried with the same key.
export function shouldClearIntent(
  intent: CheckoutIntent | null,
  selected: CheckoutRow | null | undefined,
): boolean {
  if (!intent || !intent.checkoutId || !selected) return false;
  if (selected.id !== intent.checkoutId) return false;
  return selected.state === "complete" || selected.state === "expired";
}

export function intentMatches(
  intent: CheckoutIntent | null,
  kind: CheckoutIntent["kind"],
  value: string,
): boolean {
  return Boolean(intent && intent.kind === kind && intent.value === value);
}

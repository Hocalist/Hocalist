// Local rendered-proof capability injection.
//
// Only active when HOCALIST_WEBSITE_PREVIEW=1 and never in a production
// build. It supplies synthetic billing states through the same response shape
// the real route uses, so loading/empty/pending/forbidden/review/error and the
// checkout-return bindings can be reviewed without a live provider,
// credentials or an account. Every preview payload carries `preview: true`,
// and the pages label it visibly — including the return and cancel pages.

export type PreviewKind =
  | "populated"
  | 'free'
  | 'elite'
  | "empty"
  | "pending"
  | "pending-subscription"
  | "plans-disabled"
  | "subscription"
  | "old-completed-new-pending"
  | "return-verified-deposit"
  | "return-verified-subscription"
  | "missing"
  | "forbidden"
  | "review"
  | "signedout"
  | "error";

export function previewEnabled(): boolean {
  return process.env.HOCALIST_WEBSITE_PREVIEW === "1" && process.env.NODE_ENV !== "production";
}

const MEMBERSHIP = "92000000-0000-4000-8000-000000000001";

const option = {
  id: "90000000-0000-4000-8000-000000000001",
  amount_minor: 2000,
  initial_fee_minor: 175,
  winning_total_minor: 460,
  rate_version: "deposit-20-preview",
  sort_order: 1,
};

const secondOption = {
  id: "90000000-0000-4000-8000-000000000002",
  amount_minor: 4000,
  initial_fee_minor: 165,
  winning_total_minor: 450,
  rate_version: "deposit-40-preview",
  sort_order: 2,
};

const plans = [
  { code: "pro", amount_minor: 1500, currency: "usd", enabled: true },
  { code: "elite", amount_minor: 3000, currency: "usd", enabled: true },
  { code: "pro", amount_minor: 12000, currency: "usd", enabled: true, billing_interval: 'year' },
  { code: "elite", amount_minor: 30000, currency: "usd", enabled: true, billing_interval: 'year' },
];

const completedCheckout = {
  id: "91000000-0000-4000-8000-000000000001",
  kind: "credit_deposit",
  state: "complete",
  amount_minor: 2000,
  currency: "usd",
  created_at: "2026-09-26T14:00:00.000Z",
  expires_at: "2026-09-26T15:00:00.000Z",
  credited_at: "2026-09-26T14:04:00.000Z",
  batch_id: "93000000-0000-4000-8000-000000000001",
  option_id: option.id,
  plan_code: null,
};

const openCheckout = {
  id: "91000000-0000-4000-8000-000000000002",
  kind: "credit_deposit",
  state: "open",
  amount_minor: 2000,
  currency: "usd",
  created_at: "2026-09-26T16:05:00.000Z",
  expires_at: "2026-09-26T17:05:00.000Z",
  credited_at: null,
  batch_id: null,
  option_id: option.id,
  plan_code: null,
};

const subscriptionCheckout = {
  id: "91000000-0000-4000-8000-000000000003",
  kind: "subscription",
  state: "complete",
  amount_minor: 1500,
  currency: "usd",
  created_at: "2026-09-26T13:00:00.000Z",
  expires_at: "2026-09-26T14:00:00.000Z",
  credited_at: null,
  batch_id: null,
  option_id: null,
  plan_code: "pro",
};

const subscription = {
  plan: "pro",
  provider_status: "active",
  paid_until: "2026-10-26T14:00:00.000Z",
  cancel_at_period_end: false,
  requires_review: false,
  updated_at: "2026-09-26T14:00:00.000Z",
};

function payload(changes: Record<string, unknown>) {
  return {
    preview: true,
    state: "ready",
    account: { membership_id: MEMBERSHIP },
    plans,
    options: [option, secondOption],
    subscription,
    deposits: [completedCheckout],
    selected: null,
    requires_review: false,
    credit_purchase_allowed: true,
    effective_plan: 'pro',
    entitlement: {effective_source:'billing',policy:{earned_pro_threshold:7},plans:[{plan_code:'free',weekly_target_limit:10,store_listing_limit:3},{plan_code:'pro',weekly_target_limit:50,store_listing_limit:15},{plan_code:'elite',weekly_target_limit:100,store_listing_limit:50}]},
    standard_rates: [{plan_code:'pro',initial_minor:190,winning_minor:475}],
    plan_fee_rates: [
      {plan_code:'free',initial_minor:200,winning_minor:500,deposits:[{amount_minor:2000,initial_fee_minor:195,winning_total_minor:475},{amount_minor:4000,initial_fee_minor:185,winning_total_minor:450}]},
      {plan_code:'pro',initial_minor:190,winning_minor:475,deposits:[{amount_minor:2000,initial_fee_minor:175,winning_total_minor:460},{amount_minor:4000,initial_fee_minor:165,winning_total_minor:450}]},
      {plan_code:'elite',initial_minor:180,winning_minor:450,deposits:[{amount_minor:2000,initial_fee_minor:155,winning_total_minor:375},{amount_minor:4000,initial_fee_minor:145,winning_total_minor:325}]},
    ],
    subscription_price: {amount_minor:1500,currency:'usd',billing_interval:'month'},
    ...changes,
  };
}

export function previewStatus(kind: string): { status: number; body: Record<string, unknown> } {
  switch (kind as PreviewKind) {
    case "empty":
      return {
        status: 200,
        body: payload({
          subscription: { ...subscription, plan: "free", provider_status: null, paid_until: null },
          effective_plan: 'free',
          standard_rates: [{plan_code:'free',initial_minor:200,winning_minor:500}],
          subscription_price: null,
          options: [],
          deposits: [],
        }),
      };
    case 'free':
      return {status:200,body:payload({effective_plan:'free',subscription:null,subscription_price:null,standard_rates:[{plan_code:'free',initial_minor:200,winning_minor:500}],options:[{...option,initial_fee_minor:195,winning_total_minor:475},{...secondOption,initial_fee_minor:185,winning_total_minor:450}]})};
    case 'elite':
      return {status:200,body:payload({effective_plan:'elite',subscription:{...subscription,plan:'elite'},subscription_price:{amount_minor:3000,currency:'usd',billing_interval:'month'},standard_rates:[{plan_code:'elite',initial_minor:180,winning_minor:450}],options:[{...option,initial_fee_minor:155,winning_total_minor:375},{...secondOption,initial_fee_minor:145,winning_total_minor:325}]})};
    case "pending":
      return { status: 200, body: payload({ deposits: [openCheckout], selected: openCheckout }) };
    case "pending-subscription":
      return { status: 200, body: payload({ subscription: null, credit_purchase_allowed: true,
        selected: { ...subscriptionCheckout, state: 'open' } }) };
    case "plans-disabled":
      return {
        status: 200,
        body: payload({
          plans: plans.map((plan) => ({ ...plan, enabled: false })),
          options: [],
          deposits: [],
        }),
      };
    case "subscription":
      return {
        status: 200,
        body: payload({ deposits: [], selected: subscriptionCheckout }),
      };
    case "old-completed-new-pending":
      return {
        status: 200,
        body: payload({ deposits: [openCheckout, completedCheckout], selected: openCheckout }),
      };
    case "return-verified-deposit":
      return {
        status: 200,
        body: payload({ deposits: [completedCheckout], selected: completedCheckout }),
      };
    case "return-verified-subscription":
      return {
        status: 200,
        body: payload({ deposits: [], selected: subscriptionCheckout }),
      };
    case "missing":
      return { status: 200, body: payload({ selected: null }) };
    case "forbidden":
      return {
        status: 403,
        body: { preview: true, state: "forbidden", message: "This account is not an active seller account." },
      };
    case "review":
      return {
        status: 403,
        body: {
          preview: true,
          state: "review",
          message: "This account needs a billing review before purchases can continue.",
        },
      };
    case "signedout":
      return { status: 401, body: { preview: true, state: "signed_out" } };
    case "error":
      return {
        status: 503,
        body: { preview: true, state: "error", message: "The billing service is unreachable. Try again." },
      };
    default:
      return { status: 200, body: payload({}) };
  }
}

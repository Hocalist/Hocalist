import { recipientSetupProject } from "../_shared/reward-sandbox-project.ts";
import { stripeSandboxClient } from "../_shared/stripe-reward-client.ts";
import { buyerPayoutReturnUrl } from "./return-url.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
  "Content-Type": "application/json",
};
const reply = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), { status, headers });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers });
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  try {
    const project = recipientSetupProject((name) => Deno.env.get(name));
    const accountId = Deno.env.get("HOCALIST_REWARD_SANDBOX_ACCOUNT_ID");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const secret = Deno.env.get("HOCALIST_REWARD_STRIPE_SANDBOX_KEY") ?? "";
    const redirect = Deno.env.get("HOCALIST_REWARD_RETURN_URL") ?? "";
    if (
      !project || !accountId || !service ||
      !(redirect.startsWith("https://") ||
        redirect === "http://127.0.0.1:7359/")
    ) return reply({ error: "configuration_unavailable" }, 503);
    const stripe = stripeSandboxClient(secret);
    const auth = req.headers.get("authorization") ?? "";
    if (!/^Bearer \S+$/.test(auth)) {
      return reply({ error: "authentication_required" }, 401);
    }
    const response = await fetch(project + "/auth/v1/user", {
      headers: { apikey: service, Authorization: auth },
    });
    if (!response.ok) return reply({ error: "authentication_required" }, 401);
    const user = await response.json();
    if (
      !(user.email_confirmed_at || user.phone_confirmed_at) || user.is_anonymous ||
      typeof user.id !== "string"
    ) return reply({ error: "verified_account_required" }, 403);
    const { action } = await req.json();
    if (!["status", "onboard", "manage"].includes(action)) {
      return reply({ error: "invalid_action" }, 400);
    }
    const dbHeaders = {
      apikey: service,
      Authorization: "Bearer " + service,
      "Accept-Profile": "hocalist",
      "Content-Profile": "hocalist",
      "Content-Type": "application/json",
    };
    const table = project + "/rest/v1/stripe_reward_recipients";
    const buyer = await fetch(
      project + "/rest/v1/memberships?select=id&role=eq.buyer&status=eq.active&user_id=eq." +
        encodeURIComponent(user.id),
      { headers: { ...dbHeaders, Authorization: auth } },
    );
    if (!buyer.ok) throw Error("membership_lookup");
    if (!(await buyer.json()).length) return reply({ error: "active_buyer_required" }, 403);
    async function lookup() {
      const read = await fetch(
        table + "?select=recipient_id&environment=eq.sandbox&user_id=eq." +
          encodeURIComponent(user.id),
        { headers: dbHeaders },
      );
      if (!read.ok) throw Error("storage");
      return (await read.json())[0]?.recipient_id as string | undefined;
    }
    let recipient = await lookup();
    if (action === "status" && !recipient) {
      return reply({ ready: false, saved: false });
    }
    const acct = await fetch("https://api.stripe.com/v1/account", {
      headers: { Authorization: "Bearer " + secret },
    });
    if (!acct.ok || (await acct.json()).id !== accountId) {
      throw Error("wrong_account");
    }
    if (!recipient) {
      const created = await stripe("core/accounts", {
        ...(user.email_confirmed_at && user.email ? { contact_email: user.email } : {}),
        identity: { country: "us", entity_type: "individual" },
        configuration: {
          recipient: {
            capabilities: { bank_accounts: { ach: { requested: true } } },
          },
        },
      }, "hocalist-sandbox-recipient-" + user.id);
      if (!/^acct_[a-zA-Z0-9]+$/.test(created.id)) {
        throw Error("invalid_recipient");
      }
      const saved = await fetch(table + "?on_conflict=user_id,environment", {
        method: "POST",
        headers: { ...dbHeaders, Prefer: "resolution=ignore-duplicates" },
        body: JSON.stringify({
          user_id: user.id,
          environment: "sandbox",
          recipient_id: created.id,
        }),
      });
      if (!saved.ok) throw Error("storage");
      recipient = await lookup();
      if (!recipient) throw Error("storage");
    }
    let saved = false;
    let page = "money_management/payout_methods?limit=100";
    while (page && !saved) {
      const methods = await stripe(page, undefined, undefined, recipient);
      saved = methods.data.some((
        m: { type: string; bank_account?: { archived?: boolean } },
      ) => m.type === "bank_account" && !!m.bank_account && m.bank_account.archived !== true);
      if (!methods.next_page_url) break;
      const next = new URL(methods.next_page_url, "https://api.stripe.com");
      if (next.pathname !== "/v2/money_management/payout_methods") {
        throw Error("invalid_page");
      }
      page = "money_management/payout_methods" + next.search;
    }
    if (action === "status") {
      const account = await stripe(
        "core/accounts/" + encodeURIComponent(recipient) +
          "?include[0]=configuration.recipient",
      );
      return reply({
        saved,
        ready: saved &&
          account.configuration?.recipient?.capabilities?.bank_accounts?.ach
              ?.status === "active",
      });
    }
    const type = saved ? "account_update" : "account_onboarding";
    const returnUrl = buyerPayoutReturnUrl(redirect, req.headers.get("origin"));
    const link = await stripe("core/account_links", {
      account: recipient,
      use_case: {
        type,
        [type]: { return_url: returnUrl, refresh_url: returnUrl },
      },
    });
    const url = new URL(link.url);
    if (url.protocol !== "https:" || !url.hostname.endsWith(".stripe.com")) {
      throw Error("invalid_link");
    }
    return reply({ url: url.href });
  } catch {
    return reply({ error: "payout_setup_unavailable" }, 503);
  }
});

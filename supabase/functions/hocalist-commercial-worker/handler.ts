import { rewardSandboxProject } from "../_shared/reward-sandbox-project.ts";
import { sharedProject, qaAccount } from "../_shared/stripe-test-project.ts";
import { stripeRewardProvider } from "./stripe-reward-provider.ts";
// Hocalist commercial worker request handler.
//
// Kept separate from index.ts so the HTTP contract (shared-secret
// authorization, Hocalist schema headers, RPC path/body) can be proved with an
// injected fetch. No provider is named, called or emulated here: until a
// verified adapter is installed the handler reports that state honestly.
import { type CommercialRpc, runPayoutCycle } from "./executor.ts";
import type { PayoutProvider } from "./payout_provider.ts";

export const HOCALIST_SCHEMA = "hocalist";

export interface HandlerDependencies {
  fetcher: typeof fetch;
  env: (name: string) => string | undefined;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

async function digest(value: string): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
}

async function authorized(
  request: Request,
  secret: string,
): Promise<boolean> {
  if (secret.length < 32) return false;
  const actual =
    request.headers.get("Authorization")?.replace(/^Bearer /, "") ?? "";
  const [a, b] = await Promise.all([digest(actual), digest(secret)]);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

export function serviceRpc(deps: HandlerDependencies): CommercialRpc {
  const url = deps.env("SUPABASE_URL") ?? "";
  const key = deps.env("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (url.length === 0 || key.length === 0) {
    throw new Error("configuration_error");
  }
  return async (functionName, params) => {
    const response = await deps.fetcher(
      `${url.replace(/\/$/, "")}/rest/v1/rpc/${functionName}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          // The commercial functions live in the dedicated Hocalist schema;
          // an implicit default schema is not valid routing.
          "Content-Profile": HOCALIST_SCHEMA,
          "Accept-Profile": HOCALIST_SCHEMA,
          apikey: key,
          Authorization: `Bearer ${key}`,
        },
        body: JSON.stringify(params),
        signal: AbortSignal.timeout(15000),
      },
    );
    if (!response.ok) throw new Error("provider_or_storage_unavailable");
    const data = await response.json();
    if (data === null || typeof data !== "object") {
      throw new Error("provider_or_storage_unavailable");
    }
    return data as Record<string, unknown>;
  };
}

// A verified provider adapter is coordinator work after account/country/
// recipient eligibility. Until one is installed this returns null and the
// handler reports the honest state instead of guessing an integration.
export function configuredProvider(
  deps: HandlerDependencies,
): PayoutProvider | null {
  if (deps.env("HOCALIST_PAYOUT_PROVIDER_KEY") !== "stripe_global_sandbox") {
    return null;
  }
  const secret = deps.env("HOCALIST_REWARD_STRIPE_SANDBOX_KEY") ?? "";
  const account = deps.env("HOCALIST_REWARD_FINANCIAL_ACCOUNT") ?? "";
  if (
    !(rewardSandboxProject(deps.env) || (deps.env("SUPABASE_URL") === sharedProject &&
      deps.env("HOCALIST_REWARD_SANDBOX_ACCOUNT_ID") === qaAccount)) || !secret ||
    !/^fa_[a-zA-Z0-9_]+$/.test(account)
  ) return null;
  return stripeRewardProvider(secret, account, serviceRpc(deps), deps.fetcher);
}

export function createHandler(
  deps: HandlerDependencies,
): (request: Request) => Promise<Response> {
  return async (request) => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    try {
      if (
        !await authorized(
          request,
          deps.env("HOCALIST_COMMERCIAL_WORKER_SECRET") ?? "",
        )
      ) {
        return json({ error: "authentication_required" }, 401);
      }
      if (deps.env("SUPABASE_URL") === sharedProject) {
        const guard = await serviceRpc(deps)("sandbox_payout_execution_guard", {});
        if (guard.ready !== true) return json({ status: "sandbox_guard_unavailable" }, 503);
      }
      const providerKey = deps.env("HOCALIST_PAYOUT_PROVIDER_KEY") ?? "";
      const provider = configuredProvider(deps);
      if (provider === null) {
        return json({
          status: providerKey.length === 0
            ? "provider_not_configured"
            : "provider_adapter_unavailable",
        });
      }
      const summary = await runPayoutCycle({
        rpc: serviceRpc(deps),
        provider,
      });
      return json(summary);
    } catch (error) {
      const message = error instanceof Error ? error.message : "worker_failure";
      const status = message === "configuration_error" ? 503 : 500;
      return json({ error: message }, status);
    }
  };
}

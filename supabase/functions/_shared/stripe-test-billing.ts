// Server only. Deliberately independent of Flutter and the shared project's other apps.
export const PROJECT = "https://icqwbzswokoulatomgql.supabase.co";
export const ACCOUNT = "acct_1Le6hqDmHEV44E5Y";
export type ObjectMap = Record<string, unknown>;
export function object(value: unknown): ObjectMap {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_response");
  }
  return value as ObjectMap;
}
export function id(value: unknown): string {
  if (value === null || value === undefined) return "";
  return typeof value === "string" ? value : String(object(value).id ?? "");
}
export function rows(value: unknown): ObjectMap[] {
  const list = object(value);
  if (!Array.isArray(list.data) || list.has_more !== false) {
    throw new Error("review_required");
  }
  return list.data.map(object);
}
export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
export class BillingError extends Error {
  constructor(public code: string, public status: number) {
    super(code);
  }
}
export function backend() {
  const verifiedEmails = new WeakMap<Request, string>();
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const key = Deno.env.get("HOCALIST_STRIPE_TEST_API_KEY") ?? "";
  if (
    Deno.env.get("SUPABASE_URL") !== PROJECT || !service ||
    !/^(sk|rk)_test_/.test(key)
  ) throw new Error("configuration_unavailable");
  return {
    async user(request: Request): Promise<string> {
      const authorization = request.headers.get("Authorization") ?? "";
      if (!/^Bearer \S+$/.test(authorization)) {
        throw new BillingError("authentication_required", 401);
      }
      const result = await fetch(`${PROJECT}/auth/v1/user`, {
        headers: { apikey: service, Authorization: authorization },
        signal: AbortSignal.timeout(10000),
      });
      if (!result.ok) throw new BillingError("authentication_required", 401);
      const user = object(await result.json());
      if (typeof user.id !== "string" || user.is_anonymous === true) {
        throw new BillingError("authentication_required", 401);
      }
      if (typeof user.email === "string" && user.email_confirmed_at) {
        verifiedEmails.set(request, user.email);
      }
      return user.id;
    },
    userEmail(request: Request): string | undefined {
      return verifiedEmails.get(request);
    },
    async rpc(name: string, body: ObjectMap = {}): Promise<unknown> {
      const response = await fetch(`${PROJECT}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
          apikey: service,
          Authorization: `Bearer ${service}`,
          "Content-Type": "application/json",
          "Content-Profile": "hocalist",
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) {
        const error = object(await response.json());
        const known: Record<string, number> = {
          billing_access_denied: 403,
          invalid_plan_or_key: 409,
          idempotency_conflict: 409,
          checkout_closed: 409,
          subscription_exists: 409,
          subscription_required: 409,
          checkout_pending: 409,
          checkout_reconciliation_required: 409,
          billing_review_required: 409,
          invalid_option_or_key: 400,
          invalid_customer: 400,
          invalid_session: 400,
          invalid_reference: 400,
          not_a_deposit_checkout: 400,
          customer_conflict: 409,
          session_conflict: 409,
          checkout_association_missing: 409,
          amount_mismatch: 409,
        };
        const code = String(error.message);
        if (code in known) {
          throw new BillingError(code, known[code]);
        }
        throw new Error("storage_unavailable");
      }
      // PostgREST returns 204 with no JSON body for successful void RPCs,
      // including customer/session binding. The command already committed;
      // parsing an empty body would incorrectly report a failed checkout.
      if (response.status === 204) return null;
      return response.json();
    },
    async stripe(
      path: string,
      params?: Record<string, string>,
      keyId?: string,
    ): Promise<ObjectMap> {
      const response = await fetch(`https://api.stripe.com/v1/${path}`, {
        method: params ? "POST" : "GET",
        headers: {
          Authorization: `Bearer ${key}`,
          "Stripe-Version": "2022-08-01",
          ...(params
            ? { "Content-Type": "application/x-www-form-urlencoded" }
            : {}),
          ...(keyId ? { "Idempotency-Key": keyId } : {}),
        },
        body: params ? new URLSearchParams(params) : undefined,
        signal: AbortSignal.timeout(15000),
      });
      if (!response.ok) throw new Error("provider_unavailable");
      const result = object(await response.json());
      if (result.livemode === true) throw new Error("review_required");
      return result;
    },
  };
}
export type Backend = ReturnType<typeof backend>;
export async function assertAccount(api: Backend): Promise<void> {
  if ((await api.stripe("account")).id !== ACCOUNT) {
    throw new Error("configuration_unavailable");
  }
}
export async function boundedBody(request: Request): Promise<ObjectMap> {
  if (!request.headers.get("Content-Type")?.startsWith("application/json")) {
    throw new BillingError("invalid_request", 400);
  }
  const reader = request.body?.getReader();
  if (!reader) throw new BillingError("invalid_request", 400);
  let total = 0;
  const chunks: Uint8Array[] = [];
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      total += part.value.length;
      if (total > 2048) {
        await reader.cancel();
        throw new BillingError("invalid_request", 400);
      }
      chunks.push(part.value);
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    return object(JSON.parse(new TextDecoder().decode(bytes)));
  } catch (error) {
    if (error instanceof BillingError) throw error;
    throw new BillingError("invalid_request", 400);
  }
}
export function failure(error: unknown): Response {
  return error instanceof BillingError
    ? json({ error: error.code }, error.status)
    : json({ error: "billing_unavailable" }, 503);
}

// Shared billing-only helpers. Additive: existing callers keep their behavior.

// A configured destination may only be an HTTPS Hocalist page: no port,
// credentials, or other host can be redirected to after checkout.
export function serviceUrl(
  value: unknown,
  hosts: readonly string[] = ["hocalist.com", "www.hocalist.com"],
): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error("configuration_unavailable");
  }
  const url = new URL(value);
  if (
    url.protocol !== "https:" || !hosts.includes(url.hostname) || url.port ||
    url.username || url.password
  ) throw new Error("configuration_unavailable");
  return url.toString();
}

// Provider redirect targets are never trusted from JSON: the exact scheme,
// host and path prefix are checked before a browser is sent there.
export function providerUrl(
  value: unknown,
  host: "checkout.stripe.com" | "billing.stripe.com",
): string {
  if (typeof value !== "string" || value.length > 2048 || !value.startsWith(`https://${host}/`)) {
    throw new Error("review_required");
  }
  const url = new URL(value);
  if (url.protocol !== "https:" || url.hostname !== host || url.port || url.username || url.password) {
    throw new Error("review_required");
  }
  return value;
}

// Stable payment identity for deposit dedupe: prefer the payment intent, fall
// back to the TEST checkout session id. A missing or malformed identity must
// fail closed rather than create an unbound credit batch.
export function paymentReference(session: ObjectMap): string {
  const intent = session.payment_intent;
  const candidate = typeof intent === "string" && /^pi_[A-Za-z0-9]{5,}$/.test(intent)
    ? intent
    : typeof session.id === "string" && /^cs_test_[A-Za-z0-9]{5,}$/.test(session.id)
      ? session.id
      : "";
  if (candidate.length < 8 || candidate.length > 200) {
    throw new Error("review_required");
  }
  return candidate;
}

export function positiveMinor(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) <= 0) {
    throw new Error("review_required");
  }
  return value as number;
}

export function uuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
  ) throw new BillingError("invalid_request", 400);
  return value;
}

// A provider checkout session belongs to the Hocalist credit deposit flow only
// when both identity keys are present; anything else stays on the
// subscription path.
export function isDepositSession(session: ObjectMap): boolean {
  const metadata = object(session.metadata ?? {});
  return metadata.app === "hocalist" && metadata.kind === "credit_deposit";
}

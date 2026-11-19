export const stripeVersion = "2026-10-28.endive";

// Both onboarding and dispatch must use the same sandbox account.
export function stripeSandboxClient(
  secret: string,
  fetcher: typeof fetch = fetch,
) {
  if (!secret.startsWith("sk_test_") && !secret.startsWith("rk_test_")) {
    throw Error("stripe_sandbox_key_required");
  }
  return async function stripe(
    path: string,
    body?: unknown,
    key?: string,
    recipient?: string,
  ) {
    const response = await fetcher("https://api.stripe.com/v2/" + path, {
      method: body === undefined ? "GET" : "POST",
      headers: {
        Authorization: "Bearer " + secret,
        "Stripe-Version": stripeVersion,
        "Content-Type": "application/json",
        ...(recipient ? { "Stripe-Context": recipient } : {}),
        ...(key ? { "Idempotency-Key": key } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw Error("stripe_request_failed_" + response.status);
    return await response.json();
  };
}

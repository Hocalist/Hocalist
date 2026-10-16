import type { AuthorizationResult } from "./handler.ts";

type AuthFetch = (url: string, init: RequestInit) => Promise<Response>;

// Server-only verifier. An Auth outage must never be presented as a bad login.
export function createPlacesAuthVerifier(
  project: string,
  apiKey: string,
  fetcher: AuthFetch = fetch,
): (authorization: string) => Promise<AuthorizationResult> {
  return async (authorization) => {
    try {
      const response = await fetcher(`${project}/auth/v1/user`, {
        headers: { apikey: apiKey, Authorization: authorization },
        redirect: "error",
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) {
        await response.body?.cancel();
        return {
          error: response.status === 401 || response.status === 403
            ? "unauthorized"
            : "unavailable",
        };
      }
      const user = await response.json();
      if (
        typeof user !== "object" || user === null || Array.isArray(user) ||
        typeof user.id !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          user.id,
        )
      ) return { error: "unavailable" };
      if (user.is_anonymous === true) return { error: "unauthorized" };
      return { userId: user.id };
    } catch {
      return { error: "unavailable" };
    }
  };
}

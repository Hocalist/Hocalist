// Server-only Android delivery. No app caller chooses a recipient or supplies an FCM token.
export interface PushWorkerDependencies {
  env: (name: string) => string | undefined;
  fetch: typeof fetch;
}

export function createPushWorkerHandler(deps: PushWorkerDependencies) {
  const PROJECT = "https://icqwbzswokoulatomgql.supabase.co";
  const SENDER = "hocalist-push-sender@hocalist.iam.gserviceaccount.com";
  const encode = (value: Uint8Array) =>
    btoa(String.fromCharCode(...value)).replace(/=/g, "").replace(/\+/g, "-")
      .replace(/\//g, "_");
  const text = (value: unknown) =>
    encode(new TextEncoder().encode(JSON.stringify(value)));
  function response(value: unknown, status = 200) {
    return new Response(JSON.stringify(value), {
      status,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    });
  }
  let cached: { token: string; until: number } | undefined;
  async function googleToken(): Promise<string> {
    if (cached && cached.until > Date.now() + 60000) return cached.token;
    const credential = JSON.parse(
      deps.env("HOCALIST_FCM_SERVICE_ACCOUNT_JSON") ?? "{}",
    );
    if (
      credential.type !== "service_account" ||
      credential.project_id !== "hocalist" ||
      credential.client_email !== SENDER ||
      typeof credential.private_key !== "string"
    ) throw new Error("configuration_error");
    const now = Math.floor(Date.now() / 1000);
    const data = `${text({ alg: "RS256", typ: "JWT" })}.${
      text({
        iss: SENDER,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      })
    }`;
    const der = Uint8Array.from(
      atob(
        credential.private_key.replace(/-----[^-]+-----/g, "").replace(
          /\s/g,
          "",
        ),
      ),
      (c) => c.charCodeAt(0),
    );
    const key = await crypto.subtle.importKey(
      "pkcs8",
      der,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(data),
    );
    const result = await deps.fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: `${data}.${encode(new Uint8Array(signature))}`,
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (!result.ok) throw new Error("configuration_error");
    const payload = await result.json();
    if (
      typeof payload.access_token !== "string" ||
      !Number.isFinite(payload.expires_in) || payload.expires_in <= 0
    ) throw new Error("configuration_error");
    cached = {
      token: payload.access_token,
      until: Date.now() + Math.min(payload.expires_in, 3600) * 1000,
    };
    return cached.token;
  }
  async function authorized(request: Request): Promise<boolean> {
    const secret = deps.env("HOCALIST_PUSH_WORKER_SECRET") ?? "";
    if (secret.length < 32) return false;
    const supplied = request.headers.get("Authorization") ?? "";
    const digest = async (s: string) =>
      new Uint8Array(
        await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)),
      );
    const [a, b] = await Promise.all([
      digest(supplied),
      digest(`Bearer ${secret}`),
    ]);
    let difference = 0;
    for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
    return difference === 0;
  }
  return async (request: Request) => {
    if (request.method !== "POST") {
      return response({ error: "method_not_allowed" }, 405);
    }
    if (!await authorized(request)) {
      return response({ error: "unauthorized" }, 401);
    }
    // Disabled by default. Enabling/sending requires separately reviewed deployment/configuration.
    if (deps.env("HOCALIST_PUSH_ENABLED") !== "true") {
      return response({ status: "disabled" });
    }
    const service = deps.env("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (deps.env("SUPABASE_URL") !== PROJECT || !service) {
      return response({ error: "configuration_unavailable" }, 503);
    }
    const rpc = async (name: string, input: unknown = {}) => {
      const result = await deps.fetch(`${PROJECT}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
          apikey: service,
          Authorization: `Bearer ${service}`,
          "Content-Type": "application/json",
          "Content-Profile": "hocalist",
        },
        body: JSON.stringify(input),
        signal: AbortSignal.timeout(10000),
      });
      if (!result.ok) throw new Error("storage_unavailable");
      const body = await result.text();
      // PostgreSQL void RPCs may acknowledge with an empty 200/204 body.
      // Claims and recipient projections must still provide valid JSON.
      if (name === "push_finish" && body.trim() === "") return null;
      return JSON.parse(body);
    };
    let job: { id: string; lease: string } | null = null;
    try {
      // Obtain short-lived authorization before acquiring a database lease.
      const access = await googleToken();
      job = await rpc("push_claim");
      if (!job) return response({ status: "idle" });
      const target = await rpc("push_delivery_target", {
        p_id: job.id,
        p_lease: job.lease,
      });
      if (!target) {
        await rpc("push_finish", {
          p_id: job.id,
          p_lease: job.lease,
          p_outcome: "skipped",
        });
        return response({ status: "skipped" });
      }
      const sent = await deps.fetch(
        "https://fcm.googleapis.com/v1/projects/hocalist/messages:send",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${access}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: target.token,
              notification: {
                title: "Hocalist",
                body: "You have an update. Open Hocalist to view it.",
              },
              data: { notification_id: target.notification_id },
              android: {
                restricted_package_name: "com.hocalist.app",
                ttl: "300s",
                notification: { tag: target.notification_id },
              },
            },
          }),
          signal: AbortSignal.timeout(15000),
        },
      );
      let outcome = "accepted";
      let retrySeconds = 60;
      if (!sent.ok) {
        const error = await sent.json().catch(() => ({}));
        const details = Array.isArray(error.error?.details)
          ? error.error.details
          : [];
        const unregistered = details.some((
          d: { "@type"?: string; errorCode?: string },
        ) =>
          d["@type"] ===
            "type.googleapis.com/google.firebase.fcm.v1.FcmError" &&
          d.errorCode === "UNREGISTERED"
        );
        // INVALID_ARGUMENT can describe our payload; never disable a token for that generic error.
        outcome = unregistered
          ? "unregistered"
          : sent.status === 429 || sent.status >= 500
          ? "retry"
          : "configuration_error";
        if (sent.status === 401) cached = undefined;
        const retryAfter = sent.headers.get("Retry-After");
        if (retryAfter) {
          const seconds = Number(retryAfter);
          retrySeconds = Number.isFinite(seconds)
            ? seconds
            : Math.ceil((Date.parse(retryAfter) - Date.now()) / 1000);
        }
        if (!Number.isFinite(retrySeconds)) retrySeconds = 60;
      }
      await rpc("push_finish", {
        p_id: job.id,
        p_lease: job.lease,
        p_outcome: outcome,
        p_retry_seconds: Math.max(60, Math.min(86400, retrySeconds)),
      });
      return response(
        { status: outcome },
        outcome === "retry" || outcome === "configuration_error" ? 503 : 200,
      );
    } catch {
      if (job) {
        try {
          await rpc("push_finish", {
            p_id: job.id,
            p_lease: job.lease,
            p_outcome: "retry",
            p_retry_seconds: 60,
          });
        } catch { /* Expired leases are recovered by the next claim. */ }
      }
      return response({ error: "push_unavailable" }, 503);
    }
  };
}

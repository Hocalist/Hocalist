import { createPushWorkerHandler } from "./handler.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
const secret = "synthetic-worker-secret-01234567890123456789";
const request = () =>
  new Request("https://worker.test", {
    method: "POST",
    headers: { Authorization: `Bearer ${secret}` },
  });
const pair = await crypto.subtle.generateKey(
  {
    name: "RSASSA-PKCS1-v1_5",
    modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]),
    hash: "SHA-256",
  },
  true,
  ["sign", "verify"],
);
const der = new Uint8Array(
  await crypto.subtle.exportKey("pkcs8", pair.privateKey),
);
const credential = JSON.stringify({
  type: "service_account",
  project_id: "hocalist",
  client_email: "hocalist-push-sender@hocalist.iam.gserviceaccount.com",
  private_key: `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...der))
  }\n-----END PRIVATE KEY-----`,
});

function fixture(options: {
  enabled?: boolean;
  emptyFinish?: boolean;
  missingTarget?: boolean;
  missingJob?: boolean;
  malformedClaim?: boolean;
  finishFails?: boolean;
  fcmStatus?: number;
  unregistered?: boolean;
} = {}) {
  const calls: string[] = [];
  const finishes: Record<string, unknown>[] = [];
  const values: Record<string, string> = {
    HOCALIST_PUSH_WORKER_SECRET: secret,
    HOCALIST_PUSH_ENABLED: String(options.enabled ?? true),
    SUPABASE_URL: "https://icqwbzswokoulatomgql.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-role",
    HOCALIST_FCM_SERVICE_ACCOUNT_JSON: credential,
  };
  const handler = createPushWorkerHandler({
    env: (name) => values[name],
    fetch: ((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      calls.push(
        url.includes("/rpc/") ? url.split("/rpc/")[1] : new URL(url).hostname,
      );
      if (url.includes("oauth2")) {
        return Promise.resolve(
          Response.json({ access_token: "synthetic-access", expires_in: 3600 }),
        );
      }
      if (url.endsWith("push_claim")) {
        return Promise.resolve(
          options.malformedClaim ? new Response("") : Response.json(
            options.missingJob ? null : { id: "job", lease: "lease" },
          ),
        );
      }
      if (url.endsWith("push_delivery_target")) {
        return Promise.resolve(Response.json(
          options.missingTarget
            ? null
            : { token: "synthetic-device", notification_id: "notification" },
        ));
      }
      if (url.endsWith("push_finish")) {
        finishes.push(JSON.parse(String(init?.body)));
        return Promise.resolve(
          options.finishFails
            ? new Response("failure", { status: 503 })
            : options.emptyFinish
            ? new Response(null, { status: 204 })
            : Response.json(null),
        );
      }
      if (url.includes("fcm.googleapis.com")) {
        const body = JSON.parse(String(init?.body));
        equal(body.message.data, { notification_id: "notification" });
        equal(body.message.android.restricted_package_name, "com.hocalist.app");
        return Promise.resolve(
          Response.json(
            options.unregistered
              ? {
                error: {
                  details: [{
                    "@type":
                      "type.googleapis.com/google.firebase.fcm.v1.FcmError",
                    errorCode: "UNREGISTERED",
                  }],
                },
              }
              : {},
            { status: options.fcmStatus ?? 200 },
          ),
        );
      }
      throw new Error("Unexpected destination");
    }) as typeof fetch,
  });
  return { handler, calls, finishes };
}

Deno.test("method, authentication and disabled gates dispatch nothing", async () => {
  const f = fixture({ enabled: false });
  equal((await f.handler(new Request("https://worker.test"))).status, 405);
  equal(
    (await f.handler(new Request("https://worker.test", { method: "POST" })))
      .status,
    401,
  );
  equal(await (await f.handler(request())).json(), { status: "disabled" });
  equal(f.calls, []);
});
for (const missingTarget of [false, true]) {
  Deno.test(`empty finish acknowledgement preserves ${missingTarget ? "skipped" : "accepted"} outcome`, async () => {
    const f = fixture({ emptyFinish: true, missingTarget });
    const result = await f.handler(request());
    equal(result.status, 200);
    equal(await result.json(), {
      status: missingTarget ? "skipped" : "accepted",
    });
    equal(f.finishes.length, 1);
    equal(f.finishes[0].p_outcome, missingTarget ? "skipped" : "accepted");
  });
}
Deno.test("null finish acknowledgement remains accepted", async () => {
  const f = fixture();
  equal(await (await f.handler(request())).json(), { status: "accepted" });
  equal(f.finishes.length, 1);
});
Deno.test("idle queue sends nothing", async () => {
  const f = fixture({ missingJob: true });
  equal(await (await f.handler(request())).json(), { status: "idle" });
  equal(f.finishes, []);
  equal(f.calls.includes("fcm.googleapis.com"), false);
});
Deno.test("malformed claim fails closed without sending", async () => {
  const f = fixture({ malformedClaim: true });
  equal((await f.handler(request())).status, 503);
  equal(f.calls.includes("fcm.googleapis.com"), false);
});
for (
  const [status, unregistered, outcome] of [[429, false, "retry"], [
    400,
    false,
    "configuration_error",
  ], [404, true, "unregistered"]] as const
) {
  Deno.test(`FCM ${status} maps to ${outcome}`, async () => {
    const f = fixture({ fcmStatus: status, unregistered });
    const result = await f.handler(request());
    equal(await result.json(), { status: outcome });
    equal(f.finishes.length, 1);
    equal(f.finishes[0].p_outcome, outcome);
  });
}
Deno.test("failed finish acknowledgement is not reported as success", async () => {
  const f = fixture({ finishFails: true });
  equal((await f.handler(request())).status, 503);
});

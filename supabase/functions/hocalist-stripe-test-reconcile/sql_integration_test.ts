// Provider-to-real-disposable-SQL integration for the reconciliation chain.
//
// The provider responses are synthetic, but every database call is the real
// deployed contract executed in disposable PGlite: the signed-receipt function,
// the worker claim/lease, the stored checkout context, the deposit finish and
// the credit-batch creation. This is stronger than an injected fake database
// acknowledgement, but it is still not live JWT/PostgREST or multi-connection
// proof.
import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";
import { ACCOUNT, type Backend, type ObjectMap } from "../_shared/stripe-test-billing.ts";
import { createReconcileHandler } from "./handler.ts";

const ROOT = new URL("../../../", import.meta.url);
const BOOTSTRAP = [
  "database/drafts/005_stripe_test_inbox.sql",
  "database/drafts/003_membership_private_profiles.sql",
  "database/drafts/004_account_commands.sql",
  "database/provider-rollout/apply.sql",
  "database/chat/010_chat_foundation.sql",
  "database/marketplace/020_marketplace_foundation.sql",
  "database/meetings/040_meetings_foundation.sql",
  "database/marketplace/021_request_coordinates.sql",
  "database/marketplace/023_multi_negotiation.sql",
  "database/outcomes/080_sale_confirmation.sql",
  "database/commercial/090_credit_batches.sql",
  "database/commercial/091_buyer_rewards.sql",
  "database/commercial/092_credit_settlement.sql",
  "database/commercial/094_deposit_checkout.sql",
  "database/website_completion/172_website_purchase_status.sql",
  "database/website_completion/173_website_checkout_context.sql",
];

const A = "00000000-0000-4000-8000-00000000000a";
const B = "00000000-0000-4000-8000-00000000000b";
const C = "00000000-0000-4000-8000-00000000000c";
const MB = "10000000-0000-4000-8000-00000000000b";
const MC = "10000000-0000-4000-8000-00000000000c";
const CUSTOMER_B = "cus_sqlintegrationb";
const CUSTOMER_C = "cus_sqlintegrationc";
const SESSION_B = "cs_test_sqlintegrationb";
const SESSION_B2 = "cs_test_sqlintegrationb2";
const SESSION_C = "cs_test_sqlintegrationc";

async function read(relative: string): Promise<string> {
  return await Deno.readTextFile(new URL(relative, ROOT));
}

async function bootstrap(): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(`
    DO $roles$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
    END $roles$;
    DROP SCHEMA IF EXISTS auth CASCADE;
    CREATE SCHEMA auth;
    CREATE TABLE auth.users(id uuid PRIMARY KEY, raw_user_meta_data jsonb);
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
      $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    GRANT USAGE ON SCHEMA auth TO authenticated;
    GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
    DROP SCHEMA IF EXISTS hocalist CASCADE;
    CREATE SCHEMA hocalist;
    REVOKE ALL ON SCHEMA hocalist FROM PUBLIC, anon, authenticated;
  `);
  const signup = await read("database/bootstrap/002_hocalist_signup_routing.sql");
  await db.exec(signup.slice(
    signup.indexOf("CREATE TABLE hocalist.profiles"),
    signup.indexOf("COMMIT;"),
  ));
  for (const path of BOOTSTRAP) await db.exec(await read(path));
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${A}','{}'),('${B}','{}'),('${C}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('10000000-0000-4000-8000-00000000000a','${A}','buyer','active'),
      ('${MB}','${B}','seller','active'),
      ('${MC}','${C}','seller','active');
    INSERT INTO hocalist.profiles(id) SELECT id FROM auth.users ON CONFLICT DO NOTHING;
    INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
      ('10000000-0000-4000-8000-00000000000a','Buyer A'),
      ('${MB}','Seller B'),('${MC}','Seller C');
  `);
  return db;
}

class SqlBackend {
  constructor(
    private readonly db: PGlite,
    private readonly events: Map<string, ObjectMap>,
    private readonly sessions: Map<string, ObjectMap>,
  ) {}

  async user(): Promise<string> {
    throw new Error("not used");
  }

  async rpc(name: string, body: ObjectMap = {}): Promise<unknown> {
    const scalar = async (sql: string, params: unknown[] = []) =>
      ((await this.db.query(sql, params)).rows[0] as { data: unknown }).data;
    switch (name) {
      case "stripe_test_claim":
        return scalar("SELECT hocalist.stripe_test_claim() AS data");
      case "website_checkout_context":
        return scalar("SELECT hocalist.website_checkout_context($1) AS data", [body.p_customer]);
      case "stripe_test_deposit_finish":
        return scalar(
          "SELECT hocalist.stripe_test_deposit_finish($1,$2,$3,$4,$5) AS data",
          [body.p_checkout, body.p_customer, body.p_paid_amount, body.p_reference, body.p_error ?? null],
        );
      case "stripe_test_finish":
        return scalar(
          "SELECT hocalist.stripe_test_finish($1,$2,$3,$4,$5) AS data",
          [
            body.p_token, body.p_event, body.p_customer ?? null,
            body.p_snapshot ? JSON.stringify(body.p_snapshot) : null,
            body.p_error ?? null,
          ],
        );
      default:
        throw new Error(`unexpected rpc ${name}`);
    }
  }

  async stripe(path: string): Promise<ObjectMap> {
    if (path === "account") return { id: ACCOUNT, livemode: false };
    const event = /^events\/(.+)$/.exec(path);
    if (event) return this.events.get(event[1]) ?? {};
    const session = /^checkout\/sessions\/(.+)$/.exec(path);
    if (session) return this.sessions.get(session[1]) ?? {};
    if (path.startsWith("subscriptions?")) return { data: [], has_more: false };
    throw new Error(`unexpected stripe ${path}`);
  }

  asBackend(): Backend {
    return this as unknown as Backend;
  }
}

function reconcile(api: SqlBackend) {
  return createReconcileHandler({ authorized: async () => true, api: api.asBackend() });
}

const post = () => new Request("http://localhost/reconcile", { method: "POST" });

function eventOf(id: string, sessionId: string): ObjectMap {
  return {
    id, object: "event", livemode: false,
    created: Math.floor(Date.now() / 1000),
    type: "checkout.session.completed",
    data: { object: { id: sessionId, livemode: false, customer: null } },
  };
}

function depositSession(
  sessionId: string,
  checkoutId: string,
  customer: string,
  membership: string,
  changes: ObjectMap = {},
): ObjectMap {
  return {
    id: sessionId, livemode: false, customer, mode: "payment",
    status: "complete", payment_status: "paid", amount_total: 2000, currency: "usd",
    payment_intent: `pi_${sessionId.replace(/[^A-Za-z0-9]/g, "")}`,
    metadata: {
      app: "hocalist", kind: "credit_deposit",
      checkout_id: checkoutId, membership_id: membership,
    },
    ...changes,
  };
}

async function beginAndBind(
  db: PGlite, user: string, option: string, key: string, customer: string, session: string,
): Promise<string> {
  const checkout = ((await db.query(
    "SELECT hocalist.stripe_test_deposit_begin($1,$2,$3) AS data",
    [user, option, key],
  )).rows[0] as { data: ObjectMap }).data;
  await db.query(
    "SELECT hocalist.stripe_test_deposit_bind($1,$2,$3,$4)",
    [checkout.checkout_id, customer, session, "https://checkout.stripe.com/c/pay/test"],
  );
  return String(checkout.checkout_id);
}

async function receive(db: PGlite, eventId: string, sessionId: string): Promise<void> {
  await db.query(
    "SELECT hocalist.receive_stripe_test_event($1,$2,$3,$4,$5,$6)",
    [ACCOUNT, eventId, "checkout.session.completed", sessionId, Math.floor(Date.now() / 1000), false],
  );
}

function receiptRow(db: PGlite, eventId: string) {
  return db.query<{ status: string; last_error: string | null }>(
    "SELECT status, last_error FROM hocalist.stripe_test_inbox WHERE event_id=$1", [eventId],
  ).then((result) => result.rows[0]);
}

Deno.test("reconciliation chain: paid deposit credits once, duplicates replay, anomalies quarantine", async () => {
  const db = await bootstrap();
  try {
    const option = ((await db.query(
      `INSERT INTO hocalist.credit_deposit_options(amount_minor,initial_fee_minor,winning_total_minor,rate_version)
       VALUES (2000,155,375,'deposit-20-sql') RETURNING id`)).rows[0] as { id: string }).id;

    // Flow B: paid, duplicate, then an altered amount.
    const checkoutB = await beginAndBind(
      db, B, option, "2f0c9d1a-0000-4000-8000-0000000000b1", CUSTOMER_B, SESSION_B);
    const events = new Map<string, ObjectMap>();
    const sessions = new Map<string, ObjectMap>();
    events.set("evt_sqlb1", eventOf("evt_sqlb1", SESSION_B));
    sessions.set(SESSION_B, depositSession(SESSION_B, checkoutB, CUSTOMER_B, MB));
    const api = new SqlBackend(db, events, sessions);

    await receive(db, "evt_sqlb1", SESSION_B);
    const credited = await reconcile(api)(post());
    assert.equal(credited.status, 200);
    const creditedBody = await credited.json();
    assert.equal(creditedBody.status, "deposit_credited");
    assert.equal(creditedBody.granted, true);
    const batches = await db.query<{
      deposit_reference: string; original_minor: number; balance_minor: number;
      initial_fee_minor: number; winning_total_minor: number; rate_version: string;
    }>(
      `SELECT deposit_reference, original_minor, balance_minor, initial_fee_minor, winning_total_minor, rate_version
       FROM hocalist.credit_batches`);
    assert.equal(batches.rows.length, 1);
    assert.equal(batches.rows[0].original_minor, 2000);
    assert.equal(batches.rows[0].initial_fee_minor, 155);
    assert.equal(batches.rows[0].winning_total_minor, 375);
    assert.equal(batches.rows[0].rate_version, "deposit-20-sql");
    const paymentReference = `pi_${SESSION_B.replace(/[^A-Za-z0-9]/g, "")}`;
    assert.equal(batches.rows[0].deposit_reference, `stripe_test:${paymentReference}`);
    const checkoutRow = await db.query<{ state: string; provider_reference: string | null; credit_batch_id: string | null }>(
      "SELECT state, provider_reference, credit_batch_id FROM hocalist.stripe_test_checkouts WHERE id=$1",
      [checkoutB],
    );
    assert.equal(checkoutRow.rows[0].state, "complete");
    assert.equal(checkoutRow.rows[0].provider_reference, paymentReference);
    assert.ok(checkoutRow.rows[0].credit_batch_id);
    assert.equal((await receiptRow(db, "evt_sqlb1")).status, "processed");

    // Duplicate event for the same paid session: one batch, same checkout.
    events.set("evt_sqlb2", eventOf("evt_sqlb2", SESSION_B));
    await receive(db, "evt_sqlb2", SESSION_B);
    const replay = await reconcile(api)(post());
    assert.equal(replay.status, 200);
    const replayBody = await replay.json();
    assert.equal(replayBody.status, "deposit_credited");
    assert.equal(replayBody.batch_id, creditedBody.batch_id);
    assert.equal(((await db.query("SELECT count(*)::int AS n FROM hocalist.credit_batches")).rows[0] as { n: number }).n, 1);

    // Altered amount on a new bound checkout: quarantined, nothing credited.
    const checkoutB2 = await beginAndBind(
      db, B, option, "2f0c9d1a-0000-4000-8000-0000000000b2", CUSTOMER_B, SESSION_B2);
    events.set("evt_sqlb3", eventOf("evt_sqlb3", SESSION_B2));
    sessions.set(SESSION_B2, depositSession(SESSION_B2, checkoutB2, CUSTOMER_B, MB, { amount_total: 1900 }));
    await receive(db, "evt_sqlb3", SESSION_B2);
    const altered = await reconcile(api)(post());
    assert.equal(altered.status, 503);
    const alteredCheckout = (await db.query(
      "SELECT state FROM hocalist.stripe_test_checkouts WHERE id=$1", [checkoutB2])).rows[0] as { state: string };
    assert.equal(alteredCheckout.state, "expired");
    assert.equal(((await db.query(
      "SELECT requires_review FROM hocalist.stripe_test_customers WHERE customer_id=$1",
      [CUSTOMER_B])).rows[0] as { requires_review: boolean }).requires_review, true);
    assert.equal((await receiptRow(db, "evt_sqlb3")).status, "quarantined");
    assert.equal(((await db.query("SELECT count(*)::int AS n FROM hocalist.credit_batches")).rows[0] as { n: number }).n, 1);

    // Flow C: a paid bound deposit with empty metadata must quarantine, not
    // silently process on the subscription path and consume the receipt.
    const checkoutC = await beginAndBind(
      db, C, option, "2f0c9d1a-0000-4000-8000-0000000000c1", CUSTOMER_C, SESSION_C);
    events.set("evt_sqlc1", eventOf("evt_sqlc1", SESSION_C));
    sessions.set(SESSION_C, depositSession(SESSION_C, checkoutC, CUSTOMER_C, MC, { metadata: {} }));
    await receive(db, "evt_sqlc1", SESSION_C);
    const missing = await reconcile(api)(post());
    assert.equal(missing.status, 503);
    assert.equal((await receiptRow(db, "evt_sqlc1")).status, "quarantined");
    assert.equal(((await db.query(
      "SELECT state FROM hocalist.stripe_test_checkouts WHERE id=$1", [checkoutC])).rows[0] as { state: string }).state, "expired");
    assert.equal(((await db.query("SELECT count(*)::int AS n FROM hocalist.credit_batches")).rows[0] as { n: number }).n, 1);
  } finally {
    await db.close();
  }
});

// Synthetic upgrade proof for the commercial_completion rollout bundle.
//
// Preflight drift refusal, single apply, verify, double-apply refusal and
// containment. PGlite only; never a live database.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createCommercialDb } from './fixture.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

async function expectSqlFailure(promise, messagePart) {
  try {
    await promise;
  } catch (error) {
    assert.match(error.message, new RegExp(messagePart));
    return error;
  }
  throw new Error(`expected SQL failure matching ${messagePart}`);
}

test('the bundle applies once, verifies and refuses a second apply', async () => {
  const db = await createCommercialDb({ completion: false });
  try {
    const preflight = await read('../rollout/preflight.sql');
    const apply = await read('../rollout/apply.sql');
    const verify = await read('../rollout/verify.sql');
    const containment = await read('../rollout/containment.sql');

    // Read-only preflight passes on the clean checkpoint.
    await db.exec(preflight);

    await db.exec(apply);
    // A second apply is refused by the prerequisite hash or the install guard.
    await expectSqlFailure(
      db.exec(apply),
      'Prerequisite drift|already installed|Partial installation|Already installed',
    );
    // The refused transaction must be cleared before the next statement.
    await db.exec('ROLLBACK');
    // The standalone verify block still passes after the apply.
    await db.exec(verify);

    const tables = new Set(
      (await db.query("SELECT tablename FROM pg_tables WHERE schemaname='hocalist'")).rows
        .map((r) => r.tablename));
    for (const table of [
      'entitlement_policy', 'reconciliation_policy', 'reconciliation_runs',
      'reversal_policy', 'payment_reversals', 'ledger_corrections',
      'reversal_events', 'payout_policy', 'payout_attempts',
    ]) {
      assert.ok(tables.has(table), `missing ${table}`);
    }

    // Client reads are reachable; service helpers are not.
    const client = await db.query(
      "SELECT has_function_privilege('authenticated','hocalist.commercial_credit_wallet()','EXECUTE') AS allowed");
    assert.equal(client.rows[0].allowed, true);
    const service = await db.query(
      "SELECT has_function_privilege('authenticated','hocalist.payout_claim_internal(integer,text)','EXECUTE') AS allowed");
    assert.equal(service.rows[0].allowed, false);
    const internal = await db.query(
      "SELECT has_function_privilege('service_role','hocalist.withdrawal_available_minor(uuid)','EXECUTE') AS allowed");
    assert.equal(internal.rows[0].allowed, false);

    // Containment removes the capabilities but preserves the tables.
    await db.exec(containment);
    const revoked = await db.query(
      "SELECT has_function_privilege('authenticated','hocalist.commercial_credit_wallet()','EXECUTE') AS c, has_function_privilege('service_role','hocalist.payout_claim_internal(integer,text)','EXECUTE') AS s");
    assert.equal(revoked.rows[0].c, false);
    assert.equal(revoked.rows[0].s, false);
    const stillThere = await db.query(
      "SELECT to_regclass('hocalist.ledger_corrections') IS NOT NULL AS present");
    assert.equal(stillThere.rows[0].present, true);
  } finally {
    await db.close();
  }
});

test('preflight refuses prerequisite drift', async () => {
  const db = await createCommercialDb({ completion: false });
  try {
    await db.exec(`
      CREATE OR REPLACE FUNCTION hocalist.withdrawal_available_minor(p_user uuid)
      RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
        SELECT 0::bigint;
      $$;
    `);
    const preflight = await read('../rollout/preflight.sql');
    await expectSqlFailure(db.exec(preflight), 'Prerequisite drift');
  } finally {
    await db.close();
  }
});

test('preflight refuses drift in every replaced capacity helper', async () => {
  for (const drift of [
    `CREATE OR REPLACE FUNCTION hocalist.marketplace_seller_plan(p_user uuid)
     RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT 'elite'; $$;`,
    `CREATE OR REPLACE FUNCTION hocalist.marketplace_store_limit(p_user uuid)
     RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT 999; $$;`,
    `CREATE OR REPLACE FUNCTION hocalist.marketplace_weekly_target_limit(p_user uuid)
     RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT 999; $$;`,
    `CREATE OR REPLACE FUNCTION hocalist.withdrawal_request(p_key text, p_amount_minor bigint)
     RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
     BEGIN RETURN jsonb_build_object('status','drift'); END $$;`,
  ]) {
    const db = await createCommercialDb({ completion: false });
    try {
      await db.exec(drift);
      const preflight = await read('../rollout/preflight.sql');
      await expectSqlFailure(db.exec(preflight), 'Prerequisite drift');
    } finally {
      await db.close();
    }
  }
});

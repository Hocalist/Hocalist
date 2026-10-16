// Admin 061-063 reads bundle checks: exact prerequisite hashes, guarded apply +
// verify, double-apply refusal, missing-prerequisite refusal and containment.
// Disposable PGlite only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

const BASELINE = [
  '../../provider-rollout/apply.sql',
  '../../chat/010_chat_foundation.sql',
  '../../marketplace/020_marketplace_foundation.sql',
  '../../meetings/040_meetings_foundation.sql',
  '../../outcomes/080_sale_confirmation.sql',
  '../../commercial/090_credit_batches.sql',
  '../../commercial/091_buyer_rewards.sql',
  '../../notifications/030_notification_inbox.sql',
  '../../notifications/032_push_queue_bridge.sql',
  '../../calls/110_call_signaling.sql',
  '../060_admin_reads.sql',
];

const INSTALLED_FUNCTIONS = [
  'hocalist.admin_credit_summary(integer,uuid)',
  'hocalist.admin_reward_summary(integer,uuid)',
  'hocalist.admin_credit_detail(uuid)',
  'hocalist.admin_delivery_overview()',
  'hocalist.admin_call_settings_history()',
];

async function adminBaseline({ includeCalls = true } = {}) {
  const db = await createDisposableDb();
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  for (const path of BASELINE) {
    if (!includeCalls && path.endsWith('110_call_signaling.sql')) continue;
    await db.exec(await read(path));
  }
  return db;
}

test('admin 061-063 reads bundle is guarded and additive', async (t) => {
  const db = await adminBaseline();
  try {
    await t.test('preflight passes on the exact baseline', async () => {
      await db.exec(await read('../rollout/preflight.sql'));
    });

    await t.test('apply installs and verifies the bundle', async () => {
      await db.exec(await read('../rollout/apply.sql'));
      const state = await db.query(`
        SELECT count(*)::int AS present
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='hocalist' AND p.oid::regprocedure::text = ANY($1::text[])`,
        [INSTALLED_FUNCTIONS],
      );
      assert.equal(state.rows[0].present, INSTALLED_FUNCTIONS.length);
    });

    await t.test('verify is read-only and passes after apply', async () => {
      await db.exec(await read('../rollout/verify.sql'));
    });

    await t.test('a second apply is refused before mutation', async () => {
      let message = '';
      try {
        await db.exec(await read('../rollout/apply.sql'));
      } catch (error) {
        message = error.message;
      }
      await db.exec('ROLLBACK').catch(() => {});
      assert.match(message, /Already installed or partial installation|Prerequisite drift/);
    });

    await t.test('preflight detects a changed 060 prerequisite body', async () => {
      const other = await adminBaseline();
      try {
        await other.exec(
          "CREATE OR REPLACE FUNCTION hocalist.admin_overview() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT '{}'::jsonb $$",
        );
        let message = '';
        try {
          await other.exec(await read('../rollout/preflight.sql'));
        } catch (error) {
          message = error.message;
        }
        assert.match(message, /Prerequisite drift: hocalist.admin_overview/);
      } finally {
        await other.close();
      }
    });

    await t.test('containment revokes the new reads and keeps 060', async () => {
      await db.exec(await read('../rollout/containment.sql'));
      const rows = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.admin_credit_summary(integer,uuid)','EXECUTE') AS credits,
          has_function_privilege('authenticated','hocalist.admin_delivery_overview()','EXECUTE') AS delivery,
          has_function_privilege('authenticated','hocalist.admin_call_settings_history()','EXECUTE') AS calls,
          has_function_privilege('authenticated','hocalist.admin_records(text,integer,uuid,text,text)','EXECUTE') AS records`);
      assert.deepEqual(rows.rows[0], {
        credits: false,
        delivery: false,
        calls: false,
        records: true,
      });
    });
  } finally {
    await db.close();
  }
});

test('admin 061-063 refuses a missing call prerequisite without mutation', async () => {
  const bare = await adminBaseline({ includeCalls: false });
  try {
    let message = '';
    try {
      await bare.exec(await read('../rollout/apply.sql'));
    } catch (error) {
      message = error.message;
    }
    await bare.exec('ROLLBACK').catch(() => {});
    assert.match(message, /Missing prerequisite: hocalist.call_settings_audit/);
    const present = await bare.query(
      "SELECT to_regclass('hocalist.call_settings_audit') AS audit",
    );
    assert.equal(present.rows[0].audit, null);
  } finally {
    await bare.close();
  }
});

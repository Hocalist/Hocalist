// Upgrade bundle checks: exact prerequisites, guarded apply + verify,
// double-apply refusal and containment. Disposable PGlite only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setup } from '../outcomes/tests/fixture.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const baseline = [
  '../marketplace/021_request_coordinates.sql',
  '../outcomes/080_sale_confirmation.sql',
  '../commercial/090_credit_batches.sql',
  '../commercial/091_buyer_rewards.sql',
  '../support/070_support_cases.sql',
  '../notifications/030_notification_inbox.sql',
  '../notifications/031_notification_producers.sql',
];

test('September 26 upgrade bundle is guarded and additive', async (t) => {
  const db = await setup(false);
  try {
    for (const path of baseline) await db.exec(await read(path));

    await t.test('preflight passes on the exact baseline', async () => {
      await db.exec(await read('rollout/preflight.sql'));
    });

    await t.test('apply installs and verifies the upgrade', async () => {
      await db.exec(await read('rollout/apply.sql'));
      const tables = await db.query(`
        SELECT count(*)::int AS n FROM pg_tables WHERE schemaname='hocalist'
          AND tablename IN ('credit_deposit_options','reward_policy',
            'conversation_credit_hook','withdrawal_policy','withdrawal_requests',
            'withdrawal_events','verification_submissions','health_review_notes',
            'account_restrictions','restriction_appeals')`);
      assert.equal(tables.rows[0].n, 10);
    });

    await t.test('verify is read-only and passes after apply', async () => {
      await db.exec(await read('rollout/verify.sql'));
    });

    await t.test('a second apply is refused before mutation', async () => {
      let message = '';
      try {
        await db.exec(await read('rollout/apply.sql'));
      } catch (error) {
        message = error.message;
      }
      await db.exec('ROLLBACK').catch(() => {});
      assert.match(message, /Already installed or partial installation|Prerequisite drift/);
    });

    await t.test('preflight detects a changed prerequisite body', async () => {
      const other = await setup(false);
      try {
        for (const path of baseline) await other.exec(await read(path));
        await other.exec(
          "CREATE OR REPLACE FUNCTION hocalist.marketplace_lead_json(p_request uuid) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$",
        );
        let message = '';
        try {
          await other.exec(await read('rollout/preflight.sql'));
        } catch (error) {
          message = error.message;
        }
        assert.match(message, /Prerequisite drift: hocalist.marketplace_lead_json/);
      } finally {
        await other.close();
      }
    });

    await t.test('containment removes the new client capabilities only', async () => {
      await db.exec(await read('rollout/containment.sql'));
      const rows = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.withdrawal_status()','EXECUTE') AS withdrawal,
          has_function_privilege('authenticated','hocalist.verification_submit(text,jsonb)','EXECUTE') AS verification,
          has_function_privilege('authenticated','hocalist.marketplace_command(text,text,jsonb)','EXECUTE') AS marketplace,
          (SELECT count(*)::int FROM hocalist.withdrawal_requests) AS withdrawals`);
      assert.deepEqual(rows.rows[0], {
        withdrawal: false,
        verification: false,
        marketplace: true,
        withdrawals: 0,
      });
    });
  } finally {
    await db.close();
  }
});

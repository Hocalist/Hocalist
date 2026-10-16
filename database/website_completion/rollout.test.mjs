// Website-completion bundle checks: exact prerequisites, guarded apply +
// verify, double-apply refusal and containment. Disposable PGlite only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setup } from '../outcomes/tests/fixture.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const baseline = [
  '../marketplace/021_request_coordinates.sql',
  '../marketplace/023_multi_negotiation.sql',
  '../outcomes/080_sale_confirmation.sql',
  '../commercial/090_credit_batches.sql',
  '../commercial/091_buyer_rewards.sql',
  '../commercial/092_credit_settlement.sql',
  '../commercial/094_deposit_checkout.sql',
];

test('website completion bundle is guarded and additive', async (t) => {
  const db = await setup(false);
  try {
    for (const path of baseline) await db.exec(await read(path));

    await t.test('preflight passes on the exact baseline', async () => {
      await db.exec(await read('rollout/preflight.sql'));
    });

    await t.test('apply installs and verifies the website contracts', async () => {
      await db.exec(await read('rollout/apply.sql'));
      const rows = await db.query(`
        SELECT
          (SELECT count(*)::int FROM pg_tables
             WHERE schemaname='hocalist' AND tablename IN
               ('website_waitlist_signups','website_waitlist_admissions','website_waitlist_config')) AS tables,
          has_function_privilege('anon','hocalist.website_waitlist_join(text,text,text,text,text)','EXECUTE') AS anon_join,
          has_function_privilege('authenticated','hocalist.website_waitlist_join(text,text,text,text,text)','EXECUTE') AS auth_join,
          has_function_privilege('service_role','hocalist.website_waitlist_join(text,text,text,text,text)','EXECUTE') AS service_join,
          has_function_privilege('authenticated','hocalist.website_purchase_status(uuid)','EXECUTE') AS auth_status,
          has_function_privilege('anon','hocalist.website_purchase_status(uuid)','EXECUTE') AS anon_status,
          has_function_privilege('authenticated','hocalist.stripe_test_portal_access(uuid)','EXECUTE') AS client_portal,
          has_function_privilege('service_role','hocalist.stripe_test_portal_access(uuid)','EXECUTE') AS service_portal,
          has_function_privilege('service_role','hocalist.website_checkout_context(text)','EXECUTE') AS service_context,
          has_function_privilege('authenticated','hocalist.website_checkout_context(text)','EXECUTE') AS client_context`);
      assert.deepEqual(rows.rows[0], {
        tables: 3,
        anon_join: true,
        auth_join: true,
        service_join: false,
        auth_status: true,
        anon_status: false,
        client_portal: false,
        service_portal: true,
        service_context: true,
        client_context: false,
      });
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
      assert.match(message, /Already installed or partial installation/);
    });

    await t.test('preflight detects a missing prerequisite', async () => {
      const other = await setup(false);
      try {
        for (const path of baseline) await other.exec(await read(path));
        await other.exec('DROP TABLE hocalist.stripe_test_customers CASCADE');
        let message = '';
        try {
          await other.exec(await read('rollout/preflight.sql'));
        } catch (error) {
          message = error.message;
        }
        assert.match(message, /Missing prerequisite relation: hocalist\.stripe_test_customers/);
      } finally {
        await other.close();
      }
    });

    await t.test('preflight detects a missing 094 checkout-kind contract', async () => {
      const other = await setup(false);
      try {
        for (const path of baseline.filter((path) => !/094/.test(path))) {
          await other.exec(await read(path));
        }
        let message = '';
        try {
          await other.exec(await read('rollout/preflight.sql'));
        } catch (error) {
          message = error.message;
        }
        assert.match(message, /Missing prerequisite column: stripe_test_checkouts\.kind/);
      } finally {
        await other.close();
      }
    });

    await t.test('containment removes the new capabilities but keeps stored records', async () => {
      const hash = 'a'.repeat(64);
      await db.query(
        `INSERT INTO hocalist.website_waitlist_signups(email,email_normalized,consent_version,source,client_hash)
         VALUES ('kept@example.com','kept@example.com','launch-updates-v1','fixture',$1)`, [hash]);
      await db.query(
        `INSERT INTO hocalist.website_waitlist_admissions(client_hash,window_start,admitted)
         VALUES ($1, date_trunc('hour', now()), 3)`, [hash]);
      await db.exec(await read('rollout/containment.sql'));
      const rows = await db.query(`
        SELECT
          has_function_privilege('anon','hocalist.website_waitlist_join(text,text,text,text,text)','EXECUTE') AS anon_join,
          has_function_privilege('authenticated','hocalist.website_purchase_status(uuid)','EXECUTE') AS auth_status,
          has_function_privilege('service_role','hocalist.stripe_test_portal_access(uuid)','EXECUTE') AS service_portal,
          has_function_privilege('service_role','hocalist.website_checkout_context(text)','EXECUTE') AS service_context,
          (SELECT count(*)::int FROM hocalist.website_waitlist_signups) AS signups,
          (SELECT count(*)::int FROM hocalist.website_waitlist_admissions) AS admissions`);
      assert.deepEqual(rows.rows[0], {
        anon_join: false,
        auth_status: false,
        service_portal: false,
        service_context: false,
        signups: 1,
        admissions: 1,
      });
    });
  } finally {
    await db.close();
  }
});

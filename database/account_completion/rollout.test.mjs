// Account-completion bundle checks: exact prerequisite hashes, guarded apply +
// verify, double-apply refusal, missing-prerequisite refusal and containment.
// Disposable PGlite only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setup } from '../outcomes/tests/fixture.mjs';
import { createAccountCompletionDb } from './tests/fixture.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

test('account-completion bundle is guarded and additive', async (t) => {
  const db = await createAccountCompletionDb({ migrations: [] });
  try {
    await t.test('preflight passes on the exact baseline', async () => {
      await db.exec(await read('rollout/preflight.sql'));
    });

    await t.test('apply installs and verifies the bundle', async () => {
      await db.exec(await read('rollout/apply.sql'));
      const tables = await db.query(`
        SELECT count(*)::int AS n FROM pg_tables WHERE schemaname='hocalist'
          AND tablename IN ('account_consent_documents','account_consents',
            'account_export_requests','account_exports','account_deletion_requests',
            'role_profile_categories','review_evidence_links','evidence_audit',
            'evidence_holds','media_cleanup_audit')`);
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
      const other = await createAccountCompletionDb({ migrations: [] });
      try {
        await other.exec(
          "CREATE OR REPLACE FUNCTION hocalist.media_gateway(p_user uuid, p_action text, p_input jsonb) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ SELECT '{}'::jsonb $$",
        );
        let message = '';
        try {
          await other.exec(await read('rollout/preflight.sql'));
        } catch (error) {
          message = error.message;
        }
        assert.match(message, /Prerequisite drift: hocalist.media_gateway/);
      } finally {
        await other.close();
      }
    });

    await t.test('containment revokes new client capabilities and keeps history', async () => {
      await db.exec(`
        INSERT INTO hocalist.account_consent_documents(id,version,label)
        VALUES ('terms','2026-09','Terms of service');
      `);
      await db.exec(await read('rollout/containment.sql'));
      const rows = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.account_lifecycle_status()','EXECUTE') AS lifecycle,
          has_function_privilege('authenticated','hocalist.profile_categories_update(text,bigint,jsonb)','EXECUTE') AS categories,
          has_function_privilege('authenticated','hocalist.review_evidence_attach(text,jsonb)','EXECUTE') AS evidence,
          has_function_privilege('service_role','hocalist.media_gateway(uuid,text,jsonb)','EXECUTE') AS gateway,
          (SELECT count(*)::int FROM hocalist.account_consent_documents) AS kept`);
      assert.deepEqual(rows.rows[0], {
        lifecycle: false,
        categories: false,
        evidence: false,
        gateway: true,
        kept: 1,
      });
    });
  } finally {
    await db.close();
  }
});

test('account-completion refuses a missing prerequisite without mutation', async () => {
  const bare = await setup(false);
  try {
    let message = '';
    try {
      await bare.exec(await read('132_review_evidence.sql'));
    } catch (error) {
      message = error.message;
    }
    await bare.exec('ROLLBACK').catch(() => {});
    assert.match(message, /review evidence requires media 100, trust 120, support 070 and marketplace 020/);
    const present = await bare.query(
      "SELECT to_regclass('hocalist.review_evidence_links') AS link",
    );
    assert.equal(present.rows[0].link, null);
  } finally {
    await bare.close();
  }
});

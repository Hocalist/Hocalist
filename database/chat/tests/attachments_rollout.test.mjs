// Chat 011 attachments bundle checks: exact prerequisite hashes (accepting the
// media 101 gateway body), guarded apply + verify, double-apply refusal,
// either-apply-order with media 101 and containment. Disposable PGlite only.
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
  '../010_chat_foundation.sql',
  '../../marketplace/020_marketplace_foundation.sql',
  '../../meetings/040_meetings_foundation.sql',
  '../../media/100_private_images.sql',
];

async function chatBaseline() {
  const db = await createDisposableDb();
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  for (const path of BASELINE) await db.exec(await read(path));
  return db;
}

test('chat 011 attachments bundle is guarded and additive', async (t) => {
  const db = await chatBaseline();
  try {
    await t.test('preflight passes on the exact baseline', async () => {
      await db.exec(await read('../attachments-rollout/preflight.sql'));
    });

    await t.test('apply installs and verifies the bundle', async () => {
      await db.exec(await read('../attachments-rollout/apply.sql'));
      const state = await db.query(`
        SELECT
          (SELECT count(*)::int FROM pg_attribute
            WHERE attrelid='hocalist.conversation_messages'::regclass
              AND attname='attachment_media_ids' AND attnotnull AND NOT attisdropped) AS column_count,
          (SELECT count(*)::int FROM pg_trigger
            WHERE tgrelid='hocalist.conversation_messages'::regclass
              AND tgname='chat_message_validate_attachments' AND NOT tgisinternal) AS trigger_count,
          to_regprocedure('hocalist.chat_send_attachment(uuid,text,text,jsonb)') IS NOT NULL AS send_present`);
      assert.deepEqual(state.rows[0], { column_count: 1, trigger_count: 1, send_present: true });
    });

    await t.test('verify is read-only and passes after apply', async () => {
      await db.exec(await read('../attachments-rollout/verify.sql'));
    });

    await t.test('a second apply is refused before mutation', async () => {
      let message = '';
      try {
        await db.exec(await read('../attachments-rollout/apply.sql'));
      } catch (error) {
        message = error.message;
      }
      await db.exec('ROLLBACK').catch(() => {});
      assert.match(message, /Already installed or partial installation|Prerequisite drift/);
    });

    await t.test('preflight detects a changed chat prerequisite body', async () => {
      const other = await chatBaseline();
      try {
        await other.exec(
          "CREATE OR REPLACE FUNCTION hocalist.chat_assert_participant(p_conversation uuid, p_user uuid) RETURNS hocalist.conversation_members LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT null::hocalist.conversation_members $$",
        );
        let message = '';
        try {
          await other.exec(await read('../attachments-rollout/preflight.sql'));
        } catch (error) {
          message = error.message;
        }
        assert.match(message, /Prerequisite drift: hocalist.chat_assert_participant/);
      } finally {
        await other.close();
      }
    });

    await t.test('containment revokes the new capabilities and keeps the column', async () => {
      await db.exec(await read('../attachments-rollout/containment.sql'));
      const rows = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.chat_send_attachment(uuid,text,text,jsonb)','EXECUTE') AS send_allowed,
          has_function_privilege('authenticated','hocalist.chat_validate_attachments()','EXECUTE') AS validator_allowed,
          has_function_privilege('authenticated','hocalist.media_read_chat(uuid,uuid)','EXECUTE') AS helper_allowed,
          has_function_privilege('service_role','hocalist.media_gateway(uuid,text,jsonb)','EXECUTE') AS gateway,
          (SELECT count(*)::int FROM pg_attribute
            WHERE attrelid='hocalist.conversation_messages'::regclass
              AND attname='attachment_media_ids' AND NOT attisdropped) AS kept`);
      assert.deepEqual(rows.rows[0], {
        send_allowed: false,
        validator_allowed: false,
        helper_allowed: false,
        gateway: true,
        kept: 1,
      });
    });
  } finally {
    await db.close();
  }
});

test('media 101 and chat 011 apply in either order', async (t) => {
  const mediaFirst = await chatBaseline();
  try {
    await mediaFirst.exec(await read('../../media/rollout/apply.sql'));
    await t.test('chat 011 applies and verifies after media 101', async () => {
      await mediaFirst.exec(await read('../attachments-rollout/preflight.sql'));
      await mediaFirst.exec(await read('../attachments-rollout/apply.sql'));
      await mediaFirst.exec(await read('../attachments-rollout/verify.sql'));
      await mediaFirst.exec(await read('../../media/rollout/verify.sql'));
    });
  } finally {
    await mediaFirst.close();
  }

  const chatFirst = await chatBaseline();
  try {
    await chatFirst.exec(await read('../attachments-rollout/apply.sql'));
    await t.test('media 101 applies and verifies after chat 011', async () => {
      await chatFirst.exec(await read('../../media/rollout/preflight.sql'));
      await chatFirst.exec(await read('../../media/rollout/apply.sql'));
      await chatFirst.exec(await read('../../media/rollout/verify.sql'));
      await chatFirst.exec(await read('../attachments-rollout/verify.sql'));
    });
  } finally {
    await chatFirst.close();
  }
});

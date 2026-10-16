// Media 101 profile-avatar bundle checks: exact prerequisite hashes, guarded
// apply + verify, double-apply refusal, missing-prerequisite refusal and
// containment. Disposable PGlite only.
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
  '../100_private_images.sql',
];

async function avatarBaseline({ includeMedia = true } = {}) {
  const db = await createDisposableDb();
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  for (const path of BASELINE) {
    if (!includeMedia && path.endsWith('100_private_images.sql')) continue;
    await db.exec(await read(path));
  }
  return db;
}

test('media 101 profile-avatar bundle is guarded and additive', async (t) => {
  const db = await avatarBaseline();
  try {
    await t.test('preflight passes on the exact baseline', async () => {
      await db.exec(await read('../rollout/preflight.sql'));
    });

    await t.test('apply installs and verifies the bundle', async () => {
      await db.exec(await read('../rollout/apply.sql'));
      const state = await db.query(`
        SELECT
          (SELECT count(*)::int FROM pg_attribute
            WHERE attrelid='hocalist.role_profiles'::regclass
              AND attname='image_media_id' AND NOT attisdropped) AS column_count,
          (SELECT count(*)::int FROM pg_trigger
            WHERE tgrelid='hocalist.role_profiles'::regclass
              AND tgname='profile_avatar_validate_reference' AND NOT tgisinternal) AS trigger_count`);
      assert.deepEqual(state.rows[0], { column_count: 1, trigger_count: 1 });
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

    await t.test('preflight detects a changed prerequisite body', async () => {
      const other = await avatarBaseline();
      try {
        await other.exec(
          "CREATE OR REPLACE FUNCTION hocalist.media_gateway(p_user uuid, p_action text, p_input jsonb) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ SELECT '{}'::jsonb $$",
        );
        let message = '';
        try {
          await other.exec(await read('../rollout/preflight.sql'));
        } catch (error) {
          message = error.message;
        }
        assert.match(message, /Prerequisite drift: hocalist.media_gateway/);
      } finally {
        await other.close();
      }
    });

    await t.test('containment revokes the new capabilities and keeps the column', async () => {
      await db.exec(await read('../rollout/containment.sql'));
      const rows = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.profile_avatar_update(text,text,bigint,uuid)','EXECUTE') AS update_allowed,
          has_function_privilege('authenticated','hocalist.member_avatar(uuid)','EXECUTE') AS read_allowed,
          has_function_privilege('authenticated','hocalist.media_read_profile(uuid,uuid)','EXECUTE') AS helper_allowed,
          has_function_privilege('service_role','hocalist.media_gateway(uuid,text,jsonb)','EXECUTE') AS gateway,
          (SELECT count(*)::int FROM pg_attribute
            WHERE attrelid='hocalist.role_profiles'::regclass
              AND attname='image_media_id' AND NOT attisdropped) AS kept`);
      assert.deepEqual(rows.rows[0], {
        update_allowed: false,
        read_allowed: false,
        helper_allowed: false,
        gateway: true,
        kept: 1,
      });
    });
  } finally {
    await db.close();
  }
});

test('media 101 refuses a missing media 100 prerequisite without mutation', async () => {
  const bare = await avatarBaseline({ includeMedia: false });
  try {
    let message = '';
    try {
      await bare.exec(await read('../rollout/apply.sql'));
    } catch (error) {
      message = error.message;
    }
    await bare.exec('ROLLBACK').catch(() => {});
    assert.match(message, /Prerequisite drift: hocalist.media_gateway|Missing prerequisite: hocalist.media_images/);
    const present = await bare.query(
      "SELECT to_regclass('hocalist.media_images') AS media",
    );
    assert.equal(present.rows[0].media, null);
  } finally {
    await bare.close();
  }
});

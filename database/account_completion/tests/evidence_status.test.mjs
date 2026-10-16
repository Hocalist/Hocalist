import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createAccountCompletionDb, callAs, expectRejected } from './fixture.mjs';

test('evidence status restores only the signed-in owner’s saved image references', async () => {
  const db = await createAccountCompletionDb();
  const read = name => readFile(new URL(`../evidence-status-rollout/${name}.sql`, import.meta.url), 'utf8');
  const a = '00000000-0000-4000-8000-00000000000a';
  const b = '00000000-0000-4000-8000-00000000000b';
  const media = '80000000-0000-4000-8000-000000000001';
  try {
    await db.exec(await read('preflight'));
    await db.exec(await read('apply'));
    await db.exec(await read('verify'));
    await db.exec(`INSERT INTO hocalist.media_images(id,owner_user_id,intent_key,purpose,state,content_hash,size_bytes,width,height)
      VALUES ('${media}','${a}',gen_random_uuid(),'review','ready','${'a'.repeat(64)}',2048,64,64);
      INSERT INTO hocalist.verification_submissions(user_id,kind,note,evidence_media_ids)
      VALUES ('${a}','business','Synthetic test evidence only','["${media}"]');`);
    const owner = (await callAs(db, 'authenticated', a, 'SELECT hocalist.verification_status() AS result'))[0].result;
    assert.deepEqual(owner.items[0].evidence_media_ids, [media]);
    assert.equal(owner.items[0].evidence_count, 1);
    const outsider = (await callAs(db, 'authenticated', b, 'SELECT hocalist.verification_status() AS result'))[0].result;
    assert.deepEqual(outsider.items, []);
    await expectRejected(callAs(db, 'anon', '', 'SELECT hocalist.verification_status()'));
    await expectRejected(callAs(db, 'service_role', a, 'SELECT hocalist.verification_status()'));
    await assert.rejects(db.exec(await read('apply')), /definition drift/);
    await db.exec('ROLLBACK');
    await db.exec('GRANT EXECUTE ON FUNCTION hocalist.verification_status() TO authenticated WITH GRANT OPTION');
    await assert.rejects(db.exec(await read('verify')), /ACL drift/);
    await db.exec('REVOKE GRANT OPTION FOR EXECUTE ON FUNCTION hocalist.verification_status() FROM authenticated');
    await db.exec(await read('containment'));
    await db.exec(await read('preflight'));
    assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.verification_submissions')).rows[0].n, 1);
    await db.exec(await read('apply'));
    await db.exec("CREATE OR REPLACE FUNCTION hocalist.verification_status() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$BEGIN RETURN '{}'::jsonb; END $$;");
    await assert.rejects(db.exec(await read('verify')), /definition drift/);
  } finally { await db.close(); }
});

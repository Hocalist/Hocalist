// Disposable PostgreSQL checks for the chat attachment read fence (155).
//
// Proves both supported orders: chat 011 before this bundle, and this bundle
// before chat 011 (deferred, then a standalone re-run installs the fence), with
// avatar 101 and evidence/review 120 present. PGlite is single-connection; not
// live JWT, storage or signed-URL proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { A, B, C, acceptedDeal, callAs, setup } from '../../outcomes/tests/fixture.mjs';
import { endSuite, expectDenied, rpc } from './support.mjs';

const mediaSql = await readFile(
  new URL('../../media/100_private_images.sql', import.meta.url),
  'utf8',
);
const avatarSql = await readFile(
  new URL('../../media/101_profile_avatar.sql', import.meta.url),
  'utf8',
);
const attachmentSql = await readFile(
  new URL('../../chat/011_chat_attachments.sql', import.meta.url),
  'utf8',
);
const reviewSql = await readFile(
  new URL('../../trust/120_review_workflow.sql', import.meta.url),
  'utf8',
);
const supportSql = await readFile(
  new URL('../../support/070_support_cases.sql', import.meta.url),
  'utf8',
);
const blockSql = await readFile(
  new URL('../150_chat_block.sql', import.meta.url),
  'utf8',
);
const fenceSql = await readFile(
  new URL('../155_media_block_fence.sql', import.meta.url),
  'utf8',
);

const intent = '30000000-0000-4000-8000-00000000f002';
const hash = 'a'.repeat(64);

const gateway = (db, user, action, input) =>
  callAs(db, 'service_role', user, 'SELECT hocalist.media_gateway($1,$2,$3) AS v', [
    user,
    action,
    JSON.stringify(input),
  ]);

const readImage = (db, user, image) => gateway(db, user, 'read', { id: image });

const helper = async (db, user, image) =>
  (await db.query('SELECT hocalist.media_read_chat($1,$2) AS v', [user, image])).rows[0].v;

async function seedAttachment(db) {
  const deal = await acceptedDeal(db);
  const begun = await gateway(db, A, 'begin', {
    key: intent,
    hash,
    purpose: 'chat',
  });
  const image = begun[0].v.id;
  await gateway(db, A, 'complete', {
    id: image,
    size: 1000,
    width: 10,
    height: 10,
  });
  await rpc(db, A, 'chat_send_attachment($1,$2,$3,$4)', [
    deal.conversationId,
    'attachment-key-1',
    'Synthetic chat image',
    JSON.stringify([image]),
  ]);
  return { deal, image };
}

test('blocked recipients lose new chat-image reads; the blocker keeps history', async () => {
  const db = await setup();
  try {
    await db.exec(mediaSql);
    await db.exec(avatarSql);
    await db.exec(supportSql);
    await db.exec(reviewSql);
    await db.exec(attachmentSql);
    await db.exec(blockSql);
    await db.exec(fenceSql);
    const { deal, image } = await seedAttachment(db);

    // Before any block: owner and counterpart can read, the outsider cannot.
    assert.equal(await helper(db, A, image), true);
    assert.equal(await helper(db, B, image), true);
    assert.equal(await helper(db, C, image), false);
    assert.equal((await readImage(db, B, image))[0].v.id, image);

    // A blocks B: the blocked recipient is denied a new read URL while the
    // blocker and the owner keep access.
    await rpc(db, A, 'chat_block($1,$2)', [deal.conversationId, null]);
    assert.equal(await helper(db, B, image), false);
    await expectDenied(readImage(db, B, image), /media_access_denied/);
    assert.equal(await helper(db, A, image), true);
    assert.equal((await readImage(db, A, image))[0].v.id, image);

    // Unblock, then B blocks A: B is the blocker and keeps history access. The
    // image owner still reads their own upload through the gateway owner path.
    await rpc(db, A, 'chat_unblock($1)', [deal.conversationId]);
    await rpc(db, B, 'chat_block($1,$2)', [deal.conversationId, null]);
    assert.equal(await helper(db, B, image), true);
    assert.equal((await readImage(db, B, image))[0].v.id, image);
    assert.equal(await helper(db, A, image), false);
    assert.equal((await readImage(db, A, image))[0].v.id, image);
    await rpc(db, B, 'chat_unblock($1)', [deal.conversationId]);

    // Restricted/disabled any-role membership and revoked members stay denied.
    await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE user_id=$1", [B]);
    assert.equal(await helper(db, B, image), false);
    await expectDenied(readImage(db, B, image), /media_access_denied/);
    await db.query("UPDATE hocalist.memberships SET status='active' WHERE user_id=$1", [B]);
    await db.query(
      'UPDATE hocalist.conversation_members SET revoked_at = now() WHERE conversation_id=$1 AND user_id=$2',
      [deal.conversationId, B],
    );
    assert.equal(await helper(db, B, image), false);
    await expectDenied(readImage(db, B, image), /media_access_denied/);

    // The helper stays internal.
    await expectDenied(
      callAs(db, 'authenticated', A, 'SELECT hocalist.media_read_chat($1,$2)', [A, image]),
      /permission denied/,
    );
    await expectDenied(
      callAs(db, 'authenticated', A, 'SELECT hocalist.media_gateway($1,$2,$3)', [
        A,
        'read',
        JSON.stringify({ id: image }),
      ]),
      /permission denied/,
    );
  } finally {
    await endSuite(db);
  }
});

test('the fence applies when this bundle runs before chat 011', async () => {
  const db = await setup();
  try {
    await db.exec(mediaSql);
    await db.exec(blockSql);
    // Bundle before chat 011: the correction is deferred, not an error.
    await db.exec(fenceSql);
    assert.equal(
      (await db.query("SELECT to_regprocedure('hocalist.media_read_chat(uuid,uuid)') IS NULL AS v"))
        .rows[0].v,
      true,
      'the helper is not created before chat 011',
    );

    // chat 011 then installs its own helper; a standalone re-run fences it.
    await db.exec(attachmentSql);
    assert.equal(
      (await db.query(
        "SELECT position('conversation_blocks' in pg_get_functiondef(to_regprocedure('hocalist.media_read_chat(uuid,uuid)'))) = 0 AS v",
      )).rows[0].v,
      true,
      'the 011 helper is unfenced until the correction re-runs',
    );
    await db.exec(fenceSql);

    const { deal, image } = await seedAttachment(db);
    await rpc(db, A, 'chat_block($1,$2)', [deal.conversationId, null]);
    assert.equal(await helper(db, B, image), false);
    await expectDenied(readImage(db, B, image), /media_access_denied/);
    assert.equal(await helper(db, A, image), true);
  } finally {
    await endSuite(db);
  }
});

test('a drifted media_read_chat aborts the correction before any mutation', async () => {
  const db = await setup();
  try {
    await db.exec(mediaSql);
    await db.exec(attachmentSql);
    await db.exec(blockSql);

    // A permissive body that merely mentions the table in a comment is drift,
    // not a corrected definition.
    const permissiveComment = `CREATE OR REPLACE FUNCTION hocalist.media_read_chat(p_user uuid, p_image uuid)
       RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
         SELECT true /* conversation_blocks */
       $$;`;
    await db.exec(permissiveComment);
    await assert.rejects(
      db.exec(fenceSql),
      /Prerequisite drift: hocalist.media_read_chat/,
    );
    await db.exec('ROLLBACK').catch(() => {});
    const afterComment = (
      await db.query(
        "SELECT md5(replace(pg_get_functiondef(to_regprocedure('hocalist.media_read_chat(uuid,uuid)')),chr(13),'')) AS h",
      )
    ).rows[0].h;
    assert.equal(
      (await db.query(
        "SELECT position('SELECT true' in pg_get_functiondef(to_regprocedure('hocalist.media_read_chat(uuid,uuid)'))) > 0 AS v",
      )).rows[0].v,
      true,
      'the rejected body is preserved',
    );

    // A changed predicate that still names the table (but drops the membership,
    // restriction and block constraints) is also drift.
    await db.exec(`CREATE OR REPLACE FUNCTION hocalist.media_read_chat(p_user uuid, p_image uuid)
       RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
         SELECT EXISTS (
           SELECT 1 FROM hocalist.conversation_blocks b
           WHERE b.blocked_user_id = p_user)
       $$;`);
    await assert.rejects(
      db.exec(fenceSql),
      /Prerequisite drift: hocalist.media_read_chat/,
    );
    await db.exec('ROLLBACK').catch(() => {});
    const afterPredicate = (
      await db.query(
        "SELECT md5(replace(pg_get_functiondef(to_regprocedure('hocalist.media_read_chat(uuid,uuid)')),chr(13),'')) AS h",
      )
    ).rows[0].h;
    assert.notEqual(afterPredicate, afterComment);
    assert.equal(
      (await db.query(
        "SELECT position('conversation_blocks' in pg_get_functiondef(to_regprocedure('hocalist.media_read_chat(uuid,uuid)'))) > 0 AS v",
      )).rows[0].v,
      true,
    );
  } finally {
    await endSuite(db);
  }
});

test('the corrected definition re-runs idempotently and rejects grant drift', async () => {
  const db = await setup();
  try {
    await db.exec(mediaSql);
    await db.exec(attachmentSql);
    await db.exec(blockSql);
    await db.exec(fenceSql);
    const corrected = (
      await db.query(
        "SELECT md5(replace(pg_get_functiondef(to_regprocedure('hocalist.media_read_chat(uuid,uuid)')),chr(13),'')) AS h",
      )
    ).rows[0].h;
    assert.equal(corrected, 'b1671c7e2e91a48ace319e3f94583e63');

    // Re-running the correction against the exact corrected body is a no-op.
    await db.exec(fenceSql);
    const rerun = (
      await db.query(
        "SELECT md5(replace(pg_get_functiondef(to_regprocedure('hocalist.media_read_chat(uuid,uuid)')),chr(13),'')) AS h",
      )
    ).rows[0].h;
    assert.equal(rerun, corrected);

    // Grant drift on the helper is caught by the post-apply check even when the
    // body already matches.
    await db.exec(
      'GRANT EXECUTE ON FUNCTION hocalist.media_read_chat(uuid,uuid) TO authenticated',
    );
    await assert.rejects(
      db.exec(fenceSql),
      /media_read_chat must stay an internal helper/,
    );
    await db.exec('ROLLBACK').catch(() => {});
    await db.exec(
      'REVOKE ALL ON FUNCTION hocalist.media_read_chat(uuid,uuid) FROM authenticated',
    );

    // Authorization still behaves after the idempotent re-run.
    const { deal, image } = await seedAttachment(db);
    await rpc(db, A, 'chat_block($1,$2)', [deal.conversationId, null]);
    assert.equal(await helper(db, B, image), false);
    assert.equal(await helper(db, A, image), true);
  } finally {
    await endSuite(db);
  }
});

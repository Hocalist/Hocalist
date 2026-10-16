// Disposable PostgreSQL checks for the role-profile avatar reference (draft
// database/media/101_profile_avatar.sql).
//
// PGlite is single-connection: deterministic SQL proof for ownership,
// purpose/state validation, revision checks, idempotent replay, cross-role
// restrictions, reference reads and media read authorization. It is NOT
// storage, device or public-profile proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const BUYER = '00000000-0000-4000-8000-00000000000a';
const SELLER = '00000000-0000-4000-8000-00000000000b';
const OUTSIDER = '00000000-0000-4000-8000-00000000000c';
const STRANGER = '00000000-0000-4000-8000-00000000000d';
const M_BUYER = '10000000-0000-4000-8000-00000000000a';
const M_SELLER = '10000000-0000-4000-8000-00000000000b';
const M_OUTSIDER = '10000000-0000-4000-8000-00000000000c';
const M_SELLER_BUYER = '10000000-0000-4000-8000-00000000000d';
const AVATAR_READY = '50000000-0000-4000-8000-00000000000a';
const STORE_IMAGE = '50000000-0000-4000-8000-00000000000b';
const AVATAR_PENDING = '50000000-0000-4000-8000-00000000000c';
const OTHER_PROFILE = '50000000-0000-4000-8000-00000000000d';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

async function as(db, role, user, query, params = []) {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return (await db.query(query, params)).rows;
  } finally {
    await db.exec('RESET ROLE');
  }
}

async function expectFailure(promise, code, messagePart) {
  try {
    await promise;
  } catch (error) {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}: ${error.message}`);
    if (messagePart) assert.match(error.message, new RegExp(messagePart));
    return;
  }
  assert.fail(`expected SQLSTATE ${code}`);
}

test('role-profile avatar reference on disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    for (const path of [
      '../../provider-rollout/apply.sql',
      '../../chat/010_chat_foundation.sql',
      '../../marketplace/020_marketplace_foundation.sql',
      '../100_private_images.sql',
      '../101_profile_avatar.sql',
    ]) {
      await db.exec(await read(path));
    }
    await db.exec(`
      INSERT INTO auth.users(id, raw_user_meta_data) VALUES
        ('${BUYER}','{}'),('${SELLER}','{}'),('${OUTSIDER}','{}');
      INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
        ('${M_BUYER}','${BUYER}','buyer','active'),
        ('${M_SELLER}','${SELLER}','seller','active'),
        ('${M_OUTSIDER}','${OUTSIDER}','buyer','active');
      INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
        ('${M_BUYER}','Avatar Buyer'),
        ('${M_SELLER}','Avatar Seller'),
        ('${M_OUTSIDER}','Avatar Outsider');
      INSERT INTO hocalist.media_images(
        id,owner_user_id,intent_key,purpose,state,size_bytes,width,height,content_hash)
      VALUES
        ('${AVATAR_READY}','${SELLER}','60000000-0000-4000-8000-00000000000a','profile','ready',1000,100,100,repeat('a',64)),
        ('${STORE_IMAGE}','${SELLER}','60000000-0000-4000-8000-00000000000b','store','ready',1000,100,100,repeat('b',64)),
        ('${AVATAR_PENDING}','${SELLER}','60000000-0000-4000-8000-00000000000c','profile','pending',null,null,null,repeat('c',64)),
        ('${OTHER_PROFILE}','${SELLER}','60000000-0000-4000-8000-00000000000d','profile','ready',1000,100,100,repeat('d',64));
    `);

    const setAvatar = (user, role, key, expectedRevision, mediaId) =>
      as(
        db,
        'authenticated',
        user,
        'SELECT hocalist.profile_avatar_update($1,$2,$3,$4) AS data',
        [role, key, expectedRevision, mediaId],
      );
    const avatarReference = (user, membership) =>
      as(
        db,
        'authenticated',
        user,
        'SELECT hocalist.member_avatar($1) AS data',
        [membership],
      );

    await t.test('an avatar update is revisioned, replayable and clearable', async () => {
      const first = (
        await setAvatar(SELLER, 'seller', 'avatar-1', 1, AVATAR_READY)
      )[0].data;
      assert.equal(first.membership_id, M_SELLER);
      assert.equal(first.image_media_id, AVATAR_READY);
      assert.equal(first.revision, 2);

      // Same key and payload replays the stored result without another update.
      const replay = (
        await setAvatar(SELLER, 'seller', 'avatar-1', 1, AVATAR_READY)
      )[0].data;
      assert.deepEqual(replay, first);
      const afterReplay = await db.query(
        'SELECT revision FROM hocalist.role_profiles WHERE membership_id = $1',
        [M_SELLER],
      );
      assert.equal(afterReplay.rows[0].revision, 2);

      await expectFailure(
        setAvatar(SELLER, 'seller', 'avatar-1', 1, OTHER_PROFILE),
        'P0001',
        'idempotency_conflict',
      );
      await expectFailure(
        setAvatar(SELLER, 'seller', 'avatar-2', 1, OTHER_PROFILE),
        'P0001',
        'revision_conflict',
      );

      const cleared = (
        await setAvatar(SELLER, 'seller', 'avatar-clear', 2, null)
      )[0].data;
      assert.equal(cleared.image_media_id, null);
      assert.equal(cleared.revision, 3);
      const restored = (
        await setAvatar(SELLER, 'seller', 'avatar-restore', 3, AVATAR_READY)
      )[0].data;
      assert.equal(restored.image_media_id, AVATAR_READY);
      assert.equal(restored.revision, 4);
    });

    await t.test('only ready, profile-purpose, owned images are accepted', async () => {
      await expectFailure(
        setAvatar(BUYER, 'buyer', 'buyer-1', 1, AVATAR_READY),
        '22023',
        'invalid_media_reference',
      );
      await expectFailure(
        setAvatar(SELLER, 'seller', 'seller-store', 4, STORE_IMAGE),
        '22023',
        'invalid_media_reference',
      );
      await expectFailure(
        setAvatar(SELLER, 'seller', 'seller-pending', 4, AVATAR_PENDING),
        '22023',
        'invalid_media_reference',
      );
      await expectFailure(
        setAvatar(SELLER, 'admin', 'seller-role', 4, AVATAR_READY),
        '22023',
        'invalid_field',
      );
    });

    await t.test('another active member reads only the reference and revision', async () => {
      const reference = (await avatarReference(BUYER, M_SELLER))[0].data;
      assert.equal(reference.membership_id, M_SELLER);
      assert.equal(reference.image_media_id, AVATAR_READY);
      assert.equal(reference.revision, 4);

      const rows = await as(
        db,
        'authenticated',
        BUYER,
        'SELECT count(*)::int AS n FROM hocalist.role_profiles WHERE membership_id = $1',
        [M_SELLER],
      );
      assert.equal(rows[0].n, 0, 'RLS keeps another profile row unreadable');
    });

    await t.test('a restriction in either role blocks updates and reads', async () => {
      // BUYER's other role is restricted: writes are refused for the active
      // buyer role and reference reads are refused too.
      await db.exec(`
        INSERT INTO hocalist.memberships(id,user_id,role,status)
        VALUES ('${M_SELLER_BUYER}','${BUYER}','seller','restricted');
      `);
      await expectFailure(
        setAvatar(BUYER, 'buyer', 'restricted-write', 1, AVATAR_READY),
        '42501',
        'account_restricted',
      );
      await expectFailure(
        avatarReference(BUYER, M_SELLER),
        '42501',
        'membership_required',
      );
      await db.exec(`DELETE FROM hocalist.memberships WHERE id='${M_SELLER_BUYER}'`);

      // A restricted target user is never projected even while their other
      // role stays active.
      await db.exec(`
        INSERT INTO hocalist.memberships(id,user_id,role,status)
        VALUES ('${M_SELLER_BUYER}','${SELLER}','buyer','restricted');
      `);
      await expectFailure(
        avatarReference(BUYER, M_SELLER),
        'P0002',
        'profile_not_found',
      );
      await expectFailure(
        as(
          db,
          'service_role',
          'service_role',
          `SELECT hocalist.media_gateway($1,'read',$2::jsonb)`,
          [BUYER, JSON.stringify({ id: AVATAR_READY })],
        ),
        '42501',
        'media_access_denied',
      );
      await db.exec(`DELETE FROM hocalist.memberships WHERE id='${M_SELLER_BUYER}'`);
    });

    await t.test('callers without the selected active membership are refused', async () => {
      await db.exec(
        `INSERT INTO auth.users(id, raw_user_meta_data) VALUES ('${STRANGER}','{}');
         INSERT INTO hocalist.profiles(id) VALUES ('${STRANGER}') ON CONFLICT DO NOTHING;`,
      );
      await expectFailure(
        setAvatar(STRANGER, 'buyer', 'stranger-1', 1, null),
        '42501',
        'membership_required',
      );
      await expectFailure(
        avatarReference(STRANGER, M_SELLER),
        '42501',
        'membership_required',
      );
      await db.exec(
        `UPDATE hocalist.memberships SET status='restricted' WHERE id='${M_OUTSIDER}'`,
      );
      await expectFailure(
        avatarReference(OUTSIDER, M_SELLER),
        '42501',
        'membership_required',
      );
      await db.exec(
        `UPDATE hocalist.memberships SET status='active' WHERE id='${M_OUTSIDER}'`,
      );
    });

    await t.test('the media gateway serves a referenced avatar and nothing more', async () => {
      const image = (
        await as(
          db,
          'service_role',
          'service_role',
          `SELECT hocalist.media_gateway($1,'read',$2::jsonb) AS image`,
          [BUYER, JSON.stringify({ id: AVATAR_READY })],
        )
      )[0].image;
      assert.equal(image.id, AVATAR_READY);

      await expectFailure(
        as(
          db,
          'service_role',
          'service_role',
          `SELECT hocalist.media_gateway($1,'read',$2::jsonb)`,
          [BUYER, JSON.stringify({ id: OTHER_PROFILE })],
        ),
        '42501',
        'media_access_denied',
      );
    });

    await t.test('internal validation and the gateway stay client-denied', async () => {
      const grants = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.profile_avatar_validate()','EXECUTE') AS validate,
          has_function_privilege('authenticated','hocalist.media_gateway(uuid,text,jsonb)','EXECUTE') AS gateway,
          has_function_privilege('anon','hocalist.profile_avatar_update(text,text,bigint,uuid)','EXECUTE') AS anon_update
      `);
      assert.deepEqual(grants.rows[0], {
        validate: false,
        gateway: false,
        anon_update: false,
      });
    });
  } finally {
    await db.close();
  }
});

// Disposable PostgreSQL checks for the request-update lead producer (033) and
// its guarded rollout bundle.
//
// PGlite is single-connection: this is deterministic SQL proof for recipient
// derivation, revision-scoped dedupe keys, the optional leads preference and
// producer privileges. It is NOT push delivery, real JWT or concurrency proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const sql = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const preflightSql = await sql('../request-update-rollout/preflight.sql');
const applyBundleSql = await sql('../request-update-rollout/apply.sql');
const verifySql = await sql('../request-update-rollout/verify.sql');
const containmentSql = await sql('../request-update-rollout/containment.sql');
const draftSql = await sql('../033_request_update_producer.sql');

const block = (text, tag) => {
  const marker = `DO $${tag}$`;
  const start = text.indexOf(marker);
  const endMarker = `$${tag}$;`;
  const end = text.indexOf(endMarker, start) + endMarker.length;
  assert.ok(start >= 0 && end > start, `missing ${tag} block`);
  return text.slice(start, end);
};

async function runScript(db, script) {
  try {
    await db.exec(script);
    return { ok: true };
  } catch (error) {
    await db.exec('ROLLBACK').catch(() => {});
    return { ok: false, error };
  }
}

async function knownBaseline() {
  const db = await createDisposableDb();
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  assert.equal(
    (await runScript(db, await sql('../../provider-rollout/apply.sql'))).ok,
    true,
    'push baseline',
  );
  assert.equal(
    (await runScript(db, await sql('../../chat/010_chat_foundation.sql'))).ok,
    true,
    'chat baseline',
  );
  assert.equal(
    (await runScript(db, await sql('../../marketplace/020_marketplace_foundation.sql'))).ok,
    true,
    'marketplace baseline',
  );
  assert.equal(
    (await runScript(db, await sql('../../meetings/040_meetings_foundation.sql'))).ok,
    true,
    'meetings baseline',
  );
  assert.equal(
    (await runScript(db, await sql('../030_notification_inbox.sql'))).ok,
    true,
    'inbox baseline',
  );
  assert.equal(
    (await runScript(db, await sql('../producers-rollout/apply.sql'))).ok,
    true,
    'producer baseline',
  );
  return db;
}

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const C = '00000000-0000-4000-8000-00000000000c';
const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MC = '10000000-0000-4000-8000-00000000000c';
const CATEGORY = '20000000-0000-4000-8000-000000000001';

async function asRole(db, role, user, body) {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return await body();
  } finally {
    await db.exec('RESET ROLE');
  }
}

const callAs = (db, role, user, statement, params = []) =>
  asRole(db, role, user, async () => (await db.query(statement, params)).rows);

const command = (db, user, op, key, input) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS result',
    [op, key, JSON.stringify(input)],
  );

const setPreferences = (db, user, input) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.notification_preferences_update($1::jsonb) AS data',
    [JSON.stringify(input)],
  );

const readPreferences = (db, user) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.notification_preferences() AS data',
  );

const inbox = (db, user) =>
  db.query(
    `SELECT kind, title, body, source_id, event_key, deep_link, payload
     FROM hocalist.notifications WHERE user_id = $1 ORDER BY created_at, id`,
    [user],
  );

const clearInbox = (db, user) =>
  db.query('DELETE FROM hocalist.notifications WHERE user_id = $1', [user]);

const requestInput = (title) => ({
  kind: 'product',
  title,
  description: 'Good condition',
  condition: 'used',
  quantity: 1,
  budget_minimum_minor: 35000,
  budget_maximum_minor: 48000,
  currency_code: 'USD',
  accepts_higher_offers: false,
  use_home_address: true,
  category_id: CATEGORY,
});

const offerInput = (requestId) => ({
  request_id: requestId,
  price_minor: 42000,
  currency_code: 'USD',
  message: 'Can meet tomorrow.',
  image_media_ids: [],
  schedule_date: '2026-10-01',
  schedule_time: '18:30',
  schedule_timezone: 'America/New_York',
  place_choice: 'specific_place',
  place_label: 'Cross County Mall',
  place_address: '123 Synthetic Ave',
});

async function seed(db) {
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${A}','{}'),('${B}','{}'),('${C}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${MA}','${A}','buyer','active'),
      ('${MB}','${B}','seller','active'),
      ('${MC}','${C}','seller','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
      ('${MA}','Buyer A'),('${MB}','Seller B'),('${MC}','Seller C');
    INSERT INTO hocalist.catalogue_categories(id,label,scope,status,sort_order)
    VALUES ('${CATEGORY}','Electronics','product','active',1);
    INSERT INTO hocalist.profile_contacts(user_id,address_line1) VALUES
      ('${A}','PRIVATE-A');
  `);
}

test('request-update producer rollout bundle', async (t) => {
  await t.test('guard and post-apply blocks are identical across files', () => {
    assert.equal(
      block(draftSql, 'request_update_producer_guard'),
      block(preflightSql, 'request_update_producer_guard'),
    );
    assert.equal(
      block(draftSql, 'hocalist_request_update_producer_postapply'),
      block(verifySql, 'hocalist_request_update_producer_postapply'),
    );
    assert.ok(
      applyBundleSql.includes(draftSql),
      'apply.sql must embed the reviewed draft verbatim',
    );
  });

  await t.test('preflight passes read-only before apply', async () => {
    const db = await knownBaseline();
    try {
      const preflight = await runScript(db, preflightSql);
      assert.equal(preflight.ok, true, preflight.error?.message);
      const state = await db.query(`
        SELECT
          (SELECT count(*)::int FROM pg_attribute
            WHERE attrelid='hocalist.notification_preferences'::regclass
              AND attname='leads' AND NOT attisdropped) AS leads_column,
          (SELECT count(*)::int FROM pg_trigger
            WHERE tgrelid='hocalist.requests'::regclass
              AND tgname='notification_request_update' AND NOT tgisinternal) AS trigger
      `);
      assert.deepEqual(state.rows[0], { leads_column: 0, trigger: 0 });
    } finally {
      await db.close();
    }
  });

  await t.test('apply succeeds, verify passes and repeated apply aborts', async () => {
    const db = await knownBaseline();
    try {
      const applied = await runScript(db, applyBundleSql);
      assert.equal(applied.ok, true, applied.error?.message);
      assert.equal((await runScript(db, verifySql)).ok, true);
      const repeated = await runScript(db, applyBundleSql);
      assert.equal(repeated.ok, false, 'repeated apply must abort');
      assert.match(repeated.error.message, /already exists/);
      assert.equal((await runScript(db, verifySql)).ok, true);
    } finally {
      await db.close();
    }
  });

  await t.test('containment drops the trigger and keeps the functions', async () => {
    const db = await knownBaseline();
    try {
      assert.equal((await runScript(db, applyBundleSql)).ok, true);
      assert.equal((await runScript(db, containmentSql)).ok, true);
      assert.equal((await runScript(db, containmentSql)).ok, true);
      const checks = await db.query(`
        SELECT
          (SELECT count(*)::int FROM pg_trigger
            WHERE tgrelid='hocalist.requests'::regclass
              AND tgname='notification_request_update' AND NOT tgisinternal) AS triggers,
          to_regprocedure('hocalist.notification_on_request_update()') IS NOT NULL AS function_kept
      `);
      assert.deepEqual(checks.rows[0], { triggers: 0, function_kept: true });
      const verifyAfter = await runScript(db, verifySql);
      assert.equal(verifyAfter.ok, false);
      assert.match(verifyAfter.error.message, /missing request-update producer trigger/);
    } finally {
      await db.close();
    }
  });

  await t.test('drift aborts: pre-existing producer function', async () => {
    const db = await knownBaseline();
    try {
      await db.exec(
        'CREATE FUNCTION hocalist.notification_on_request_update() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$',
      );
      const preflight = await runScript(db, preflightSql);
      assert.equal(preflight.ok, false);
      assert.match(preflight.error.message, /already exists/);
    } finally {
      await db.close();
    }
  });

  await t.test('drift aborts: emitter definition changed', async () => {
    const db = await knownBaseline();
    try {
      await db.exec(
        `CREATE OR REPLACE FUNCTION hocalist.notification_emit(
           p_user uuid, p_event uuid, p_kind text, p_source uuid,
           p_title text, p_body text, p_deep_link text, p_payload jsonb)
         RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
         BEGIN RETURN NULL; END; $$`,
      );
      const preflight = await runScript(db, preflightSql);
      assert.equal(preflight.ok, false);
      assert.match(preflight.error.message, /Prerequisite function drift/);
    } finally {
      await db.close();
    }
  });
});

test('request-update producer behavior in disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    await db.exec(await sql('../../provider-rollout/apply.sql'));
    await db.exec(await sql('../../chat/010_chat_foundation.sql'));
    await db.exec(await sql('../../marketplace/020_marketplace_foundation.sql'));
    await db.exec(await sql('../../meetings/040_meetings_foundation.sql'));
    await db.exec(await sql('../030_notification_inbox.sql'));
    await db.exec(await sql('../producers-rollout/apply.sql'));
    await db.exec(await sql('../033_request_update_producer.sql'));
    await seed(db);

    const request = (
      await command(db, A, 'request.create', 'req-update-1', requestInput('iPad Air'))
    )[0].result;
    const offer = (
      await command(db, B, 'offer.submit', 'offer-update-1', offerInput(request.id))
    )[0].result;
    // Clear the buyer's new-offer row so later assertions count only updates.
    await db.exec(`DELETE FROM hocalist.notifications WHERE user_id = '${A}'`);

    await t.test('an updated request notifies only sellers with a live offer', async () => {
      await command(db, A, 'request.update', 'req-update-2', {
        request_id: request.id,
        expected_revision: request.revision,
        ...requestInput('iPad Air, updated condition'),
      });
      const rows = (await inbox(db, B)).rows;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].kind, 'request_update');
      assert.equal(rows[0].source_id, request.id);
      assert.equal(rows[0].deep_link, `hocalist://offers/${offer.id}`);
      assert.equal(rows[0].payload.request_id, request.id);
      assert.equal(rows[0].payload.offer_id, offer.id);
      assert.ok(!rows[0].body.includes('PRIVATE-A'));
      assert.ok(!rows[0].body.includes('123 Synthetic Ave'));
      assert.equal((await inbox(db, C)).rows.length, 0, 'unrelated sellers are not notified');
    });

    await t.test('the same event key never duplicates a row', async () => {
      const key = (
        await db.query('SELECT md5($1)::uuid AS key', [
          `request:update:${request.id}:999:${B}`,
        ])
      ).rows[0].key;
      const emit = (event) =>
        db.query(
          `SELECT hocalist.notification_emit($1,$2,'request_update',$3,$4,$5,$6,$7::jsonb)`,
          [
            B,
            event,
            request.id,
            'Request updated',
            'Deterministic replay check.',
            `hocalist://offers/${offer.id}`,
            JSON.stringify({ request_id: request.id, offer_id: offer.id }),
          ],
        );
      await emit(key);
      await emit(key);
      const count = (
        await db.query(
          `SELECT count(*)::int AS n FROM hocalist.notifications
           WHERE user_id = $1 AND event_key = $2`,
          [B, key],
        )
      ).rows[0].n;
      assert.equal(count, 1, 'replaying one event key inserts once');
      await db.exec(
        `DELETE FROM hocalist.notifications WHERE user_id = '${B}' AND event_key = '${key}'`,
      );
    });

    await t.test('a disabled leads topic suppresses and re-enabling restores', async () => {
      await clearInbox(db, B);
      await setPreferences(db, B, {
        offers: true,
        messages: true,
        deals: true,
        leads: false,
        expected_revision: 0,
      });
      const prefs = (await readPreferences(db, B))[0].data;
      assert.equal(prefs.leads, false);
      await command(db, A, 'request.update', 'req-update-3', {
        request_id: request.id,
        expected_revision: request.revision + 1,
        ...requestInput('iPad Air, budget change'),
      });
      assert.equal((await inbox(db, B)).rows.length, 0, 'disabled topic stays quiet');

      await setPreferences(db, B, {
        offers: true,
        messages: true,
        deals: true,
        leads: true,
        expected_revision: 1,
      });
      await command(db, A, 'request.update', 'req-update-4', {
        request_id: request.id,
        expected_revision: request.revision + 2,
        ...requestInput('iPad Air, final change'),
      });
      assert.equal((await inbox(db, B)).rows.length, 1);
      assert.equal((await inbox(db, B)).rows[0].kind, 'request_update');
    });

    await t.test('an omitted leads field keeps the stored value', async () => {
      await setPreferences(db, B, {
        offers: true,
        messages: true,
        deals: true,
        expected_revision: 2,
      });
      const prefs = (await readPreferences(db, B))[0].data;
      assert.equal(prefs.leads, true, 'legacy payloads do not reset the topic');
    });

    await t.test('a withdrawn offer seller is no longer notified', async () => {
      await command(db, B, 'offer.withdraw', 'withdraw-update-1', {
        offer_id: offer.id,
        expected_offer_revision: offer.revision,
      });
      const before = (await inbox(db, B)).rows.length;
      await command(db, A, 'request.update', 'req-update-5', {
        request_id: request.id,
        expected_revision: request.revision + 3,
        ...requestInput('iPad Air, after withdrawal'),
      });
      assert.equal((await inbox(db, B)).rows.length, before);
    });

    await t.test('producer function has no client execute grant', async () => {
      const grants = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.notification_on_request_update()','EXECUTE') AS authenticated,
          has_function_privilege('anon','hocalist.notification_on_request_update()','EXECUTE') AS anon,
          has_function_privilege('service_role','hocalist.notification_on_request_update()','EXECUTE') AS service
      `);
      assert.deepEqual(grants.rows[0], {
        authenticated: false,
        anon: false,
        service: false,
      });
    });
  } finally {
    await db.close();
  }
});

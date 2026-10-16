// Rollout checks for the generated discovery_completion package, including
// adversarial drift: same-signature authorization replacement, grant and
// policy drift, package body drift, partial installation and non-destructive
// containment.
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
const B = '00000000-0000-4000-8000-00000000000b';
const MB = '10000000-0000-4000-8000-00000000000b';

async function applyPrerequisites(db) {
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  for (const path of [
    '../../provider-rollout/apply.sql',
    '../../chat/010_chat_foundation.sql',
    '../../marketplace/020_marketplace_foundation.sql',
    '../../marketplace/021_request_coordinates.sql',
    '../../marketplace/023_multi_negotiation.sql',
    '../../meetings/040_meetings_foundation.sql',
    '../../outcomes/080_sale_confirmation.sql',
    '../../outcomes/081_purchase_seller.sql',
  ]) {
    await db.exec(await read(path));
  }
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES ('${B}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status)
      VALUES ('${MB}','${B}','seller','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name,area_label)
      VALUES ('${MB}','Seller B','Yonkers, NY');
    INSERT INTO hocalist.catalogue_categories(id,label,scope,status,sort_order)
      VALUES ('20000000-0000-4000-8000-000000000001','Electronics','product','active',1);
  `);
}

async function applyPackage(db) {
  try {
    await db.exec(await read('../rollout/apply.sql'));
  } finally {
    // An aborted migration leaves the session inside a failed transaction.
    await db.exec('ROLLBACK;').catch(() => {});
  }
}

async function expectFails(body, messagePart) {
  try {
    await body();
  } catch (error) {
    assert.match(error.message, new RegExp(messagePart));
    return;
  }
  assert.fail(`expected failure matching ${messagePart}`);
}

async function expectPasses(body) {
  await body();
}

async function runPreflight(db) {
  try {
    await db.exec(
      (await read('../rollout/preflight.sql'))
        .replace(/BEGIN READ ONLY;/, 'BEGIN;')
        .replace(/ROLLBACK;/, ''),
    );
  } finally {
    await db.exec('ROLLBACK;').catch(() => {});
  }
}

async function runVerify(db) {
  try {
    await db.exec(await read('../rollout/verify.sql'));
  } finally {
    await db.exec('ROLLBACK;').catch(() => {});
  }
}

async function hasExecute(db, role, fn) {
  const name = fn.startsWith('hocalist.') ? fn : 'hocalist.' + fn;
  return (await db.query('SELECT has_function_privilege($1,$2,$3) AS ok', [role, name, 'EXECUTE']))
    .rows[0].ok;
}

test('discovery_completion rollout: preflight, apply, verify, refuse and contain', async () => {
  const db = await createDisposableDb();
  try {
    await applyPrerequisites(db);

    await expectPasses(() => runPreflight(db));
    await applyPackage(db);

    // Grants: client functions executable by authenticated only; internal helpers not.
    for (const fn of [
      'discovery_origin_set(text,jsonb)',
      'marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)',
      'review_submit(text,jsonb)',
      'seller_public_reputation(uuid)',
      'buyer_public_profile_consent_set(text,jsonb)',
      'hocatrends_trends(integer)',
      'discovery_open_enquiry(text,jsonb)',
    ]) {
      assert.equal(await hasExecute(db, 'authenticated', fn), true, fn);
      assert.equal(await hasExecute(db, 'anon', fn), false, fn);
      assert.equal(await hasExecute(db, 'service_role', fn), false, fn);
    }
    for (const fn of [
      'discovery_lead_json(uuid,double precision,integer,jsonb)',
      'discovery_assert_active_member(uuid)',
      'review_json(uuid)',
    ]) {
      assert.equal(await hasExecute(db, 'authenticated', fn), false, fn);
    }
    for (const table of ['seller_discovery_origins', 'outcome_reviews', 'buyer_public_profile_consent']) {
      assert.equal(
        (await db.query(
          "SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.'||$1)::regclass", [table])).rows[0].relrowsecurity,
        true,
        table);
    }

    // Second apply is refused cleanly rather than partially repeated.
    await expectFails(() => applyPackage(db), /already installed|already exist/);

    // Containment is grants-only and preserves rows.
    await db.exec(`
      INSERT INTO hocalist.seller_discovery_origins(
        seller_user_id, seller_profile_id, area_label, radius_miles)
      VALUES ('${B}','${MB}','Yonkers, NY',25)`);
    await db.exec(await read('../rollout/containment.sql'));
    assert.equal(await hasExecute(db, 'authenticated', 'review_submit(text,jsonb)'), false);
    assert.equal(await hasExecute(db, 'authenticated', 'hocalist.chat_send(uuid,text,text)'), true);
    const preserved = await db.query(
      'SELECT count(*)::int AS n FROM hocalist.seller_discovery_origins');
    assert.equal(preserved.rows[0].n, 1, 'containment preserves rows');
  } finally {
    await db.close();
  }
});

test('preflight and apply detect a same-signature authorization replacement', async () => {
  const db = await createDisposableDb();
  try {
    await applyPrerequisites(db);
    await db.exec(`
      CREATE OR REPLACE FUNCTION hocalist.marketplace_assert_role(p_user uuid, p_role text)
      RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
      BEGIN
        RETURN '10000000-0000-4000-8000-00000000000b';
      END $$;`);
    await expectFails(() => runPreflight(db), 'prerequisite definition drift: marketplace_assert_role');
    await expectFails(() => applyPackage(db), 'prerequisite definition drift: marketplace_assert_role');
  } finally {
    await db.close();
  }
});

test('preflight detects an unexpected authorization overload', async () => {
  const db = await createDisposableDb();
  try {
    await applyPrerequisites(db);
    await db.exec(`
      CREATE FUNCTION hocalist.marketplace_assert_role(p_user text)
      RETURNS uuid LANGUAGE sql AS $$ SELECT '10000000-0000-4000-8000-00000000000b'::uuid $$;`);
    await expectFails(() => runPreflight(db), 'authorization function overload inventory changed');
  } finally {
    await db.close();
  }
});

test('preflight detects a partial installation', async () => {
  const db = await createDisposableDb();
  try {
    await applyPrerequisites(db);
    await db.exec(await read('../140_discovery_leads.sql'));
    await expectFails(() => runPreflight(db), 'partial installation detected \\(1/7 objects\\)');
  } finally {
    await db.close();
  }
});

test('verify detects grant, policy and package-body drift after apply', async () => {
  const db = await createDisposableDb();
  try {
    await applyPrerequisites(db);
    await applyPackage(db);

    await db.exec('GRANT EXECUTE ON FUNCTION hocalist.review_json(uuid) TO authenticated');
    await expectFails(() => runVerify(db),
      'internal discovery_completion function is executable');
    await db.exec('REVOKE EXECUTE ON FUNCTION hocalist.review_json(uuid) FROM authenticated');

    await db.exec('GRANT SELECT ON hocalist.outcome_reviews TO authenticated');
    await expectFails(() => runVerify(db),
      'unexpected SELECT for authenticated on outcome_reviews');
    await db.exec('REVOKE SELECT ON hocalist.outcome_reviews FROM authenticated');

    await db.exec(
      'CREATE POLICY discovery_permissive ON hocalist.outcome_reviews FOR SELECT TO authenticated USING (true)');
    await expectFails(() => runVerify(db),
      'unexpected package table policy: outcome_reviews');
    await db.exec('DROP POLICY discovery_permissive ON hocalist.outcome_reviews');

    await db.exec(`
      CREATE OR REPLACE FUNCTION hocalist.review_json(p_review uuid)
      RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
        SELECT jsonb_build_object('id', p_review)
      $$;`);
    await expectFails(() => runVerify(db),
      'package definition drift: review_json');

    // The prerequisite authorization helper is also checked post-apply.
    await db.exec(`
      CREATE OR REPLACE FUNCTION hocalist.marketplace_assert_role(p_user uuid, p_role text)
      RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
      BEGIN
        RETURN '10000000-0000-4000-8000-00000000000b';
      END $$;`);
    await expectFails(() => runVerify(db),
      'prerequisite definition drift: marketplace_assert_role');
  } finally {
    await db.close();
  }
});



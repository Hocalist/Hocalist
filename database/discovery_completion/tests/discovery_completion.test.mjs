// Disposable PostgreSQL checks for discovery_completion 140-144.
//
// Scope: seller discovery filters/sorts/cursor/radius, recommended matching,
// confirmed-purchase reviews with idempotency and moderation, Hocatrends and
// Winners projections, buyer public-profile consent, and origin-isolated
// Store/Hocatrends enquiry opening.
//
// PGlite is single-connection: deterministic SQL proof only, not live JWT,
// PostgREST or concurrent-writer proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const A = '00000000-0000-4000-8000-00000000000a'; // buyer
const B = '00000000-0000-4000-8000-00000000000b'; // seller (winner)
const C = '00000000-0000-4000-8000-00000000000c'; // seller (outsider)
const D = '00000000-0000-4000-8000-00000000000d'; // second active buyer
const P = '00000000-0000-4000-8000-00000000000e'; // pending-only membership
const ADM = '00000000-0000-4000-8000-000000000011';
const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MC = '10000000-0000-4000-8000-00000000000c';
const MD = '10000000-0000-4000-8000-00000000000d';
const MP = '10000000-0000-4000-8000-00000000000e';
const MADM = '10000000-0000-4000-8000-000000000011';
const CATEGORY = '20000000-0000-4000-8000-000000000001';
const TOPIC = '20000000-0000-4000-8000-000000000002';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

async function asRole(db, role, user, body) {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return await body();
  } finally {
    await db.exec('RESET ROLE');
  }
}

async function callAs(db, role, user, sql, params = []) {
  return asRole(db, role, user, async () => (await db.query(sql, params)).rows);
}

async function expectRejected(promise, messagePart, code = '42501') {
  try {
    await promise;
  } catch (error) {
    assert.equal(error.code, code, `${messagePart}: got ${error.code} ${error.message}`);
    if (messagePart) assert.match(error.message, new RegExp(messagePart));
    return error;
  }
  assert.fail(`expected SQLSTATE ${code} for ${messagePart}`);
}

const command = (db, user, op, key, input) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS result',
    [op, key, JSON.stringify(input)]);

const leads = (db, user, params = [null, null, null, 50, null, 'newest', null, null, null, null]) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.marketplace_discovery_leads($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) AS data', params);

const originSet = (db, user, key, input) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.discovery_origin_set($1,$2::jsonb) AS data',
    [key, JSON.stringify(input)]);

const recommended = (db, user, limit = 6) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.marketplace_recommended_leads($1) AS data', [limit]);

const reviewStatus = (db, user, request) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.review_status($1) AS data', [request]);

const reviewSubmit = (db, user, key, input) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.review_submit($1,$2::jsonb) AS data',
    [key, JSON.stringify(input)]);

const reviewUpdate = (db, user, key, input) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.review_update($1,$2::jsonb) AS data',
    [key, JSON.stringify(input)]);

const reviewModerate = (db, user, key, input) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.review_moderate($1,$2::jsonb) AS data',
    [key, JSON.stringify(input)]);

const reputation = (db, user, profile) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.seller_public_reputation($1) AS data', [profile]);

const trends = (db, user, limit = 10) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.hocatrends_trends($1) AS data', [limit]);

const winners = (db, user, limit = 10) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.hocatrends_winners($1) AS data', [limit]);

const topicSellers = (db, user, topic, limit = 20) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.hocatrends_topic_sellers($1,$2) AS data', [topic, limit]);

const consentSet = (db, user, key, input) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.buyer_public_profile_consent_set($1,$2::jsonb) AS data',
    [key, JSON.stringify(input)]);

const publicProfile = (db, user, profile) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.buyer_public_profile($1) AS data', [profile]);

const openEnquiry = (db, user, key, input) =>
  callAs(db, 'authenticated', user,
    'SELECT hocalist.discovery_open_enquiry($1,$2::jsonb) AS data',
    [key, JSON.stringify(input)]);

const salePin = (db, user, meeting, action, pin = null) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.sale_pin($1,$2,$3) AS data',
    [meeting, action, pin]);

const propose = (db, user, conversation, key, overrides = {}) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.meeting_propose($1,$2,$3) AS data',
    [conversation, JSON.stringify(schedule(overrides)), key]);

const respond = (db, user, meeting, revision, accept, key) =>
  callAs(db, 'authenticated', user, 'SELECT hocalist.meeting_respond($1,$2,$3,$4) AS data',
    [meeting, accept, revision, key]);

const requestInput = (overrides = {}) => ({
  kind: 'product',
  title: 'iPad Air, 5th gen or newer',
  description: 'Needs to be in good condition.',
  condition: 'used',
  quantity: 1,
  budget_minimum_minor: 35000,
  budget_maximum_minor: 48000,
  currency_code: 'USD',
  accepts_higher_offers: false,
  use_home_address: false,
  address_line1: 'Synthetic place',
  city: 'Yonkers',
  region: 'NY',
  country_code: 'US',
  latitude: 40.93,
  longitude: -73.9,
  category_id: CATEGORY,
  ...overrides,
});

const offerInput = (requestId, overrides = {}) => ({
  request_id: requestId,
  price_minor: 42000,
  currency_code: 'USD',
  message: 'Can meet tomorrow.',
  image_media_ids: [],
  schedule_date: '2026-11-05',
  schedule_time: '18:30',
  schedule_timezone: 'America/New_York',
  place_choice: 'specific_place',
  place_label: 'Cross County Mall',
  place_address: '123 Synthetic Ave',
  ...overrides,
});

const schedule = (overrides = {}) => ({
  schedule_date: '2026-11-05',
  schedule_time: '18:30',
  schedule_timezone: 'America/New_York',
  place_choice: 'specific_place',
  place_label: 'Cross County Mall',
  place_address: '123 Synthetic Ave',
  ...overrides,
});

async function seed(db) {
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${A}','{}'),('${B}','{}'),('${C}','{}'),('${D}','{}'),
      ('${P}','{}'),('${ADM}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${MA}','${A}','buyer','active'),
      ('${MB}','${B}','seller','active'),
      ('${MC}','${C}','seller','active'),
      ('${MD}','${D}','buyer','active'),
      ('${MP}','${P}','buyer','pending'),
      ('${MADM}','${ADM}','seller','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name,area_label) VALUES
      ('${MA}','Buyer A','Yonkers, NY'),('${MB}','Seller B','Yonkers, NY'),
      ('${MC}','Seller C','Queens, NY'),('${MD}','Buyer D','Queens, NY'),
      ('${MP}','Pending Buyer','Queens, NY'),('${MADM}','Admin','Yonkers, NY');
    INSERT INTO hocalist.platform_admins(user_id) VALUES ('${ADM}');
    INSERT INTO hocalist.catalogue_categories(id,label,scope,status,sort_order)
      VALUES ('${CATEGORY}','Electronics','product','active',1),
             ('${TOPIC}','Home services','service','active',2);
  `);
}

async function applyPackage(db) {
  for (const path of [
    '../../provider-rollout/apply.sql',
    '../../chat/010_chat_foundation.sql',
    '../../marketplace/020_marketplace_foundation.sql',
    '../../marketplace/021_request_coordinates.sql',
    '../../marketplace/023_multi_negotiation.sql',
    '../../meetings/040_meetings_foundation.sql',
    '../../outcomes/080_sale_confirmation.sql',
    '../../outcomes/081_purchase_seller.sql',
    '../140_discovery_leads.sql',
    '../141_recommended_leads.sql',
    '../142_reviews.sql',
    '../143_trends_consent.sql',
    '../144_discovery_enquiry.sql',
    '../145_seller_outcomes.sql',
    '../146_topic_sellers.sql',
  ]) {
    await db.exec(await read(path));
  }
}

async function createDb() {
  const db = await createDisposableDb();
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  await applyPackage(db);
  await seed(db);
  return db;
}

// Creates a confirmed purchase for buyer A / seller B and returns the ids the
// review and winners suites need.
async function confirmPurchase(db, { title = 'iPad Air, 5th gen or newer', category = CATEGORY } = {}) {
  const request = (await command(db, A, 'request.create', `req-${title}`,
    requestInput({ title, category_id: category })))[0].result;
  const offer = (await command(db, B, 'offer.submit', `offer-${title}`,
    offerInput(request.id)))[0].result;
  await command(db, A, 'offer.select', `select-${title}`, {
    offer_id: offer.id,
    revision_id: offer.revisions[0].id,
    expected_offer_revision: offer.revision,
  });
  const conversation = (await command(db, A, 'conversation.open_offer', `open-${title}`, {
    offer_id: offer.id,
  }))[0].result.conversation_id;
  const proposed = (await propose(db, A, conversation, `propose-${title}`))[0].data;
  const accepted = (await respond(db, B, proposed.id, proposed.revision, true,
    `accept-${title}`))[0].data;
  await command(db, A, 'purchase.select', `purchase-${title}`, {
    offer_id: offer.id,
    expected_offer_revision: offer.revision + 1,
  });
  const pin = (await salePin(db, A, accepted.id, 'display'))[0].data;
  const confirmed = (await salePin(db, B, accepted.id, 'verify', pin.pin))[0].data;
  assert.equal(confirmed.status, 'confirmed');
  return { request, offer, conversation, meeting: accepted.id };
}

test('missing buyer area never creates a service-area match', async () => {
  const db = await createDb();
  try {
    const request = (await command(db, A, 'request.create', 'missing-area', requestInput()))[0].result;
    await db.exec(`UPDATE hocalist.requests SET city = NULL, region = NULL, latitude = NULL, longitude = NULL WHERE id = '${request.id}';
      UPDATE hocalist.role_profiles SET area_label = '' WHERE membership_id = '${MA}';
      UPDATE hocalist.role_profiles SET area_label = 'United States' WHERE membership_id = '${MC}'`);
    assert.equal((await leads(db, C))[0].data.items.find(row => row.request_id === request.id).match_percent, 30,
      'historical blank-area defect is independently reproduced');
    await db.exec(await read('../../runtime_repairs/area-match-preflight.sql'));
    await db.exec(await read('../../runtime_repairs/191_discovery_area_match.sql'));
    await db.exec(await read('../../runtime_repairs/area-match-verify.sql'));
    const page = (await leads(db, C))[0].data;
    const item = page.items.find(row => row.request_id === request.id);
    assert.ok(item);
    assert.equal(item.match_percent, null);
    assert.deepEqual(item.match_reasons, []);
    const recommendations = (await recommended(db, C))[0].data;
    assert.equal(recommendations.items.length, 0);
    await db.exec(`UPDATE hocalist.role_profiles SET area_label = '  ' WHERE membership_id = '${MA}';
      UPDATE hocalist.requests SET city = '', region = '  ' WHERE id = '${request.id}'`);
    assert.equal((await leads(db, C))[0].data.items.find(row => row.request_id === request.id).match_percent, null);
    await db.exec(`UPDATE hocalist.requests SET city = 'United States' WHERE id = '${request.id}'`);
    assert.equal((await leads(db, C))[0].data.items.find(row => row.request_id === request.id).match_percent, 30,
      'known matching city still supplies the service-area match');
    await assert.rejects(db.exec(await read('../../runtime_repairs/191_discovery_area_match.sql')), /definition drift/);
    await db.exec('ROLLBACK');
    await db.exec(`GRANT EXECUTE ON FUNCTION hocalist.marketplace_recommended_leads(integer) TO anon`);
    await assert.rejects(db.exec(await read('../../runtime_repairs/area-match-verify.sql')), /privilege drift/);
    await db.exec('ROLLBACK');
  } finally { await db.close(); }
});

test('seller discovery: filters, stable cursors, radius and privacy', async (t) => {
  const db = await createDb();
  try {
    await db.exec(`
      UPDATE hocalist.store_listings SET status='active', moderation_status='approved'
        WHERE seller_user_id='${B}'`);
    for (const [index, extra] of [
      { area: 'Yonkers', lat: 40.94 },
      { area: 'Queens', lat: 40.72, lng: -73.79 },
      { area: 'Yonkers', lat: 40.95 },
    ].entries()) {
      await command(db, A, 'request.create', `req-${index}`, requestInput({
        title: `Request ${index}`,
        city: extra.area,
        latitude: extra.lat,
        longitude: extra.lng ?? -73.9,
      }));
    }

    await t.test('non-sellers (buyer/outsider role) cannot read discovery', async () => {
      await expectRejected(leads(db, A), 'role_not_active');
      await expectRejected(
        callAs(db, 'anon', '',
          'SELECT hocalist.marketplace_discovery_leads(NULL,NULL,NULL,50,NULL,NULL,NULL,NULL,NULL,NULL) AS data'),
        'permission denied for schema hocalist', '42501');
    });

    await t.test('origin write is owner-scoped, validated and idempotent', async () => {
      await expectRejected(
        originSet(db, A, 'origin-a', { area_label: 'Yonkers, NY' }),
        'role_not_active', '42501');
      await expectRejected(
        originSet(db, B, 'origin-bad', { latitude: 40.9, radius_miles: 0 }),
        'invalid_field', '22023');
      const first = (await originSet(db, B, 'origin-1', {
        area_label: 'Yonkers, NY', latitude: 40.93, longitude: -73.9, radius_miles: 50,
      }))[0].data;
      assert.equal(first.coordinates_present, true);
      assert.equal(first.revision, 1);
      const replay = (await originSet(db, B, 'origin-1', {
        area_label: 'Yonkers, NY', latitude: 40.93, longitude: -73.9, radius_miles: 50,
      }))[0].data;
      assert.equal(replay.revision, 1, 'unchanged replay keeps one intent');
      await expectRejected(
        originSet(db, B, 'origin-1', { area_label: 'Queens, NY' }),
        'idempotency_conflict', 'P0001');
    });

    await t.test('cursor walk returns every lead once and rejects tampering', async () => {
      const seen = new Set();
      const metrics = new Set();
      let cursor = null;
      for (let page = 0; page < 10; page++) {
        const data = (await leads(db, B, [
          null, null, null, 1, cursor, 'recommended', 50, null, null, null,
        ]))[0].data;
        for (const item of data.items) {
          assert.equal(seen.has(item.request_id), false, 'no duplicate across pages');
          seen.add(item.request_id);
          metrics.add(item.match_percent);
        }
        cursor = data.next_cursor;
        if (!cursor) break;
      }
      assert.equal(seen.size, 3, 'all three eligible requests returned');
      const newest = (await leads(db, B, [null, null, null, 2, null, 'newest', 50, null, null, null]))[0].data;
      assert.ok(newest.next_cursor);
      await expectRejected(
        leads(db, B, [null, null, null, 2, newest.next_cursor, 'closest', 50, null, null, null]),
        'invalid_cursor', '22023');
      await expectRejected(
        leads(db, B, [null, null, null, 2, 'newest|not-a-number|not-a-uuid', 'newest', 50, null, null, null]),
        'invalid_cursor', '22023');
    });

    await t.test('filters and sorts are server-authorized', async () => {
      const category = (await leads(db, B, [
        null, CATEGORY, null, 50, null, 'newest', null, null, null, null,
      ]))[0].data;
      assert.equal(category.items.length, 3);
      const none = (await leads(db, B, [
        null, TOPIC, null, 50, null, 'newest', null, null, null, null,
      ]))[0].data;
      assert.equal(none.items.length, 0);
      const searched = (await leads(db, B, [
        null, null, null, 50, null, 'newest', null, 'Request 1', null, null,
      ]))[0].data;
      assert.deepEqual(searched.items.map((row) => row.title), ['Request 1']);
      const budgeted = (await leads(db, B, [
        null, null, null, 50, null, 'budget', null, null, 60000, null,
      ]))[0].data;
      assert.equal(budgeted.items.length, 0, 'no request budget reaches the 60000 floor');
      await expectRejected(
        leads(db, B, [null, null, null, 50, null, 'drop-table', null, null, null, null]),
        'invalid_field: sort', '22023');
    });

    await t.test('radius discovery narrows to the declared area and apportions distance', async () => {
      const nearby = (await leads(db, B, [
        null, null, null, 50, null, 'closest', 5, null, null, null,
      ]))[0].data;
      assert.equal(nearby.items.length, 2, 'the Queens request is outside 5 miles');
      assert.equal(nearby.items[0].distance_miles != null, true);
      for (const item of nearby.items) {
        assert.ok(item.distance_miles <= 5);
        assert.ok(!Object.hasOwn(item, 'latitude'));
        assert.ok(!Object.hasOwn(item, 'longitude'));
        assert.ok(!Object.hasOwn(item, 'address_line1'));
      }
      const manual = (await leads(db, B, [
        null, null, 'Queens', 50, null, 'newest', null, null, null, null,
      ]))[0].data;
      assert.equal(manual.items.length >= 1, true, 'manual area fallback keeps working');
    });

    await t.test('recommended leads explain their basis and stay honest when absent', async () => {
      await db.exec(`UPDATE hocalist.role_profiles SET area_label = NULL WHERE membership_id = '${MC}'`);
      const empty = (await recommended(db, C))[0].data;
      assert.equal(empty.items.length, 0);
      assert.equal(empty.unavailable_reason, 'no_matching_basis');
      await db.exec(`UPDATE hocalist.role_profiles SET area_label = 'Queens, NY' WHERE membership_id = '${MC}'`);

      await db.exec(`
        INSERT INTO hocalist.store_listings(
          seller_user_id, seller_profile_id, kind, title, category_id, category_label,
          price_label, status, moderation_status)
        VALUES ('${B}','${MB}','product','iPad listing','${CATEGORY}','Electronics',
                'From $50','active','approved')`);
      const withListing = (await recommended(db, B))[0].data;
      assert.equal(withListing.items.length >= 1, true);
      assert.equal(withListing.basis.declared_categories[0].label, 'Electronics');
      for (const item of withListing.items) {
        assert.ok(item.match_percent >= 50);
        assert.ok(item.match_reasons.includes('Matches your declared category'));
      }
    });
  } finally {
    await db.close();
  }
});

test('reviews: eligibility, idempotent submission, moderation and aggregate', async (t) => {
  const db = await createDb();
  try {
    const { request, meeting } = await confirmPurchase(db);

    await t.test('eligibility is buyer-only and requires a confirmed purchase', async () => {
      const confirmed = (await reviewStatus(db, A, request.id))[0].data;
      assert.equal(confirmed.eligible, true, 'the purchase is confirmed above');
      assert.equal(confirmed.reason, 'confirmed_purchase');

      const unconfirmed = (await command(db, A, 'request.create', 'req-unconfirmed',
        requestInput({ title: 'Never purchased' })))[0].result;
      const status = (await reviewStatus(db, A, unconfirmed.id))[0].data;
      assert.equal(status.eligible, false);
      assert.equal(status.reason, 'not_confirmed');
      await expectRejected(
        reviewSubmit(db, A, 'review-unconfirmed', {
          request_id: unconfirmed.id, rating: 5, body: 'Nice',
        }),
        'review_not_eligible', 'P0001');
    });

    await t.test('a seller or outsider cannot submit or inspect the review', async () => {
      // Authorization precedes eligibility: a seller-only identity is refused
      // before any outcome data is read or replayed.
      await expectRejected(
        reviewSubmit(db, B, 'review-seller', {
          request_id: request.id, rating: 5, body: 'Self review',
        }),
        'role_not_active', '42501');
      await expectRejected(
        reviewStatus(db, C, request.id),
        'role_not_active', '42501');
      // Another active buyer is not the outcome buyer: an honest
      // not_participant view with no review content.
      const otherBuyer = (await reviewStatus(db, D, request.id))[0].data;
      assert.equal(otherBuyer.eligible, false);
      assert.equal(otherBuyer.reason, 'not_participant');
      assert.equal(otherBuyer.review, null);
    });

    await t.test('restricted, disabled and pending memberships are refused', async () => {
      await db.exec(
        `UPDATE hocalist.memberships SET status='restricted' WHERE id='${MA}'`);
      await expectRejected(reviewStatus(db, A, request.id), 'account_restricted', '42501');
      await expectRejected(
        reviewSubmit(db, A, 'review-restricted', {
          request_id: request.id, rating: 5, body: 'Should be refused',
        }),
        'account_restricted', '42501');
      await expectRejected(
        consentSet(db, A, 'consent-restricted', {
          is_public: true, show_display_name: true, show_area: true, show_categories: true,
        }),
        'account_restricted', '42501');
      await expectRejected(trends(db, A), 'account_restricted', '42501');
      await db.exec(
        `UPDATE hocalist.memberships SET status='active' WHERE id='${MA}'`);

      await db.exec(
        `UPDATE hocalist.memberships SET status='disabled' WHERE id='${MD}'`);
      await expectRejected(winners(db, D), 'account_restricted', '42501');
      await db.exec(
        `UPDATE hocalist.memberships SET status='active' WHERE id='${MD}'`);

      // A pending-only identity has no active membership and no buyer role.
      await expectRejected(trends(db, P), 'active_membership_required', '42501');
      await expectRejected(winners(db, P), 'active_membership_required', '42501');
      await expectRejected(
        reviewSubmit(db, P, 'review-pending', {
          request_id: request.id, rating: 5, body: 'Pending',
        }),
        'role_not_active', '42501');
    });

    await t.test('a restricted second membership blocks a dual-role identity', async () => {
      await db.exec(`
        INSERT INTO hocalist.memberships(id,user_id,role,status,created_at)
          VALUES ('20000000-0000-4000-8000-0000000000bb','${B}','buyer','restricted',
                  now() - interval '2 days');
        INSERT INTO hocalist.role_profiles(membership_id,display_name)
          VALUES ('20000000-0000-4000-8000-0000000000bb','Buyer-side B');`);
      await expectRejected(trends(db, B), 'account_restricted', '42501');
      await expectRejected(winners(db, B), 'account_restricted', '42501');
      await expectRejected(topicSellers(db, B, TOPIC), 'account_restricted', '42501');
      await expectRejected(
        callAs(db, 'authenticated', B,
          'SELECT hocalist.discovery_origin_json() AS data'),
        'account_restricted', '42501');
      await expectRejected(reputation(db, B, MB), 'account_restricted', '42501');
      await db.exec(`
        DELETE FROM hocalist.role_profiles
          WHERE membership_id='20000000-0000-4000-8000-0000000000bb';
        DELETE FROM hocalist.memberships
          WHERE id='20000000-0000-4000-8000-0000000000bb';`);
    });

    let reviewId;
    await t.test('submission is one authoritative review with safe retries', async () => {
      const input = { request_id: request.id, rating: 4, body: 'Clear photos and fair price.' };
      const first = (await reviewSubmit(db, A, 'review-key-1', input))[0].data;
      reviewId = first.id;
      assert.equal(first.rating, 4);
      assert.equal(first.status, 'published');
      const replay = (await reviewSubmit(db, A, 'review-key-1', input))[0].data;
      assert.equal(replay.id, reviewId, 'same intent key returns the same review');
      await expectRejected(
        reviewSubmit(db, A, 'review-key-1', { ...input, rating: 1 }),
        'idempotency_conflict', 'P0001');
      const duplicate = (await reviewSubmit(db, A, 'review-key-2', input))[0].data;
      assert.equal(duplicate.id, reviewId, 'identical content never duplicates');
      await expectRejected(
        reviewSubmit(db, A, 'review-key-3', { ...input, rating: 2 }),
        'review_exists', 'P0001');
      const count = await db.query('SELECT count(*)::int AS n FROM hocalist.outcome_reviews');
      assert.equal(count.rows[0].n, 1);
    });

    await t.test('update respects expected revision and moderators only', async () => {
      const updated = (await reviewUpdate(db, A, 'review-update-1', {
        review_id: reviewId, expected_revision: 1, rating: 5, body: 'Updated after the meetup.',
      }))[0].data;
      assert.equal(updated.revision, 2);
      assert.equal(updated.rating, 5);
      await expectRejected(
        reviewUpdate(db, A, 'review-update-2', {
          review_id: reviewId, expected_revision: 1, rating: 3, body: 'Stale',
        }),
        'revision_conflict', 'P0001');
      await expectRejected(
        reviewModerate(db, C, 'review-mod-seller', {
          review_id: reviewId, expected_revision: 2, status: 'hidden', reason: 'Not allowed',
        }),
        'admin', '42501');
      const hidden = (await reviewModerate(db, ADM, 'review-mod-1', {
        review_id: reviewId, expected_revision: 2, status: 'hidden', reason: 'Reported and under review',
      }))[0].data;
      assert.equal(hidden.status, 'hidden');
      const rep = (await reputation(db, A, MB))[0].data;
      assert.equal(rep.rating_count, 0, 'hidden reviews leave the aggregate');
      assert.equal(rep.completed_deals, 1);
    });

    await t.test('public aggregate exposes published reviews without private identity', async () => {
      const republished = (await reviewModerate(db, ADM, 'review-mod-2', {
        review_id: reviewId, expected_revision: 3, status: 'published', reason: 'No violation found',
      }))[0].data;
      assert.equal(republished.status, 'published');
      const rep = (await reputation(db, A, MB))[0].data;
      assert.equal(rep.rating_count, 1);
      assert.equal(rep.rating_sum, 5);
      assert.equal(rep.completed_deals, 1);
      const serialized = JSON.stringify(rep);
      assert.doesNotMatch(serialized, new RegExp(A));
      assert.doesNotMatch(serialized, /@|phone|address_line1|latitude|longitude/i);
      assert.equal(rep.reviews[0].reviewer_label, 'Hocalist buyer');
    });

    await t.test('buyer consent switches the reviewer label explicitly', async () => {
      const consent = (await consentSet(db, A, 'consent-1', {
        is_public: true, show_display_name: true, show_area: false, show_categories: false,
      }))[0].data;
      assert.equal(consent.is_public, true);
      const rep = (await reputation(db, C, MB))[0].data;
      assert.equal(rep.reviews[0].reviewer_label, 'Buyer A');
      const profile = (await publicProfile(db, C, MA))[0].data;
      assert.equal(profile.available, true);
      assert.equal(profile.display_name, 'Buyer A');
      assert.equal(profile.area_label, null, 'area stays hidden until enabled');
      assert.ok(!Object.hasOwn(profile, 'address_line1'));
      const closed = (await consentSet(db, A, 'consent-2', {
        is_public: false, show_display_name: false, show_area: false, show_categories: false,
      }))[0].data;
      assert.equal(closed.is_public, false);
      const after = (await publicProfile(db, C, MA))[0].data;
      assert.equal(after.available, false);
      assert.equal(after.reason, 'consent_withheld');
    });

    await t.test('mixed consent flags never leak beyond the master opt-in', async () => {
      // Withdrawn master consent with an area opt-in still leaks nothing.
      await consentSet(db, A, 'consent-mixed-1', {
        is_public: false, show_display_name: false, show_area: true, show_categories: false,
      });
      const withdrawn = (await winners(db, D))[0].data;
      assert.equal(withdrawn.items.length, 1);
      assert.equal(withdrawn.items[0].buyer_label, 'Hocalist buyer');
      assert.equal(withdrawn.items[0].area_label, null);
      const withheldProfile = (await publicProfile(db, D, MA))[0].data;
      assert.equal(withheldProfile.available, false);
      assert.equal(withheldProfile.reason, 'consent_withheld');
      const withheldRep = (await reputation(db, D, MB))[0].data;
      assert.equal(withheldRep.reviews[0].reviewer_label, 'Hocalist buyer');

      // Master consent on with only the area opt-in exposes the area and
      // nothing else.
      await consentSet(db, A, 'consent-mixed-2', {
        is_public: true, show_display_name: false, show_area: true, show_categories: true,
      });
      const areaOnly = (await winners(db, D))[0].data;
      assert.equal(areaOnly.items[0].buyer_label, 'Hocalist buyer');
      assert.equal(areaOnly.items[0].area_label, 'Yonkers, NY');
      const areaProfile = (await publicProfile(db, D, MA))[0].data;
      assert.equal(areaProfile.available, true);
      assert.equal(areaProfile.display_name, null);
      assert.equal(areaProfile.area_label, 'Yonkers, NY');

      // Explicit withdrawal removes the area again.
      await consentSet(db, A, 'consent-mixed-3', {
        is_public: false, show_display_name: false, show_area: false, show_categories: false,
      });
      const afterWithdrawal = (await winners(db, D))[0].data;
      assert.equal(afterWithdrawal.items[0].area_label, null);
      assert.equal(afterWithdrawal.items[0].buyer_label, 'Hocalist buyer');
    });

    await t.test('reviewer labels select the buyer role for dual-role identities', async () => {
      await db.exec(`
        INSERT INTO hocalist.memberships(id,user_id,role,status,created_at)
          VALUES ('20000000-0000-4000-8000-0000000000aa','${A}','seller','active',
                  now() - interval '2 days');
        INSERT INTO hocalist.role_profiles(membership_id,display_name,area_label)
          VALUES ('20000000-0000-4000-8000-0000000000aa','Seller-side A','Queens, NY');`);
      await consentSet(db, A, 'consent-dual', {
        is_public: true, show_display_name: true, show_area: false, show_categories: false,
      });
      const rep = (await reputation(db, D, MB))[0].data;
      assert.equal(
        rep.reviews[0].reviewer_label,
        'Buyer A',
        'the buyer-role profile is selected, not the earlier seller membership',
      );
      const profile = (await publicProfile(db, D, MA))[0].data;
      assert.equal(profile.display_name, 'Buyer A');
      assert.equal(profile.area_label, null, 'the seller profile area is not projected');
    });

    await t.test('review status returns the buyer their own review after retries', async () => {
      const status = (await reviewStatus(db, A, request.id))[0].data;
      assert.equal(status.eligible, true);
      assert.equal(status.review.id, reviewId);
      assert.equal(status.review.revision, 4);
      assert.equal(meeting.length > 0, true);
    });

    await t.test('seller outcomes expose only the confirmed meeting projection', async () => {
      const outcomes = (await callAs(db, 'authenticated', B,
        'SELECT hocalist.marketplace_seller_outcomes(100) AS data'))[0].data;
      assert.equal(outcomes.items.length, 1);
      assert.equal(outcomes.items[0].meeting_id, meeting);
      assert.equal(outcomes.items[0].request_id, request.id);
      assert.doesNotMatch(JSON.stringify(outcomes), /pin|latitude|longitude|address/i);
      await expectRejected(
        callAs(db, 'authenticated', D,
          'SELECT hocalist.marketplace_seller_outcomes(100) AS data'),
        'role_not_active', '42501');
    });
  } finally {
    await db.close();
  }
});

test('Hocatrends offer participants and listing owners share enquiry eligibility', async (t) => {
  const db = await createDb();
  try {
    const req = (await command(db,A,'request.create','trend-request',requestInput()))[0].result;
    const offer = (await command(db,B,'offer.submit','trend-offer',offerInput(req.id)))[0].result;
    assert.equal((await topicSellers(db,A,CATEGORY))[0].data.items.length,0,'reproduce listing-only omission');
    const enquiryDefinition=(await db.query("SELECT pg_get_functiondef('hocalist.discovery_open_enquiry(text,jsonb)'::regprocedure) AS body")).rows[0].body;
    await db.exec(enquiryDefinition.replace(/\n/g,'\r\n'));
    await db.exec((await read('../../runtime_repairs/224_hocatrends_seller_eligibility.sql')).replace(/\r?\n/g,'\r\n'));
    await t.test('recent offer seller is discoverable without a store listing',async()=>{
      const data=(await topicSellers(db,A,CATEGORY))[0].data;
      assert.equal(data.items.length,1); assert.equal(data.items[0].seller_profile_id,MB);
      assert.equal(data.items[0].listing_id,null);
      assert.doesNotMatch(JSON.stringify(data),/latitude|longitude|address|@|price_minor|message/);
      assert.equal((await topicSellers(db,A,TOPIC))[0].data.items.length,0);
    });
    await t.test('discovered offer-only seller can open an enquiry with safe retry',async()=>{
      const input={origin:'hocatrends_enquiry',topic_id:CATEGORY,seller_profile_id:MB};
      const first=(await openEnquiry(db,A,'offer-only-enquiry',input))[0].data;
      const retry=(await openEnquiry(db,A,'offer-only-enquiry',input))[0].data;
      assert.equal(first.conversation_id,retry.conversation_id);
      const members=(await db.query('SELECT user_id FROM hocalist.conversation_members WHERE conversation_id=$1',[first.conversation_id])).rows;
      assert.deepEqual(members.map(row=>row.user_id).sort(),[A,B].sort());
      await expectRejected(openEnquiry(db,A,'unrelated',{...input,seller_profile_id:MC}),'seller_not_eligible','P0001');
    });
    await t.test('old and withdrawn offers alone do not qualify',async()=>{
      await db.query("UPDATE hocalist.offers SET created_at=now()-interval '31 days' WHERE id=$1",[offer.id]);
      assert.equal((await topicSellers(db,A,CATEGORY))[0].data.items.length,0);
      await db.query("UPDATE hocalist.offers SET created_at=now(),status='withdrawn' WHERE id=$1",[offer.id]);
      assert.equal((await topicSellers(db,A,CATEGORY))[0].data.items.length,0);
      await db.query("UPDATE hocalist.offers SET status='submitted' WHERE id=$1",[offer.id]);
    });
    await t.test('multiple matching listings and offers produce one seller',async()=>{
      await db.exec(`INSERT INTO hocalist.store_listings(seller_user_id,seller_profile_id,kind,title,category_id,category_label,price_label,status,moderation_status)
        SELECT '${B}','${MB}','product','Synthetic listing '||n,'${CATEGORY}','Electronics','Ask seller','active','approved' FROM generate_series(1,2) n;`);
      const rows=(await topicSellers(db,A,CATEGORY))[0].data.items;
      assert.equal(rows.length,1); assert.ok(rows[0].listing_id);
    });
    await t.test('inactive or restricted sellers cannot be discovered or contacted',async()=>{
      for(const status of ['pending','restricted','disabled']) {
        await db.query('UPDATE hocalist.memberships SET status=$1 WHERE id=$2',[status,MB]);
        assert.equal((await topicSellers(db,A,CATEGORY))[0].data.items.length,0);
        await expectRejected(openEnquiry(db,A,`blocked-${status}`,{origin:'hocatrends_enquiry',topic_id:CATEGORY,seller_profile_id:MB}),'seller_not_eligible','P0001');
      }
      await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1",[MB]);
    });
    await t.test('anonymous reads and direct internal-helper calls remain denied',async()=>{
      await assert.rejects(callAs(db,'anon','', 'SELECT hocalist.hocatrends_topic_sellers($1,20)',[CATEGORY]),{code:'42501'});
      await assert.rejects(callAs(db,'authenticated',A,'SELECT * FROM hocalist.discovery_topic_seller_candidates($1)',[CATEGORY]),{code:'42501'});
    });
    await t.test('migration safely reapplies without changing enquiry receipts',async()=>{
      await db.exec(await read('../../runtime_repairs/224_hocatrends_seller_eligibility.sql'));
      assert.equal((await topicSellers(db,A,CATEGORY))[0].data.items.length,1);
    });
  } finally { await db.close(); }
});

test('Hocatrends, Winners and discovery enquiry origin isolation', async (t) => {
  const db = await createDb();
  try {
    await db.exec(`
      INSERT INTO hocalist.store_listings(
        seller_user_id, seller_profile_id, kind, title, category_id, category_label,
        price_label, status, moderation_status)
      VALUES ('${B}','${MB}','service','Deep clean','${TOPIC}','Home services',
              'From $80','active','approved')`);
    const purchase = await confirmPurchase(db, { title: 'iPad Air, 5th gen or newer' });

    await t.test('trends reflect verified activity only', async () => {
      await expectRejected(
        callAs(db, 'anon', '',
          'SELECT hocalist.hocatrends_trends(10) AS data'),
        'permission denied for schema hocalist', '42501');
      // Keep one request open in the electronics topic so demand is current;
      // the confirmed purchase above closed its own request.
      await command(db, A, 'request.create', 'req-trend-open',
        requestInput({ title: 'Open electronics demand' }));
      const data = (await trends(db, A))[0].data;
      assert.equal(data.window_days, 30);
      const electronics = data.items.find((row) => row.category_id === CATEGORY);
      assert.ok(electronics, 'the category with real activity is ranked');
      assert.equal(electronics.open_requests, 1);
      assert.equal(electronics.competing_sellers, 1);
      assert.equal(electronics.confirmed_purchases, 1);
      assert.equal(electronics.percent, 100);
      assert.equal(electronics.verified_activity, true);
      assert.ok(!data.items.find((row) => row.category_id === TOPIC), 'no invented topic');
    });

    await t.test('winners mask identity until consent and never leak private data', async () => {
      const before = (await winners(db, A))[0].data;
      assert.equal(before.items.length, 1);
      assert.equal(before.items[0].buyer_label, 'Hocalist buyer');
      assert.equal(before.items[0].area_label, null);
      assert.equal(before.items[0].category_label, 'Electronics');
      assert.doesNotMatch(JSON.stringify(before), /latitude|longitude|address|@/i);

      await consentSet(db, A, 'winner-consent', {
        is_public: true, show_display_name: true, show_area: true, show_categories: true,
      });
      const after = (await winners(db, A))[0].data;
      assert.equal(after.items[0].buyer_label, 'Buyer A');
      assert.equal(after.items[0].area_label, 'Yonkers, NY');
    });

    await t.test('topic sellers expose real counts and no private data', async () => {
      const data = (await callAs(db, 'authenticated', C,
        'SELECT hocalist.hocatrends_topic_sellers($1,20) AS data', [TOPIC]))[0].data;
      assert.equal(data.topic_id, TOPIC);
      assert.equal(data.items.length, 1);
      assert.equal(data.items[0].seller_profile_id, MB);
      assert.equal(data.items[0].listing_title, 'Deep clean');
      assert.equal(data.items[0].completed_deals, 1, 'the confirmed purchase counts');
      assert.equal(
        data.items[0].rating_count,
        0,
        'no review was submitted in this database, so no rating is fabricated',
      );
      assert.doesNotMatch(JSON.stringify(data), /latitude|longitude|address|@/i);
      await expectRejected(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.hocatrends_topic_sellers($1,20) AS data',
          ['99999999-0000-4000-8000-000000000099']),
        'topic_not_found', 'P0002');
    });

    await t.test('restricted targets are withheld from public projections', async () => {
      await db.exec(
        `UPDATE hocalist.memberships SET status='restricted' WHERE id='${MB}'`);
      const rep = (await reputation(db, A, MB))[0].data;
      assert.equal(rep.available, false);
      assert.equal(rep.reason, 'target_unavailable');
      assert.equal(rep.rating_count, 0);
      assert.equal(rep.completed_deals, 0);
      const topic = (await topicSellers(db, A, TOPIC))[0].data;
      assert.equal(topic.items.length, 0, 'restricted sellers leave discovery');
      await expectRejected(
        openEnquiry(db, A, 'enq-restricted-target', {
          origin: 'hocatrends_enquiry', topic_id: TOPIC, seller_profile_id: MB,
        }),
        'seller_not_eligible', 'P0001');
      const profile = (await publicProfile(db, A, MA))[0].data;
      assert.equal(profile.available, true, 'consent is unchanged for the buyer');
      await db.exec(
        `UPDATE hocalist.memberships SET status='restricted' WHERE id='${MA}'`);
      const restrictedTarget = (await publicProfile(db, D, MA))[0].data;
      assert.equal(restrictedTarget.available, false);
      assert.equal(restrictedTarget.reason, 'target_unavailable');
      await db.exec(
        `UPDATE hocalist.memberships SET status='active' WHERE id='${MA}'`);
      await db.exec(
        `UPDATE hocalist.memberships SET status='active' WHERE id='${MB}'`);
    });

    await t.test('Store enquiry opens an origin-isolated conversation', async () => {
      const listing = (await db.query(
        `SELECT id FROM hocalist.store_listings WHERE seller_user_id='${B}' AND category_id='${TOPIC}'`
      )).rows[0].id;
      await expectRejected(
        openEnquiry(db, B, 'enq-seller', { origin: 'store_listing', listing_id: listing }),
        'buyer_membership_required', '42501');
      await expectRejected(
        openEnquiry(db, A, 'enq-bad', { origin: 'store_listing', listing_id: listing, topic_id: TOPIC }),
        'invalid_enquiry', '22023');
      const opened = (await openEnquiry(db, A, 'enq-1', {
        origin: 'store_listing', listing_id: listing,
      }))[0].data;
      assert.equal(opened.origin, 'store_listing');
      assert.equal(opened.subject_id, listing);
      const replay = (await openEnquiry(db, A, 'enq-1', {
        origin: 'store_listing', listing_id: listing,
      }))[0].data;
      assert.equal(replay.conversation_id, opened.conversation_id);
      const row = await db.query(
        'SELECT origin, listing_id, request_id, offer_id FROM hocalist.conversations WHERE id=$1',
        [opened.conversation_id]);
      assert.deepEqual(row.rows[0], {
        origin: 'store_listing', listing_id: listing, request_id: null, offer_id: null,
      });
      const members = await db.query(
        'SELECT user_id FROM hocalist.conversation_members WHERE conversation_id=$1 ORDER BY user_id',
        [opened.conversation_id]);
      assert.deepEqual(members.rows.map((r) => r.user_id).sort(), [A, B].sort());
      await expectRejected(
        callAs(db, 'authenticated', C,
          'SELECT hocalist.chat_conversation($1) AS data', [opened.conversation_id]),
        'conversation_access_denied', '42501');
    });

    await t.test('Hocatrends enquiry requires a real listing in the topic', async () => {
      await expectRejected(
        openEnquiry(db, A, 'enq-topic-bad', {
          origin: 'hocatrends_enquiry', topic_id: TOPIC, seller_profile_id: MC,
        }),
        'seller_not_eligible', 'P0001');
      const opened = (await openEnquiry(db, A, 'enq-topic-1', {
        origin: 'hocatrends_enquiry', topic_id: TOPIC, seller_profile_id: MB,
      }))[0].data;
      assert.equal(opened.origin, 'hocatrends_enquiry');
      const row = await db.query(
        'SELECT origin, discovery_topic_id FROM hocalist.conversations WHERE id=$1',
        [opened.conversation_id]);
      assert.equal(row.rows[0].origin, 'hocatrends_enquiry');
      assert.equal(row.rows[0].discovery_topic_id, TOPIC);
    });

    await t.test('the enquiry opener cannot create a targeted-request conversation', async () => {
      await expectRejected(
        openEnquiry(db, A, 'enq-targeted', {
          origin: 'targeted_request', request_id: purchase.request.id,
        }),
        'invalid_origin', '22023');
    });
  } finally {
    await db.close();
  }
});


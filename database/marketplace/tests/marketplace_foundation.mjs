// Disposable PostgreSQL checks for the marketplace foundation.
//
// PGlite is single-connection: this is deterministic SQL proof for
// authorization, revisions, idempotency, offers, eligibility and Store rules.
// It is NOT real JWT, PostgREST, concurrent-writer or live proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const C = '00000000-0000-4000-8000-00000000000c';
const D = '00000000-0000-4000-8000-00000000000d';
const ADM = '00000000-0000-4000-8000-00000000000e';
const E = '00000000-0000-4000-8000-00000000000f';
const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MC = '10000000-0000-4000-8000-00000000000c';
const ME = '10000000-0000-4000-8000-00000000000e';
const MF = '10000000-0000-4000-8000-00000000000f';

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

async function expectDenied(promise, messagePart, code = '42501') {
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
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS result',
    [op, key, JSON.stringify(input)],
  );

const adminCommand = (db, user, op, key, input) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.marketplace_admin_command($1,$2,$3::jsonb) AS result',
    [op, key, JSON.stringify(input)],
  );

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
  use_home_address: true,
  ...overrides,
});

const offerInput = (requestId, overrides = {}) => ({
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
  ...overrides,
});

const listingInput = (categoryId, overrides = {}) => ({
  kind: 'product',
  title: 'iPad Air 5th Gen 64GB',
  description: 'Excellent condition with charger included.',
  category_id: categoryId,
  price_label: '$650',
  service_area: 'Yonkers, NY',
  availability: 'Available today',
  image_media_ids: [],
  publish_intent: 'draft',
  ...overrides,
});

async function seed(db) {
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${A}','{}'),('${B}','{}'),('${C}','{}'),('${D}','{}'),('${ADM}','{}'),('${E}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${MA}','${A}','buyer','active'),
      ('${MB}','${B}','seller','active'),
      ('${MC}','${C}','seller','active'),
      ('${ME}','${ADM}','seller','active'),
      ('${MF}','${E}','buyer','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name,area_label) VALUES
      ('${MA}','Buyer A','Yonkers, NY'),('${MB}','Seller B','Yonkers, NY'),
      ('${MC}','Seller C','Queens, NY'),('${ME}','Admin E','Yonkers, NY'),
      ('${MF}','Buyer F','Queens, NY');
    INSERT INTO hocalist.platform_admins(user_id) VALUES ('${ADM}');
  `);
}

test('marketplace foundation in disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyAccountDrafts(db);
    await db.exec(await readFile(new URL('../../chat/010_chat_foundation.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../020_marketplace_foundation.sql', import.meta.url), 'utf8'));
    await seed(db);

    let categoryId;
    let serviceCategoryId;
    let groupId;
    let requestId;
    let offerB;
    let offerC;

    await t.test('admin configuration is platform-admin only', async () => {
      await expectDenied(
        adminCommand(db, A, 'category.create', 'cat-denied', {
          label: 'Electronics', scope: 'product', sort_order: 1,
        }),
        'admin_required',
      );
      const created = (await adminCommand(db, ADM, 'category.create', 'cat-1', {
        label: 'Electronics', slug: 'electronics', scope: 'product', sort_order: 1,
      }))[0].result;
      categoryId = created.id;
      assert.ok(categoryId);
      const service = (await adminCommand(db, ADM, 'category.create', 'cat-2', {
        label: 'Home services', scope: 'service', sort_order: 2,
      }))[0].result;
      serviceCategoryId = service.id;
      groupId = (await adminCommand(db, ADM, 'group.create', 'group-1', {
        category_id: categoryId, label: 'Condition', selection_mode: 'single', is_required: true,
      }))[0].result.id;
      await adminCommand(db, ADM, 'option.create', 'option-1', {
        group_id: groupId, label: 'Like new', sort_order: 1,
      });
      const replayed = (await adminCommand(db, ADM, 'category.create', 'cat-1', {
        label: 'Electronics', slug: 'electronics', scope: 'product', sort_order: 1,
      }))[0].result;
      assert.deepEqual(replayed, created);
      await expectDenied(
        adminCommand(db, ADM, 'category.create', 'cat-1', {
          label: 'Changed', slug: 'electronics', scope: 'product', sort_order: 1,
        }),
        'idempotency_conflict',
        'P0001',
      );
    });

    await t.test('catalogue and locations read for active members', async () => {
      const catalogue = (await callAs(
        db, 'authenticated', A,
        'SELECT hocalist.marketplace_catalogue(NULL,false) AS data',
      ))[0].data;
      assert.equal(catalogue.categories.length, 2);
      const electronics = catalogue.categories.find((row) => row.id === categoryId);
      assert.equal(electronics.groups.length, 1);
      assert.equal(electronics.groups[0].options.length, 1);
      assert.equal(electronics.groups[0].options[0].label, 'Like new');

      const scoped = (await callAs(
        db, 'authenticated', A,
        'SELECT hocalist.marketplace_catalogue($1,false) AS data',
        ['service'],
      ))[0].data;
      assert.equal(scoped.categories.length, 1);
      assert.equal(scoped.categories[0].scope, 'service');

      await adminCommand(db, ADM, 'location.create', 'loc-1', {
        country_code: 'US', region: 'NY', city: 'Yonkers', label: 'Yonkers, NY',
      });
      const locations = (await callAs(
        db, 'authenticated', A, 'SELECT hocalist.marketplace_locations() AS data',
      ))[0].data;
      assert.equal(locations.items.length, 1);
      assert.equal(locations.items[0].label, 'Yonkers, NY');
      await expectDenied(
        callAs(db, 'anon', '', 'SELECT hocalist.marketplace_catalogue(NULL,false)'),
        'permission denied',
      );
    });

    await t.test('request create, read projections and revisions', async () => {
      const created = (await command(db, A, 'request.create', 'req-1', requestInput({ category_id: categoryId })))[0].result;
      requestId = created.id;
      assert.equal(created.status, 'active');
      assert.equal(created.revision, 1);
      assert.equal(created.budget.minimum_minor, 35000);
      assert.equal(created.location.use_home_address, true);

      const replay = (await command(db, A, 'request.create', 'req-1', requestInput({ category_id: categoryId })))[0].result;
      assert.deepEqual(replay, created);

      const ownerView = (await callAs(
        db, 'authenticated', A, 'SELECT hocalist.marketplace_request($1) AS data', [requestId],
      ))[0].data;
      assert.equal(ownerView.title, 'iPad Air, 5th gen or newer');

      const leadView = (await callAs(
        db, 'authenticated', B, 'SELECT hocalist.marketplace_request($1) AS data', [requestId],
      ))[0].data;
      assert.equal(leadView.request_id, requestId);
      assert.equal(leadView.buyer_display_name, 'Buyer A');
      assert.equal(leadView.area_label, 'Yonkers, NY');
      assert.equal(leadView.location, undefined, 'lead projection must not expose the address');

      await expectDenied(
        callAs(db, 'authenticated', D, 'SELECT hocalist.marketplace_request($1)', [requestId]),
        'request_access_denied',
      );

      const updated = (await command(db, A, 'request.update', 'req-update', {
        request_id: requestId,
        expected_revision: 1,
        ...requestInput({
          category_id: categoryId,
          title: 'iPad Air 5 or newer',
          use_home_address: false,
          address_line1: '1 Private Way',
          city: 'Yonkers',
          region: 'NY',
        }),
      }))[0].result;
      assert.equal(updated.revision, 2);
      assert.equal(updated.location.use_home_address, false);
      assert.equal(updated.location.address_line1, '1 Private Way');

      await expectDenied(
        command(db, A, 'request.update', 'req-stale', {
          request_id: requestId, expected_revision: 1, ...requestInput({ category_id: categoryId }),
        }),
        'revision_conflict',
        'P0001',
      );
      await expectDenied(
        command(db, E, 'request.update', 'req-other', {
          request_id: requestId, expected_revision: 2, ...requestInput({ category_id: categoryId }),
        }),
        'request_access_denied',
      );
      await expectDenied(
        command(db, A, 'request.create', 'req-invalid', requestInput({ category_id: categoryId, kind: 'service', condition: 'used' })),
        'invalid_field',
        '22023',
      );
      await expectDenied(
        command(db, A, 'request.create', 'req-category', requestInput({ category_id: serviceCategoryId })),
        'invalid_category',
        '22023',
      );
    });

    await t.test('seller leads exclude own and non-active requests', async () => {
      const leads = (await callAs(
        db, 'authenticated', B,
        'SELECT hocalist.marketplace_seller_leads(NULL,NULL,NULL,50,NULL) AS data',
      ))[0].data;
      assert.equal(leads.items.length, 1);
      assert.equal(leads.items[0].request_id, requestId);
      assert.equal(leads.items[0].request_revision, 2);

      const filtered = (await callAs(
        db, 'authenticated', B,
        'SELECT hocalist.marketplace_seller_leads($1,NULL,NULL,50,NULL) AS data',
        ['service'],
      ))[0].data;
      assert.equal(filtered.items.length, 0);

      await expectDenied(
        callAs(db, 'authenticated', A, 'SELECT hocalist.marketplace_seller_leads(NULL,NULL,NULL,50,NULL)'),
        'role_not_active',
      );
    });

    await t.test('offers submit, revise, withdraw rules and selection', async () => {
      const submitted = (await command(db, B, 'offer.submit', 'offer-b-1', offerInput(requestId)))[0].result;
      offerB = submitted.id;
      assert.equal(submitted.status, 'submitted');
      assert.equal(submitted.revisions.length, 1);
      assert.equal(submitted.revisions[0].sequence, 1);
      assert.equal(submitted.revisions[0].price_minor, 42000);
      assert.equal(submitted.revisions[0].schedule_time, '18:30');

      await expectDenied(
        command(db, B, 'offer.submit', 'offer-b-2', offerInput(requestId)),
        'offer_exists',
        'P0001',
      );
      await expectDenied(
        command(db, A, 'offer.submit', 'offer-own', offerInput(requestId)),
        'role_not_active',
      );

      const revised = (await command(db, B, 'offer.revise', 'offer-b-revise', {
        offer_id: offerB, expected_offer_revision: 1,
        ...offerInput(requestId, { price_minor: 40000 }),
      }))[0].result;
      assert.equal(revised.revision, 2);
      assert.equal(revised.revisions.length, 2);
      assert.equal(revised.revisions[0].status, 'superseded');
      assert.equal(revised.revisions[1].sequence, 2);

      await expectDenied(
        command(db, B, 'offer.revise', 'offer-b-stale', {
          offer_id: offerB, expected_offer_revision: 1,
          ...offerInput(requestId, { price_minor: 39000 }),
        }),
        'revision_conflict',
        'P0001',
      );

      const sellerOffers = (await callAs(
        db, 'authenticated', B,
        'SELECT hocalist.marketplace_request_offers($1,50,NULL) AS data', [requestId],
      ))[0].data;
      assert.equal(sellerOffers.items.length, 1);

      const selected = (await command(db, A, 'offer.select', 'offer-b-select', {
        offer_id: offerB, revision_id: revised.revisions[1].id, expected_offer_revision: 2,
      }))[0].result;
      assert.equal(selected.status, 'selected');
      assert.equal(selected.accepted_revision_id, revised.revisions[1].id);
      assert.equal(selected.revisions[1].status, 'accepted');

      // Replaying the same acceptance with a new key returns the committed
      // selection instead of creating a second accepted state.
      const reselected = (await command(db, A, 'offer.select', 'offer-b-reselect', {
        offer_id: offerB, revision_id: revised.revisions[1].id, expected_offer_revision: 3,
      }))[0].result;
      assert.equal(reselected.status, 'selected');
      assert.equal(reselected.accepted_revision_id, revised.revisions[1].id);
      assert.equal(reselected.revision, 3);

      offerC = (await command(db, C, 'offer.submit', 'offer-c-1', offerInput(requestId, { price_minor: 41000 })))[0].result;
      await expectDenied(
        command(db, A, 'offer.select', 'offer-c-select', {
          offer_id: offerC.id, revision_id: offerC.revisions[0].id, expected_offer_revision: 1,
        }),
        'selection_policy_pending',
        'P0001',
      );
      await expectDenied(
        command(db, B, 'offer.revise', 'offer-b-locked', {
          offer_id: offerB, expected_offer_revision: 2,
          ...offerInput(requestId, { price_minor: 38000 }),
        }),
        'offer_not_open',
        'P0001',
      );

      // A closed request cannot accept an offer or a new selection, and the
      // reopen transition is serialized through the same request row.
      const closed = (await command(db, A, 'request.close', 'request-close', {
        request_id: requestId, expected_revision: 2,
      }))[0].result;
      assert.equal(closed.status, 'closed');
      await expectDenied(
        command(db, A, 'offer.select', 'offer-c-after-close', {
          offer_id: offerC.id, revision_id: offerC.revisions[0].id, expected_offer_revision: 1,
        }),
        'request_not_open',
        'P0001',
      );
      await expectDenied(
        command(db, C, 'offer.submit', 'offer-c-after-close', offerInput(requestId, { price_minor: 40000 })),
        'request_not_open',
        'P0001',
      );
      const reopened = (await command(db, A, 'request.reopen', 'request-reopen', {
        request_id: requestId, expected_revision: 3,
      }))[0].result;
      assert.equal(reopened.status, 'active');
    });

    await t.test('conversation opens only from an accepted offer for participants', async () => {
      await expectDenied(
        command(db, A, 'conversation.open_offer', 'open-early', { offer_id: offerC.id }),
        'conversation_not_eligible',
        'P0001',
      );
      const opened = (await command(db, A, 'conversation.open_offer', 'open-b', { offer_id: offerB }))[0].result;
      assert.ok(opened.conversation_id);
      const replay = (await command(db, A, 'conversation.open_offer', 'open-b', { offer_id: offerB }))[0].result;
      assert.deepEqual(replay, opened);
      const bySeller = (await command(db, B, 'conversation.open_offer', 'open-b-seller', { offer_id: offerB }))[0].result;
      assert.equal(bySeller.conversation_id, opened.conversation_id);

      const inbox = (await callAs(
        db, 'authenticated', A, 'SELECT hocalist.chat_inbox(50,NULL) AS data',
      ))[0].data;
      assert.equal(inbox.items.length, 1);
      assert.equal(inbox.items[0].conversation.id, opened.conversation_id);
      assert.equal(inbox.items[0].conversation.origin, 'targeted_request');

      await expectDenied(
        command(db, D, 'conversation.open_offer', 'open-outsider', { offer_id: offerB }),
        'offer_access_denied',
      );
    });

    await t.test('store listings enforce category, moderation and plan limits', async () => {
      await expectDenied(
        command(db, B, 'store.create', 'store-bad-cat', listingInput(serviceCategoryId)),
        'invalid_category',
        '22023',
      );
      const draft = (await command(db, B, 'store.create', 'store-1', listingInput(categoryId)))[0].result;
      assert.equal(draft.status, 'draft');
      assert.equal(draft.moderation_status, 'pending_review');
      assert.equal(draft.category_label, 'Electronics');

      const published = (await command(db, B, 'store.publish', 'store-1-publish', {
        listing_id: draft.id, expected_revision: 1, publish: true,
      }))[0].result;
      assert.equal(published.status, 'active');
      assert.ok(published.published_at);

      await expectDenied(
        callAs(db, 'authenticated', A, 'SELECT hocalist.marketplace_store_listing($1)', [draft.id]),
        'listing_access_denied',
      );
      const publicBefore = (await callAs(
        db, 'authenticated', A,
        'SELECT hocalist.marketplace_public_store_listings($1,NULL,50,NULL) AS data', [MB],
      ))[0].data;
      assert.equal(publicBefore.items.length, 0, 'pending moderation is not public');

      const approved = (await adminCommand(db, ADM, 'store.set_moderation', 'moderate-1', {
        listing_id: draft.id, expected_revision: 2, moderation_status: 'approved',
      }))[0].result;
      assert.equal(approved.moderation_status, 'approved');
      const publicAfter = (await callAs(
        db, 'authenticated', A,
        'SELECT hocalist.marketplace_public_store_listings($1,NULL,50,NULL) AS data', [MB],
      ))[0].data;
      assert.equal(publicAfter.items.length, 1);
      assert.equal(publicAfter.items[0].seller_user_id, undefined, 'public projection hides the owner identity');

      const summary = (await callAs(
        db, 'authenticated', B, 'SELECT hocalist.marketplace_store_summary() AS data',
      ))[0].data;
      assert.equal(summary.active_count, 1);
      assert.equal(summary.plan_code, 'free');
      assert.equal(summary.store_listing_limit, 3);

      await command(db, B, 'store.create', 'store-2', listingInput(categoryId, { title: 'Second listing' }));
      await command(db, B, 'store.create', 'store-3', listingInput(categoryId, { title: 'Third listing' }));
      await expectDenied(
        command(db, B, 'store.create', 'store-4', listingInput(categoryId, { title: 'Fourth listing' })),
        'store_limit_exceeded',
        'P0001',
      );
      await expectDenied(
        command(db, B, 'store.duplicate', 'store-dup', { listing_id: draft.id }),
        'store_limit_exceeded',
        'P0001',
      );

      await command(db, B, 'store.archive', 'store-archive', {
        listing_id: draft.id, expected_revision: 3,
      });
      const afterArchive = (await callAs(
        db, 'authenticated', B, 'SELECT hocalist.marketplace_store_summary() AS data',
      ))[0].data;
      assert.equal(afterArchive.archived_count, 1);
      assert.equal(afterArchive.active_count, 0);
    });

    await t.test('saved items toggle per identity', async () => {
      const itemId = '30000000-0000-4000-8000-000000000001';
      const first = (await command(db, A, 'saved.toggle', 'save-1', {
        item_type: 'store_listing', item_id: itemId,
      }))[0].result;
      assert.equal(first.saved, true);
      const saved = (await callAs(
        db, 'authenticated', A, 'SELECT hocalist.marketplace_saved_items() AS data',
      ))[0].data;
      assert.equal(saved.items.length, 1);
      const second = (await command(db, A, 'saved.toggle', 'save-2', {
        item_type: 'store_listing', item_id: itemId,
      }))[0].result;
      assert.equal(second.saved, false);
    });

    await t.test('timezone validation rejects abbreviations and fixed offsets', async () => {
      const checks = await db.query(`
        SELECT
          hocalist.marketplace_valid_timezone('America/New_York') AS ny,
          hocalist.marketplace_valid_timezone('Europe/London') AS london,
          hocalist.marketplace_valid_timezone('America/Phoenix') AS phoenix,
          hocalist.marketplace_valid_timezone('UTC') AS utc,
          hocalist.marketplace_valid_timezone('EST') AS est,
          hocalist.marketplace_valid_timezone('Etc/GMT+5') AS etc,
          hocalist.marketplace_valid_timezone('SystemV/EST5') AS systemv,
          hocalist.marketplace_valid_timezone('Not/AZone') AS bogus,
          hocalist.marketplace_valid_timezone(NULL) AS null_zone
      `);
      assert.deepEqual(checks.rows[0], {
        ny: true,
        london: true,
        phoenix: true,
        utc: false,
        est: false,
        etc: false,
        systemv: false,
        bogus: false,
        null_zone: false,
      });

      const zones = (await callAs(
        db, 'authenticated', A, 'SELECT hocalist.marketplace_timezones() AS data',
      ))[0].data.items;
      assert.ok(zones.includes('America/New_York'));
      assert.ok(zones.includes('Europe/London'));
      assert.ok(!zones.includes('UTC'));
      assert.ok(!zones.some((zone) => zone.startsWith('Etc/')));
      assert.ok(!zones.some((zone) => zone.startsWith('SystemV/')));
    });

    await t.test('offer schedules resolve named zones with DST handling', async () => {
      const TZ_SELLER = '00000000-0000-4000-8000-000000000010';
      const TZ_PROFILE = '10000000-0000-4000-8000-000000000010';
      await db.query("INSERT INTO auth.users(id, raw_user_meta_data) VALUES ($1,'{}')", [TZ_SELLER]);
      await db.query(
        "INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES ($1,$2,'seller','active')",
        [TZ_PROFILE, TZ_SELLER],
      );
      await db.query(
        "INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES ($1,'Seller TZ')",
        [TZ_PROFILE],
      );
      const tzRequest = (await command(db, A, 'request.create', 'tz-request', requestInput({
        category_id: categoryId,
        title: 'Timezone probe request',
      })))[0].result.id;
      const tzOffer = (overrides) => ({ ...offerInput(tzRequest), ...overrides });

      await expectDenied(
        command(db, TZ_SELLER, 'offer.submit', 'tz-bad-zone', tzOffer({ schedule_timezone: 'EST' })),
        'invalid_field',
        '22023',
      );
      await expectDenied(
        command(db, TZ_SELLER, 'offer.submit', 'tz-gap', tzOffer({
          schedule_date: '2026-03-08', schedule_time: '02:30',
        })),
        'nonexistent_local_time',
        '22023',
      );
      await expectDenied(
        command(db, TZ_SELLER, 'offer.submit', 'tz-ambiguous', tzOffer({
          schedule_date: '2026-11-01', schedule_time: '01:30',
        })),
        'ambiguous_local_time',
        '22023',
      );
      await expectDenied(
        command(db, TZ_SELLER, 'offer.submit', 'tz-occurrence-unique', tzOffer({
          schedule_date: '2026-10-01', schedule_time: '18:30', schedule_occurrence: 'later',
        })),
        'invalid_field',
        '22023',
      );
      // A 30-minute fall-back is ambiguous too and must not assume a one-hour
      // shift: Australia/Lord_Howe repeats 01:30-01:59.
      await expectDenied(
        command(db, TZ_SELLER, 'offer.submit', 'tz-lord-howe-ambiguous', tzOffer({
          schedule_timezone: 'Australia/Lord_Howe',
          schedule_date: '2026-04-05', schedule_time: '01:45',
        })),
        'ambiguous_local_time',
        '22023',
      );
      // A 30-minute spring-forward gap is nonexistent.
      await expectDenied(
        command(db, TZ_SELLER, 'offer.submit', 'tz-lord-howe-gap', tzOffer({
          schedule_timezone: 'Australia/Lord_Howe',
          schedule_date: '2026-10-04', schedule_time: '02:15',
        })),
        'nonexistent_local_time',
        '22023',
      );
      // A two-hour fall-back repeats 01:00-02:59 in Antarctica/Troll.
      await expectDenied(
        command(db, TZ_SELLER, 'offer.submit', 'tz-troll-ambiguous', tzOffer({
          schedule_timezone: 'Antarctica/Troll',
          schedule_date: '2026-10-25', schedule_time: '01:30',
        })),
        'ambiguous_local_time',
        '22023',
      );
      // A two-hour spring-forward gap is nonexistent.
      await expectDenied(
        command(db, TZ_SELLER, 'offer.submit', 'tz-troll-gap', tzOffer({
          schedule_timezone: 'Antarctica/Troll',
          schedule_date: '2026-03-29', schedule_time: '01:30',
        })),
        'nonexistent_local_time',
        '22023',
      );

      const submitAndWithdraw = async (key, overrides, expectedOffset, expectedInstant) => {
        const offer = (await command(db, TZ_SELLER, 'offer.submit', key, tzOffer(overrides)))[0].result;
        assert.equal(offer.revisions[0].schedule_utc_offset_minutes, expectedOffset, key);
        assert.equal(
          new Date(offer.revisions[0].schedule_utc_instant).toISOString(),
          expectedInstant,
          key,
        );
        await command(db, TZ_SELLER, 'offer.withdraw', `${key}-withdraw`, {
          offer_id: offer.id,
          expected_offer_revision: offer.revision,
        });
      };

      // Repeated US fall-back hour: earlier = daylight (-04:00), later = standard (-05:00).
      await submitAndWithdraw(
        'tz-earlier',
        { schedule_date: '2026-11-01', schedule_time: '01:30', schedule_occurrence: 'earlier' },
        -240,
        '2026-11-01T05:30:00.000Z',
      );
      await submitAndWithdraw(
        'tz-later',
        { schedule_date: '2026-11-01', schedule_time: '01:30', schedule_occurrence: 'later' },
        -300,
        '2026-11-01T06:30:00.000Z',
      );
      // 30-minute fall-back: earlier is daylight +11:00 (+660), later is
      // standard +10:30 (+630).
      await submitAndWithdraw(
        'tz-lord-howe-earlier',
        {
          schedule_timezone: 'Australia/Lord_Howe',
          schedule_date: '2026-04-05', schedule_time: '01:45',
          schedule_occurrence: 'earlier',
        },
        660,
        '2026-04-04T14:45:00.000Z',
      );
      await submitAndWithdraw(
        'tz-lord-howe-later',
        {
          schedule_timezone: 'Australia/Lord_Howe',
          schedule_date: '2026-04-05', schedule_time: '01:45',
          schedule_occurrence: 'later',
        },
        630,
        '2026-04-04T15:15:00.000Z',
      );
      // Two-hour fall-back: earlier is daylight +02:00, later is +00:00.
      await submitAndWithdraw(
        'tz-troll-earlier',
        {
          schedule_timezone: 'Antarctica/Troll',
          schedule_date: '2026-10-25', schedule_time: '01:30',
          schedule_occurrence: 'earlier',
        },
        120,
        '2026-10-24T23:30:00.000Z',
      );
      await submitAndWithdraw(
        'tz-troll-later',
        {
          schedule_timezone: 'Antarctica/Troll',
          schedule_date: '2026-10-25', schedule_time: '01:30',
          schedule_occurrence: 'later',
        },
        0,
        '2026-10-25T01:30:00.000Z',
      );
      // Non-DST zone.
      await submitAndWithdraw(
        'tz-phoenix',
        { schedule_timezone: 'America/Phoenix', schedule_date: '2026-11-01', schedule_time: '18:30' },
        -420,
        '2026-11-02T01:30:00.000Z',
      );
      // Year boundary.
      await submitAndWithdraw(
        'tz-year-end',
        { schedule_date: '2026-12-31', schedule_time: '23:30' },
        -300,
        '2027-01-01T04:30:00.000Z',
      );
      // A unique summer time keeps its daylight offset.
      await submitAndWithdraw(
        'tz-summer',
        { schedule_date: '2026-07-15', schedule_time: '18:30' },
        -240,
        '2026-07-15T22:30:00.000Z',
      );
    });

    await t.test('exclusive next-local-day cutoff uses the accepted zone', async () => {
      const rows = (await db.query(`
        SELECT
          hocalist.marketplace_next_local_day_start('2026-03-07','America/New_York') AS spring_eve,
          hocalist.marketplace_next_local_day_start('2026-03-08','America/New_York') AS spring_day,
          hocalist.marketplace_next_local_day_start('2026-11-01','America/New_York') AS fall_day,
          hocalist.marketplace_next_local_day_start('2026-11-01','America/Phoenix') AS phoenix,
          hocalist.marketplace_next_local_day_start('2026-12-31','America/New_York') AS year_end
      `)).rows[0];
      assert.equal(new Date(rows.spring_eve).toISOString(), '2026-03-08T05:00:00.000Z');
      assert.equal(new Date(rows.spring_day).toISOString(), '2026-03-09T04:00:00.000Z');
      assert.equal(new Date(rows.fall_day).toISOString(), '2026-11-02T05:00:00.000Z');
      assert.equal(new Date(rows.phoenix).toISOString(), '2026-11-02T07:00:00.000Z');
      assert.equal(new Date(rows.year_end).toISOString(), '2027-01-01T05:00:00.000Z');
      await expectDenied(
        db.query("SELECT hocalist.marketplace_next_local_day_start('2026-11-01','UTC')"),
        'invalid_field',
        '22023',
      );
    });

    await t.test('admin locations carry an optional validated zone', async () => {
      const created = (await adminCommand(db, ADM, 'location.create', 'loc-tz', {
        country_code: 'US', region: 'NY', city: 'Yonkers', label: 'Yonkers downtown',
        timezone_id: 'America/New_York',
      }))[0].result;
      await expectDenied(
        adminCommand(db, ADM, 'location.create', 'loc-bad-tz', {
          country_code: 'US', label: 'Bad zone', timezone_id: 'EST',
        }),
        'invalid_field',
        '22023',
      );
      const locations = (await callAs(
        db, 'authenticated', A, 'SELECT hocalist.marketplace_locations() AS data',
      ))[0].data.items;
      const configured = locations.find((location) => location.id === created.id);
      assert.equal(configured.timezone_id, 'America/New_York');
      const unconfigured = locations.find((location) => location.id !== created.id);
      assert.equal(unconfigured.timezone_id, null);
    });

    await t.test('client roles have no direct table access and no internal helpers', async () => {
      for (const role of ['authenticated', 'anon', 'service_role']) {
        for (const table of ['requests', 'offers', 'offer_revisions', 'store_listings', 'catalogue_categories']) {
          await expectDenied(
            asRole(db, role, role === 'authenticated' ? A : '', () =>
              db.query(`SELECT * FROM hocalist.${table}`),
            ),
            'permission denied',
          );
        }
      }
      const privileges = await db.query(`
        SELECT
          has_function_privilege('authenticated','hocalist.marketplace_command(text,text,jsonb)','EXECUTE') AS command,
          has_function_privilege('anon','hocalist.marketplace_command(text,text,jsonb)','EXECUTE') AS anon_command,
          has_function_privilege('service_role','hocalist.marketplace_command(text,text,jsonb)','EXECUTE') AS service_command,
          has_function_privilege('authenticated','hocalist.marketplace_normalize_request(jsonb)','EXECUTE') AS normalizer,
          has_function_privilege('authenticated','hocalist.marketplace_assert_admin(uuid)','EXECUTE') AS assert_admin,
          has_function_privilege('authenticated','hocalist.marketplace_admin_moderation_queue(integer,text)','EXECUTE') AS queue,
          has_function_privilege('authenticated','hocalist.marketplace_timezones()','EXECUTE') AS timezones,
          has_function_privilege('authenticated','hocalist.marketplace_valid_timezone(text)','EXECUTE') AS valid_timezone
      `);
      assert.deepEqual(privileges.rows[0], {
        command: true,
        anon_command: false,
        service_command: false,
        normalizer: false,
        assert_admin: false,
        queue: true,
        timezones: true,
        valid_timezone: false,
      });
    });
  } finally {
    await db.close();
  }
});

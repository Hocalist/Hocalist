// Deterministic regression proof for the hardened account command contract.
//
// Single-connection PGlite: fast, repeatable checks only. Concurrency and real
// API behaviour are covered by the opt-in harnesses in concurrency.test.mjs
// and acceptance.test.mjs and are never claimed by this suite.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import {
  applyAccountDrafts,
  applySignupSeed,
  createDisposableDb,
} from './fixture.mjs';

const newId = () => randomUUID();

async function runAs(db, role, user, body) {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec(`SET ROLE ${role}`);
  try {
    return await body();
  } finally {
    await db.exec('RESET ROLE');
  }
}

async function command(db, op, key, input) {
  const result = await db.query(
    'SELECT hocalist.account_command($1,$2,$3::jsonb) AS result',
    [op, key, JSON.stringify(input)],
  );
  return result.rows[0].result;
}

async function commandAs(db, user, op, key, input) {
  return runAs(db, 'authenticated', user, () => command(db, op, key, input));
}

async function expectCommandError(db, user, op, key, input, code, messagePart) {
  return runAs(db, 'authenticated', user, async () => {
    try {
      await command(db, op, key, input);
    } catch (error) {
      assert.equal(error.code, code, `${op}: expected ${code}, got ${error.code}: ${error.message}`);
      if (messagePart !== undefined) {
        assert.match(error.message, new RegExp(messagePart));
      }
      return error;
    }
    assert.fail(`${op}: expected SQLSTATE ${code}, but the command succeeded`);
  });
}

async function insertIdentity(db, meta = { full_name: 'Synthetic Probe' }) {
  const id = newId();
  await db.query('INSERT INTO auth.users(id, raw_user_meta_data) VALUES ($1, $2)', [id, meta]);
  return id;
}

async function insertMembership(db, userId, role, status = 'active', displayName = 'Probe') {
  const id = newId();
  await db.query(
    "INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES ($1,$2,$3,$4)",
    [id, userId, role, status],
  );
  await db.query(
    'INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES ($1,$2)',
    [id, displayName],
  );
  return id;
}

async function ensureContact(db, userId) {
  await db.query(
    'INSERT INTO hocalist.profile_contacts(user_id) VALUES ($1) ON CONFLICT(user_id) DO NOTHING',
    [userId],
  );
}

async function readAs(db, user, sql) {
  return runAs(db, 'authenticated', user, async () => (await db.query(sql)).rows);
}

test('hardened account command regression in disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyAccountDrafts(db);

    await t.test('unknown fields are rejected per operation with no state change', async () => {
      const user = await insertIdentity(db);
      for (const [op, input] of [
        ['onboard', { role: 'buyer', display_name: 'X', status: 'active' }],
        ['onboard', { role: 'buyer', display_name: 'X', verified: true }],
        ['profile.update', { profile_id: newId(), expected_revision: 1, display_name: 'X', admin: true }],
        ['contact.update', { expected_revision: 1, email: 'x@example.invalid' }],
      ]) {
        await expectCommandError(db, user, op, `unknown-${op}-${newId()}`, input, '22023', 'unknown_field');
      }
      const counts = await db.query(
        `SELECT
           (SELECT count(*)::int FROM hocalist.memberships WHERE user_id=$1) AS memberships,
           (SELECT count(*)::int FROM hocalist.profile_contacts WHERE user_id=$1) AS contacts,
           (SELECT count(*)::int FROM hocalist.command_receipts WHERE user_id=$1) AS receipts`,
        [user],
      );
      assert.deepEqual(counts.rows[0], { memberships: 0, contacts: 0, receipts: 0 });
    });

    await t.test('every role/status combination behaves as documented', async () => {
      for (const role of ['buyer', 'seller']) {
        for (const status of ['pending', 'active', 'restricted', 'disabled']) {
          const user = await insertIdentity(db);
          const membership = await insertMembership(db, user, role, status);
          await ensureContact(db, user);
          const label = `${role}/${status}`;
          const active = status === 'active';
          const otherRole = role === 'buyer' ? 'seller' : 'buyer';
          const patch =
            role === 'seller'
              ? { profile_id: membership, expected_revision: 1, display_name: 'Updated', pickup_availability: 'Weekends' }
              : { profile_id: membership, expected_revision: 1, display_name: 'Updated' };

          if (active) {
            assert.equal(
              (await commandAs(db, user, 'profile.update', `matrix-profile-${label}`, patch)).revision,
              2,
              label,
            );
            assert.equal(
              (await commandAs(db, user, 'contact.update', `matrix-contact-${label}`, { expected_revision: 1, city: 'Synthetic' })).revision,
              2,
              label,
            );
          } else if (status === 'pending') {
            await expectCommandError(db, user, 'profile.update', `matrix-profile-${label}`, patch, '42501', 'profile_access_denied');
            await expectCommandError(db, user, 'contact.update', `matrix-contact-${label}`, { expected_revision: 1 }, '42501', 'contact_access_denied');
          } else {
            await expectCommandError(db, user, 'profile.update', `matrix-profile-${label}`, patch, '42501', 'account_restricted');
            await expectCommandError(db, user, 'contact.update', `matrix-contact-${label}`, { expected_revision: 1 }, '42501', 'account_restricted');
          }

          const visibleProfiles = await readAs(db, user, 'SELECT membership_id FROM hocalist.role_profiles');
          const visibleContacts = await readAs(db, user, 'SELECT user_id FROM hocalist.profile_contacts');
          const visibleMemberships = await readAs(db, user, 'SELECT id FROM hocalist.memberships');
          assert.equal(visibleProfiles.length, active ? 1 : 0, `profiles ${label}`);
          assert.equal(visibleContacts.length, active ? 1 : 0, `contacts ${label}`);
          assert.equal(visibleMemberships.length, 1, `memberships ${label}`);

          if (status === 'restricted' || status === 'disabled') {
            await expectCommandError(db, user, 'onboard', `matrix-other-${label}`, { role: otherRole, display_name: 'Other' }, '42501', 'account_restricted');
          } else {
            assert.equal(
              (await commandAs(db, user, 'onboard', `matrix-other-${label}`, { role: otherRole, display_name: 'Other' })).role,
              otherRole,
              label,
            );
            const after = await readAs(db, user, 'SELECT id FROM hocalist.memberships');
            assert.equal(after.length, 2, `memberships after second role ${label}`);
          }
        }
      }
    });

    await t.test('invalid roles and duplicate enrollment are rejected', async () => {
      for (const role of ['admin', 'BUYER', 'seller ', '', null, 5, true]) {
        const user = await insertIdentity(db);
        await expectCommandError(
          db, user, 'onboard', `bad-role-${newId()}`,
          { role, display_name: 'X' }, '22023',
        );
      }
      const user = await insertIdentity(db);
      await commandAs(db, user, 'onboard', 'dup-1', { role: 'buyer', display_name: 'First' });
      await expectCommandError(
        db, user, 'onboard', 'dup-2',
        { role: 'buyer', display_name: 'Second' }, 'P0001', 'membership_exists',
      );
      await commandAs(db, user, 'onboard', 'dup-3', { role: 'seller', display_name: 'Seller' });
      const rows = await db.query('SELECT role FROM hocalist.memberships WHERE user_id=$1 ORDER BY role', [user]);
      assert.deepEqual(rows.rows, [{ role: 'buyer' }, { role: 'seller' }]);
    });

    await t.test('profile and contact revisions are independent', async () => {
      const user = await insertIdentity(db);
      const buyer = await commandAs(db, user, 'onboard', 'ind-1', { role: 'buyer', display_name: 'Independent' });
      await commandAs(db, user, 'onboard', 'ind-2', { role: 'seller', display_name: 'Independent Seller' });
      const seller = await db.query(
        "SELECT id FROM hocalist.memberships WHERE user_id=$1 AND role='seller'",
        [user],
      );
      const sellerId = seller.rows[0].id;

      assert.equal((await commandAs(db, user, 'profile.update', 'ind-p1', {
        profile_id: buyer.profile_id, expected_revision: 1, display_name: 'Buyer v2',
      })).revision, 2);
      let stamps = await db.query(
        'SELECT revision FROM hocalist.role_profiles WHERE membership_id=$1',
        [buyer.profile_id],
      );
      assert.equal(stamps.rows[0].revision, 2);
      stamps = await db.query('SELECT revision FROM hocalist.profile_contacts WHERE user_id=$1', [user]);
      assert.equal(stamps.rows[0].revision, 1, 'contact revision untouched by profile update');

      assert.equal((await commandAs(db, user, 'contact.update', 'ind-c1', {
        expected_revision: 1, phone: 'SYNTHETIC-PHONE',
      })).revision, 2);
      stamps = await db.query('SELECT revision FROM hocalist.profile_contacts WHERE user_id=$1', [user]);
      assert.equal(stamps.rows[0].revision, 2);
      stamps = await db.query('SELECT revision FROM hocalist.role_profiles WHERE membership_id=$1', [buyer.profile_id]);
      assert.equal(stamps.rows[0].revision, 2, 'profile revision untouched by contact update');

      assert.equal((await commandAs(db, user, 'profile.update', 'ind-p2', {
        profile_id: sellerId, expected_revision: 1, display_name: 'Seller v2',
      })).revision, 2);
      stamps = await db.query(
        'SELECT membership_id, revision FROM hocalist.role_profiles WHERE membership_id IN ($1,$2) ORDER BY membership_id',
        [buyer.profile_id, sellerId],
      );
      assert.deepEqual(
        stamps.rows,
        [
          { membership_id: buyer.profile_id, revision: 2 },
          { membership_id: sellerId, revision: 2 },
        ].sort((x, y) => x.membership_id.localeCompare(y.membership_id)),
      );

      await expectCommandError(db, user, 'profile.update', 'ind-stale-p', {
        profile_id: buyer.profile_id, expected_revision: 1, display_name: 'Stale',
      }, 'P0001', 'revision_conflict');
      await expectCommandError(db, user, 'contact.update', 'ind-stale-c', {
        expected_revision: 1, phone: 'Stale',
      }, 'P0001', 'revision_conflict');
      stamps = await db.query('SELECT revision FROM hocalist.profile_contacts WHERE user_id=$1', [user]);
      assert.equal(stamps.rows[0].revision, 2);
    });

    await t.test('replay returns the original result and key reuse is rejected', async () => {
      const user = await insertIdentity(db);
      const onboardInput = { role: 'buyer', display_name: 'Replay Buyer' };
      const first = await commandAs(db, user, 'onboard', 'replay-onboard', onboardInput);
      assert.deepEqual(await commandAs(db, user, 'onboard', 'replay-onboard', onboardInput), first);

      const profileInput = { profile_id: first.profile_id, expected_revision: 1, display_name: 'Replay v2' };
      const profileFirst = await commandAs(db, user, 'profile.update', 'replay-profile', profileInput);
      assert.deepEqual(profileFirst, { profile_id: first.profile_id, revision: 2 });
      await commandAs(db, user, 'profile.update', 'replay-profile-next', {
        profile_id: first.profile_id, expected_revision: 2, display_name: 'Replay v3',
      });
      assert.deepEqual(
        await commandAs(db, user, 'profile.update', 'replay-profile', profileInput),
        { profile_id: first.profile_id, revision: 2 },
        'allowed replay keeps the original minimal result after later changes',
      );
      await expectCommandError(db, user, 'profile.update', 'replay-profile', {
        ...profileInput, display_name: 'Changed payload',
      }, 'P0001', 'idempotency_conflict');

      const contactInput = { expected_revision: 1, city: 'Replay City' };
      const contactFirst = await commandAs(db, user, 'contact.update', 'replay-contact', contactInput);
      assert.deepEqual(contactFirst, { revision: 2 });
      assert.deepEqual(await commandAs(db, user, 'contact.update', 'replay-contact', contactInput), { revision: 2 });
      await expectCommandError(db, user, 'contact.update', 'replay-contact', {
        expected_revision: 1, city: 'Different City',
      }, 'P0001', 'idempotency_conflict');

      const sharedKey = `shared-${newId()}`;
      await commandAs(db, user, 'onboard', sharedKey, { role: 'seller', display_name: 'Shared Key' });
      const contactResult = await commandAs(db, user, 'contact.update', sharedKey, {
        expected_revision: 2, region: 'Shared Region',
      });
      assert.equal(contactResult.revision, 3, 'same key is scoped per operation');

      const maxKey = 'k'.repeat(128);
      assert.ok(await commandAs(db, user, 'contact.update', maxKey, { expected_revision: 3, region: 'Max' }));
      await expectCommandError(db, user, 'contact.update', 'k'.repeat(129), { expected_revision: 4 }, '22023', 'invalid_command');
    });

    await t.test('missing seed and missing contact stay explicit', async () => {
      const seedless = await insertIdentity(db);
      await db.query('DELETE FROM hocalist.profiles WHERE id=$1', [seedless]);
      await expectCommandError(
        db, seedless, 'onboard', `seedless-${newId()}`,
        { role: 'buyer', display_name: 'No Seed' }, '42501', 'onboarding_seed_required',
      );

      const user = await insertIdentity(db);
      const onboard = await commandAs(db, user, 'onboard', `contact-${newId()}`, { role: 'buyer', display_name: 'No Contact' });
      await db.query('DELETE FROM hocalist.profile_contacts WHERE user_id=$1', [user]);
      const key = `missing-contact-${newId()}`;
      await expectCommandError(db, user, 'contact.update', key, {
        expected_revision: 1, phone: 'Never Stored',
      }, 'P0001', 'revision_conflict');
      const state = await db.query(
        `SELECT
           (SELECT count(*)::int FROM hocalist.profile_contacts WHERE user_id=$1) AS contacts,
           (SELECT count(*)::int FROM hocalist.command_receipts WHERE user_id=$1 AND idempotency_key=$2) AS receipts,
           (SELECT revision FROM hocalist.role_profiles WHERE membership_id=$3) AS profile_revision`,
        [user, key, onboard.profile_id],
      );
      assert.deepEqual(state.rows[0], { contacts: 0, receipts: 0, profile_revision: 1 });
    });

    await t.test('invalid and null types are rejected within bounds', async () => {
      const user = await insertIdentity(db);
      const onboard = await commandAs(db, user, 'onboard', `types-${newId()}`, { role: 'buyer', display_name: 'Types' });
      const profileId = onboard.profile_id;

      for (const op of [null, 'onboard ', 'admin', '']) {
        await expectCommandError(db, user, op, `bad-op-${newId()}`, {}, '22023', 'invalid_operation');
      }
      for (const key of [null, '', '   ', 'k'.repeat(129)]) {
        await expectCommandError(db, user, 'contact.update', key, { expected_revision: 1 }, '22023', 'invalid_command');
      }
      for (const input of [null, [], 'text', 5, true]) {
        await expectCommandError(db, user, 'contact.update', `bad-input-${newId()}`, input, '22023', 'invalid_command');
      }
      await expectCommandError(db, user, 'contact.update', `oversized-${newId()}`, {
        expected_revision: 1, city: 'x'.repeat(17000),
      }, '22023', 'invalid_command');

      for (const revision of [undefined, null, '1', 1.5, 0, -1, 1000000000000000000]) {
        const input = { expected_revision: revision, city: 'Type Probe' };
        if (revision === undefined) delete input.expected_revision;
        await expectCommandError(db, user, 'contact.update', `bad-rev-${newId()}`, input, '22023', 'invalid_revision');
      }
      await expectCommandError(db, user, 'contact.update', `huge-rev-${newId()}`, {
        expected_revision: 999999999, city: 'Huge',
      }, 'P0001', 'revision_conflict');

      for (const profile of [undefined, null, 'not-a-uuid']) {
        const input = { expected_revision: 1, display_name: 'X' };
        if (profile !== undefined) input.profile_id = profile;
        await expectCommandError(db, user, 'profile.update', `bad-pid-${newId()}`, input, '22023', 'invalid_profile_id');
      }
      await expectCommandError(db, user, 'profile.update', `typed-pid-${newId()}`, {
        expected_revision: 1, display_name: 'X', profile_id: 5,
      }, '22023', 'invalid_field_type');
      await expectCommandError(db, user, 'profile.update', `missing-pid-${newId()}`, {
        expected_revision: 1, display_name: 'X',
      }, '22023', 'invalid_profile_id');

      for (const name of [undefined, null, '', '   ', 'n'.repeat(201)]) {
        const input = { profile_id: profileId, expected_revision: 1 };
        if (name !== undefined) input.display_name = name;
        await expectCommandError(db, user, 'profile.update', `bad-name-${newId()}`, input, '22023', 'invalid_display_name');
      }
      assert.equal((await commandAs(db, user, 'profile.update', `max-name-${newId()}`, {
        profile_id: profileId, expected_revision: 1, display_name: 'n'.repeat(200),
      })).revision, 2);

      assert.equal((await commandAs(db, user, 'profile.update', `max-area-${newId()}`, {
        profile_id: profileId, expected_revision: 2, display_name: 'Types', area_label: 'a'.repeat(200),
      })).revision, 3);
      await expectCommandError(db, user, 'profile.update', `over-area-${newId()}`, {
        profile_id: profileId, expected_revision: 3, display_name: 'Types', area_label: 'a'.repeat(201),
      }, '22023', 'invalid_field_value');
      await expectCommandError(db, user, 'profile.update', `over-note-${newId()}`, {
        profile_id: profileId, expected_revision: 3, display_name: 'Types', profile_note: 'n'.repeat(2001),
      }, '22023', 'invalid_field_value');
      await expectCommandError(db, user, 'contact.update', `over-phone-${newId()}`, {
        expected_revision: 1, phone: '1'.repeat(41),
      }, '22023', 'invalid_field_value');

      for (const code of ['us', 'USA', '1A', 'U1', '']) {
        await expectCommandError(db, user, 'contact.update', `bad-cc-${newId()}`, {
          expected_revision: 1, country_code: code,
        }, '22023', 'invalid_country_code');
      }
      assert.equal((await commandAs(db, user, 'contact.update', `good-cc-${newId()}`, {
        expected_revision: 1, country_code: 'US',
      })).revision, 2);

      const seller = await insertIdentity(db);
      const sellerMembership = await commandAs(db, seller, 'onboard', `seller-${newId()}`, { role: 'seller', display_name: 'Seller Types' });
      for (const radius of ['5', 1.5, -1, 123456789, true]) {
        await expectCommandError(db, seller, 'profile.update', `bad-radius-${newId()}`, {
          profile_id: sellerMembership.profile_id, expected_revision: 1, display_name: 'Seller Types', service_radius_miles: radius,
        }, '22023', 'invalid_radius');
      }
      assert.equal((await commandAs(db, seller, 'profile.update', `zero-radius-${newId()}`, {
        profile_id: sellerMembership.profile_id, expected_revision: 1, display_name: 'Seller Types', service_radius_miles: 0,
      })).revision, 2);
      assert.equal((await commandAs(db, seller, 'profile.update', `max-radius-${newId()}`, {
        profile_id: sellerMembership.profile_id, expected_revision: 2, display_name: 'Seller Types', service_radius_miles: 99999999,
      })).revision, 3);
      assert.equal((await commandAs(db, seller, 'profile.update', `clear-radius-${newId()}`, {
        profile_id: sellerMembership.profile_id, expected_revision: 3, display_name: 'Seller Types', service_radius_miles: null,
      })).revision, 4);
      await expectCommandError(db, seller, 'profile.update', `over-pickup-${newId()}`, {
        profile_id: sellerMembership.profile_id, expected_revision: 4, display_name: 'Seller Types', pickup_availability: 'p'.repeat(501),
      }, '22023', 'invalid_field_value');

      await expectCommandError(db, user, 'profile.update', `buyer-seller-field-${newId()}`, {
        profile_id: profileId, expected_revision: 3, display_name: 'Types', service_radius_miles: 10,
      }, '22023', 'seller_fields_on_buyer');

      const cleared = await commandAs(db, user, 'contact.update', `clear-${newId()}`, {
        expected_revision: 2,
        phone: 'SYNTHETIC',
        city: 'Synthetic City',
        country_code: 'US',
      });
      assert.equal(cleared.revision, 3);
      const allCleared = await commandAs(db, user, 'contact.update', `clear-all-${newId()}`, {
        expected_revision: 3, phone: null, city: null, country_code: null,
      });
      assert.equal(allCleared.revision, 4);
      const contact = await db.query(
        'SELECT phone, city, country_code FROM hocalist.profile_contacts WHERE user_id=$1',
        [user],
      );
      assert.deepEqual(contact.rows[0], { phone: null, city: null, country_code: null });
    });

    await t.test('results stay minimal, receipts stay private and no privilege is synthesized', async () => {
      const user = await insertIdentity(db, {
        full_name: 'Hostile Metadata',
        role: 'admin',
        verified: true,
        onboarding_status: 'complete',
      });
      const onboard = await commandAs(db, user, 'onboard', `shape-${newId()}`, { role: 'buyer', display_name: 'Shapes' });
      assert.deepEqual(Object.keys(onboard).sort(), ['profile_id', 'revision', 'role']);
      const profile = await commandAs(db, user, 'profile.update', `shape-p-${newId()}`, {
        profile_id: onboard.profile_id, expected_revision: 1, display_name: 'Shapes v2',
      });
      assert.deepEqual(Object.keys(profile).sort(), ['profile_id', 'revision']);
      const contact = await commandAs(db, user, 'contact.update', `shape-c-${newId()}`, {
        expected_revision: 1, phone: 'SYNTHETIC-PRIVATE',
      });
      assert.deepEqual(contact, { revision: 2 });

      const columns = await db.query(
        `SELECT table_name, column_name FROM information_schema.columns
         WHERE table_schema='hocalist' AND table_name='memberships'
         ORDER BY ordinal_position`,
      );
      assert.deepEqual(columns.rows.map((row) => row.column_name), [
        'id', 'user_id', 'role', 'status', 'revision', 'created_at', 'updated_at',
      ]);
      const privileges = await db.query(
        `SELECT count(*)::int AS n FROM hocalist.memberships
         WHERE user_id=$1 AND (role NOT IN ('buyer','seller') OR status<>'active')`,
        [user],
      );
      assert.equal(privileges.rows[0].n, 0);

      await runAs(db, 'authenticated', user, async () => {
        try {
          await db.query('SELECT * FROM hocalist.command_receipts');
        } catch (error) {
          assert.equal(error.code, '42501');
          return;
        }
        assert.fail('authenticated must not read command receipts');
      });
      await runAs(db, 'authenticated', user, async () => {
        try {
          await db.query("INSERT INTO hocalist.memberships(user_id,role,status) VALUES ($1,'seller','active')", [user]);
        } catch (error) {
          assert.equal(error.code, '42501');
          return;
        }
        assert.fail('authenticated must not write memberships directly');
      });
    });

    await t.test('restriction is checked before replaying a stored receipt', async () => {
      const user = await insertIdentity(db);
      const key = `restricted-replay-${newId()}`;
      const input = { role: 'buyer', display_name: 'Replay Restricted' };
      const stored = await commandAs(db, user, 'onboard', key, input);
      await db.query("UPDATE hocalist.memberships SET status='disabled' WHERE user_id=$1", [user]);
      await expectCommandError(db, user, 'onboard', key, input, '42501', 'account_restricted');
      await expectCommandError(db, user, 'contact.update', `restricted-contact-${newId()}`, { expected_revision: 1 }, '42501', 'account_restricted');
      await db.query("UPDATE hocalist.memberships SET status='active' WHERE user_id=$1", [user]);
      assert.deepEqual(await commandAs(db, user, 'onboard', key, input), stored);
    });
  } finally {
    await db.close();
  }
});

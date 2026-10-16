// Disposable PostgreSQL checks for the administrator commercial configuration
// read (draft database/admin_completion/160_admin_commercial_config.sql).
//
// PGlite is single-connection: deterministic SQL proof for admin-only access,
// empty/unconfigured states, revision carrying and immutable batch rates. It is
// NOT live JWT or a live configuration apply.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ADMIN,
  BUYER,
  OUTSIDER,
  SELLER,
  applyAdminBaseline,
  callAs,
  read,
  seedAdminIdentities,
} from './fixture.mjs';

const option = (overrides = {}) => ({
  amount_minor: 2000,
  initial_fee_minor: 155,
  winning_total_minor: 375,
  rate_version: 'elite-v1',
  active: true,
  sort_order: 0,
  ...overrides,
});

const creditAdmin = (db, user, op, key, input) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.credit_admin_command($1,$2,$3::jsonb) AS data',
    [op, key, JSON.stringify(input)],
  ).then((rows) => rows[0].data);

const config = (db, user) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.admin_commercial_config() AS data',
  ).then((rows) => rows[0].data);

test('admin commercial configuration read on disposable PostgreSQL', async (t) => {
  const db = await applyAdminBaseline();
  try {
    await seedAdminIdentities(db);
    await db.exec(await read('../160_admin_commercial_config.sql'));

    await t.test('only an explicitly provisioned admin can read it', async () => {
      await assert.rejects(config(db, OUTSIDER), { code: '42501' });
      await assert.rejects(config(db, BUYER), { code: '42501' });
      await assert.rejects(
        callAs(db, 'anon', ADMIN, 'SELECT hocalist.admin_commercial_config()'),
        { code: '42501' },
      );
      await assert.rejects(
        callAs(db, 'service_role', ADMIN, 'SELECT hocalist.admin_commercial_config()'),
        { code: '42501' },
      );
    });

    await t.test('an unconfigured catalogue is an explicit empty state', async () => {
      const data = await config(db, ADMIN);
      assert.deepEqual(data.deposit_options, []);
      assert.equal(data.reward_policy, null);
    });

    await t.test('an admin adds a batch option and a reward policy', async () => {
      await creditAdmin(db, ADMIN, 'deposit_option.set', 'opt-1', option());
      const data = await config(db, ADMIN);
      assert.equal(data.deposit_options.length, 1);
      const row = data.deposit_options[0];
      assert.equal(row.amount_minor, 2000);
      assert.equal(row.initial_fee_minor, 155);
      assert.equal(row.winning_total_minor, 375);
      assert.equal(row.rate_version, 'elite-v1');
      assert.equal(row.active, true);
      assert.equal(row.revision, 1);

      await creditAdmin(db, ADMIN, 'reward_policy.set', 'policy-1', {
        normal_minor: 15,
        late_minor: 30,
        late_window_hours: 12,
        rule_version: 'reward-v1',
      });
      const withPolicy = await config(db, ADMIN);
      assert.equal(withPolicy.reward_policy.normal_minor, 15);
      assert.equal(withPolicy.reward_policy.late_minor, 30);
      assert.equal(withPolicy.reward_policy.late_window_hours, 12);
      assert.equal(withPolicy.reward_policy.revision, 1);
    });

    await t.test('edits carry the revision and stale revisions conflict', async () => {
      const before = (await config(db, ADMIN)).deposit_options[0];
      await creditAdmin(db, ADMIN, 'deposit_option.set', 'opt-1-edit', {
        id: before.id,
        ...option({ sort_order: 4 }),
        expected_revision: before.revision,
      });
      const after = (await config(db, ADMIN)).deposit_options[0];
      assert.equal(after.revision, before.revision + 1);
      assert.equal(after.sort_order, 4);

      await assert.rejects(
        creditAdmin(db, ADMIN, 'deposit_option.set', 'opt-1-stale', {
          id: before.id,
          ...option({ sort_order: 9 }),
          expected_revision: before.revision,
        }),
        { code: 'P0001', message: /revision_conflict/ },
      );

      await assert.rejects(
        creditAdmin(db, ADMIN, 'reward_policy.set', 'policy-stale', {
          normal_minor: 15,
          late_minor: 30,
          late_window_hours: 12,
          rule_version: 'reward-v2',
          expected_revision: 0,
        }),
        { code: 'P0001', message: /revision_conflict/ },
      );
    });

    await t.test('a retired option stays visible with its revision', async () => {
      const current = (await config(db, ADMIN)).deposit_options[0];
      await creditAdmin(db, ADMIN, 'deposit_option.retire', 'opt-1-retire', {
        id: current.id,
        expected_revision: current.revision,
      });
      const rows = (await config(db, ADMIN)).deposit_options;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].active, false);
      assert.equal(rows[0].revision, current.revision + 1);
    });

    await t.test('the read reprices no historical batch', async () => {
      await db.exec(`
        INSERT INTO hocalist.credit_batches(
          user_id,deposit_reference,original_minor,balance_minor,reserved_minor,
          initial_fee_minor,winning_total_minor,rate_version)
        VALUES ('${SELLER}','deposit-a',2000,2000,0,155,375,'elite-v1');
      `);
      await creditAdmin(db, ADMIN, 'deposit_option.set', 'opt-2', {
        ...option({ amount_minor: 4000, initial_fee_minor: 145, winning_total_minor: 325 }),
      });
      const batch = (
        await db.query(
          "SELECT initial_fee_minor, winning_total_minor, rate_version FROM hocalist.credit_batches WHERE user_id=$1",
          [SELLER],
        )
      ).rows[0];
      assert.equal(batch.initial_fee_minor, 155);
      assert.equal(batch.winning_total_minor, 375);
      assert.equal(batch.rate_version, 'elite-v1');
    });

    await t.test('the private configuration tables stay client-denied', async () => {
      await assert.rejects(
        callAs(db, 'authenticated', ADMIN, 'SELECT count(*) FROM hocalist.credit_deposit_options'),
        { code: '42501' },
      );
      await assert.rejects(
        callAs(db, 'authenticated', ADMIN, 'SELECT count(*) FROM hocalist.reward_policy'),
        { code: '42501' },
      );
      await assert.rejects(
        callAs(db, 'anon', ADMIN, 'SELECT count(*) FROM hocalist.credit_deposit_options'),
        { code: '42501' },
      );
    });

    await t.test('a repeat apply is refused before any replacement', async () => {
      await assert.rejects(db.exec(await read('../160_admin_commercial_config.sql')), {
        message: /already exists/,
      });
    });
  } finally {
    await db.close();
  }
});

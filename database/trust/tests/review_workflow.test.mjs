// Disposable PostgreSQL checks for the manual review workflow: reviewed
// evidence separate from Auth verification, reports as signals only, recorded
// restriction reasons and a working appeal route.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';

const A = '00000000-0000-4000-8000-00000000000a';
const ADM = '00000000-0000-4000-8000-00000000000e';
const OUT = '00000000-0000-4000-8000-00000000000f';
const MA = '10000000-0000-4000-8000-00000000000a';
const MAS = '10000000-0000-4000-8000-00000000001a';
const MADM = '10000000-0000-4000-8000-00000000000e';
const MOUT = '10000000-0000-4000-8000-00000000000f';

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

test('manual review, restriction and appeal workflow', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyStripeInbox(db);
    await applyAccountDrafts(db);
    for (const path of [
      '../../provider-rollout/apply.sql',
      '../../chat/010_chat_foundation.sql',
      '../../marketplace/020_marketplace_foundation.sql',
      '../../support/070_support_cases.sql',
      '../120_review_workflow.sql',
    ]) {
      await db.exec(await read(path));
    }
    await db.exec(`
      INSERT INTO auth.users(id, raw_user_meta_data) VALUES
        ('${A}','{}'),('${ADM}','{}'),('${OUT}','{}');
      INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
        ('${MA}','${A}','buyer','active'),('${MAS}','${A}','seller','active'),
        ('${MADM}','${ADM}','seller','active'),('${MOUT}','${OUT}','buyer','active');
      INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
        ('${MA}','Seller A'),('${MAS}','Seller A'),('${MADM}','Admin'),('${MOUT}','Outsider');
      INSERT INTO hocalist.platform_admins(user_id) VALUES ('${ADM}');
    `);

    const submit = (key, input) =>
      callAs(db, 'authenticated', A,
        'SELECT hocalist.verification_submit($1,$2::jsonb) AS data',
        [key, JSON.stringify(input)]).then((rows) => rows[0].data);
    const adminTrust = (op, key, input) =>
      callAs(db, 'authenticated', ADM,
        'SELECT hocalist.admin_trust_command($1,$2,$3::jsonb) AS data',
        [op, key, JSON.stringify(input)]).then((rows) => rows[0].data);

    let submission;
    await t.test('a seller submits reviewable evidence once', async () => {
      submission = await submit('ver-1', {
        kind: 'business',
        note: 'Registered business licence and storefront photo attached.',
        evidence_media_ids: [],
      });
      assert.equal(submission.status, 'pending');
      const replay = await submit('ver-1', {
        kind: 'business',
        note: 'Registered business licence and storefront photo attached.',
        evidence_media_ids: [],
      });
      assert.equal(replay.id, submission.id);
      await expectRejected(
        submit('ver-2', { kind: 'business', note: 'A second pending submission is not allowed.' }),
        'verification_pending',
        'P0001',
      );
      const status = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.verification_status() AS data'))[0].data;
      assert.equal(status.items.length, 1);
      assert.equal(status.email_phone.email_verified, false);
      assert.equal(status.email_phone.phone_verified, false);
    });

    await t.test('only a provisioned admin can review', async () => {
      await expectRejected(
        callAs(db, 'authenticated', OUT,
          "SELECT hocalist.admin_trust_command('verification.decide','x','{}'::jsonb)"),
        'admin_required',
      );
      await expectRejected(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.admin_trust_queue(50)'),
        'admin_required',
      );
    });

    await t.test('approval records the reviewer, reason and revision', async () => {
      const decided = await adminTrust('verification.decide', 'decide-1', {
        submission_id: submission.id,
        status: 'approved',
        reason: 'Licence matches the storefront evidence.',
        expected_revision: submission.revision,
      });
      assert.equal(decided.status, 'approved');
      const replay = await adminTrust('verification.decide', 'decide-1', {
        submission_id: submission.id,
        status: 'approved',
        reason: 'Licence matches the storefront evidence.',
        expected_revision: submission.revision,
      });
      assert.deepEqual(replay, decided);
      await expectRejected(
        adminTrust('verification.decide', 'decide-2', {
          submission_id: submission.id,
          status: 'rejected',
          reason: 'Changed mind',
          expected_revision: submission.revision,
        }),
        'revision_conflict',
        'P0001',
      );
      const status = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.verification_status() AS data'))[0].data;
      assert.equal(status.items[0].status, 'approved');
      assert.equal(status.items[0].decision_reason, 'Licence matches the storefront evidence.');
    });

    let caseId;
    await t.test('a report is reviewed without any automatic restriction', async () => {
      const created = (await callAs(db, 'authenticated', A,
        "SELECT hocalist.support_command('create','report-1',$1::jsonb) AS data",
        [JSON.stringify({ reason_code: 'safety', body: 'Buyer reported a no-show at the meetup.' })]))[0].data;
      caseId = created.id;
      const review = await adminTrust('health.review', 'health-1', {
        case_id: caseId,
        decision: 'no_action',
        reason: 'Schedules did not overlap; no further action.',
      });
      assert.equal(review.decision, 'no_action');
      const memberships = await db.query(
        'SELECT status FROM hocalist.memberships WHERE user_id=$1 ORDER BY role', [A]);
      assert.deepEqual(memberships.rows.map((row) => row.status), ['active', 'active']);
      const health = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.account_health_status() AS data'))[0].data;
      assert.equal(health.restrictions.length, 0);
      assert.equal(health.reports_are_signals_only, true);
    });

    let restriction;
    await t.test('a restriction records its reviewer reason and offers an appeal', async () => {
      restriction = await adminTrust('restriction.apply', 'restrict-1', {
        user_id: A,
        scope: 'seller',
        reason: 'Repeated confirmed no-shows after review.',
        source: 'health',
        case_id: caseId,
      });
      assert.equal(restriction.status, 'active');
      const membership = await db.query(
        "SELECT status FROM hocalist.memberships WHERE user_id=$1 AND role='seller'", [A]);
      assert.equal(membership.rows[0].status, 'restricted');
      const health = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.account_health_status() AS data'))[0].data;
      assert.equal(health.restrictions.length, 1);
      assert.equal(health.restrictions[0].reason, 'Repeated confirmed no-shows after review.');
      assert.equal(health.restrictions[0].appeal_status, null);
    });

    let appeal;
    await t.test('the user files one appeal and an admin reverses it', async () => {
      appeal = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.restriction_appeal_submit($1,$2::jsonb) AS data',
        ['appeal-1', JSON.stringify({
          restriction_id: restriction.id,
          body: 'The buyer cancelled both appointments on the day.',
        })]))[0].data;
      assert.equal(appeal.status, 'submitted');
      await expectRejected(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.restriction_appeal_submit($1,$2::jsonb)',
          ['appeal-2', JSON.stringify({ restriction_id: restriction.id, body: 'Second appeal body.' })]),
        'appeal_exists',
        'P0001',
      );
      const decided = await adminTrust('appeal.decide', 'appeal-decide-1', {
        appeal_id: appeal.id,
        status: 'reversed',
        reason: 'Cancellation records support the appeal.',
        expected_revision: appeal.revision,
      });
      assert.equal(decided.status, 'reversed');
      const membership = await db.query(
        "SELECT status FROM hocalist.memberships WHERE user_id=$1 AND role='seller'", [A]);
      assert.equal(membership.rows[0].status, 'active');
      const health = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.account_health_status() AS data'))[0].data;
      assert.equal(health.restrictions.length, 0);
    });

    await t.test('the admin queue reports the review history', async () => {
      const queue = (await callAs(db, 'authenticated', ADM,
        'SELECT hocalist.admin_trust_queue(50) AS data'))[0].data;
      assert.equal(queue.verifications.length, 1);
      assert.equal(queue.health_reviews.length, 1);
      assert.equal(queue.health_reviews[0].decision, 'no_action');
      assert.equal(queue.restrictions[0].status, 'revoked');
      assert.equal(queue.single_report_penalty, false);
    });

    await t.test('review tables stay closed to clients', async () => {
      await expectRejected(
        callAs(db, 'authenticated', A, 'SELECT * FROM hocalist.verification_submissions'),
        'permission denied',
      );
      await expectRejected(
        callAs(db, 'authenticated', A, 'SELECT * FROM hocalist.account_restrictions'),
        'permission denied',
      );
    });
  } finally {
    await db.close();
  }
});

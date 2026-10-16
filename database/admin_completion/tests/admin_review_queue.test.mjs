// Disposable PostgreSQL checks for the administrator review queue with carried
// revisions, actionable-state filters and keyset pagination
// (draft database/admin_completion/161_admin_review_queue.sql).
//
// Covers admin-only access, bounded evidence references, verification,
// health-review, restriction and appeal decisions with the committed revision,
// stale-revision refusal, newest-first ordering and multi-page paging. PGlite
// is single-connection deterministic SQL proof; it is NOT the accounts evidence
// gateway or live JWT proof.
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

const EVIDENCE_A = '90000000-0000-4000-8000-00000000000a';
const EVIDENCE_B = '90000000-0000-4000-8000-00000000000b';
const QUEUE_SQL =
  'SELECT hocalist.admin_review_queue($1,$2,$3,$4,$5,$6,$7) AS data';

// cursor, verification status, health state, restriction status
const queue = (db, user, overrides = {}) => {
  const params = [
    overrides.limit ?? 50,
    overrides.verificationsCursor ?? null,
    overrides.healthCursor ?? null,
    overrides.restrictionsCursor ?? null,
    overrides.verificationStatus ?? null,
    overrides.healthState ?? null,
    overrides.restrictionStatus ?? null,
  ];
  return callAs(db, 'authenticated', user, QUEUE_SQL, params).then((rows) => rows[0].data);
};

const trust = (db, user, op, key, input) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.admin_trust_command($1,$2,$3::jsonb) AS data',
    [op, key, JSON.stringify(input)],
  ).then((rows) => rows[0].data);

test('admin review queue filters, pagination and revisions on disposable PostgreSQL', async (t) => {
  const db = await applyAdminBaseline();
  try {
    await seedAdminIdentities(db);
    await db.exec(await read('../161_admin_review_queue.sql'));

    let submission;
    let caseId;

    await t.test('only an explicitly provisioned admin can read the queue', async () => {
      await assert.rejects(queue(db, BUYER), { code: '42501' });
      await assert.rejects(queue(db, OUTSIDER), { code: '42501' });
      await assert.rejects(
        callAs(db, 'anon', ADMIN, QUEUE_SQL, [50, null, null, null, null, null, null]),
        { code: '42501' },
      );
      await assert.rejects(
        callAs(db, 'service_role', ADMIN, QUEUE_SQL, [50, null, null, null, null, null, null]),
        { code: '42501' },
      );
      await assert.rejects(queue(db, ADMIN, { limit: 0 }), { code: '22023' });
      await assert.rejects(queue(db, ADMIN, { limit: 101 }), { code: '22023' });
      await assert.rejects(
        queue(db, ADMIN, { verificationStatus: 'lost' }),
        { code: '22023' },
      );
      await assert.rejects(queue(db, ADMIN, { verificationsCursor: 'bad' }), { code: '22023' });
    });

    await t.test('a pending submission keeps its revision and bounded evidence references', async () => {
      submission = (
        await callAs(
          db,
          'authenticated',
          SELLER,
          'SELECT hocalist.verification_submit($1,$2::jsonb) AS data',
          [
            'ver-evidence-1',
            JSON.stringify({
              kind: 'business',
              note: 'Registered business licence and storefront photo attached.',
              evidence_media_ids: [EVIDENCE_A, EVIDENCE_B],
            }),
          ],
        )
      )[0].data;
      assert.equal(submission.revision, 1);

      const data = await queue(db, ADMIN);
      const row = data.verifications.items.find((entry) => entry.id === submission.id);
      assert.equal(row.status, 'pending');
      assert.equal(row.revision, 1);
      assert.equal(row.evidence_count, 2);
      assert.deepEqual(row.evidence_media_ids, [EVIDENCE_A, EVIDENCE_B]);
      assert.equal(data.verifications.next_cursor, null);
      // References only: no URL, bucket path, token or credential.
      assert.doesNotMatch(JSON.stringify(row), /https?:|token|secret|bucket|storage/i);
    });

    await t.test('the evidence reference check is narrow and admin-only', async () => {
      const submissionId = (await queue(db, ADMIN)).verifications.items[0].id;
      const reference = (user, targetSubmission, media) =>
        callAs(
          db,
          'authenticated',
          user,
          'SELECT hocalist.admin_evidence_reference($1,$2) AS data',
          [targetSubmission, media],
        ).then((rows) => rows[0].data);

      const matched = await reference(ADMIN, submissionId, EVIDENCE_A);
      assert.equal(matched.reference_ok, true);
      assert.equal(matched.submission_id, submissionId);
      assert.equal(matched.status, 'pending');
      assert.doesNotMatch(JSON.stringify(matched), /https?:|bucket|token/i);

      const unmatched = await reference(
        ADMIN,
        submissionId,
        '90000000-0000-4000-8000-0000000000ff',
      );
      assert.equal(unmatched.reference_ok, false);

      await assert.rejects(reference(BUYER, submissionId, EVIDENCE_A), { code: '42501' });
      await assert.rejects(
        reference(ADMIN, '00000000-0000-4000-8000-0000000000ff', EVIDENCE_A),
        { code: 'P0002' },
      );
      await assert.rejects(reference(ADMIN, null, EVIDENCE_A), { code: '22023' });
    });

    await t.test('completed rows never hide newer pending work', async () => {
      await db.exec(`
        INSERT INTO hocalist.verification_submissions(
          user_id,kind,note,evidence_media_ids,status,reviewer_id,decision_reason,
          revision,created_at,decided_at,updated_at)
        SELECT '${SELLER}','identity','Historical reviewed submission '||n,
          '[]','approved','${ADMIN}','Historical reason',2,
          timestamptz '2026-09-01 00:00:00+00' + (n || ' minutes')::interval,
          timestamptz '2026-09-01 01:00:00+00', now()
        FROM generate_series(1,3) AS n;
      `);
      const newest = await queue(db, ADMIN, { limit: 2 });
      assert.equal(newest.verifications.items[0].id, submission.id);
      assert.equal(newest.verifications.items[0].status, 'pending');
      assert.ok(newest.verifications.next_cursor);

      const approvedOnly = await queue(db, ADMIN, { verificationStatus: 'approved' });
      assert.equal(approvedOnly.verifications.items.length, 3);
      assert.equal(
        approvedOnly.verifications.items.every((row) => row.status === 'approved'),
        true,
      );

      const pendingOnly = await queue(db, ADMIN, { verificationStatus: 'pending' });
      assert.deepEqual(
        pendingOnly.verifications.items.map((row) => row.id),
        [submission.id],
      );
    });

    await t.test('keyset paging is deterministic with tied timestamps', async () => {
      const tiedAt = '2026-09-02 00:00:00+00';
      await db.exec(`
        INSERT INTO hocalist.verification_submissions(
          user_id,kind,note,evidence_media_ids,status,revision,created_at,updated_at)
        SELECT '${SELLER}','identity','Tied submission '||n,
          '[]','pending',1,timestamptz '${tiedAt}',now()
        FROM generate_series(1,4) AS n;
      `);
      const seen = new Set();
      let cursor = null;
      let pages = 0;
      for (let i = 0; i < 10; i += 1) {
        const page = await queue(db, ADMIN, { verificationsCursor: cursor, limit: 2 });
        for (const row of page.verifications.items) {
          assert.equal(seen.has(row.id), false, `repeated ${row.id}`);
          seen.add(row.id);
        }
        pages += 1;
        if (!page.verifications.next_cursor) break;
        cursor = page.verifications.next_cursor;
      }
      assert.equal(pages >= 3, true);
      assert.equal(seen.size >= 7, true);
    });

    await t.test('health cases filter between needs-review and reviewed', async () => {
      const inserted = await db.query(`
        INSERT INTO hocalist.support_cases(reporter_id,reason_code,body,created_at)
        SELECT '${BUYER}','safety','Health case '||n,
          timestamptz '2026-09-03 00:00:00+00' + (n || ' minutes')::interval
        FROM generate_series(1,3) AS n
        RETURNING id;
      `);
      caseId = inserted.rows[2].id;
      await trust(db, ADMIN, 'health.review', 'health-1', {
        case_id: caseId,
        decision: 'watch',
        reason: 'Reviewed health signal with a recorded reason.',
      });
      const needsReview = await queue(db, ADMIN, { healthState: 'needs_review' });
      assert.equal(needsReview.health_reviews.items.length, 2);
      assert.equal(
        needsReview.health_reviews.items.every((row) => row.decision === null),
        true,
      );
      const reviewed = await queue(db, ADMIN, { healthState: 'reviewed' });
      assert.equal(reviewed.health_reviews.items.length, 1);
      assert.equal(reviewed.health_reviews.items[0].case_id, caseId);
      assert.equal(reviewed.health_reviews.items[0].decision, 'watch');
      assert.match(reviewed.health_reviews.items[0].decision_reason, /recorded reason/);
    });

    await t.test('restrictions carry revisions and filter by status', async () => {
      await trust(db, ADMIN, 'restriction.apply', 'restrict-1', {
        user_id: SELLER,
        scope: 'seller',
        reason: 'Reviewed restriction with a recorded reason.',
        source: 'health',
        case_id: caseId,
      });
      const active = await queue(db, ADMIN, { restrictionStatus: 'active' });
      assert.equal(active.restrictions.items.length, 1);
      const restriction = active.restrictions.items[0];
      assert.equal(restriction.status, 'active');
      assert.equal(restriction.revision, 1);

      const appeal = (
        await callAs(
          db,
          'authenticated',
          SELLER,
          'SELECT hocalist.restriction_appeal_submit($1,$2::jsonb) AS data',
          [
            'appeal-1',
            JSON.stringify({
              restriction_id: restriction.id,
              body: 'My evidence was not reviewed before this restriction was applied.',
            }),
          ],
        )
      )[0].data;
      assert.equal(appeal.revision, 1);

      let current = (await queue(db, ADMIN)).restrictions.items[0];
      assert.equal(current.appeal_id, appeal.id);
      assert.equal(current.appeal_status, 'submitted');
      assert.equal(current.appeal_revision, 1);

      await trust(db, ADMIN, 'appeal.decide', 'appeal-decide-1', {
        appeal_id: appeal.id,
        status: 'reversed',
        reason: 'The original restriction did not account for the attached receipt.',
        expected_revision: current.appeal_revision,
      });
      current = (await queue(db, ADMIN)).restrictions.items[0];
      assert.equal(current.appeal_status, 'reversed');
      assert.equal(current.appeal_revision, 2);
      assert.equal(current.status, 'revoked');
      assert.equal(current.revision, 2);

      const revoked = await queue(db, ADMIN, { restrictionStatus: 'revoked' });
      assert.equal(revoked.restrictions.items.length, 1);
      const activeNone = await queue(db, ADMIN, { restrictionStatus: 'active' });
      assert.equal(activeNone.restrictions.items.length, 0);

      await assert.rejects(
        trust(db, ADMIN, 'restriction.revoke', 'restrict-stale', {
          restriction_id: current.id,
          reason: 'Attempt to revoke an already revoked restriction.',
          expected_revision: 1,
        }),
        { code: 'P0001', message: /revision_conflict/ },
      );
    });

    await t.test('a decision advances the verification revision and stale decisions fail', async () => {
      const pending = (await queue(db, ADMIN, { verificationStatus: 'pending' })).verifications.items[0];
      await trust(db, ADMIN, 'verification.decide', 'ver-decide-1', {
        submission_id: pending.id,
        status: 'approved',
        reason: 'Business licence matches the submitted store details.',
        expected_revision: pending.revision,
      });
      const decided = (await queue(db, ADMIN, { verificationStatus: 'approved' })).verifications.items.find(
        (row) => row.id === pending.id,
      );
      assert.equal(decided.revision, pending.revision + 1);
      assert.match(decided.decision_reason, /licence/);

      await assert.rejects(
        trust(db, ADMIN, 'verification.decide', 'ver-decide-stale', {
          submission_id: pending.id,
          status: 'rejected',
          reason: 'Second review attempt.',
          expected_revision: pending.revision,
        }),
        { code: 'P0001', message: /revision_conflict/ },
      );
    });

    await t.test('private review tables stay client-denied', async () => {
      for (const table of [
        'verification_submissions',
        'account_restrictions',
        'restriction_appeals',
        'health_review_notes',
      ]) {
        await assert.rejects(
          callAs(db, 'authenticated', SELLER, `SELECT count(*) FROM hocalist.${table}`),
          { code: '42501' },
        );
      }
    });

    await t.test('a repeat apply is refused before any replacement', async () => {
      await assert.rejects(db.exec(await read('../161_admin_review_queue.sql')), {
        message: /already exists/,
      });
    });
  } finally {
    await db.close();
  }
});

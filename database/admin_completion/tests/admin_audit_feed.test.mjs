// Disposable PostgreSQL checks for the administrator cross-feature audit feed
// (draft database/admin_completion/163_admin_audit_feed.sql).
//
// Covers admin-only access, allowlisted sources, actor/query filters, keyset
// pagination and the exclusion of private message bodies, provider payloads,
// idempotency keys and credentials. PGlite is single-connection deterministic
// SQL proof; it is NOT live JWT or a complete production audit review.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ADMIN,
  BUYER,
  OUTSIDER,
  applyAdminBaseline,
  callAs,
  read,
  seedAdminIdentities,
} from './fixture.mjs';

const LISTING = '20000000-0000-4000-8000-0000000000a1';
const CATEGORY = '20000000-0000-4000-8000-0000000000a2';
const OPTION = '20000000-0000-4000-8000-0000000000a3';

const feed = (db, user, params = [50, null, null, null, null]) =>
  callAs(
    db,
    'authenticated',
    user,
    'SELECT hocalist.admin_audit_feed($1,$2,$3,$4,$5) AS data',
    params,
  ).then((rows) => rows[0].data);

test('admin cross-feature audit feed on disposable PostgreSQL', async (t) => {
  const db = await applyAdminBaseline();
  try {
    await seedAdminIdentities(db);
    await db.exec(await read('../163_admin_audit_feed.sql'));
    const caseId = (
      await db.query(
        `INSERT INTO hocalist.support_cases(reporter_id,reason_code,body)
         VALUES ($1,'safety','Reported meeting did not match the agreed location.')
         RETURNING id`,
        [BUYER],
      )
    ).rows[0].id;
    const restrictionId = '30000000-0000-4000-8000-0000000000b1';
    const appealId = '30000000-0000-4000-8000-0000000000b2';
    const withdrawalId = '30000000-0000-4000-8000-0000000000b3';
    await db.exec(`
      INSERT INTO hocalist.marketplace_receipts(user_id,operation,idempotency_key,request_hash,result)
      VALUES
        ('${ADMIN}','store.set_moderation','secret-moderation-key','h1',
          '{"id":"${LISTING}","moderation_status":"approved"}'),
        ('${ADMIN}','category.create','secret-category-key','h2',
          '{"id":"${CATEGORY}","status":"active"}'),
        ('${ADMIN}','credit_admin.deposit_option.set','secret-credit-key','h3',
          '{"id":"${OPTION}","active":true}'),
        ('${BUYER}','offer.submit','secret-client-key','h4',
          '{"id":"40000000-0000-4000-8000-0000000000c1"}');
      INSERT INTO hocalist.support_case_events(case_id,revision,actor_id,status,response)
      VALUES
        ('${caseId}',1,'${BUYER}','open','PRIVATE REPORTER RESPONSE TEXT'),
        ('${caseId}',2,'${ADMIN}','in_review','PRIVATE ADMIN RESPONSE TEXT');
      INSERT INTO hocalist.verification_submissions(
        user_id,kind,note,evidence_media_ids,status,reviewer_id,decision_reason,
        revision,created_at,decided_at)
      VALUES ('${BUYER}','business','Business licence and storefront photo attached.',
        '[]','approved','${ADMIN}','Reviewed business licence.',2,now(),now());
      INSERT INTO hocalist.account_restrictions(
        id,user_id,scope,status,reason,source,source_case_id,created_by,revision,created_at)
      VALUES ('${restrictionId}','${OUTSIDER}','buyer','active',
        'Recorded restriction reason.','review','${caseId}','${ADMIN}',1,now());
      INSERT INTO hocalist.restriction_appeals(
        id,restriction_id,user_id,body,status,reviewer_id,decision_reason,revision,created_at,decided_at)
      VALUES ('${appealId}','${restrictionId}','${OUTSIDER}',
        'Please review the recorded evidence again.','upheld','${ADMIN}',
        'Appeal upheld reason.',2,now(),now());
      INSERT INTO hocalist.health_review_notes(case_id,reviewer_id,decision,reason)
      VALUES ('${caseId}','${ADMIN}','watch','Health review reason.');
      INSERT INTO hocalist.call_settings_audit(revision,enabled,changed_by)
      VALUES (1,true,'${ADMIN}');
      INSERT INTO hocalist.withdrawal_requests(
        id,user_id,client_key,amount_minor,fee_minor,net_minor,status)
      VALUES ('${withdrawalId}','${BUYER}','withdraw-1',3000,250,2750,'failed');
      INSERT INTO hocalist.withdrawal_events(withdrawal_id,revision,event,actor,detail)
      VALUES ('${withdrawalId}',1,'failed','provider','PRIVATE PROVIDER DETAIL');
    `);

    await t.test('only an explicitly provisioned admin can read the feed', async () => {
      await assert.rejects(feed(db, BUYER), { code: '42501' });
      await assert.rejects(feed(db, OUTSIDER), { code: '42501' });
      await assert.rejects(
        callAs(db, 'anon', ADMIN, 'SELECT hocalist.admin_audit_feed(50,null,null,null,null)'),
        { code: '42501' },
      );
      await assert.rejects(
        callAs(db, 'service_role', ADMIN, 'SELECT hocalist.admin_audit_feed(50,null,null,null,null)'),
        { code: '42501' },
      );
    });

    await t.test('the feed exposes allowlisted sources without private bodies', async () => {
      const data = await feed(db, ADMIN);
      const sources = new Set(data.items.map((row) => row.source));
      for (const expected of ['moderation', 'configuration', 'commercial', 'support', 'trust', 'calls', 'withdrawals']) {
        assert.equal(sources.has(expected), true, `missing source ${expected}`);
      }
      assert.deepEqual(data.sources, [
        'moderation', 'configuration', 'commercial', 'support', 'trust', 'calls', 'withdrawals',
      ]);
      const payload = JSON.stringify(data);
      assert.doesNotMatch(payload, /PRIVATE|secret-|idempotency|request_hash|card|token/i);
      assert.doesNotMatch(payload, /offer\.submit/);
      const supportRows = data.items.filter((row) => row.source === 'support');
      assert.deepEqual(
        supportRows.map((row) => row.action).sort(),
        ['support.create', 'support.review'],
      );
      const trustRow = data.items.find((row) => row.action === 'appeal.decide');
      assert.equal(trustRow.detail, 'Appeal upheld reason.');
    });

    await t.test('source, actor and query filters are bounded and exact', async () => {
      const trustOnly = await feed(db, ADMIN, [50, null, 'trust', null, null]);
      assert.equal(trustOnly.items.length > 0, true);
      assert.equal(trustOnly.items.every((row) => row.source === 'trust'), true);

      const actorRows = await feed(db, ADMIN, [50, null, null, BUYER, null]);
      assert.equal(actorRows.items.every((row) => row.actor === BUYER), true);
      assert.equal(actorRows.items.some((row) => row.action === 'support.create'), true);
      assert.equal(actorRows.items.some((row) => row.source === 'withdrawals'), false);

      const queried = await feed(db, ADMIN, [50, null, null, null, 'moderation']);
      assert.equal(queried.items.length, 1);
      assert.equal(queried.items[0].action, 'store.set_moderation');
      assert.equal(queried.items[0].target, LISTING);

      await assert.rejects(feed(db, ADMIN, [50, null, 'everything', null, null]), { code: '22023' });
      await assert.rejects(feed(db, ADMIN, [50, null, null, null, 'x'.repeat(101)]), { code: '22023' });
      await assert.rejects(feed(db, ADMIN, [0, null, null, null, null]), { code: '22023' });
      await assert.rejects(feed(db, ADMIN, [50, 'bad-cursor', null, null, null]), { code: '22023' });
    });

    await t.test('keyset pagination has no repeated rows', async () => {
      const seen = new Set();
      let cursor = null;
      for (let page = 0; page < 20; page += 1) {
        const data = await feed(db, ADMIN, [2, cursor, null, null, null]);
        for (const row of data.items) {
          assert.equal(seen.has(row.id), false, `repeated audit id ${row.id}`);
          seen.add(row.id);
        }
        if (!data.next_cursor) break;
        cursor = data.next_cursor;
      }
      assert.equal(seen.size >= 10, true);
    });

    await t.test('audit source tables stay client-denied', async () => {
      for (const table of [
        'marketplace_receipts',
        'support_case_events',
        'call_settings_audit',
        'withdrawal_events',
      ]) {
        await assert.rejects(
          callAs(db, 'authenticated', ADMIN, `SELECT count(*) FROM hocalist.${table}`),
          { code: '42501' },
        );
      }
    });

    await t.test('a repeat apply is refused before any replacement', async () => {
      await assert.rejects(db.exec(await read('../163_admin_audit_feed.sql')), {
        message: /already exists/,
      });
    });
  } finally {
    await db.close();
  }
});

// Account lifecycle (130), seller categories (131), review evidence (132) and
// media cleanup (133) on a disposable PostgreSQL.
//
// Covers owner/participant/admin/outsider authorization, both roles, rejected
// cross-user evidence, retired catalogue handling and the no-deletion default.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  callAs,
  createAccountCompletionDb,
  expectRejected,
} from './fixture.mjs';

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const ADMIN = '00000000-0000-4000-8000-00000000000d';
const OUT = '00000000-0000-4000-8000-00000000000e';
const MA = '10000000-0000-4000-8000-00000000000a';
const MBA = '10000000-0000-4000-8000-00000000001a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MADM = '10000000-0000-4000-8000-00000000000d';
const MOUT = '10000000-0000-4000-8000-00000000000e';
const RECENT = '80000000-0000-4000-8000-000000000001';
const RECENT2 = '80000000-0000-4000-8000-000000000002';
const REPORT_IMAGE = '80000000-0000-4000-8000-000000000003';
const OLD_DRAFT = '80000000-0000-4000-8000-000000000004';
const OLD_DRAFT_2 = '80000000-0000-4000-8000-000000000007';
const OLD_ORPHAN = '80000000-0000-4000-8000-000000000005';
const OLD_EVIDENCE = '80000000-0000-4000-8000-000000000006';
const OLD_CHAT = '80000000-0000-4000-8000-000000000008';
const HASH = 'a'.repeat(64);

async function seedAccounts(db) {
  await db.exec(`
    INSERT INTO auth.users(id, raw_user_meta_data) VALUES
      ('${ADMIN}','{}'),('${OUT}','{}');
    INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES
      ('${MBA}','${A}','seller','active'),
      ('${MADM}','${ADMIN}','buyer','active'),
      ('${MOUT}','${OUT}','buyer','active');
    INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES
      ('${MBA}','Seller A'),('${MADM}','Admin'),('${MOUT}','Outsider');
    INSERT INTO hocalist.platform_admins(user_id) VALUES ('${ADMIN}');
  `);
}

function mediaRow(id, owner, purpose, { state = 'ready', created = "now()" } = {}) {
  return `INSERT INTO hocalist.media_images(id,owner_user_id,intent_key,purpose,state,content_hash,size_bytes,width,height,created_at)
    VALUES ('${id}','${owner}',gen_random_uuid(),'${purpose}','${state}','${HASH}',2048,64,64,${created});`;
}

test('account completion migrations', async (t) => {
  const db = await createAccountCompletionDb();
  try {
    await seedAccounts(db);
    await t.test('130 lifecycle tables, RLS and grants are installed', async () => {
      const rows = await db.query(`
        SELECT
          (SELECT count(*)::int FROM pg_tables WHERE schemaname='hocalist'
            AND tablename IN ('account_consent_documents','account_consents',
              'account_export_requests','account_exports','account_deletion_requests',
              'role_profile_categories','review_evidence_links','evidence_audit',
              'evidence_holds','media_cleanup_audit')) AS tables,
          has_function_privilege('authenticated','hocalist.account_lifecycle_status()','EXECUTE') AS lifecycle,
          has_function_privilege('authenticated','hocalist.account_export_build(uuid)','EXECUTE') AS builder,
          has_function_privilege('authenticated','hocalist.media_gateway(uuid,text,jsonb)','EXECUTE') AS gateway,
          has_function_privilege('service_role','hocalist.media_gateway(uuid,text,jsonb)','EXECUTE') AS gateway_service,
          has_function_privilege('authenticated','hocalist.media_cleanup_plan(integer)','EXECUTE') AS cleanup`);
      assert.deepEqual(rows.rows[0], {
        tables: 10,
        lifecycle: true,
        builder: false,
        gateway: false,
        gateway_service: true,
        cleanup: false,
      });
    });

    await t.test('consent documents stay admin-managed and versioned', async () => {
      await expectRejected(
        callAs(db, 'authenticated', A,
          "SELECT hocalist.admin_account_lifecycle_command('consent.save','c1',$1::jsonb)",
          [JSON.stringify({ id: 'terms', version: '2026-09', label: 'Terms', is_required: true, is_active: true, sort_order: 0 })]),
        'admin_required',
      );
      await callAs(db, 'authenticated', ADMIN,
        "SELECT hocalist.admin_account_lifecycle_command('consent.save','c1',$1::jsonb)",
        [JSON.stringify({ id: 'terms', version: '2026-09', label: 'Terms of service', is_required: true, is_active: true, sort_order: 0 })]);
      const saved = await callAs(db, 'authenticated', ADMIN,
        "SELECT hocalist.admin_account_lifecycle_command('consent.save','c2',$1::jsonb) AS data",
        [JSON.stringify({ id: 'terms', version: '2026-10', label: 'Terms of service', is_required: true, is_active: true, sort_order: 0, expected_revision: 1 })]);
      assert.equal(saved[0].data.revision, 2);

      const accepted = await callAs(db, 'authenticated', A,
        'SELECT hocalist.account_consent_record($1,$2::jsonb) AS data',
        ['consent-1', JSON.stringify({ document_id: 'terms', version: '2026-10' })]);
      assert.equal(accepted[0].data.version, '2026-10');
      const replay = await callAs(db, 'authenticated', A,
        'SELECT hocalist.account_consent_record($1,$2::jsonb) AS data',
        ['consent-1', JSON.stringify({ document_id: 'terms', version: '2026-10' })]);
      assert.equal(replay[0].data.accepted_at, accepted[0].data.accepted_at);
      await expectRejected(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.account_consent_record($1,$2::jsonb)',
          ['consent-2', JSON.stringify({ document_id: 'terms', version: '2025-01' })]),
        'consent_version_mismatch',
        'P0001',
      );
      const outsider = await callAs(db, 'authenticated', OUT,
        'SELECT hocalist.account_lifecycle_status() AS data');
      assert.equal(outsider[0].data.accepted_consents.length, 0);
      assert.equal(outsider[0].data.consent_documents.length, 1);
    });

    await t.test('export builds Hocalist-scope data and is owner-only', async () => {
      const started = await callAs(db, 'authenticated', A,
        "SELECT hocalist.account_export_request('export-1') AS data");
      assert.equal(started[0].data.status, 'ready');
      const replay = await callAs(db, 'authenticated', A,
        "SELECT hocalist.account_export_request('export-1') AS data");
      assert.equal(replay[0].data.request_id, started[0].data.request_id);

      const read = await callAs(db, 'authenticated', A,
        'SELECT hocalist.account_export_read($1) AS data',
        [started[0].data.request_id]);
      assert.equal(read[0].data.payload.schema_scope, 'hocalist');
      assert.equal(read[0].data.payload.memberships.length, 2);
      assert.equal(read[0].data.payload.role_profiles.length, 2);
      assert.equal(read[0].data.payload.deletion_requests.length, 0);
      assert.ok(read[0].data.payload.shared_identity_note.includes('not included'));

      await expectRejected(
        callAs(db, 'authenticated', OUT,
          'SELECT hocalist.account_export_read($1)',
          [started[0].data.request_id]),
        'export_not_found',
        'P0002',
      );
    });

    let deletion;
    await t.test('deletion is a request with holds, never an execution', async () => {
      deletion = (await callAs(db, 'authenticated', A,
        "SELECT hocalist.account_deletion_request('delete-1') AS data"))[0].data;
      assert.equal(deletion.status, 'requested');
      assert.equal(deletion.scope, 'hocalist');
      assert.deepEqual(deletion.holds, []);
      const replay = await callAs(db, 'authenticated', A,
        "SELECT hocalist.account_deletion_request('delete-2') AS data");
      assert.equal(replay[0].data.request_id, deletion.request_id);
      assert.equal(replay[0].data.reused, true);
      const profiles = await db.query('SELECT count(*)::int AS n FROM hocalist.profiles');
      const memberships = await db.query('SELECT count(*)::int AS n FROM hocalist.memberships WHERE user_id=$1', [A]);
      assert.ok(profiles.rows[0].n >= 4);
      assert.equal(memberships.rows[0].n, 2);
    });

    await t.test('a stale cancellation is refused and a valid one succeeds', async () => {
      await expectRejected(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.account_deletion_cancel($1,$2::jsonb)',
          ['cancel-bad', JSON.stringify({ request_id: deletion.request_id, expected_revision: 99 })]),
        'revision_conflict',
        'P0001',
      );
      const cancelled = await callAs(db, 'authenticated', A,
        'SELECT hocalist.account_deletion_cancel($1,$2::jsonb) AS data',
        ['cancel-1', JSON.stringify({ request_id: deletion.request_id, expected_revision: deletion.revision })]);
      assert.equal(cancelled[0].data.status, 'cancelled');
      const status = await callAs(db, 'authenticated', A,
        'SELECT hocalist.account_lifecycle_status() AS data');
      assert.equal(status[0].data.deletion, null);
    });

    await t.test('a withdrawal reservation blocks deletion until it clears', async () => {
      await db.exec(`
        INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,initial_fee_minor,winning_total_minor,rate_version)
        VALUES (gen_random_uuid(),'${B}','synthetic-deposit',4000,4000,155,375,'synthetic-v1');
        INSERT INTO hocalist.withdrawal_requests(user_id,client_key,amount_minor,fee_minor,net_minor)
        VALUES ('${B}','synthetic-withdrawal',3000,250,2750);
      `);
      const request = (await callAs(db, 'authenticated', B,
        "SELECT hocalist.account_deletion_request('delete-b') AS data"))[0].data;
      assert.equal(request.status, 'blocked');
      assert.ok(request.holds.some((hold) => hold.kind === 'withdrawal_processing'));
      await db.query("UPDATE hocalist.withdrawal_requests SET status='paid',provider_reference='synthetic' WHERE user_id=$1", [B]);
      await callAs(db, 'authenticated', B,
        'SELECT hocalist.account_deletion_cancel($1,$2::jsonb)',
        ['cancel-b', JSON.stringify({ request_id: request.request_id, expected_revision: request.revision })]);
      const after = (await callAs(db, 'authenticated', B,
        "SELECT hocalist.account_deletion_request('delete-b-2') AS data"))[0].data;
      assert.equal(after.status, 'requested');
    });

    await t.test('131 seller categories use real catalogue ids and revisions', async () => {
      await db.exec(`
        INSERT INTO hocalist.catalogue_categories(id,label,scope,status,sort_order) VALUES
          ('20000000-0000-4000-8000-000000000010','Trade services','service','active',1),
          ('20000000-0000-4000-8000-000000000011','Retired category','product','retired',2);
      `);
      const read = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.seller_profile_categories() AS data'))[0].data;
      assert.equal(read.membership_id, MBA);
      assert.equal(read.available.length, 2);
      const updated = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.profile_categories_update($1,$2,$3::jsonb) AS data',
        ['cat-1', read.revision, JSON.stringify(['20000000-0000-4000-8000-000000000010'])]))[0].data;
      assert.equal(updated.revision, read.revision + 1);
      assert.deepEqual(updated.category_ids, ['20000000-0000-4000-8000-000000000010']);

      const replay = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.profile_categories_update($1,$2,$3::jsonb) AS data',
        ['cat-1', read.revision, JSON.stringify(['20000000-0000-4000-8000-000000000010'])]))[0].data;
      assert.deepEqual(replay, updated);
      await expectRejected(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.profile_categories_update($1,$2,$3::jsonb)',
          ['cat-2', read.revision, JSON.stringify([])]),
        'revision_conflict',
        'P0001',
      );
      await expectRejected(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.profile_categories_update($1,$2,$3::jsonb)',
          ['cat-3', updated.revision, JSON.stringify(['20000000-0000-4000-8000-000000000011'])]),
        'retired_category_selection',
        '22023',
      );
      await expectRejected(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.profile_categories_update($1,$2,$3::jsonb)',
          ['cat-4', updated.revision, JSON.stringify(['20000000-0000-4000-8000-000000000099'])]),
        'unknown_category',
        'P0002',
      );
      await expectRejected(
        callAs(db, 'authenticated', OUT,
          'SELECT hocalist.seller_profile_categories()'),
        'seller_membership_required',
      );
      await expectRejected(
        callAs(db, 'authenticated', OUT,
          'SELECT hocalist.profile_categories_update($1,$2,$3::jsonb)',
          ['cat-5', 1, JSON.stringify([])]),
        'seller_membership_required',
      );
      const projection = (await callAs(db, 'authenticated', OUT,
        'SELECT hocalist.member_seller_categories($1) AS data', [MBA]))[0].data;
      assert.equal(projection.categories.length, 1);
    });

    await t.test('a retired selection stays readable on re-save', async () => {
      await db.exec(`
        INSERT INTO hocalist.role_profile_categories(membership_id,category_id)
        VALUES ('${MBA}','20000000-0000-4000-8000-000000000011');
        UPDATE hocalist.role_profiles SET revision=revision+1 WHERE membership_id='${MBA}';
      `);
      const read = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.seller_profile_categories() AS data'))[0].data;
      assert.equal(read.selected.length, 2);
      assert.equal(read.selected.find((row) => row.status === 'retired').selectable, false);
      const saved = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.profile_categories_update($1,$2,$3::jsonb) AS data',
        ['cat-retired', read.revision, JSON.stringify([
          '20000000-0000-4000-8000-000000000010',
          '20000000-0000-4000-8000-000000000011',
        ])]))[0].data;
      assert.equal(saved.category_ids.length, 2);
    });

    let submission;
    await t.test('132 evidence requires owned ready review media', async () => {
      await db.exec(mediaRow(RECENT, A, 'review'));
      await db.exec(mediaRow(RECENT2, B, 'review'));
      await db.exec(mediaRow(REPORT_IMAGE, A, 'report'));
      submission = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.verification_submit($1,$2::jsonb) AS data',
        ['ver-1', JSON.stringify({ kind: 'business', note: 'Licence for the storefront.', evidence_media_ids: [] })]))[0].data;
      assert.equal(submission.status, 'pending');

      await expectRejected(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.review_evidence_attach($1,$2::jsonb)',
          ['ev-bad', JSON.stringify({ submission_id: submission.id, media_ids: [RECENT2] })]),
        'invalid_evidence_reference',
        '22023',
      );
      const attached = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.review_evidence_attach($1,$2::jsonb) AS data',
        ['ev-1', JSON.stringify({ submission_id: submission.id, media_ids: [RECENT] })]))[0].data;
      assert.equal(attached.evidence_media_ids.length, 1);
      assert.equal(attached.revision, submission.revision + 1);
      const audit = await db.query('SELECT action, actor_id FROM hocalist.evidence_audit WHERE media_id=$1', [RECENT]);
      assert.equal(audit.rows.length, 1);
      assert.equal(audit.rows[0].action, 'attach');
    });

    await t.test('evidence reads are owner/admin only, never generic', async () => {
      const ownerRead = await db.query(
        "SELECT hocalist.media_read_review_evidence($1,$2) AS ok", [A, RECENT]);
      assert.equal(ownerRead.rows[0].ok, true);
      const adminRead = await db.query(
        "SELECT hocalist.media_read_review_evidence($1,$2) AS ok", [ADMIN, RECENT]);
      assert.equal(adminRead.rows[0].ok, true);
      const outsiderRead = await db.query(
        "SELECT hocalist.media_read_review_evidence($1,$2) AS ok", [OUT, RECENT]);
      assert.equal(outsiderRead.rows[0].ok, false);
      // Unlinked review media is not readable even by an admin.
      const unlinkedAdmin = await db.query(
        "SELECT hocalist.media_read_review_evidence($1,$2) AS ok", [ADMIN, REPORT_IMAGE]);
      assert.equal(unlinkedAdmin.rows[0].ok, false);
      // Media gateway: outsider read denied, owner read allowed.
      await expectRejected(
        db.query("SELECT hocalist.media_gateway($1,'read',$2::jsonb)", [OUT, JSON.stringify({ id: RECENT })]),
        'media_access_denied',
      );
      const gatewayOwner = await db.query(
        "SELECT hocalist.media_gateway($1,'read',$2::jsonb) AS data", [A, JSON.stringify({ id: RECENT })]);
      assert.equal(gatewayOwner.rows[0].data.id, RECENT);
      const gatewayAdmin = await db.query(
        "SELECT hocalist.media_gateway($1,'read',$2::jsonb) AS data", [ADMIN, JSON.stringify({ id: RECENT })]);
      assert.equal(gatewayAdmin.rows[0].data.id, RECENT);
    });

    await t.test('report evidence keeps the restricted support channel', async () => {
      await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE id=$1", [MBA]);
      const restrictedDeletion = (await callAs(db, 'authenticated', A,
        "SELECT hocalist.account_deletion_request('delete-restricted') AS data"))[0].data;
      assert.equal(restrictedDeletion.status, 'blocked');
      assert.ok(restrictedDeletion.holds.some((hold) => hold.kind === 'active_restriction'));
      const caseRow = (await callAs(db, 'authenticated', A,
        "SELECT hocalist.support_command('create','case-1',$1::jsonb) AS data",
        [JSON.stringify({ reason_code: 'safety', body: 'A restricted account still files a report.' })]))[0].data;
      const begin = await db.query(
        "SELECT hocalist.media_gateway($1,'begin',$2::jsonb) AS data",
        [A, JSON.stringify({ key: '80000000-0000-4000-8000-0000000000aa', purpose: 'report', hash: HASH })]);
      assert.equal(begin.rows[0].data.state, 'pending');
      const attached = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.report_evidence_attach($1,$2::jsonb) AS data',
        ['report-ev-1', JSON.stringify({ case_id: caseRow.id, media_ids: [REPORT_IMAGE] })]))[0].data;
      assert.equal(attached.case_id, caseRow.id);
      const adminRead = await db.query(
        "SELECT hocalist.media_read_review_evidence($1,$2) AS ok", [ADMIN, REPORT_IMAGE]);
      assert.equal(adminRead.rows[0].ok, true);
      // Review uploads stay blocked while restricted.
      await expectRejected(
        db.query(
          "SELECT hocalist.media_gateway($1,'begin',$2::jsonb)",
          [A, JSON.stringify({ key: '80000000-0000-4000-8000-0000000000bb', purpose: 'review', hash: HASH })]),
        'media_access_denied',
      );
      await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1", [MBA]);
    });

    await t.test('holds block removal and the admin contract exposes linkage', async () => {
      const held = (await callAs(db, 'authenticated', ADMIN,
        'SELECT hocalist.admin_evidence_hold($1,$2::jsonb) AS data',
        ['hold-1', JSON.stringify({ operation: 'set', media_id: RECENT, kind: 'legal', reason: 'Counsel hold for review.' })]))[0].data;
      assert.equal(held.kind, 'legal');
      await expectRejected(
        callAs(db, 'authenticated', A,
          'SELECT hocalist.review_evidence_detach($1,$2::jsonb)',
          ['detach-held', JSON.stringify({ submission_id: submission.id, media_id: RECENT })]),
        'evidence_hold_active',
        'P0001',
      );
      const queue = (await callAs(db, 'authenticated', ADMIN,
        'SELECT hocalist.admin_review_evidence(50) AS data'))[0].data;
      assert.equal(queue.retention_jobs_enabled, false);
      assert.equal(queue.items.length, 2);
      const reviewItem = queue.items.find((row) => row.media_id === RECENT);
      assert.equal(reviewItem.submission_id, submission.id);
      assert.equal(reviewItem.held, true);
      assert.equal(reviewItem.purpose, 'review');
      await expectRejected(
        callAs(db, 'authenticated', OUT,
          'SELECT hocalist.admin_review_evidence(50)'),
        'admin_required',
      );
      const released = (await callAs(db, 'authenticated', ADMIN,
        'SELECT hocalist.admin_evidence_hold($1,$2::jsonb) AS data',
        ['hold-2', JSON.stringify({ operation: 'release', hold_id: held.hold_id })]))[0].data;
      assert.equal(released.released, true);
      const detached = (await callAs(db, 'authenticated', A,
        'SELECT hocalist.review_evidence_detach($1,$2::jsonb) AS data',
        ['detach-1', JSON.stringify({ submission_id: submission.id, media_id: RECENT })]))[0].data;
      assert.equal(detached.evidence_media_ids.length, 0);
      const audits = await db.query('SELECT action FROM hocalist.evidence_audit WHERE media_id=$1 ORDER BY id', [RECENT]);
      assert.deepEqual(audits.rows.map((row) => row.action), ['attach', 'detach']);
    });

    await t.test('133 cleanup plans exclude evidence, held and referenced media', async () => {
      // Empty plans: reproducible for one limit, distinct across limits.
      const emptyA = (await db.query('SELECT hocalist.media_cleanup_plan(500) AS data')).rows[0].data;
      const emptyB = (await db.query('SELECT hocalist.media_cleanup_plan(500) AS data')).rows[0].data;
      const emptySmall = (await db.query('SELECT hocalist.media_cleanup_plan(1) AS data')).rows[0].data;
      assert.equal(emptyA.drafts.length, 0);
      assert.equal(emptyA.orphans.length, 0);
      assert.equal(emptyA.plan_hash, emptyB.plan_hash);
      assert.notEqual(emptyA.plan_hash, emptySmall.plan_hash);

      await db.exec(mediaRow(OLD_DRAFT, A, 'store', { state: 'pending', created: "now() - interval '2 days'" }));
      await db.exec(mediaRow(OLD_ORPHAN, A, 'profile', { created: "now() - interval '8 days'" }));
      await db.exec(mediaRow(OLD_EVIDENCE, A, 'review', { created: "now() - interval '8 days'" }));
      await db.exec(mediaRow(OLD_CHAT, A, 'chat', { created: "now() - interval '8 days'" }));
      await db.exec(`UPDATE hocalist.role_profiles SET image_media_id='${OLD_ORPHAN}' WHERE membership_id='${MBA}'`);
      await db.exec(`
        INSERT INTO hocalist.conversations(id,origin,listing_id)
        VALUES ('70000000-0000-4000-8000-000000000001','store_listing',gen_random_uuid());
        INSERT INTO hocalist.conversation_messages(
          conversation_id,sender_user_id,sender_profile_id,kind,text,
          client_message_id,request_hash,attachment_media_ids)
        VALUES ('70000000-0000-4000-8000-000000000001','${A}','${MBA}','attachment','',
          'cleanup-chat-1','synthetic','["${OLD_CHAT}"]');
      `);

      const plan = (await db.query('SELECT hocalist.media_cleanup_plan(500) AS data')).rows[0].data;
      assert.equal(plan.dry_run_only, true);
      assert.equal(plan.plan_limit, 500);
      assert.equal(typeof plan.plan_hash, 'string');
      assert.equal(plan.plan_hash.length, 64);
      assert.equal(plan.drafts.length, 1);
      assert.equal(plan.drafts[0].id, OLD_DRAFT);
      const orphanIds = plan.orphans.map((row) => row.id);
      assert.ok(!orphanIds.includes(OLD_ORPHAN), 'referenced avatar must be excluded');
      assert.ok(!orphanIds.includes(OLD_EVIDENCE), 'evidence must be excluded');
      assert.ok(!orphanIds.includes(OLD_CHAT), 'chat attachment must be excluded');
      const chatReferenced = await db.query('SELECT hocalist.media_referenced($1) AS used', [OLD_CHAT]);
      assert.equal(chatReferenced.rows[0].used, true);

      await expectRejected(
        db.query('SELECT hocalist.media_cleanup_apply($1,$2::jsonb)', [
          'cleanup-bad',
          JSON.stringify({ plan_hash: 'no', plan_limit: 500, dry_run: false }),
        ]),
        'plan_changed',
        'P0001',
      );
      const dry = (await db.query('SELECT hocalist.media_cleanup_apply($1,$2::jsonb) AS data', [
        'cleanup-dry',
        JSON.stringify({ plan_hash: plan.plan_hash, plan_limit: 500 }),
      ])).rows[0].data;
      assert.equal(dry.dry_run, true);
      assert.equal(dry.rejected_count, 0);
      const stillPending = await db.query('SELECT state FROM hocalist.media_images WHERE id=$1', [OLD_DRAFT]);
      assert.equal(stillPending.rows[0].state, 'pending');

      // A changed plan invalidates the old hash until it is recomputed.
      await db.exec(mediaRow(OLD_DRAFT_2, A, 'store', { state: 'pending', created: "now() - interval '3 days'" }));
      await expectRejected(
        db.query('SELECT hocalist.media_cleanup_apply($1,$2::jsonb)', [
          'cleanup-stale',
          JSON.stringify({ plan_hash: plan.plan_hash, plan_limit: 500, dry_run: true }),
        ]),
        'plan_changed',
        'P0001',
      );
      const nextPlan = (await db.query('SELECT hocalist.media_cleanup_plan(500) AS data')).rows[0].data;
      assert.notEqual(nextPlan.plan_hash, plan.plan_hash);
      // A different limit is a different candidate set and a different hash.
      const limited = (await db.query('SELECT hocalist.media_cleanup_plan(1) AS data')).rows[0].data;
      assert.equal(limited.plan_limit, 1);
      assert.notEqual(limited.plan_hash, nextPlan.plan_hash);

      // Identical non-empty candidates at different limits must still hash
      // differently, and apply must reject a hash confirmed under another
      // limit even though the candidate lists match.
      const limitedTwo = (await db.query('SELECT hocalist.media_cleanup_plan(2) AS data')).rows[0].data;
      assert.equal(limitedTwo.drafts.length, nextPlan.drafts.length);
      assert.deepEqual(
        limitedTwo.drafts.map((row) => row.id),
        nextPlan.drafts.map((row) => row.id),
      );
      assert.deepEqual(limitedTwo.orphans, nextPlan.orphans);
      assert.notEqual(limitedTwo.plan_hash, nextPlan.plan_hash);
      await expectRejected(
        db.query('SELECT hocalist.media_cleanup_apply($1,$2::jsonb)', [
          'cleanup-cross-limit',
          JSON.stringify({ plan_hash: limitedTwo.plan_hash, plan_limit: 500, dry_run: true }),
        ]),
        'plan_changed',
        'P0001',
      );
      const dryAtOwnLimit = (await db.query('SELECT hocalist.media_cleanup_apply($1,$2::jsonb) AS data', [
        'cleanup-own-limit',
        JSON.stringify({ plan_hash: limitedTwo.plan_hash, plan_limit: 2 }),
      ])).rows[0].data;
      assert.equal(dryAtOwnLimit.dry_run, true);
      assert.equal(dryAtOwnLimit.plan_limit, 2);

      const applied = (await db.query('SELECT hocalist.media_cleanup_apply($1,$2::jsonb) AS data', [
        'cleanup-run',
        JSON.stringify({ plan_hash: nextPlan.plan_hash, plan_limit: 500, dry_run: false }),
      ])).rows[0].data;
      assert.equal(applied.rejected_count, 2);
      assert.equal(applied.actor_kind, 'user');
      const rejected = await db.query('SELECT state FROM hocalist.media_images WHERE id=$1', [OLD_DRAFT]);
      assert.equal(rejected.rows[0].state, 'rejected');
      const evidence = await db.query('SELECT state FROM hocalist.media_images WHERE id=$1', [OLD_EVIDENCE]);
      assert.equal(evidence.rows[0].state, 'ready');
      const chat = await db.query('SELECT state FROM hocalist.media_images WHERE id=$1', [OLD_CHAT]);
      assert.equal(chat.rows[0].state, 'ready');

      // A service-role worker without a user subject is attributed explicitly
      // and never given a forged user id.
      const servicePlan = (await db.query('SELECT hocalist.media_cleanup_plan(500) AS data')).rows[0].data;
      await db.query("SELECT set_config('request.jwt.claim.sub','',false)");
      await db.exec('SET ROLE service_role');
      let serviceDry;
      try {
        serviceDry = (await db.query('SELECT hocalist.media_cleanup_apply($1,$2::jsonb) AS data', [
          'cleanup-service',
          JSON.stringify({ plan_hash: servicePlan.plan_hash, plan_limit: 500 }),
        ])).rows[0].data;
      } finally {
        await db.exec('RESET ROLE');
        await db.query("SELECT set_config('request.jwt.claim.sub','',false)");
      }
      assert.equal(serviceDry.actor_kind, 'service_role');
      assert.equal(serviceDry.dry_run, true);
      const serviceAudit = await db.query(
        "SELECT actor_kind, ran_by FROM hocalist.media_cleanup_audit WHERE plan_hash=$1 AND actor_kind='service_role'",
        [servicePlan.plan_hash],
      );
      assert.equal(serviceAudit.rows.length, 1);
      assert.equal(serviceAudit.rows[0].ran_by, null);

      const audit = await db.query('SELECT count(*)::int AS n FROM hocalist.media_cleanup_audit');
      assert.equal(audit.rows[0].n, 4);
      await expectRejected(
        callAs(db, 'authenticated', A, 'SELECT hocalist.media_cleanup_plan(10)'),
        'permission denied',
      );
    });

    await t.test('client tables stay closed and read-only paths hold', async () => {
      await expectRejected(
        callAs(db, 'authenticated', A, 'SELECT * FROM hocalist.evidence_holds'),
        'permission denied',
      );
      await expectRejected(
        callAs(db, 'authenticated', A, 'SELECT * FROM hocalist.account_consents'),
        'permission denied',
      );
      await expectRejected(
        callAs(db, 'authenticated', A, 'SELECT * FROM hocalist.review_evidence_links'),
        'permission denied',
      );
      // The purpose constraint accepts review/report and rejects anything else.
      await expectRejected(
        db.query(
          "INSERT INTO hocalist.media_images(owner_user_id,intent_key,purpose,content_hash) VALUES ($1,gen_random_uuid(),'evidence',$2)",
          [A, HASH]),
        'media_images_purpose_check',
        '23514',
      );
    });
  } finally {
    await db.close();
  }
});

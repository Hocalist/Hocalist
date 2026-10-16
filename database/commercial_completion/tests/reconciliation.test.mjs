// Reservation-expiry / reconciliation orchestration proof (migration 181).
//
// Accepted-meeting preservation, discovery-expiry release, no-show grace,
// winning-difference repair, repeated runs, the gated late-window override,
// weekly-slot preservation and the service/admin fence. PGlite is
// single-connection deterministic proof, not multi-writer proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createCommercialDb, callAs, expectRejected, IDS } from './fixture.mjs';

const { buyer, seller, admin } = IDS;

async function seedDeal(db, n, {
  requestStatus = 'closed',
  acceptanceExpires = null,
  meetingStatus = 'accepted',
  meetingExpires = "now() + interval '1 day'",
  targetStatus = 'reserved',
  charged = 0,
  initial = 100,
  winning = 200,
  original = 400,
  withSale = false,
  conversationMessages = false,
} = {}) {
  const id = String(n).padStart(12, '0');
  const request = `30000000-0000-4000-8001-${id}`;
  const offer = `40000000-0000-4000-8001-${id}`;
  const meeting = `50000000-0000-4000-8001-${id}`;
  const conversation = `60000000-0000-4000-8001-${id}`;
  const batch = `80000000-0000-4000-8001-${id}`;
  const target = `81000000-0000-4000-8001-${id}`;
  const reserved = winning - charged;
  const balance = original - charged;
  const weekStart = "date_trunc('week', now() AT TIME ZONE 'UTC')::date";
  await db.exec(`
    INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status,
      first_accepted_at,acceptance_expires_at)
    VALUES('${request}','${buyer}','${IDS.buyerMembership}','product','Deal ${n}','used','${requestStatus}',
      ${acceptanceExpires ? "now() - interval '8 days'" : 'NULL'},${acceptanceExpires ?? 'NULL'});
    INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
    VALUES('${offer}','${request}','${buyer}','${seller}','${IDS.sellerMembership}',
      '${requestStatus === 'closed' ? 'completed' : 'selected'}');
    INSERT INTO hocalist.conversations(id,origin,request_id,offer_id)
    VALUES('${conversation}','targeted_request','${request}','${offer}');
    INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status,meeting_expires_at)
    VALUES('${meeting}','${conversation}','${request}','${offer}','${buyer}','${seller}',
      '${meetingStatus}',${meetingExpires});
    INSERT INTO hocalist.credit_batches(id,user_id,deposit_reference,original_minor,balance_minor,
      reserved_minor,initial_fee_minor,winning_total_minor,rate_version)
    VALUES('${batch}','${seller}','dep-${n}',${original},${balance},${reserved},${initial},${winning},'v1');
    INSERT INTO hocalist.credit_targets(id,user_id,request_id,batch_id,offer_id,initial_minor,winning_minor,
      charged_minor,reserved_minor,status,week_start,rate_version)
    VALUES('${target}','${seller}','${request}','${batch}','${offer}',${initial},${winning},
      ${charged},${reserved},'${targetStatus}',${weekStart},'v1');
  `);
  if (conversationMessages) {
    await db.exec(`
      INSERT INTO hocalist.conversation_messages(conversation_id,sender_user_id,kind,text,client_message_id)
      VALUES('${conversation}','${buyer}','text','hi','m-a-${n}'),
            ('${conversation}','${seller}','text','hello','m-b-${n}');
    `);
  }
  if (withSale) {
    await db.exec(`
      INSERT INTO hocalist.offer_revisions(id,offer_id,sequence,price_minor,currency_code,message,
        schedule_date,schedule_time,schedule_timezone,schedule_offset_minutes,schedule_instant,
        place_choice,place_label,status,proposed_by_user_id)
      VALUES('41000000-0000-4000-8001-${id}','${offer}',1,42000,'USD','','2026-11-05','18:30',
        'America/New_York',-240,'2026-11-05T22:30:00Z','specific_place','Synthetic place','accepted','${seller}');
      INSERT INTO hocalist.sale_confirmations(id,request_id,meeting_id,offer_id,schedule_revision_id,
        buyer_user_id,seller_user_id)
      VALUES('70000000-0000-4000-8001-${id}','${request}','${meeting}','${offer}',
        '41000000-0000-4000-8001-${id}','${buyer}','${seller}');
    `);
  }
  return { request, offer, meeting, conversation, batch, target };
}

const sweep = (db, limit = 50) =>
  callAs(db, 'service_role', null,
    'SELECT hocalist.commercial_reconcile_sweep($1,$2) AS data', [limit, 'test'])
    .then((rows) => rows[0].data);

const targetRow = (db, id) =>
  db.query("SELECT status, charged_minor, reserved_minor FROM hocalist.credit_targets WHERE id=$1", [id])
    .then((r) => r.rows[0]);

const batchRow = (db, id) =>
  db.query('SELECT balance_minor, reserved_minor FROM hocalist.credit_batches WHERE id=$1', [id])
    .then((r) => r.rows[0]);

test('accepted meetings keep their reserve through discovery expiry', async () => {
  const db = await createCommercialDb();
  try {
    const deal = await seedDeal(db, 1, {
      acceptanceExpires: "now() - interval '1 hour'",
      meetingStatus: 'accepted',
      meetingExpires: "now() + interval '1 day'",
    });
    const run = await sweep(db);
    assert.equal(run.status, 'completed');
    assert.equal(run.released, 0);
    assert.equal(run.kept, 1);
    assert.equal((await targetRow(db, deal.target)).status, 'reserved');

    // A reschedule proposal also keeps the reservation.
    await db.exec(`
      UPDATE hocalist.meetings SET status='reschedule_proposed' WHERE id='${deal.meeting}';
    `);
    const run2 = await sweep(db);
    assert.equal(run2.released, 0);
    assert.equal(run2.kept, 1);
  } finally {
    await db.close();
  }
});

test('a pending proposal after discovery expiry keeps the reserve', async () => {
  const db = await createCommercialDb();
  try {
    const deal = await seedDeal(db, 2, {
      requestStatus: 'active',
      acceptanceExpires: "now() - interval '1 hour'",
      meetingStatus: 'proposed',
      meetingExpires: 'NULL',
    });
    const run = await sweep(db);
    assert.equal(run.released, 0);
    assert.equal(run.kept, 1);
    assert.equal((await targetRow(db, deal.target)).status, 'reserved');
  } finally {
    await db.close();
  }
});

test('an ended negotiation releases exactly once and keeps quota history', async () => {
  const db = await createCommercialDb();
  try {
    const deal = await seedDeal(db, 3, {
      meetingStatus: 'accepted',
      meetingExpires: "now() - interval '1 hour'",
    });
    const before = await batchRow(db, deal.batch);
    assert.deepEqual(before, { balance_minor: 400, reserved_minor: 200 });

    const run = await sweep(db);
    assert.equal(run.released, 1);
    assert.equal(run.examined, 1);
    const after = await targetRow(db, deal.target);
    assert.equal(after.status, 'released');
    assert.equal(after.reserved_minor, 0);
    // No release on a repeated run, and the weekly slot remains consumed.
    const run2 = await sweep(db);
    assert.equal(run2.released, 0);
    assert.equal(run2.examined, 0);
    const quota = await db.query(
      "SELECT count(*)::int AS n FROM hocalist.credit_targets WHERE user_id=$1 AND week_start=date_trunc('week',now() AT TIME ZONE 'UTC')::date",
      [seller]);
    assert.equal(quota.rows[0].n, 1);
  } finally {
    await db.close();
  }
});

test('the no-show grace is configurable and gated', async () => {
  const db = await createCommercialDb();
  try {
    const deal = await seedDeal(db, 4, {
      meetingStatus: 'accepted',
      meetingExpires: "now() - interval '2 hours'",
    });
    await callAs(db, 'authenticated', admin,
      'SELECT hocalist.reconciliation_admin_command($1,$2::jsonb)',
      ['grace-1', JSON.stringify({ no_show_grace_hours: 24 })]).then((r) => r[0]);
    const kept = await sweep(db);
    assert.equal(kept.kept, 1);
    assert.equal(kept.released, 0);

    await callAs(db, 'authenticated', admin,
      'SELECT hocalist.reconciliation_admin_command($1,$2::jsonb)',
      ['grace-2', JSON.stringify({ no_show_grace_hours: 0 })]).then((r) => r[0]);
    const released = await sweep(db);
    assert.equal(released.released, 1);

    // The unapproved late-window override cannot be switched on.
    await expectRejected(
      callAs(db, 'authenticated', admin,
        'SELECT hocalist.reconciliation_admin_command($1,$2::jsonb)',
        ['gate-1', JSON.stringify({ late_window_fee_override: true })]),
      'late_window_override_unapproved',
      'P0001',
    );
    await db.exec('UPDATE hocalist.reconciliation_policy SET late_window_fee_override=true');
    await expectRejected(sweep(db), 'late_window_override_unapproved', 'P0001');
    await db.exec('UPDATE hocalist.reconciliation_policy SET late_window_fee_override=false');
  } finally {
    await db.close();
  }
});

test('an interrupted winning settlement is repaired with only the difference', async () => {
  const db = await createCommercialDb();
  try {
    const deal = await seedDeal(db, 5, {
      targetStatus: 'initial_charged',
      charged: 100,
      withSale: true,
      meetingExpires: "now() + interval '1 hour'",
    });
    const batchBefore = await batchRow(db, deal.batch);
    assert.deepEqual(batchBefore, { balance_minor: 300, reserved_minor: 100 });

    const run = await sweep(db);
    assert.equal(run.settled, 1);
    assert.equal(run.released, 0);
    const after = await targetRow(db, deal.target);
    assert.equal(after.status, 'won');
    assert.equal(after.charged_minor, 200);
    assert.equal(after.reserved_minor, 0);
    const batchAfter = await batchRow(db, deal.batch);
    // Only the 100 difference is charged; the initial fee is not charged twice.
    assert.deepEqual(batchAfter, { balance_minor: 200, reserved_minor: 0 });

    const replay = await sweep(db);
    assert.equal(replay.settled, 0);
    assert.equal((await batchRow(db, deal.batch)).balance_minor, 200);
    const entries = await db.query(
      "SELECT count(*)::int AS n FROM hocalist.credit_entries WHERE target_id=$1 AND kind='win'",
      [deal.target]);
    assert.equal(entries.rows[0].n, 1);
  } finally {
    await db.close();
  }
});

test('withdrawn offers and closed requests release their own reserve only', async () => {
  const db = await createCommercialDb();
  try {
    const ended = await seedDeal(db, 6, {
      requestStatus: 'closed',
      meetingStatus: 'cancelled',
      meetingExpires: 'NULL',
    });
    const live = await seedDeal(db, 7, {
      requestStatus: 'active',
      acceptanceExpires: "now() + interval '1 day'",
      meetingStatus: 'accepted',
      meetingExpires: "now() + interval '2 days'",
    });
    const run = await sweep(db);
    assert.equal(run.released, 1);
    assert.equal(run.kept, 1);
    assert.equal((await targetRow(db, ended.target)).status, 'released');
    assert.equal((await targetRow(db, live.target)).status, 'reserved');
  } finally {
    await db.close();
  }
});

test('the sweep and internals are fenced to the service/admin boundary', async () => {
  const db = await createCommercialDb();
  try {
    await expectRejected(
      callAs(db, 'authenticated', seller,
        'SELECT hocalist.commercial_reconcile_sweep(10,$1)', ['x']),
      'permission denied',
      '42501',
    );
    await expectRejected(
      callAs(db, 'authenticated', seller,
        'SELECT hocalist.credit_reconcile_target_internal($1)',
        ['81000000-0000-4000-8001-000000000099']),
      'permission denied',
      '42501',
    );
    await expectRejected(
      callAs(db, 'authenticated', seller,
        "SELECT hocalist.admin_reconciliation_overview(5)"),
      'admin_required',
      '42501',
    );
    const overview = await callAs(db, 'authenticated', admin,
      'SELECT hocalist.admin_reconciliation_overview(5) AS data')
      .then((rows) => rows[0].data);
    assert.equal(overview.policy.late_window_fee_override, false);
    assert.ok(Array.isArray(overview.runs));
  } finally {
    await db.close();
  }
});

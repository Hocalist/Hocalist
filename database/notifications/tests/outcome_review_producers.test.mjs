// Disposable PostgreSQL checks for the outcome/review/withdrawal producers:
// recipient policy, preference suppression, deterministic dedupe and generic
// content. No push delivery is claimed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setup } from '../../outcomes/tests/fixture.mjs';

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const C = '00000000-0000-4000-8000-00000000000c';
const MA = '10000000-0000-4000-8000-00000000000a';
const MB = '10000000-0000-4000-8000-00000000000b';
const MC = '10000000-0000-4000-8000-00000000000c';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

const soldChain = (db, n, buyer, seller, buyerProfile, sellerProfile) => db.exec(`
  INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status)
  VALUES ('30000000-0000-4000-8000-00000000000${n}','${buyer}','${buyerProfile}','product','Sold item ${n}','used','closed');
  INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status,accepted_revision_id)
  VALUES ('40000000-0000-4000-8000-00000000000${n}','30000000-0000-4000-8000-00000000000${n}','${buyer}','${seller}','${sellerProfile}','completed',
          '41000000-0000-4000-8000-00000000000${n}');
  INSERT INTO hocalist.offer_revisions(id,offer_id,sequence,price_minor,currency_code,message,schedule_date,schedule_time,
    schedule_timezone,schedule_offset_minutes,schedule_instant,place_choice,place_label,status,proposed_by_user_id)
  VALUES ('41000000-0000-4000-8000-00000000000${n}','40000000-0000-4000-8000-00000000000${n}',1,42000,'USD','','2026-11-05','18:30',
    'America/New_York',-240,'2026-11-05T22:30:00Z','specific_place','Synthetic place','accepted','${seller}');
  INSERT INTO hocalist.conversations(id,origin,request_id,offer_id)
  VALUES ('60000000-0000-4000-8000-00000000000${n}','targeted_request','30000000-0000-4000-8000-00000000000${n}','40000000-0000-4000-8000-00000000000${n}');
  INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status,accepted_revision_id,meeting_expires_at)
  VALUES ('50000000-0000-4000-8000-00000000000${n}','60000000-0000-4000-8000-00000000000${n}','30000000-0000-4000-8000-00000000000${n}',
    '40000000-0000-4000-8000-00000000000${n}','${buyer}','${seller}','accepted','44000000-0000-4000-8000-00000000000${n}',now()+interval '1 day');
  INSERT INTO hocalist.sale_confirmations(id,request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id)
  VALUES ('70000000-0000-4000-8000-00000000000${n}','30000000-0000-4000-8000-00000000000${n}','50000000-0000-4000-8000-00000000000${n}',
    '40000000-0000-4000-8000-00000000000${n}','44000000-0000-4000-8000-00000000000${n}','${buyer}','${seller}');
`);

test('outcome, review and withdrawal producers', async (t) => {
  const db = await setup(false);
  try {
    for (const path of [
      '../../marketplace/021_request_coordinates.sql',
      '../../marketplace/023_multi_negotiation.sql',
      '../../outcomes/080_sale_confirmation.sql',
      '../../commercial/090_credit_batches.sql',
      '../../commercial/091_buyer_rewards.sql',
      '../../commercial/092_credit_settlement.sql',
      '../../commercial/093_withdrawals.sql',
      '../../support/070_support_cases.sql',
      '../../trust/120_review_workflow.sql',
      '../030_notification_inbox.sql',
      '../031_notification_producers.sql',
      '../034_outcome_review_producers.sql',
    ]) {
      await db.exec(await read(path));
    }
    const notifications = (user) =>
      db.query(
        'SELECT kind, title, body, deep_link, payload FROM hocalist.notifications WHERE user_id=$1 ORDER BY created_at',
        [user],
      ).then((rows) => rows.rows);

    await t.test('a confirmed purchase notifies both sides with generic content', async () => {
      await soldChain(db, 1, A, B, MA, MB);
      const buyer = (await notifications(A)).filter(
        (row) => row.title === 'Purchase confirmed',
      );
      const seller = (await notifications(B)).filter(
        (row) => row.title === 'Purchase confirmed',
      );
      assert.equal(buyer.length, 1);
      assert.equal(seller.length, 1);
      assert.equal(buyer[0].kind, 'meeting_update');
      assert.equal(
        buyer[0].deep_link,
        'hocalist://meetings/50000000-0000-4000-8000-000000000001',
      );
      const raw = JSON.stringify([buyer[0], seller[0]]);
      assert.doesNotMatch(raw, /address_line|postal|cus_|pi_/);
      assert.doesNotMatch(`${buyer[0].title} ${buyer[0].body}`, /\d{5}/);
      assert.equal('pin' in (buyer[0].payload ?? {}), false);
    });

    await t.test('a disabled deals topic suppresses only that recipient', async () => {
      await db.query(
        `INSERT INTO hocalist.notification_preferences(user_id,deals) VALUES ('${B}',false)`);
      await soldChain(db, 2, A, C, MA, MC);
      const purchases = (rows) =>
        rows.filter((row) => row.title === 'Purchase confirmed');
      assert.equal(purchases(await notifications(A)).length, 2);
      assert.equal(purchases(await notifications(C)).length, 1);
      assert.equal(
        purchases(await notifications(B)).length,
        1,
        'the seller with deals off receives nothing new',
      );
      await db.query(`UPDATE hocalist.notification_preferences SET deals=true WHERE user_id='${B}'`);
    });

    await t.test('a verification decision notifies once per decision revision', async () => {
      await db.query(
        `INSERT INTO hocalist.verification_submissions(id,user_id,kind,note)
         VALUES ('90000000-0000-4000-8000-000000000001','${B}','business','Registered licence for review.')`);
      const before = (await notifications(B)).length;
      await db.query(
        `UPDATE hocalist.verification_submissions
         SET status='approved',reviewer_id='${A}',decision_reason='Matches records',
             revision=revision+1,decided_at=now(),updated_at=now()
         WHERE id='90000000-0000-4000-8000-000000000001'`);
      const after = await notifications(B);
      assert.equal(after.length, before + 1);
      const latest = after[after.length - 1];
      assert.equal(latest.kind, 'account_update');
      assert.equal(latest.title, 'Verification review updated');
      await db.query(
        `UPDATE hocalist.verification_submissions SET updated_at=now()
         WHERE id='90000000-0000-4000-8000-000000000001'`);
      assert.equal((await notifications(B)).length, after.length, 'no duplicate without a status change');
    });

    await t.test('a recorded restriction and its appeal notify the user', async () => {
      const before = (await notifications(B)).length;
      await db.query(
        `INSERT INTO hocalist.account_restrictions(id,user_id,scope,reason,source,created_by)
         VALUES ('91000000-0000-4000-8000-000000000001','${B}','seller','Repeated no-shows','review','${A}')`);
      const afterRestriction = await notifications(B);
      assert.equal(afterRestriction.length, before + 1);
      assert.equal(afterRestriction[afterRestriction.length - 1].kind, 'account_update');
      assert.match(afterRestriction[afterRestriction.length - 1].body, /appeal/);
      await db.query(
        `INSERT INTO hocalist.restriction_appeals(id,restriction_id,user_id,body)
         VALUES ('92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','${B}','The buyer cancelled.')`);
      const beforeDecision = (await notifications(B)).length;
      await db.query(
        `UPDATE hocalist.restriction_appeals
         SET status='reversed',reviewer_id='${A}',decision_reason='Cancellation records',revision=revision+1,decided_at=now()
         WHERE id='92000000-0000-4000-8000-000000000001'`);
      const afterDecision = await notifications(B);
      assert.equal(afterDecision.length, beforeDecision + 1);
      assert.equal(afterDecision[afterDecision.length - 1].title, 'Appeal decision recorded');
    });

    await t.test('withdrawal processing and payment notify without amounts', async () => {
      const before = (await notifications(B)).length;
      await db.query(
        `INSERT INTO hocalist.withdrawal_requests(id,user_id,client_key,amount_minor,fee_minor,net_minor)
         VALUES ('94000000-0000-4000-8000-000000000001','${B}','wd-1',3000,250,2750)`);
      const processing = await notifications(B);
      assert.equal(processing.length, before + 1);
      await db.query(
        `UPDATE hocalist.withdrawal_requests
         SET status='paid',provider='stripe_global_payouts',provider_reference='po-1',updated_at=now()
         WHERE id='94000000-0000-4000-8000-000000000001'`);
      const paid = await notifications(B);
      assert.equal(paid.length, processing.length + 1);
      assert.equal(paid[paid.length - 1].title, 'Withdrawal paid');
      assert.doesNotMatch(JSON.stringify(paid[paid.length - 1]), /2750|3000/);
    });

    await t.test('a restricted account is never notified', async () => {
      await db.query(
        `UPDATE hocalist.memberships SET status='restricted' WHERE user_id='${B}' AND role='seller'`);
      await db.query(
        `INSERT INTO hocalist.account_restrictions(id,user_id,scope,reason,source,created_by)
         VALUES ('91000000-0000-4000-8000-000000000002','${B}','all','Second review','review','${A}')`);
      const rows = await notifications(B);
      assert.equal(
        rows.filter((row) => row.deep_link?.includes('91000000-0000-4000-8000-000000000002')).length,
        0,
      );
    });
  } finally {
    await db.close();
  }
});

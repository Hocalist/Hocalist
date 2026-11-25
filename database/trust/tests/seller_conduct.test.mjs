import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb, callAs, expectRejected, IDS} from '../../commercial_completion/tests/fixture.mjs';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');

test('seller report priority and score are separate', async () => {
  const db = await createCommercialDb();
  try {
    for (const path of [
      '../../support/070_support_cases.sql', '../120_review_workflow.sql',
      '../../admin_completion/161_admin_review_queue.sql',
      '../../../supabase/migrations/20261125202712_seller_conduct_review_priorities.sql',
    ]) await db.exec(await read(path));

    const buyers = [{id: IDS.buyer, membership: IDS.buyerMembership}];
    for (let i = 0; i < 2; i++) {
      const id = crypto.randomUUID(), membership = crypto.randomUUID();
      await db.query("INSERT INTO auth.users(id,raw_user_meta_data) VALUES($1,'{}')", [id]);
      await db.query("INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES($1,$2,'buyer','active')", [membership,id]);
      buyers.push({id,membership});
    }
    async function offer(buyer, seller = IDS.seller, membership = IDS.sellerMembership) {
      const request = (await db.query(`INSERT INTO hocalist.requests(buyer_user_id,buyer_profile_id,kind,title,condition,status)
        VALUES($1,$2,'product','Synthetic conduct test','used','active') RETURNING id`, [buyer.id,buyer.membership])).rows[0].id;
      return (await db.query(`INSERT INTO hocalist.offers(request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
        VALUES($1,$2,$3,$4,'submitted') RETURNING id`, [request,buyer.id,seller,membership])).rows[0].id;
    }
    const report = async (buyer, id, category) => (await callAs(db,'authenticated',buyer,
      'SELECT hocalist.seller_conduct_report($1,$2,$3,$4) AS data',
      [id,category,'This is a synthetic report for testing.',crypto.randomUUID()]))[0].data;
    const queue = async (user = IDS.admin, limit = 25, cursor = null) => (await callAs(db,'authenticated',user,
      "SELECT hocalist.admin_review_queue(p_limit=>$1,p_health_cursor=>$2,p_health_state=>'priority') AS data", [limit,cursor]))[0].data.health_reviews;
    const conduct = async (user = IDS.seller) => (await callAs(db,'authenticated',user,
      "SELECT hocalist.account_health_status()->'conduct' AS data"))[0].data;
    const review = (caseId, decision) => callAs(db,'authenticated',IDS.admin,
      "SELECT hocalist.admin_trust_command('health.review',$1,$2::jsonb)",
      [crypto.randomUUID(),JSON.stringify({case_id:caseId,decision,reason:'Synthetic reviewer decision.'})]);

    const offers = await Promise.all(buyers.map((buyer) => offer(buyer)));
    const price = await report(buyers[0].id, offers[0], 'price_disagreement');
    await expectRejected(report(buyers[1].id, offers[0], 'fraud'), 'offer_access_denied');
    await expectRejected(queue(IDS.seller), 'admin_required');
    await expectRejected(review(price.id,'violation_confirmed'), 'conduct_case_required', '22023');
    assert.deepEqual((await queue()).items, []);
    assert.deepEqual(await conduct(), {score:100,confirmed_incidents:0});

    const first = await report(buyers[0].id, offers[0], 'changed_terms');
    assert.equal((await report(buyers[0].id, offers[0], 'changed_terms')).id, first.id);
    await report(buyers[0].id, offers[0], 'other_conduct');
    const second = await report(buyers[1].id, offers[1], 'missed_meetup');
    const third = await report(buyers[2].id, offers[2], 'changed_terms');
    await db.query("UPDATE hocalist.seller_conduct_reports SET created_at=now()-interval '6 months'-interval '1 day' WHERE case_id=$1",[second.id]);
    assert.deepEqual((await queue()).items, [], 'duplicate and older reports do not qualify');
    await db.query("UPDATE hocalist.seller_conduct_reports SET created_at=now()-interval '5 months' WHERE case_id=$1",[second.id]);
    const [pattern] = (await queue()).items;
    assert.equal(pattern.seller_id, IDS.seller);
    assert.equal(pattern.reporting_buyers, 3);
    assert.equal(pattern.priority, 1);

    const urgentOffer = await offer(buyers[0], IDS.seller2, IDS.seller2Membership);
    const urgent = await report(buyers[0].id, urgentOffer, 'off_platform_evasion');
    const page = await queue(IDS.admin,1);
    assert.equal(page.items[0].case_id, urgent.id);
    assert.equal(page.items[0].priority, 2);
    assert.equal((await queue(IDS.admin,1,page.next_cursor)).items[0].seller_id, IDS.seller);
    assert.deepEqual(await conduct(IDS.seller2), {score:100,confirmed_incidents:0});
    await review(urgent.id,'violation_confirmed');
    assert.deepEqual(await conduct(IDS.seller2), {score:75,confirmed_incidents:1});
    await review(urgent.id,'no_action');
    assert.deepEqual(await conduct(IDS.seller2), {score:100,confirmed_incidents:0});
    await review(third.id,'violation_confirmed');
    assert.deepEqual(await conduct(), {score:90,confirmed_incidents:1});
    assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.account_restrictions')).rows[0].n,0);
    await db.query("UPDATE hocalist.seller_conduct_reports SET created_at=now()-interval '7 months' WHERE case_id=$1",[third.id]);
    assert.deepEqual(await conduct(), {score:100,confirmed_incidents:0});
  } finally {
    await db.close();
  }
});

test('safety alarms are private, durable, and reviewed without penalties', async () => {
  const db = await createCommercialDb();
  try {
    for (const path of [
      '../../support/070_support_cases.sql', '../120_review_workflow.sql',
      '../../admin_completion/161_admin_review_queue.sql',
      '../../../supabase/migrations/20261125202712_seller_conduct_review_priorities.sql',
      '../../../supabase/migrations/20261125203955_private_safety_phrase_alarms.sql',
    ]) await db.exec(await read(path));

    const admin = (sql, args = []) => callAs(db, 'authenticated', IDS.admin, sql, args);
    const buyer = (sql, args = []) => callAs(db, 'authenticated', IDS.buyer, sql, args);
    const report = async (reason, body) => (await buyer(
      "SELECT hocalist.support_command('create',$1,$2::jsonb) AS data",
      [crypto.randomUUID(), JSON.stringify({reason_code:reason,body})]
    ))[0].data;
    const count = async () => (await admin('SELECT hocalist.admin_safety_alarm_count() AS n'))[0].n;
    const queue = async (cursor = null) => (await admin(
      "SELECT hocalist.admin_review_queue(p_limit=>1,p_health_cursor=>$1,p_health_state=>'priority') AS data",
      [cursor]
    ))[0].data.health_reviews;

    await expectRejected(buyer('SELECT hocalist.admin_safety_alarm_count()'), 'admin_required');
    await expectRejected(buyer('SELECT hocalist.admin_safety_phrase_rules()'), 'admin_required');
    await expectRejected(buyer("SELECT hocalist.admin_save_safety_phrase('sample alarm phrase',true)"), 'admin_required');
    await expectRejected(buyer('SELECT * FROM hocalist.safety_phrase_matches'), 'permission denied');
    await expectRejected(admin("SELECT hocalist.admin_save_safety_phrase('disagreement',true)"), 'invalid_safety_phrase', '22023');

    const custom = 'threatened to smash my windows';
    const [{id}] = await admin('SELECT hocalist.admin_save_safety_phrase($1,true) AS id', [custom]);
    const flagged = await report('general', 'They THREATENED, to smash my windows and threatened to shoot me.');
    assert.deepEqual(Object.keys(flagged).sort(), ['id','revision','status']);
    await report('deal', 'The seller refused to lower the price, so I declined.');
    await report('deal', 'The message said threatened to shoot meow, unrelated.');
    const urgent = await report('safety', 'This is a separate synthetic safety report.');
    assert.equal(await count(), 1);
    const first = await queue();
    assert.equal(first.items[0].case_id, flagged.id);
    assert.equal(first.items[0].priority, 3);
    assert.deepEqual(first.items[0].matched_phrases, ['threatened to shoot me', custom]);
    assert.equal((await queue(first.next_cursor)).items[0].case_id, urgent.id);

    await admin('SELECT hocalist.admin_save_safety_phrase($1,false,$2,1)', ['threatened to smash a door', id]);
    await expectRejected(admin('SELECT hocalist.admin_save_safety_phrase($1,true,$2,1)', [custom, id]), 'revision_conflict', 'P0001');
    await report('general', 'They threatened to smash my windows again.');
    await report('general', 'They threatened to smash a door this time.');
    assert.equal(await count(), 1);
    assert.ok((await queue()).items[0].matched_phrases.includes(custom));
    await admin("SELECT hocalist.admin_trust_command('health.review',$1,$2::jsonb)",
      [crypto.randomUUID(), JSON.stringify({case_id:flagged.id, decision:'no_action', reason:'Synthetic review.'})]);
    assert.equal(await count(), 0);
    assert.equal((await queue()).items[0].case_id, urgent.id);

    const request = (await db.query(`INSERT INTO hocalist.requests(buyer_user_id,buyer_profile_id,kind,title,condition,status)
      VALUES($1,$2,'product','Synthetic alarm test','used','active') RETURNING id`, [IDS.buyer, IDS.buyerMembership])).rows[0].id;
    const offer = (await db.query(`INSERT INTO hocalist.offers(request_id,buyer_user_id,seller_user_id,seller_profile_id,status)
      VALUES($1,$2,$3,$4,'submitted') RETURNING id`, [request, IDS.buyer, IDS.seller, IDS.sellerMembership])).rows[0].id;
    await buyer('SELECT hocalist.seller_conduct_report($1,$2,$3,$4)',
      [offer, 'other_conduct', 'El vendedor ME AMENAZÓ CON UN ARMA.', crypto.randomUUID()]);
    assert.equal(await count(), 1);
    assert.equal((await queue()).items[0].seller_id, IDS.seller);
    const [{conduct}] = await callAs(db, 'authenticated', IDS.seller,
      "SELECT hocalist.account_health_status()->'conduct' AS conduct");
    assert.deepEqual(conduct, {score:100,confirmed_incidents:0});
    assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.account_restrictions')).rows[0].n, 0);
  } finally {
    await db.close();
  }
});

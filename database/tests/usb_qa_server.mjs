import { createServer } from 'node:http';
import { randomBytes, randomUUID, createHmac } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { createCommercialDb, IDS, callAs } from '../commercial_completion/tests/fixture.mjs';

import { seedUsbQaCatalogue } from './usb_qa_catalogue.mjs';

const port = Number(process.env.HOCALIST_USB_QA_PORT ?? 48913);
const clientKey = 'sb_publishable_local_hocalist_qa';
const password = 'UsbQa2026TestOnly';
const secret = randomBytes(32);
const identities = new Map([
  ['buyer@hocalist-qa.invalid', { id: IDS.buyer, name: 'USB QA Buyer', role: 'buyer' }],
  ['seller@hocalist-qa.invalid', { id: IDS.seller, name: 'USB QA Seller', role: 'seller' }],
]);
const sessions = new Map();
const refreshSessions = new Map();
const requestIds = { offer: randomUUID(), close: randomUUID() };
const buyerDemo = process.env.HOCALIST_USB_QA_BUYER_DEMO === '1';
const demoMeetupAvatarId = randomUUID();
const demoEliteAvatarId = randomUUID();
const demoBuyerAvatarId = randomUUID();
const demoSellers = [
  { user: IDS.seller, profile: IDS.sellerMembership, name: 'Maya QA', price: 27500,
    sales: 24, image: randomUUID(), file: 'maya-ipad.jpg', place: 'Riverside Park', day: 1 },
  { user: IDS.seller2, profile: IDS.seller2Membership, name: 'Alex QA', price: 29000,
    sales: 86, image: randomUUID(), file: 'alex-ipad.jpg', place: 'Downtown Library', day: 2 },
];
const readSql = (file) => readFile(new URL(file, import.meta.url), 'utf8');
const db = await createCommercialDb();

for (const file of [
  '../calls/110_call_signaling.sql',
  '../communication_completion/150_chat_block.sql',
  '../chat/012_credit_qualification.sql',
  '../notifications/030_notification_inbox.sql',
  '../notifications/031_notification_producers.sql',
  '../runtime_repairs/207_offer_submission_fee.sql',
  '../runtime_repairs/228_target_fee_policy.sql',
  '../runtime_repairs/229_earned_pro_policy.sql',
  '../runtime_repairs/231_deal_chat_threads.sql',
  '../runtime_repairs/235_paygo_payment_setup.sql',
  '../runtime_repairs/236_paygo_collection.sql',
  '../../supabase/migrations/20261027065137_elite_deferred_initial_fee.sql',
  '../../supabase/migrations/20261125190045_free_weekly_unique_buyers.sql',
  '../../supabase/migrations/20261125192441_pro_buyer_quota_and_offer_pull_out.sql',
  '../runtime_repairs/248_seller_customer_tools.sql',
  '../../supabase/migrations/20261125193543_elite_buyer_quota_and_lead_insights.sql',
  '../runtime_repairs/245_seller_home_summary.sql',
  '../discovery_completion/140_discovery_leads.sql',
  '../discovery_completion/145_seller_outcomes.sql',
  '../support/070_support_cases.sql',
  '../trust/120_review_workflow.sql',
  '../admin_completion/161_admin_review_queue.sql',
  '../../supabase/migrations/20261125202712_seller_conduct_review_priorities.sql',
]) await db.exec(await readSql(file));

await db.exec("ALTER TABLE hocalist.requests ADD COLUMN location_timezone text");
const timezoneMigration = await readSql('../runtime_repairs/210_request_location_timezone.sql');
for (const name of ['marketplace_lead_json', 'discovery_lead_json']) {
  const start = timezoneMigration.indexOf('CREATE OR REPLACE FUNCTION hocalist.' + name + '(');
  if (start < 0) throw new Error('Missing timezone projection: ' + name);
  await db.exec(timezoneMigration.slice(start, timezoneMigration.indexOf('$$;', start) + 3));
}

await db.exec("ALTER TABLE hocalist.offer_revisions ADD COLUMN IF NOT EXISTS place_latitude double precision, ADD COLUMN IF NOT EXISTS place_longitude double precision; ALTER TABLE hocalist.meeting_schedule_revisions ADD COLUMN IF NOT EXISTS place_latitude double precision, ADD COLUMN IF NOT EXISTS place_longitude double precision");
const definitions = async (file, names) => {
  const sql = await readSql(file);
  for (const name of names) {
    const start = sql.indexOf('CREATE OR REPLACE FUNCTION hocalist.' + name + '(');
    if (start < 0) throw new Error('Missing SQL definition: ' + name);
    await db.exec(sql.slice(start, sql.indexOf('$$;', start) + 3));
  }
};
// Use the same local setup for the legacy reschedule guard as the
// accept-offered-meeting contract test.
await definitions('../runtime_repairs/192_confirmed_meeting_coordinates.sql',
  ['marketplace_normalize_offer', 'meeting_normalize_schedule', 'meeting_revision_json', 'meeting_reschedule_propose']);
let reschedule = (await db.query("SELECT pg_get_functiondef('hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)'::regprocedure) AS d")).rows[0].d;
reschedule = reschedule.replace("IF v_row.status NOT IN ('accepted','reschedule_proposed') THEN",
  "-- seller_counterproposal\nIF v_user=v_row.seller_user_id AND EXISTS(SELECT 1 FROM hocalist.meeting_schedule_revisions WHERE meeting_id=p_meeting AND status='proposed' AND proposed_by_user_id=v_row.buyer_user_id) THEN UPDATE hocalist.meeting_schedule_revisions SET status='superseded',resolved_at=now() WHERE meeting_id=p_meeting AND status='proposed'; ELSIF v_row.status NOT IN ('accepted','reschedule_proposed') THEN")
  .replace("SET status = 'reschedule_proposed',", "SET status = CASE WHEN v_row.accepted_revision_id IS NULL THEN 'proposed' ELSE 'reschedule_proposed' END,");
await db.exec(reschedule);
for (const file of [
  '../runtime_repairs/meeting_reschedule_single_notification.sql',
  '../../supabase/migrations/20261121120000_accept_offered_meeting.sql',
  '../../supabase/migrations/20261121140000_confirmed_meeting_notification.sql',
  '../../supabase/migrations/20261120111441_buyer_offer_decline.sql',
  '../runtime_repairs/249_multi_seller_buyer_rewards.sql',
  '../runtime_repairs/274_buyer_catalogue_choices.sql',
  '../runtime_repairs/221_category_questions.sql',
  '../../supabase/migrations/20261126092555_marketplace_runtime_integration.sql',
  '../../supabase/migrations/20261126210128_limit_active_deals_per_pair.sql',
  '../../supabase/migrations/20261126213410_deal_price_proposals.sql',
]) await db.exec(await readSql(file));
await seedUsbQaCatalogue(db);
// Match the deployed read projection without replaying the historical migration
// guard or replacing its unrelated chat/support functions in this fixture.
const auditReads = await readSql('../audit_repairs/200_audit_reads.sql');
const metadata = auditReads.match(/DO \$metadata\$[\s\S]*?END \$metadata\$;/);
if (!metadata) throw new Error('Missing audited request metadata projection');
await db.exec(metadata[0]);
await definitions('../runtime_repairs/209_pair_conversations.sql', ['chat_open_internal', 'chat_deals']);
await db.exec('REVOKE ALL ON FUNCTION hocalist.chat_deals(uuid) FROM PUBLIC, anon, service_role; GRANT EXECUTE ON FUNCTION hocalist.chat_deals(uuid) TO authenticated');
await db.exec("INSERT INTO hocalist.reward_policy(singleton,normal_minor,late_minor,late_window_hours,rule_version) VALUES(true,15,30,12,'usb-qa-reward') ON CONFLICT (singleton) DO NOTHING");

for (const [label, title] of [
  ['offer', 'USB QA Camera Tripod'],
  ['close', 'USB QA Close Request'],
]) {
  await db.query(
    'INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,description,condition,status,city,location_timezone) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',
    [requestIds[label], IDS.buyer, IDS.buyerMembership, 'product', title, 'Synthetic USB test request.', 'used', 'active', 'Orlando, FL', 'America/New_York'],
  );
}
await db.exec("UPDATE hocalist.role_profiles SET area_label='Orlando, FL'");
await db.query("INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source) VALUES($1,'pro','admin')", [IDS.seller]);
await db.query("SELECT hocalist.credit_deposit_internal($1,'usb-qa-credit',5000,190,475,'test')", [IDS.seller]);

const command = async (identity, operation, key, values) => (await callAs(db, 'authenticated', identity,
  'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS result',
  [operation, key, values]))[0].result;
const { day: date, time: demoTime } = (await db.query(`
  SELECT ((now() AT TIME ZONE 'America/New_York')::date +
    CASE WHEN $1::boolean AND (now() AT TIME ZONE 'America/New_York')::time < '23:59'::time THEN 0 ELSE 1 END)::text AS day,
    CASE WHEN $1::boolean THEN '23:59' ELSE '15:00' END AS time
`, [buyerDemo])).rows[0];
await command(IDS.buyer, 'request.close', 'usb-qa-seed-previous-close-test',
  { request_id: requestIds.close, expected_revision: 1 });
const offer = await command(IDS.seller, 'offer.submit', 'usb-qa-seed-previous-offer', {
  request_id: requestIds.offer, price_minor: 3500, currency_code: 'USD',
  message: 'Tripod available for the synthetic QA meetup.',
  schedule_date: date, schedule_time: demoTime, schedule_timezone: 'America/New_York',
  place_choice: 'specific_place', place_label: 'USB QA Library',
  place_address: '123 Synthetic Test Rd, Orlando, FL',
  place_latitude: 28.54, place_longitude: -81.38, image_media_ids: [],
});
const selected = await command(IDS.buyer, 'offer.select', 'usb-qa-seed-previous-selection',
  { offer_id: offer.id, revision_id: offer.revisions[0].id, expected_offer_revision: offer.revision });
const opened = await command(IDS.buyer, 'conversation.open_offer', 'usb-qa-seed-previous-conversation',
  { offer_id: selected.id });
await callAs(db, 'authenticated', IDS.buyer, 'SELECT hocalist.chat_deal_send($1,$2,$3,$4)',
  [opened.conversation_id, selected.id, 'usb-qa-seed-previous-chat', 'USB QA message']);

if (buyerDemo) {
  const [{ revision }] = (await db.query('SELECT revision FROM hocalist.offers WHERE id=$1', [selected.id])).rows;
  await callAs(db, 'authenticated', IDS.buyer,
    'SELECT hocalist.meeting_accept_offer($1,$2,NULL,$3)',
    [selected.id, revision, 'usb-qa-demo-confirmed-meeting']);
  const product = randomUUID();
  const service = randomUUID();
  for (const [id, kind, title, condition, serviceType] of [
    [product, 'product', 'iPad Air 5, 256 GB', 'used', null],
    [service, 'service', 'House cleaning', null, 'one_time'],
  ]) {
    await db.query(
      "INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,service_type,status,city,location_timezone) VALUES($1,$2,$3,$4,$5,$6,$7,'active','Orlando, FL','America/New_York')",
      [id, IDS.buyer, IDS.buyerMembership, kind, title, condition, serviceType],
    );
  }
  await db.query("INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source) VALUES($1,'elite','admin')", [IDS.seller2]);
  await db.query("SELECT hocalist.credit_deposit_internal($1,'usb-qa-elite-credit',5000,190,475,'test')", [IDS.seller2]);
  for (const seller of demoSellers) {
    await db.query('UPDATE hocalist.role_profiles SET display_name=$1 WHERE membership_id=$2', [seller.name, seller.profile]);
    const [{ day }] = (await db.query("SELECT ((now() AT TIME ZONE 'America/New_York')::date+$1::int)::text AS day", [seller.day])).rows;
    // Give the second fixture offer a rate snapshot inside the late window.
    if (seller.day === 2) {
      await db.query("UPDATE hocalist.requests SET first_accepted_at=now(),acceptance_expires_at=now()+interval '6 hours' WHERE id=$1", [product]);
    }
    const sampleOffer = await command(seller.user, 'offer.submit', 'usb-qa-demo-offer-' + seller.day, {
      request_id: product, price_minor: seller.price, currency_code: 'USD',
      message: seller.day === 1 ? 'Protective case included' : 'USB-C cable included',
      schedule_date: day, schedule_time: '15:00', schedule_timezone: 'America/New_York',
      place_choice: 'specific_place', place_label: seller.place,
      place_latitude: 28.54, place_longitude: -81.38, image_media_ids: [seller.image],
    });
    // Fixture already has eligible interactions so both offers can still be
    // displayed in Compare offers. End-to-end qualification is tested separately.
    const [{ id: target }] = (await db.query(
      'UPDATE hocalist.credit_targets SET qualified_at=now() WHERE offer_id=$1 RETURNING id',
      [sampleOffer.id],
    )).rows;
    await db.query("SELECT hocalist.credit_settle_internal($1,'initial')", [target]);
  }
}

const identifier = /^[a-z_][a-z0-9_]*$/;
const safeIdentifier = (value) => {
  if (!identifier.test(value)) throw new Error('Invalid fixture field');
  return '"' + value + '"';
};
const json = (response, status, payload) => {
  response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  response.end(JSON.stringify(payload));
};
const readBody = async (request) => {
  let result = '';
  for await (const part of request) {
    result += part;
    if (result.length > 100_000) throw new Error('Fixture request too large');
  }
  // PostgREST clients can send JSON null for a no-argument RPC.
  const body = result ? JSON.parse(result) : null;
  if (body == null) return {};
  if (typeof body !== 'object' || Array.isArray(body)) {
    throw new Error('Fixture request must be a JSON object');
  }
  return body;
};
const claims = (email, user) => ({
  id: user.id, aud: 'authenticated', role: 'authenticated', email,
  email_confirmed_at: '2026-11-01T00:00:00Z',
  app_metadata: { provider: 'email', providers: ['email'] },
  user_metadata: { full_name: user.name, role: user.role },
  created_at: '2026-11-01T00:00:00Z', identities: [],
});
function session(email, user) {
  const now = Math.floor(Date.now() / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const base = encode({ alg: 'HS256', typ: 'JWT' }) + '.' +
    encode({ sub: user.id, iss: 'http://127.0.0.1:48913/auth/v1', aud: 'authenticated', role: 'authenticated', email, iat: now, exp: now + 3600, session_id: randomUUID() });
  const token = base + '.' + createHmac('sha256', secret).update(base).digest('base64url');
  const refresh = randomBytes(32).toString('hex');
  sessions.set(token, { email, user });
  refreshSessions.set(refresh, { email, user });
  return { access_token: token, token_type: 'bearer', expires_in: 3600, expires_at: now + 3600, refresh_token: refresh, user: claims(email, user) };
}
const visibleTables = new Set(['memberships', 'role_profiles', 'profile_contacts', 'notifications']);
let queue = Promise.resolve();
async function handle(request, response) {
  const endpoint = new URL(request.url, 'http://127.0.0.1:' + port);
  if (endpoint.pathname === '/__qa/state') {
    const requests = (await db.query(
      'SELECT title,status,revision FROM hocalist.requests WHERE id = ANY($1::uuid[]) ORDER BY title',
      [Object.values(requestIds)],
    )).rows;
    const offers = (await db.query(
      'SELECT o.status, o.revision, r.title, v.price_minor FROM hocalist.offers o JOIN hocalist.requests r ON r.id=o.request_id LEFT JOIN LATERAL (SELECT price_minor FROM hocalist.offer_revisions WHERE offer_id=o.id ORDER BY sequence DESC LIMIT 1) v ON true ORDER BY r.title',
    )).rows;
    const meetings = (await db.query('SELECT status, accepted_revision_id IS NOT NULL AS accepted_schedule FROM hocalist.meetings')).rows;
    const purchaseCount = (await db.query('SELECT count(*)::int AS n FROM hocalist.sale_confirmations')).rows[0].n;
    const rewards = (await db.query('SELECT count(*)::int AS rows,coalesce(sum(amount_minor),0)::int AS amount_minor FROM hocalist.buyer_rewards', [])).rows[0];
    const wallet = (await callAs(db, 'authenticated', IDS.buyer, 'SELECT hocalist.commercial_reward_wallet() AS result'))[0].result;
    return json(response, 200, { database: 'usb-qa', requests, offers, meetings, purchaseCount, rewards, wallet });
  }
  const demoImageRead = buyerDemo && endpoint.pathname === '/functions/v1/hocalist-media' &&
    endpoint.searchParams.get('action') === 'read' && request.method === 'POST';
  if (!demoImageRead && request.headers.apikey !== clientKey) return json(response, 401, { message: 'Invalid QA API key' });
  const token = request.headers.authorization?.replace(/^Bearer /i, '');
  const signedIn = sessions.get(token);
  const body = await readBody(request);
  if (endpoint.pathname === '/auth/v1/token') {
    if (endpoint.searchParams.get('grant_type') === 'refresh_token') {
      const saved = refreshSessions.get(body.refresh_token);
      return saved ? json(response, 200, session(saved.email, saved.user)) : json(response, 400, { msg: 'Invalid refresh token' });
    }
    const user = identities.get(body.email);
    if (!user || body.password !== password) return json(response, 400, { msg: 'Invalid login credentials' });
    return json(response, 200, session(body.email, user));
  }
  if (endpoint.pathname === '/auth/v1/logout') {
    sessions.delete(token);
    response.writeHead(204).end();
    return;
  }
  if (!signedIn) return json(response, 401, { message: 'Sign in to USB QA first' });
  const { email, user } = signedIn;
  if (endpoint.pathname === '/auth/v1/user') return json(response, 200, claims(email, user));
  if (demoImageRead) {
    const id = endpoint.searchParams.get('id');
    const seller = demoSellers.find((row) => row.image === id);
    const avatarPath = new Map([
      [demoBuyerAvatarId, '../../assets/approved_onboarding_home/buyer-avatar.png'],
      [demoMeetupAvatarId, '../../assets/approved_offers_chat/john-avatar.png'],
      [demoEliteAvatarId, '../../assets/approved_seller/home-seller-avatar.png'],
    ]).get(id);
    if (user.id !== IDS.buyer || (!seller && !avatarPath)) {
      return json(response, 404, { message: 'QA image unavailable' });
    }
    const path = avatarPath ?? './fixtures/buyer-offers/' + seller.file;
    const bytes = await readFile(new URL(path, import.meta.url));
    response.writeHead(200, {
      'content-type': avatarPath ? 'image/png' : 'image/jpeg', 'cache-control': 'no-store',
    });
    response.end(bytes);
    return;
  }
  if (!endpoint.pathname.startsWith('/rest/v1/')) return json(response, 404, { message: 'External providers disabled for USB QA' });
  const verb = endpoint.pathname.slice('/rest/v1/'.length);
  const profile = request.headers['content-profile'] ?? request.headers['accept-profile'];
  if (profile !== 'hocalist') return json(response, 400, { message: 'Only the synthetic marketplace schema is exposed' });

  if (verb.startsWith('rpc/')) {
    const name = verb.slice(4);
    if (buyerDemo && name === 'member_avatar' && user.id === IDS.buyer &&
        body.p_membership === IDS.buyerMembership) {
      return json(response, 200, {
        membership_id: IDS.buyerMembership, revision: 1, image_media_id: demoBuyerAvatarId,
      });
    }
    if (buyerDemo && name === 'seller_profile_public') {
      const seller = demoSellers.find((row) => row.profile === body.p_profile);
      if (user.id !== IDS.buyer || !seller) return json(response, 200, { available: false });
      const [{ plan }] = (await db.query("SELECT hocalist.entitlement_resolve_internal($1)->>'effective_plan' AS plan", [seller.user])).rows;
      return json(response, 200, {
        available: true, plan_code: plan, badges: ['Admin reviewed'], completed_sales: seller.sales,
        avatar_media_id: seller.user === IDS.seller ? demoMeetupAvatarId : demoEliteAvatarId,
      });
    }
    const parts = Object.keys(body);
    const bindings = parts.map((part, i) => safeIdentifier(part) + ' => $' + (i + 1));
    const values = parts.map((part) => body[part]);
    const rows = await callAs(db, 'authenticated', user.id,
      'SELECT hocalist.' + safeIdentifier(name) + '(' + bindings.join(', ') + ') AS result', values);
    if (name === 'marketplace_command') {
      console.log('WRITE ' + user.role + ' ' + body.p_operation);
    }
    return json(response, 200, rows[0]?.result ?? null);
  }

  if (request.method !== 'GET' || !visibleTables.has(verb)) {
    return json(response, 404, { code: 'PGRST205', message: 'QA table not exposed' });
  }
  const select = endpoint.searchParams.get('select') ?? '*';
  const projection = select === '*' ? '*' : select.split(',').map(safeIdentifier).join(', ');
  const values = [];
  const conditions = [];
  for (const [field, value] of endpoint.searchParams) {
    if (['select', 'order', 'limit', 'offset'].includes(field)) continue;
    const key = safeIdentifier(field);
    if (value.startsWith('eq.')) {
      values.push(value.slice(3));
      conditions.push(key + ' = $' + values.length);
    } else if (value === 'is.null') conditions.push(key + ' IS NULL');
    else throw new Error('Unsupported QA filter');
  }
  const order = endpoint.searchParams.get('order');
  const orderBy = order ? ' ORDER BY ' + order.split(',').map((term) => {
    const [column, direction] = term.split('.');
    return safeIdentifier(column) + (direction === 'desc' ? ' DESC' : ' ASC');
  }).join(', ') : '';
  const rows = await callAs(db, 'authenticated', user.id,
    'SELECT ' + projection + ' FROM hocalist.' + safeIdentifier(verb) +
    (conditions.length ? ' WHERE ' + conditions.join(' AND ') : '') + orderBy, values);
  const single = request.headers.accept?.includes('application/vnd.pgrst.object+json');
  return json(response, 200, single ? rows[0] ?? null : rows);
}
const server = createServer((request, response) => {
  queue = queue.then(() => handle(request, response)).catch((error) => {
    console.log('ERROR ' + request.method + ' ' + request.url.split('?')[0] + ' ' + (error.code ?? '') + ' ' + error.message);
    if (!response.headersSent) json(response, 400, { code: error.code ?? 'QA000', message: error.message });
    else response.end();
  });
}).listen(port, '127.0.0.1', () => console.log('USB QA READY on 127.0.0.1:' + server.address().port));

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readFile } from 'node:fs/promises';
import { createCommercialDb, IDS, callAs } from '../commercial_completion/tests/fixture.mjs';

// Exercise the same HTTP fixture and migration files used by the device preview.
test('marketplace fixture supports health, history, Any condition and buyer meetup changes', { timeout: 120000 }, async (t) => {
  const child = spawn(process.execPath, [fileURLToPath(new URL('./usb_qa_server.mjs', import.meta.url))], {
    env: { ...process.env, HOCALIST_USB_QA_PORT: '0', HOCALIST_USB_QA_BUYER_DEMO: '1' },
    stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true,
  });
  t.after(() => child.kill());
  const base = await new Promise((resolve, reject) => {
    let log = '';
    child.stdout.on('data', data => {
      log += data;
      const match = log.match(/USB QA READY on (127\.0\.0\.1:\d+)/);
      if (match) resolve('http://' + match[1]);
    });
    child.stderr.on('data', data => { log += data; });
    child.once('exit', code => reject(new Error('Fixture exited ' + code + ': ' + log.slice(-1500))));
  });
  const baseHeaders = { apikey: 'sb_publishable_local_hocalist_qa', 'content-type': 'application/json', 'content-profile': 'hocalist' };
  const login = async role => {
    const response = await fetch(base + '/auth/v1/token?grant_type=password', { method: 'POST', headers: baseHeaders,
      body: JSON.stringify({ email: role + '@hocalist-qa.invalid', password: 'UsbQa2026TestOnly' }) });
    assert.equal(response.status, 200);
    return (await response.json()).access_token;
  };
  const buyer = await login('buyer'), seller = await login('seller');
  const rpc = async (token, name, input = {}, expected = 200) => {
    const response = await fetch(base + '/rest/v1/rpc/' + name, { method: 'POST',
      headers: { ...baseHeaders, authorization: 'Bearer ' + token }, body: JSON.stringify(input) });
    const result = await response.json();
    assert.equal(response.status, expected, name + ': ' + JSON.stringify(result));
    return result;
  };
  for (const token of [buyer, seller]) {
    await rpc(token, 'verification_status');
    const health = await rpc(token, 'account_health_status');
    assert.ok(health.conduct);
  }
  // Match the SDK's no-argument RPC wire body, not only explicit {} calls.
  const billing = await rpc(seller, 'stripe_test_billing_status', null);
  assert.equal(billing.plan, 'free'); // No Stripe subscription in this fixture.
  const entitlement = await rpc(seller, 'account_entitlement', null);
  assert.equal(entitlement.effective_plan, 'pro'); // Existing admin access wins.
  await rpc(buyer, 'account_entitlement', null, 400);
  assert.deepEqual((await rpc(seller, 'marketplace_seller_outcomes', { p_limit: 100 })).items, []);
  await rpc(buyer, 'marketplace_seller_outcomes', { p_limit: 100 }, 400);
  const request = await rpc(buyer, 'marketplace_command', { p_operation: 'request.create', p_key: 'any-condition-integration',
    p_input: { kind: 'product', title: 'Any condition integration', description: 'Synthetic local request', condition: null,
      quantity: 1, use_home_address: false, city: 'Orlando', region: 'FL', country_code: 'US' } });
  assert.equal(request.condition, null);
  const reward = await rpc(buyer, 'commercial_request_potential_reward', { p_request: request.id });
  assert.equal(reward.estimated_minor, 0);
  await rpc(seller, 'commercial_request_potential_reward', { p_request: request.id }, 400);
  const meeting = (await rpc(buyer, 'meeting_list', { p_status: null, p_limit: 50, p_cursor: null })).items[0];
  const offers = (await rpc(buyer, 'marketplace_request_offers', {
    p_request: meeting.request_id, p_limit: 50, p_cursor: null,
  })).items;
  const meetingOffer = offers.find(offer => offer.id === meeting.offer_id);
  assert.equal(meetingOffer.request_title, 'USB QA Camera Tripod');
  const sellerOffer = await rpc(seller, 'marketplace_offer', { p_offer: meeting.offer_id });
  assert.equal(sellerOffer.request_title, meetingOffer.request_title);
  assert.deepEqual(await rpc(seller, 'call_command', { p_action: 'incoming', p_input: {} }), { call: null, enabled: false });
  await rpc(seller, 'chat_block_state', { p_conversation: meeting.conversation_id });
  const tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
  const change = { p_meeting: meeting.id, p_expected_revision: meeting.revision,
    p_key: 'reschedule-integration', p_action: 'reschedule', p_reason: 'schedule_changed', p_note: null,
    p_input: { schedule_date: tomorrow, schedule_time: '16:00', schedule_timezone: 'America/New_York',
      place_choice: 'specific_place', place_label: 'Test library', place_address: '123 Synthetic Test Rd, Orlando, FL', place_id: null } };
  const proposed = await rpc(buyer, 'meeting_buyer_manage', change);
  assert.equal(proposed.status, 'reschedule_proposed');
  assert.deepEqual(await rpc(buyer, 'meeting_buyer_manage', change), proposed);
  const accepted = await rpc(seller, 'meeting_respond', { p_meeting: meeting.id, p_accept: true,
    p_expected_revision: proposed.revision, p_key: 'accept-reschedule-integration' });
  assert.equal(accepted.accepted_schedule.schedule_date, tomorrow);
  const buyerMeetings = await rpc(buyer, 'meeting_list', { p_status: null, p_limit: 50, p_cursor: null });
  assert.equal(buyerMeetings.items.find(row => row.id === meeting.id).accepted_schedule.schedule_date, tomorrow);
  const input = { p_meeting: meeting.id, p_expected_revision: accepted.revision,
    p_key: 'cancel-integration', p_action: 'cancel', p_reason: 'schedule_changed', p_note: null, p_input: null };
  assert.match((await rpc(seller, 'meeting_buyer_manage', input, 400)).message, /meeting_access_denied/);
  const canceled = await rpc(buyer, 'meeting_buyer_manage', input);
  assert.equal(canceled.status, 'cancelled');
  assert.deepEqual(await rpc(buyer, 'meeting_buyer_manage', input), canceled);
  assert.equal(canceled.buyer_change_reason, 'schedule_changed');
  const sellerMeetings = await rpc(seller, 'meeting_list', { p_status: null, p_limit: 50, p_cursor: null });
  assert.equal(sellerMeetings.items.find(row => row.id === meeting.id).status, 'cancelled');
});

test('public plan response preserves access checks, unavailable profiles and existing fields', async () => {
  const db = await createCommercialDb();
  try {
    // Minimal original response contract; the migration must retain this body and ACL.
    await db.exec(`CREATE FUNCTION hocalist.seller_profile_public(p_profile uuid) RETURNS jsonb
      LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$ DECLARE u uuid; BEGIN
      PERFORM hocalist.marketplace_assert_role(auth.uid(),'buyer');
      SELECT user_id INTO u FROM hocalist.memberships WHERE id=p_profile AND role='seller' AND status='active';
      IF u IS NULL THEN RETURN jsonb_build_object('available',false); END IF;
      RETURN jsonb_build_object('available',true,'display_name','Existing name','phone',NULL);
      END $$;
      REVOKE ALL ON FUNCTION hocalist.seller_profile_public(uuid) FROM PUBLIC,anon,service_role;
      GRANT EXECUTE ON FUNCTION hocalist.seller_profile_public(uuid) TO authenticated;`);
    const migration = await readFile(new URL('../../supabase/migrations/20261126093001_public_seller_plan_contract.sql', import.meta.url), 'utf8');
    await db.exec(migration);
    await db.exec(migration);
    const profile = async (user = IDS.buyer, id = IDS.sellerMembership) =>
      (await callAs(db, 'authenticated', user, 'SELECT hocalist.seller_profile_public($1) AS data', [id]))[0].data;
    for (const plan of ['free', 'pro', 'elite']) {
      await db.query('DELETE FROM hocalist.seller_entitlements WHERE user_id=$1', [IDS.seller]);
      if (plan !== 'free') await db.query("INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source) VALUES($1,$2,'admin')", [IDS.seller, plan]);
      const result = await profile();
      assert.equal(result.plan_code, plan);
      assert.equal(result.display_name, 'Existing name');
      assert.equal(result.phone, null);
    }
    assert.deepEqual(await profile(IDS.buyer, IDS.buyerMembership), { available: false });
    await assert.rejects(profile(IDS.outsider));
    await assert.rejects(callAs(db,'anon',null,'SELECT hocalist.seller_profile_public($1)',[IDS.sellerMembership]), /permission denied/);
  } finally { await db.close(); }
});

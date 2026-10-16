// Disposable local SQL safety checks only. No network, credentials or provider sends.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import {createDisposableDb,applySignupSeed,applyStripeInbox} from '../tests/fixture.mjs';

const sql = name => readFile(new URL(name, import.meta.url),'utf8');
test('billing and push foundation denies cross-user and unauthorized operations', async () => {
 const db=await createDisposableDb();
 const a='00000000-0000-4000-8000-000000000001';
 const b='00000000-0000-4000-8000-000000000002';
 const device='10000000-0000-4000-8000-000000000001';
 const event='20000000-0000-4000-8000-000000000001';
 const secret='a'.repeat(64);
 const actor=async(role,user,statement,params=[])=>{
  await db.exec('BEGIN');
  try {
   await db.exec(`SET LOCAL ROLE ${role}`);
   await db.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[user]);
   const result=await db.query(statement,params);
   await db.exec('COMMIT'); return result.rows;
  } catch(error) { await db.exec('ROLLBACK'); throw error; }
 };
 try {
  await applySignupSeed(db); await applyStripeInbox(db);
  await db.exec(await sql('../rollout/account_apply.sql'));
  await db.exec(await sql('../provider-rollout/apply.sql'));
  await db.exec(await sql('../provider-rollout/verify.sql'));
  // The account verification must still hold after provider additions.
  await db.exec(await sql('../rollout/verify.sql'));
  await db.query('INSERT INTO auth.users(id,raw_user_meta_data) VALUES($1,$3::jsonb),($2,$3::jsonb)',[a,b,'{}']);
  for(const user of [a,b]) await actor('authenticated',user,
   "SELECT hocalist.account_command('onboard',$1,$2::jsonb)",[user,JSON.stringify({role:'seller',display_name:'Synthetic seller'})]);
  await assert.rejects(actor('anon','', 'SELECT * FROM hocalist.push_devices'),/permission denied/);
  await assert.rejects(actor('authenticated',a, 'SELECT * FROM hocalist.push_devices'),/permission denied/);
  await assert.rejects(actor('service_role','', 'SELECT * FROM hocalist.push_devices'),/permission denied/);
  assert.equal((await db.query('SELECT count(*)::int n FROM hocalist.stripe_test_plans WHERE enabled')).rows[0].n,0);
  await assert.rejects(actor('service_role','',
   'SELECT hocalist.stripe_test_checkout_begin($1,$2,$3)',[a,'pro',event]),/invalid_plan_or_key/);
  await assert.rejects(actor('authenticated',a,
   'SELECT hocalist.stripe_test_checkout_begin($1,$2,$3)',[a,'pro',event]),/permission denied/);
  await actor('authenticated',a,'SELECT hocalist.push_device_register($1,$2,$3,true)',[device,secret,'synthetic-token-for-user-a']);
  await assert.rejects(actor('authenticated',b,
   'SELECT hocalist.push_device_register($1,$2,$3,true)',[device,'b'.repeat(64),'synthetic-token-for-user-b']),/device_access_denied/);
  const enqueued=await actor('service_role','',
   'SELECT hocalist.notification_enqueue($1,$2,$3,$4) id',[a,event,'new_message',event]);
  assert.equal((await actor('authenticated',a,'SELECT id FROM hocalist.notifications')).length,1);
  assert.equal((await actor('authenticated',b,'SELECT id FROM hocalist.notifications')).length,0);
  await assert.rejects(actor('authenticated',b,
   'SELECT hocalist.notification_enqueue($1,$2,$3,$4)',[b,event,'new_message',event]),/permission denied/);
  const claimed=(await actor('service_role','','SELECT hocalist.push_claim() job'))[0].job;
  assert.ok(claimed.id && claimed.lease);
  const target=(await actor('service_role','',
   'SELECT hocalist.push_delivery_target($1,$2) target',[claimed.id,claimed.lease]))[0].target;
  assert.equal(target.notification_id,enqueued[0].id);
  await actor('authenticated',a,'SELECT hocalist.push_device_disable($1,$2)',[device,secret]);
  assert.equal((await actor('service_role','',
   'SELECT hocalist.push_delivery_target($1,$2) target',[claimed.id,claimed.lease]))[0].target,null);
  await assert.rejects(actor('service_role','',
   "SELECT hocalist.push_finish($1,$2,'accepted')",[claimed.id,claimed.lease]),/push_lease_lost/);
  const billing=(await actor('authenticated',a,'SELECT hocalist.stripe_test_billing_status() billing'))[0].billing;
  assert.equal(billing.plan,'free');
 } finally {await db.close();}
});

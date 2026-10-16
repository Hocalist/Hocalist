import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createDisposableDb, applySignupSeed, applyAccountDrafts, applyStripeInbox } from '../../tests/fixture.mjs';

const ADMIN='00000000-0000-4000-8000-000000000001';
const USER='00000000-0000-4000-8000-000000000002';
const M1='10000000-0000-4000-8000-000000000001';
const M2='10000000-0000-4000-8000-000000000002';
const read = path => readFile(new URL(path, import.meta.url),'utf8');
async function as(db,role,user,query,params=[]) {
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[user]);
  await db.exec(`SET ROLE ${role}`);
  try { return (await db.query(query,params)).rows; }
  finally { await db.exec('RESET ROLE'); }
}
test('admin read contracts on disposable PostgreSQL', async t => {
  const db=await createDisposableDb();
  try {
    await applySignupSeed(db); await applyStripeInbox(db); await applyAccountDrafts(db);
    for (const path of ['../../provider-rollout/apply.sql','../../chat/010_chat_foundation.sql','../../marketplace/020_marketplace_foundation.sql']) await db.exec(await read(path));
    await db.exec(`INSERT INTO auth.users(id,raw_user_meta_data) VALUES ('${ADMIN}','{}'),('${USER}','{}');
      INSERT INTO hocalist.profiles(id) VALUES ('${ADMIN}'),('${USER}') ON CONFLICT DO NOTHING;
      INSERT INTO hocalist.memberships(id,user_id,role,status) VALUES ('${M1}','${USER}','buyer','active'),('${M2}','${USER}','seller','active');
      INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES ('${M1}','Test Buyer'),('${M2}','Test Seller');
      INSERT INTO hocalist.profile_contacts(user_id,phone,address_line1) VALUES ('${USER}','PRIVATE PHONE','PRIVATE STREET');
      INSERT INTO hocalist.platform_admins(user_id) VALUES ('${ADMIN}');
      INSERT INTO hocalist.stripe_test_subscriptions(membership_id,subscription_id,plan_code,provider_status,cancel_at_period_end) VALUES ('${M2}','sub_synthetic','pro','active',false);`);
    const apply=await read('../060_admin_reads.sql');
    await db.exec(apply);
    const records=(user,params=[])=>as(db,'authenticated',user,'SELECT hocalist.admin_records($1,$2,$3,$4,$5) AS data',params.length?params:['users',50,null,null,null]);
    await t.test('only an explicitly provisioned admin can read',async()=>{
      await assert.rejects(records(USER), {code:'42501'});
      await assert.rejects(as(db,'anon',USER,"SELECT hocalist.admin_overview()"),{code:'42501'});
      await assert.rejects(as(db,'service_role',ADMIN,"SELECT hocalist.admin_overview()"),{code:'42501'});
      assert.equal((await records(ADMIN))[0].data.items.length,2);
    });
    await t.test('pagination has no repeated rows and search/status are applied',async()=>{
      const first=(await records(ADMIN,['users',1,null,null,null]))[0].data;
      const second=(await records(ADMIN,['users',1,first.next_cursor,null,null]))[0].data;
      assert.notEqual(first.items[0].id,second.items[0].id); assert.equal(second.next_cursor,null);
      const filtered=(await records(ADMIN,['users',50,null,'Seller','active']))[0].data;
      assert.equal(filtered.items.length,1); assert.equal(filtered.items[0].id,M2);
    });
    await t.test('private contacts and provider credentials never enter projections',async()=>{
      const users=JSON.stringify(await records(ADMIN));
      assert.doesNotMatch(users,/PRIVATE PHONE|PRIVATE STREET/);
      const billing=JSON.stringify(await records(ADMIN,['billing',50,null,null,null]));
      assert.doesNotMatch(billing,/sub_synthetic|customer_id|session_url/);
      assert.match(billing,/pro/);
    });
    await t.test('empty request and offer pages are honest; overview counts memberships',async()=>{
      for(const resource of ['requests','offers']) assert.deepEqual((await records(ADMIN,[resource,50,null,null,null]))[0].data.items,[]);
      const overview=(await as(db,'authenticated',ADMIN,'SELECT hocalist.admin_overview() AS data'))[0].data;
      assert.equal(overview.active_memberships,2); assert.equal(overview.test_subscriptions,1);
    });
    await t.test('invalid resource, size and search rejected',async()=>{
      for(const params of [['contacts',50,null,null,null],['users',0,null,null,null],['users',101,null,null,null],['users',50,null,'x'.repeat(101),null]])
        await assert.rejects(records(ADMIN,params),{code:'22023'});
    });
    await t.test('restricted admin loses access without removing the admin grant',async()=>{
      await db.exec(`INSERT INTO hocalist.memberships(user_id,role,status) VALUES('${ADMIN}','buyer','restricted')`);
      await assert.rejects(records(ADMIN),{code:'42501'});
      await db.exec(`UPDATE hocalist.memberships SET status='active' WHERE user_id='${ADMIN}'`);
    });
    await t.test('verify passes; repeat apply aborts; containment removes only access',async()=>{
      await db.exec(await read('../verify.sql'));
      await assert.rejects(db.exec(apply),/already exist/); await db.exec('ROLLBACK');
      await db.exec(await read('../containment.sql'));
      await assert.rejects(records(ADMIN),{code:'42501'});
      assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.stripe_test_subscriptions')).rows[0].n,1);
    });
  } finally { await db.close(); }
});

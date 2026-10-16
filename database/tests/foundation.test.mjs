import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  SYNTHETIC,
  applySignupSeed,
  asRole,
  createDisposableDb,
  expectDenied,
  loadSql,
  seedSyntheticIdentities,
} from './fixture.mjs';

const { a, b, outsider, ma, mb, pending } = SYNTHETIC;

test('membership/private profile SQL permissions in disposable PostgreSQL', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await db.exec(await loadSql('../drafts/003_membership_private_profiles.sql'));
    await seedSyntheticIdentities(db);
    async function as(role, user, body) {
      await asRole(db, role, user, body);
    }
    async function denied(sql, role = 'authenticated', user = a) {
      await expectDenied(db, sql, role, user);
    }
    await t.test('signup remains private and metadata cannot provision privileges', async () => {
      const seed = await db.query('SELECT onboarding_status FROM hocalist.profiles WHERE id=$1', [a]);
      assert.equal(seed.rows[0].onboarding_status, 'pending');
      const memberships = await db.query('SELECT count(*)::int AS n FROM hocalist.memberships WHERE user_id=$1', [outsider]);
      assert.equal(memberships.rows[0].n, 0);
      await denied('SELECT * FROM hocalist.profiles');
      await denied('SELECT * FROM auth.users');
    });
    await t.test('active owner reads self; guessed other IDs return no rows', async () => {
      await as('authenticated', a, async () => {
        const profiles = await db.query('SELECT display_name FROM hocalist.role_profiles');
        assert.deepEqual(profiles.rows, [{display_name:'A Buyer'}]);
        const contacts = await db.query('SELECT address_line1 FROM hocalist.profile_contacts');
        assert.deepEqual(contacts.rows, [{address_line1:'PRIVATE-A'}]);
        assert.equal((await db.query('SELECT * FROM hocalist.profile_contacts WHERE user_id=$1', [b])).rows.length, 0);
        assert.equal((await db.query('SELECT * FROM hocalist.memberships')).rows.length, 2);
      });
      await as('authenticated', b, async () => {
        assert.deepEqual((await db.query('SELECT display_name FROM hocalist.role_profiles')).rows, [{display_name:'B Seller'}]);
      });
    });
    await t.test('shared Auth identity without membership gets no private records', async () => {
      await as('authenticated', outsider, async () => {
        for (const table of ['memberships','role_profiles','profile_contacts']) {
          assert.equal((await db.query(`SELECT * FROM hocalist.${table}`)).rows.length, 0);
        }
      });
    });
    await t.test('pending, restricted and disabled memberships deny private reads', async () => {
      for (const status of ['pending','restricted','disabled']) {
        await db.query('UPDATE hocalist.memberships SET status=$1 WHERE id=$2', [status, ma]);
        await as('authenticated', a, async () => {
          assert.equal((await db.query('SELECT * FROM hocalist.role_profiles')).rows.length, 0);
          assert.equal((await db.query('SELECT * FROM hocalist.profile_contacts')).rows.length, 0);
          assert.equal((await db.query('SELECT * FROM hocalist.memberships')).rows.length, 2);
        });
      }
      await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1", [ma]);
    });
    await t.test('anonymous and missing identity deny access', async () => {
      await denied('SELECT * FROM hocalist.profile_contacts', 'anon', '');
      await as('authenticated', '', async () => {
        assert.equal((await db.query('SELECT * FROM hocalist.profile_contacts')).rows.length, 0);
      });
    });
    await t.test('all client insert/update/delete operations denied', async () => {
      for (const sql of [
        `INSERT INTO hocalist.memberships(user_id,role,status) VALUES ('${outsider}','buyer','active')`,
        `UPDATE hocalist.memberships SET status='active' WHERE id='${pending}'`,
        `UPDATE hocalist.memberships SET user_id='${b}' WHERE id='${ma}'`,
        'DELETE FROM hocalist.memberships',
        `INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES ('${pending}','Forged')`,
        "UPDATE hocalist.role_profiles SET display_name='Forged'",
        'DELETE FROM hocalist.role_profiles',
        `INSERT INTO hocalist.profile_contacts(user_id,phone) VALUES ('${outsider}','Forged')`,
        "UPDATE hocalist.profile_contacts SET phone='Forged'",
        'DELETE FROM hocalist.profile_contacts',
        'SELECT * FROM public.unrelated_business',
        'CREATE TABLE hocalist.client_created(id int)',
      ]) await denied(sql);
    });
    await t.test('constraints reject orphan, duplicate role and admin role', async () => {
      await assert.rejects(db.query("INSERT INTO hocalist.memberships(user_id,role) VALUES ($1,'buyer')", [a]), e=>e.code==='23505');
      await assert.rejects(db.query("INSERT INTO hocalist.memberships(user_id,role) VALUES ($1,'admin')", [outsider]), e=>e.code==='23514');
      await assert.rejects(db.query("INSERT INTO hocalist.role_profiles(membership_id,display_name) VALUES ($1,'Orphan')", [outsider]), e=>e.code==='23503');
    });
    await t.test('no new function privileges or modification of unrelated records', async () => {
      assert.equal((await db.query("SELECT has_function_privilege('authenticated', 'hocalist.handle_new_user()', 'EXECUTE') AS allowed")).rows[0].allowed, false);
      assert.equal((await db.query('SELECT count(*)::int AS n FROM public.unrelated_business')).rows[0].n, 1);
      assert.equal((await db.query("SELECT count(*)::int AS n FROM pg_class WHERE relnamespace='hocalist'::regnamespace AND relkind='r' AND NOT relrowsecurity")).rows[0].n, 0);
    });
    await db.exec(await loadSql('../drafts/004_account_commands.sql'));
    const command = (op,key,input) => db.query('SELECT hocalist.account_command($1,$2,$3::jsonb) AS result',[op,key,JSON.stringify(input)]);
    await t.test('onboarding grants ordinary role only, atomically and idempotently', async () => {
      await as('authenticated', outsider, async () => {
        const input={role:'buyer',display_name:'New Buyer'};
        const first=(await command('onboard','onboard-1',input)).rows[0].result;
        assert.deepEqual((await command('onboard','onboard-1',input)).rows[0].result,first);
        assert.equal((await db.query('SELECT * FROM hocalist.memberships')).rows.length,1);
        assert.equal((await db.query('SELECT * FROM hocalist.profile_contacts')).rows.length,1);
        assert.equal(first.role,'buyer');
      });
    });
    await t.test('mass assignment and idempotency payload replacement rejected', async () => {
      for(const input of [{role:'admin',display_name:'X'},{role:'buyer',display_name:'X',status:'active'},{role:'buyer',display_name:'X',verified:true}]) {
        await as('authenticated', outsider, async()=>assert.rejects(command('onboard','bad',input),e=>e.code==='22023'));
      }
      await as('authenticated', a, async()=>{
        const input={profile_id:ma,expected_revision:1,display_name:'Changed'};
        await command('profile.update','same-key',input);
        await assert.rejects(command('profile.update','same-key',{...input,display_name:'Different'}),e=>e.message.includes('idempotency_conflict'));
      });
    });
    await t.test('profile update clears nulls, preserves omitted fields and rejects stale revisions', async () => {
      await as('authenticated',a,async()=>{
        const input={profile_id:ma,expected_revision:1,display_name:'A Updated',area_label:'Area',profile_note:'Note'};
        assert.equal((await command('profile.update','p1',input)).rows[0].result.revision,2);
        assert.equal((await command('profile.update','p1',input)).rows[0].result.revision,2);
        await command('profile.update','p2',{profile_id:ma,expected_revision:2,display_name:'A Updated',profile_note:null});
        assert.deepEqual((await db.query('SELECT area_label,profile_note,revision FROM hocalist.role_profiles')).rows,[{area_label:'Area',profile_note:null,revision:3}]);
        await assert.rejects(command('profile.update','stale',input),e=>e.message.includes('revision_conflict'));
      });
    });
    await t.test('foreign profile, pending role and anonymous commands denied',async()=>{
      await as('authenticated',a,async()=>assert.rejects(command('profile.update','foreign',{profile_id:mb,expected_revision:1,display_name:'Intrusion'}),e=>e.code==='42501'));
      await as('authenticated',a,async()=>assert.rejects(command('profile.update','pending',{profile_id:pending,expected_revision:1,display_name:'Pending'}),e=>e.code==='42501'));
      await denied("SELECT hocalist.account_command('onboard','a','{}')",'anon','');
      await as('authenticated','',async()=>assert.rejects(command('onboard','empty',{role:'buyer',display_name:'X'}),e=>e.code==='42501'));
      await denied('SELECT * FROM hocalist.command_receipts');
    });
    await t.test('contact updates use own revision and never return private payload',async()=>{
      await as('authenticated',a,async()=>{
        const input={expected_revision:1,phone:null,city:'Synthetic City'};
        assert.deepEqual((await command('contact.update','c1',input)).rows[0].result,{revision:2});
        assert.deepEqual((await command('contact.update','c1',input)).rows[0].result,{revision:2});
        const row=(await db.query('SELECT phone,city,address_line1 FROM hocalist.profile_contacts')).rows[0];
        assert.deepEqual(row,{phone:null,city:'Synthetic City',address_line1:'PRIVATE-A'});
        await assert.rejects(command('contact.update','c2',{expected_revision:1,phone:'Stale'}),e=>e.message.includes('revision_conflict'));
      });
    });
    await t.test('restriction stops retry and new-role enrollment',async()=>{
      await db.query("UPDATE hocalist.memberships SET status='disabled' WHERE id=$1",[ma]);
      await as('authenticated',a,async()=>assert.rejects(command('onboard','newrole',{role:'seller',display_name:'Bypass'}),e=>e.code==='42501'));
      await as('authenticated',a,async()=>assert.rejects(command('contact.update','retry',{expected_revision:1,phone:'X'}),e=>e.code==='42501'));
      await db.query("UPDATE hocalist.memberships SET status='active' WHERE id=$1",[ma]);
    });
    await db.exec(await loadSql('../drafts/005_stripe_test_inbox.sql'));
    const receive=(id='evt_synthetic1',live=false,object='in_synthetic1')=>db.query(
      "SELECT hocalist.receive_stripe_test_event('acct_1Le6hqDmHEV44E5Y',$1,'invoice.paid',$2,1000,$3) AS inserted",[id,object,live]);
    await t.test('Stripe event receipt deduplicates and keeps processing pending',async()=>{
      await as('service_role','',async()=>{
        assert.equal((await receive()).rows[0].inserted,true);
        assert.equal((await receive()).rows[0].inserted,false);
        await assert.rejects(receive('evt_synthetic1',false,'in_different'),e=>e.message.includes('event_identity_conflict'));
      });
      // Rollback above ensures isolated fixtures; create one committed fixture.
      await receive('evt_persisted');
      assert.deepEqual((await db.query('SELECT status,livemode FROM hocalist.stripe_test_inbox')).rows,[{status:'pending',livemode:false}]);
    });
    await t.test('live events and client receipt injection are rejected',async()=>{
      await as('service_role','',async()=>assert.rejects(receive('evt_live',true),e=>e.code==='22023'));
      await as('authenticated',a,async()=>assert.rejects(receive('evt_inject'),e=>e.code==='42501'));
      await denied('SELECT * FROM hocalist.stripe_test_inbox');
      await denied("INSERT INTO hocalist.stripe_test_inbox(account_id,event_id,event_type,object_id,event_created,livemode) VALUES ('acct_1Le6hqDmHEV44E5Y','evt_forged','invoice.paid','in_fake',1000,false)");
    });
  } finally { await db.close(); }
});

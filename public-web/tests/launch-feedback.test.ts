import {test} from 'node:test';
import {strict as assert} from 'node:assert';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {downloadOptions} from '../app/lib/download-options';
import {validateWaitlistSubmission} from '../app/api/waitlist/waitlist';

test('downloads reject unsafe and unrelated destinations; absent platforms stay unavailable',()=>{
  assert.deepEqual(downloadOptions({}),{android:null,ios:null});
  assert.equal(downloadOptions({NEXT_PUBLIC_PLAY_STORE_URL:'https://evil.test/app'}).android,null);
  assert.equal(downloadOptions({HOCALIST_ANDROID_TEST_DOWNLOAD_URL:'http://hocalist.com/test.apk'}).android,null);
  assert.equal(downloadOptions({HOCALIST_IOS_TESTFLIGHT_URL:'https://testflight.apple.com/join/example'}).ios,'https://testflight.apple.com/join/example');
});
test('lead inputs are bounded and interest is explicit',()=>{
  assert.equal(validateWaitlistSubmission({email:'a@example.com',consent:true,lead:{name:'A',city:'City',interest:'both'}}).ok,true);
  assert.equal(validateWaitlistSubmission({email:'a@example.com',consent:true,lead:{name:'A',city:'City',interest:'admin'}}).ok,false);
});
test('launch migration preserves consent, rejects anonymous reads, deduplicates opens and checks report ownership',async()=>{
  const db=new PGlite();
  try {
    await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
      CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY);
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
      CREATE SCHEMA hocalist; GRANT USAGE ON SCHEMA hocalist TO anon,authenticated;
      CREATE TABLE hocalist.profiles(id uuid); CREATE TABLE hocalist.memberships(user_id uuid);
      CREATE TABLE hocalist.review_evidence_links(case_id uuid,media_id uuid);
      CREATE FUNCTION hocalist.marketplace_assert_admin(u uuid) RETURNS void LANGUAGE plpgsql AS $$BEGIN
        IF u IS DISTINCT FROM '00000000-0000-4000-8000-000000000001'::uuid THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501'; END IF; END$$;
      CREATE FUNCTION hocalist.support_assert_user() RETURNS uuid LANGUAGE plpgsql AS $$BEGIN
        IF auth.uid() IS NULL THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501'; END IF; RETURN auth.uid(); END$$;`);
    await db.exec(await readFile('../database/website_completion/170_website_waitlist.sql','utf8'));
    await db.exec(await readFile('../supabase/migrations/20261119092950_buyer_launch_feedback.sql','utf8'));
    const token='private-test-intake-token-0123456789';
    await db.query('select hocalist.website_waitlist_configure($1)',[token]);
    const join=()=>db.query(`select hocalist.website_waitlist_join('a@example.com','launch-updates-v1','download-page',$1,$2,'{"name":"Alice","city":"Chicago","interest":"both"}')`,['a'.repeat(64),token]);
    await join(); await join();
    const leads=await db.query<{name:string;count:number}>(`select name,count(*)::int as count from hocalist.website_waitlist_signups group by name`);
    assert.equal(leads.rows[0].count,1);assert.equal(leads.rows[0].name,'Alice');
    await db.exec('SET ROLE anon');
    await assert.rejects(db.query('select * from hocalist.website_waitlist_signups'));
    await assert.rejects(db.query('select * from hocalist.website_launch_events'));
    await assert.rejects(db.query('select hocalist.admin_launch_overview()'));
    await db.exec('RESET ROLE');
    await assert.rejects(db.query(`select hocalist.website_download_record(gen_random_uuid(),'android','download-page',$1,'wrong')`,['a'.repeat(64)]));
    await db.query(`select hocalist.website_download_record('00000000-0000-4000-8000-000000000005','android','download-page',$1,$2)`,['b'.repeat(64),token]);
    await db.exec(`INSERT INTO auth.users VALUES('00000000-0000-4000-8000-000000000001'); INSERT INTO hocalist.memberships SELECT id FROM auth.users;
      SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);`);
    await db.query(`select hocalist.launch_record_app_open('android')`);await db.query(`select hocalist.launch_record_app_open('android')`);
    const stats=await db.query<{data:{download_clicks:number;first_app_opens:number}}>('select hocalist.admin_launch_overview() as data');
    assert.equal(stats.rows[0].data.download_clicks,1);assert.equal(stats.rows[0].data.first_app_opens,1);
    await db.exec(`INSERT INTO hocalist.review_evidence_links VALUES('00000000-0000-4000-8000-000000000010','00000000-0000-4000-8000-000000000011')`);
    const linked=await db.query<{data:{reference_ok:boolean}}>(`select hocalist.admin_report_evidence_reference('00000000-0000-4000-8000-000000000010','00000000-0000-4000-8000-000000000011') as data`);
    assert.equal(linked.rows[0].data.reference_ok,true);
    const unrelated=await db.query<{data:{reference_ok:boolean}}>(`select hocalist.admin_report_evidence_reference('00000000-0000-4000-8000-000000000012','00000000-0000-4000-8000-000000000011') as data`);
    assert.equal(unrelated.rows[0].data.reference_ok,false);
    await db.exec(`SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false)`);
    await assert.rejects(db.query('select hocalist.admin_launch_overview()'));
    await assert.rejects(db.query("select hocalist.admin_support_evidence('00000000-0000-4000-8000-000000000010')"));
  } finally {await db.close();}
});

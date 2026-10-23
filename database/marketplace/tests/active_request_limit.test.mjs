import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createDisposableDb,applySignupSeed,applyStripeInbox,applyAccountDrafts} from '../../tests/fixture.mjs';
const A='00000000-0000-4000-8000-000000000001', B='00000000-0000-4000-8000-000000000002', ADM='00000000-0000-4000-8000-000000000003';
const read=path=>readFile(new URL(path,import.meta.url),'utf8');
async function asUser(db,user,sql,params=[],aal='aal2') {
 await db.exec('BEGIN; SET LOCAL ROLE authenticated');
 try {
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claims',$2,true)",[user,JSON.stringify({sub:user,aal})]);
  const rows=(await db.query(sql,params)).rows;await db.exec('COMMIT');return rows;
 } catch(error){await db.exec('ROLLBACK');throw error;}
}
const input={kind:'product',title:'Synthetic request',description:'Synthetic capacity check',condition:'used',quantity:1,use_home_address:false,address_line1:'Synthetic public meeting point',city:'Chicago',region:'IL',country_code:'US'};
const create=(db,user,key)=>asUser(db,user,'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS result',['request.create',key,JSON.stringify(input)]);
const setting=(db,limit=null,revision=null,key=null,user=ADM,aal='aal2')=>asUser(db,user,'SELECT hocalist.admin_request_posting_settings($1,$2,$3) AS result',[limit,revision,key],aal);

test('admin-managed active request capacity',async t=>{
 const db=await createDisposableDb();
 try {
  await applySignupSeed(db);await applyStripeInbox(db);await applyAccountDrafts(db);
  for(const path of ['../../provider-rollout/apply.sql','../../chat/010_chat_foundation.sql','../020_marketplace_foundation.sql','../021_request_coordinates.sql','../023_multi_negotiation.sql']) await db.exec(await read(path));
  await db.exec(`CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$; GRANT EXECUTE ON FUNCTION auth.jwt() TO authenticated;
   INSERT INTO auth.users(id,raw_user_meta_data) VALUES('${A}','{}'),('${B}','{}'),('${ADM}','{}');
   INSERT INTO hocalist.memberships(user_id,role,status) VALUES('${A}','buyer','active'),('${B}','buyer','active'),('${ADM}','seller','active');
   INSERT INTO hocalist.platform_admins(user_id) VALUES('${ADM}');`);
  const existing=[];
  for(let n=0;n<5;n++)existing.push((await create(db,A,`before-${n}`))[0].result.id);
  await db.exec(await read('../../runtime_repairs/225_buyer_active_request_limit.sql'));
  await t.test('default four preserves existing requests and blocks another',async()=>{
   assert.equal((await setting(db))[0].result.maximum_active_requests,4);
   assert.equal((await db.query('SELECT count(*)::int n FROM hocalist.requests WHERE buyer_user_id=$1 AND status=\'active\'',[A])).rows[0].n,5);
   await assert.rejects(create(db,A,'over-default'),/active_request_limit_reached:4/);
  });
  await t.test('editing existing request and replaying a create stay valid at cap',async()=>{
   await db.query("UPDATE hocalist.requests SET title='Edited synthetic request' WHERE id=$1",[existing[0]]);
   assert.equal((await create(db,A,'before-0'))[0].result.id,existing[0]);
  });
  await t.test('only open unexpired requests count and buyers are independent',async()=>{
   await db.query("UPDATE hocalist.requests SET status='closed' WHERE id=ANY($1::uuid[])",[existing.slice(0,2)]);
   await create(db,A,'fourth');
   await assert.rejects(create(db,A,'fifth'),/active_request_limit_reached:4/);
   await create(db,B,'other-buyer');
   await db.query("UPDATE hocalist.requests SET first_accepted_at=now()-interval '2 days',acceptance_expires_at=now()-interval '1 day' WHERE id=$1",[existing[2]]);
   await create(db,A,'after-expiry');
   await assert.rejects(db.query("UPDATE hocalist.requests SET acceptance_expires_at=now()+interval '1 day' WHERE id=$1",[existing[2]]),/active_request_limit_reached:4/);
   await assert.rejects(db.query("UPDATE hocalist.requests SET status='active' WHERE id=$1",[existing[0]]),/active_request_limit_reached:4/);
  });
  await t.test('admin save retries deduplicate and stale edits are rejected',async()=>{
   const saved=(await setting(db,6,1,'raise-limit'))[0].result;
   assert.equal(saved.maximum_active_requests,6);assert.equal(saved.revision,2);
   assert.deepEqual((await setting(db,6,1,'raise-limit'))[0].result,saved);
   await assert.rejects(setting(db,5,1,'raise-limit'),/idempotency_conflict/);
   await assert.rejects(setting(db,5,1,'stale'),/revision_conflict/);
   assert.equal((await db.query('SELECT count(*)::int n FROM hocalist.request_posting_settings_audit')).rows[0].n,1);
   await create(db,A,'raised-capacity');
   await setting(db,2,2,'lower-limit');
   await assert.rejects(create(db,A,'lowered-capacity'),/active_request_limit_reached:2/);
  });
  await t.test('invalid values, non-admin and non-MFA saves are rejected',async()=>{
   for(const limit of [0,-1,101])await assert.rejects(setting(db,limit,3,`invalid-${limit}`),/invalid_posting_limit/);
   await assert.rejects(setting(db,4,3,'buyer-change',A),{code:'42501'});
   await assert.rejects(setting(db,4,3,'no-mfa',ADM,'aal1'),/admin_mfa_required/);
   await assert.rejects(asUser(db,A,'SELECT * FROM hocalist.request_posting_settings'),{code:'42501'});
  });
 }finally{await db.close();}
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '../../../public-web/node_modules/@electric-sql/pglite/dist/index.js';
const migration = await readFile(new URL('../../runtime_repairs/216_admin_mfa_enforcement.sql', import.meta.url), 'utf8');
const admin = '00000000-0000-4000-8000-000000000001';
const other = '00000000-0000-4000-8000-000000000002';
async function fixture(verified) {
 const db = new PGlite();
 await db.exec(`CREATE SCHEMA hocalist; CREATE SCHEMA auth;
 CREATE TABLE hocalist.platform_admins(user_id uuid);
 CREATE TABLE hocalist.memberships(user_id uuid, status text);
 CREATE TABLE auth.mfa_factors(user_id uuid, status text);
 CREATE TABLE auth.users(id uuid,email_confirmed_at timestamptz,deleted_at timestamptz);
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
 CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT coalesce(nullif(current_setting('test.jwt',true),''),'{}')::jsonb $$;
 INSERT INTO hocalist.platform_admins VALUES ('${admin}');`);
 if(verified) await db.exec(`INSERT INTO auth.mfa_factors VALUES ('${admin}','verified');`);
 await db.exec(`INSERT INTO auth.users VALUES ('${admin}',now(),null);`);
 if(verified) await db.exec(`CREATE FUNCTION hocalist.admin_mfa_enrollment_eligible() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;`);
 return db;
}
test('MFA activation refuses a missing bootstrap enrolment path', async () => {
 const db=await fixture(false);
 await assert.rejects(db.exec(migration), /admin_mfa_bootstrap_required/);
 await db.exec('ROLLBACK'); await db.close();
});
test('admin RPC guard requires own identity, AAL2 and unrestricted membership', async () => {
 const db=await fixture(true); await db.exec(migration);
 async function allowed(uid, aal, target=admin) {
  await db.query("SELECT set_config('test.uid',$1,false),set_config('test.jwt',$2,false)",[uid,JSON.stringify({aal})]);
  return (await db.query('SELECT hocalist.marketplace_is_admin($1::uuid) AS allowed',[target])).rows[0].allowed;
 }
 assert.equal(await allowed(admin,'aal1'),false);
 assert.equal(await allowed(admin,'aal2'),true);
 assert.equal(await allowed(other,'aal2'),false);
 assert.equal(await allowed(admin,'aal2',other),false);
 await db.exec(`INSERT INTO hocalist.memberships VALUES ('${admin}','restricted');`);
 assert.equal(await allowed(admin,'aal2'),false);
 await db.close();
});

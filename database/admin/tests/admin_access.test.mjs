import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '../../../public-web/node_modules/@electric-sql/pglite/dist/index.js';
const migration=await readFile(new URL('../../runtime_repairs/218_admin_access_management.sql',import.meta.url),'utf8');
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
async function fixture(){
 const db=new PGlite();
 await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
 CREATE SCHEMA hocalist; CREATE SCHEMA auth;
 CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,email_confirmed_at timestamptz,deleted_at timestamptz);
 CREATE TABLE auth.mfa_factors(user_id uuid,status text);
 CREATE TABLE hocalist.profiles(id uuid PRIMARY KEY);
 CREATE TABLE hocalist.memberships(user_id uuid,status text);
 CREATE TABLE hocalist.platform_admins(user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id),granted_by uuid,granted_at timestamptz DEFAULT now());
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
 CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT coalesce(nullif(current_setting('test.jwt',true),''),'{}')::jsonb $$;
 CREATE FUNCTION hocalist.marketplace_assert_admin(p_user uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM hocalist.platform_admins WHERE user_id=p_user) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF; END $$;
 GRANT USAGE ON SCHEMA hocalist,auth TO authenticated,anon;
 `);
 for(let n=1;n<=7;n++){
  await db.query('INSERT INTO auth.users VALUES($1,$2,$3,null)',[id(n),'admin'+n+'@example.test',n===6?null:new Date().toISOString()]);
  if(n!==7)await db.query('INSERT INTO hocalist.profiles VALUES($1)',[id(n)]);
 }
 for(const n of [1,2,3])await db.query('INSERT INTO hocalist.platform_admins(user_id) VALUES($1)',[id(n)]);
 await db.exec(migration);
 for(const n of [1,2])await db.query('INSERT INTO hocalist.admin_access_managers(user_id) VALUES($1)',[id(n)]);
 async function actor(n,aal='aal2'){await db.query("SELECT set_config('test.uid',$1,false),set_config('test.jwt',$2,false)",[id(n),JSON.stringify({aal})]);}
 async function command(action,n,key=100){return db.query('SELECT hocalist.admin_access_command($1,$2,$3::uuid)',[action,'admin'+n+'@example.test',id(key)]);}
 return {db,actor,command};
}
async function scenario(fn){const f=await fixture();try{await fn(f);}finally{await f.db.close();}}
test('outsiders and password-only managers cannot view or change access',()=>scenario(async({db,actor,command})=>{
 await actor(4);await assert.rejects(db.query('SELECT hocalist.admin_access_list()'),/admin_required/);
 await actor(1,'aal1');await assert.rejects(db.query('SELECT hocalist.admin_access_list()'),/admin_mfa_required/);await assert.rejects(command('grant',4),/admin_access_manager_required/);
}));
test('regular administrators cannot grant another administrator',()=>scenario(async({db,actor,command})=>{
 await actor(3);assert.equal((await db.query('SELECT hocalist.admin_access_list() AS v')).rows[0].v.can_manage,false);await assert.rejects(command('grant',4),/admin_access_manager_required/);
}));
test('verified grant is atomic, audited, idempotent and rejects retry reuse',()=>scenario(async({db,actor,command})=>{
 await actor(1);await command('grant',4);await command('grant',4);
 assert.equal((await db.query('SELECT count(*) AS n FROM hocalist.admin_access_audit')).rows[0].n,1);
 assert.equal((await db.query('SELECT count(*) AS n FROM hocalist.platform_admins WHERE user_id=$1',[id(4)])).rows[0].n,1);
 await assert.rejects(command('grant',5),/admin_access_retry_conflict/);
}));
test('unverified, missing-profile and restricted accounts cannot be added',()=>scenario(async({db,actor,command})=>{
 await actor(1);await assert.rejects(command('grant',6),/verified_hocalist_account_required/);await assert.rejects(command('grant',7),/verified_hocalist_account_required/);
 await db.query("INSERT INTO hocalist.memberships VALUES($1,'restricted')",[id(4)]);await assert.rejects(command('grant',4),/account_restricted/);
}));
test('managers and self are protected while regular removal is immediate',()=>scenario(async({db,actor,command})=>{
 await actor(1);await assert.rejects(command('revoke',1),/protected_administrator/);await assert.rejects(command('revoke',2),/protected_administrator/);await command('revoke',3);
 await actor(3);await assert.rejects(db.query('SELECT hocalist.admin_access_list()'),/admin_required/);
}));
test('bootstrap eligibility exposes own status without granting privileged access',()=>scenario(async({db,actor})=>{
 await actor(1,'aal1');assert.equal((await db.query('SELECT hocalist.admin_mfa_enrollment_eligible() AS v')).rows[0].v,true);
 await actor(4,'aal1');assert.equal((await db.query('SELECT hocalist.admin_mfa_enrollment_eligible() AS v')).rows[0].v,false);
}));
test('anonymous RPC and authenticated direct table writes are denied',()=>scenario(async({db,actor})=>{
 await actor(1);await db.exec('SET ROLE anon');await assert.rejects(db.query('SELECT hocalist.admin_access_list()'),/permission denied/);
 await db.exec('RESET ROLE; SET ROLE authenticated');await assert.rejects(db.query('INSERT INTO hocalist.admin_access_managers VALUES($1,now())',[id(4)]),/permission denied/);
 await db.exec('RESET ROLE');
}));

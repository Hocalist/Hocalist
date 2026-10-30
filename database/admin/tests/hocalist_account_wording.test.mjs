import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '../../../public-web/node_modules/@electric-sql/pglite/dist/index.js';
const sql=await readFile(new URL('../../runtime_repairs/217_hocalist_account_wording.sql',import.meta.url),'utf8');
test('wording repair is idempotent and preserves Hocalist-only scope and definer boundaries',async()=>{
 const db=new PGlite(); await db.exec(`CREATE SCHEMA hocalist;
 CREATE FUNCTION hocalist.account_export_build(uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT jsonb_build_object('schema_scope','hocalist','shared_identity_note','This export contains Hocalist records only. Shared Supabase Auth credentials and Postaneur records are not included.') $$;
 CREATE FUNCTION hocalist.account_lifecycle_status() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT jsonb_build_object('deletion_scope_note','Deletion requests cover Hocalist records only. Shared Supabase Auth identity, Postaneur records and legal evidence are not deleted here.') $$;`);
 await db.exec(sql); await db.exec(sql);
 const exportRow=(await db.query("SELECT hocalist.account_export_build(null) AS value")).rows[0].value;
 const status=(await db.query('SELECT hocalist.account_lifecycle_status() AS value')).rows[0].value;
 assert.equal(exportRow.schema_scope,'hocalist'); assert.ok(!JSON.stringify([exportRow,status]).toLowerCase().includes('postaneur'));
 const funcs=(await db.query("SELECT prosecdef,proconfig FROM pg_proc WHERE pronamespace='hocalist'::regnamespace")).rows;
 assert.ok(funcs.every(f=>f.prosecdef && f.proconfig.includes('search_path=""')));
 await db.close();
});

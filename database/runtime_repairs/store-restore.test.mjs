import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createAccountCompletionDb,callAs} from '../account_completion/tests/fixture.mjs';
const owner='00000000-0000-4000-8000-00000000000b',buyer='00000000-0000-4000-8000-00000000000a';
test('Store restore preserves ownership, private draft and capacity',async t=>{
 const db=await createAccountCompletionDb();try{
 const sql=await readFile(new URL('./273_store_restore.sql',import.meta.url),'utf8'); await db.exec(sql);
 const row=(await db.query(`INSERT INTO hocalist.store_listings(seller_user_id,seller_profile_id,kind,title,price_label,description,status,moderation_status) VALUES($1,'10000000-0000-4000-8000-00000000000b','product','TEST archive','15','Keep original description','archived','approved') RETURNING id,revision`,[owner])).rows[0];
 const restore=async(user=owner,revision=row.revision,key='restore-1',role='authenticated')=>(await callAs(db,role,user,'SELECT hocalist.marketplace_restore_store_listing($1,$2,$3) AS d',[row.id,revision,key]))[0].d;
 await t.test('buyer and anonymous denied',async()=>{await assert.rejects(restore(buyer));await assert.rejects(restore(owner,row.revision,'a','anon'),{code:'42501'});});
 await t.test('seller cannot restore another account listing',async()=>{await db.query('UPDATE hocalist.store_listings SET seller_user_id=$1 WHERE id=$2',[buyer,row.id]);await assert.rejects(restore(),/listing_not_found/);await db.query('UPDATE hocalist.store_listings SET seller_user_id=$1 WHERE id=$2',[owner,row.id]);});
 await t.test('stale revision cannot restore',async()=>assert.rejects(restore(owner,row.revision+1,'stale'),{code:'40001'}));
 await t.test('restores original record privately with content unchanged',async()=>{const r=await restore();assert.equal(r.id,row.id);assert.equal(r.status,'draft');assert.equal(r.description,'Keep original description');assert.equal(r.moderation_status,'approved');const state=(await db.query('SELECT revision,published_at FROM hocalist.store_listings WHERE id=$1',[row.id])).rows[0];assert.equal(state.revision,row.revision+1);assert.equal(state.published_at,null);});
 await t.test('same retry replays without extra revision; different intent rejected',async()=>{assert.equal((await restore()).id,row.id);await assert.rejects(restore(owner,row.revision+1),/idempotency_conflict/);assert.equal((await db.query('SELECT revision FROM hocalist.store_listings WHERE id=$1',[row.id])).rows[0].revision,row.revision+1);});
 await t.test('non-archived cannot restore again',async()=>assert.rejects(restore(owner,row.revision+1,'new-key'),/invalid_transition/));
 await t.test('full store leaves archived record untouched',async()=>{await db.query("UPDATE hocalist.store_listings SET status='archived' WHERE id=$1",[row.id]);await db.exec('CREATE OR REPLACE FUNCTION hocalist.marketplace_store_limit(p_user uuid) RETURNS integer LANGUAGE sql STABLE AS $$SELECT 0$$');await assert.rejects(restore(owner,row.revision+1,'limit'),/store_limit_exceeded/);assert.equal((await db.query('SELECT status FROM hocalist.store_listings WHERE id=$1',[row.id])).rows[0].status,'archived');});
 await t.test('reapplication is safe',async()=>{await db.exec(sql);assert.equal((await restore()).id,row.id);});
 }finally{await db.close()}
});


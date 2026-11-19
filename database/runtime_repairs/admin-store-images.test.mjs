import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createAccountCompletionDb,callAs} from '../account_completion/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const owner='00000000-0000-4000-8000-00000000000b',buyer='00000000-0000-4000-8000-00000000000a',admin='00000000-0000-4000-8000-00000000000e';
test('Store review photos preserve admin, MFA and exact listing access',async t=>{
 const db=await createAccountCompletionDb();try{
 await db.exec(`ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz; ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
 CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
 CREATE FUNCTION hocalist.admin_mfa_enrollment_eligible() RETURNS boolean LANGUAGE sql AS $$SELECT false$$;
 INSERT INTO auth.users(id,email_confirmed_at) VALUES('${admin}',now()); INSERT INTO hocalist.platform_admins(user_id) VALUES('${admin}');`);
 await db.exec(await read('./216_admin_mfa_enforcement.sql'));
 const media=(await db.query("INSERT INTO hocalist.media_images(owner_user_id,intent_key,purpose,content_hash,state) VALUES($1,gen_random_uuid(),'store',repeat('a',64),'ready') RETURNING id",[owner])).rows[0].id;
 const listing=(await db.query("INSERT INTO hocalist.store_listings(seller_user_id,seller_profile_id,kind,title,price_label,image_media_ids) VALUES($1,'10000000-0000-4000-8000-00000000000b','product','TEST ONLY','15',$2::jsonb) RETURNING id",[owner,JSON.stringify([media])])).rows[0].id;
 const repair=await read('./272_admin_store_images.sql');await db.exec(repair);
 async function request(user=admin,aal='aal2',lid=listing,mid=media,role='authenticated'){
 await db.query("SELECT set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,aal,role})]);
 return (await callAs(db,role,user,'SELECT hocalist.admin_store_image($1,$2) AS d',[lid,mid]))[0].d;}
 await t.test('admitted admin reads pending exact listing image',async()=>assert.equal((await request()).id,media));
 await t.test('owner buyer weak MFA anonymous service role denied',async()=>{for(const args of [[owner],[buyer],[admin,'aal1'],[admin,'aal2',listing,media,'anon'],[admin,'aal2',listing,media,'service_role']])await assert.rejects(request(...args),{code:'42501'});});
 await t.test('unrelated image and listing denied',async()=>{await assert.rejects(request(admin,'aal2',crypto.randomUUID()),{code:'P0002'});await assert.rejects(request(admin,'aal2',listing,crypto.randomUUID()),{code:'P0002'});});
 await t.test('completed review and archived listing denied',async()=>{await db.query("UPDATE hocalist.store_listings SET moderation_status='approved' WHERE id=$1",[listing]);await assert.rejects(request(),{code:'P0002'});await db.query("UPDATE hocalist.store_listings SET moderation_status='pending_review',status='archived' WHERE id=$1",[listing]);await assert.rejects(request(),{code:'P0002'});await db.query("UPDATE hocalist.store_listings SET status='draft' WHERE id=$1",[listing]);});
 await t.test('reapply safe and revoked admin denied',async()=>{await db.exec(repair);assert.equal((await request()).id,media);await db.query('DELETE FROM hocalist.platform_admins WHERE user_id=$1',[admin]);await assert.rejects(request(),{code:'42501'});});
 }finally{await db.close()}
});

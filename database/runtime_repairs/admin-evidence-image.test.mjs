import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createAccountCompletionDb,callAs} from '../account_completion/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const owner='00000000-0000-4000-8000-00000000000b',buyer='00000000-0000-4000-8000-00000000000a',admin='00000000-0000-4000-8000-00000000000e';
test('private evidence preserves administrator identity and MFA',async t=>{
 const db=await createAccountCompletionDb();
 try{
  await db.exec(await read('../admin_completion/161_admin_review_queue.sql'));
  await db.exec(`ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz; ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
   CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
   CREATE FUNCTION hocalist.admin_mfa_enrollment_eligible() RETURNS boolean LANGUAGE sql AS $$SELECT false$$;
   INSERT INTO auth.users(id,email_confirmed_at) VALUES('${admin}',now()); INSERT INTO hocalist.platform_admins(user_id) VALUES('${admin}');`);
  await db.exec(await read('./216_admin_mfa_enforcement.sql'));
  const media=(await db.query("INSERT INTO hocalist.media_images(owner_user_id,intent_key,purpose,content_hash,state) VALUES($1,gen_random_uuid(),'review',repeat('a',64),'ready') RETURNING id",[owner])).rows[0].id;
  const submission=(await db.query("INSERT INTO hocalist.verification_submissions(user_id,kind,note,evidence_media_ids) VALUES($1,'business','TEST ONLY private evidence',$2::jsonb) RETURNING id",[owner,JSON.stringify([media])])).rows[0].id;
  await db.query('INSERT INTO hocalist.review_evidence_links(media_id,submission_id,attached_by) VALUES($1,$2,$3)',[media,submission,owner]);
  const repair=await read('./252_admin_evidence_image.sql');await db.exec(repair);
  const request=async(user,aal='aal2',sid=submission,mid=media,role='authenticated')=>{
   await db.query("SELECT set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,aal,role})]);
   return (await callAs(db,role,user,'SELECT hocalist.admin_evidence_image($1,$2) AS d',[sid,mid]))[0].d;
  };
  await t.test('admin without buyer or seller membership can read an attached ready image',async()=>{
   assert.deepEqual(await request(admin),{id:media,owner_user_id:owner,state:'ready'});
  });
  await t.test('ordinary owner, buyer, anonymous, service role and weaker MFA are denied',async()=>{
   for(const args of [[owner],[buyer],[admin,'aal1'],[admin,'aal2',submission,media,'anon'],[admin,'aal2',submission,media,'service_role']]) await assert.rejects(request(...args),{code:'42501'});
  });
  await t.test('wrong reference, unready image and detached evidence are denied',async()=>{
   await assert.rejects(request(admin,'aal2',submission,crypto.randomUUID()),{code:'P0002'});
   await db.query("UPDATE hocalist.media_images SET state='pending' WHERE id=$1",[media]);
   await assert.rejects(request(admin),{code:'P0002'});
   await db.query("UPDATE hocalist.media_images SET state='ready' WHERE id=$1",[media]);
   await db.query('DELETE FROM hocalist.review_evidence_links WHERE media_id=$1',[media]);
   await assert.rejects(request(admin),{code:'P0002'});
   await db.query('INSERT INTO hocalist.review_evidence_links(media_id,submission_id,attached_by) VALUES($1,$2,$3)',[media,submission,owner]);
  });
  await t.test('repeat application preserves evidence and revoked admins lose access',async()=>{
   await db.exec(repair);assert.equal((await request(admin)).id,media);
   await db.query('DELETE FROM hocalist.platform_admins WHERE user_id=$1',[admin]);
   await assert.rejects(request(admin),{code:'42501'});
  });
 }finally{await db.close();}
});

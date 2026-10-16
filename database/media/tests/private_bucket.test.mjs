import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {setup,A,callAs} from '../../outcomes/tests/fixture.mjs';
test('private image bucket denies direct clients even with legacy broad storage policies',async()=>{
 const db=await setup();try{
  await db.exec(`CREATE SCHEMA storage;CREATE TABLE storage.buckets(id text PRIMARY KEY,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
   CREATE TABLE storage.objects(id uuid DEFAULT gen_random_uuid(),bucket_id text,name text);
   ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
   GRANT USAGE ON SCHEMA storage TO anon,authenticated;GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO anon,authenticated;
   CREATE POLICY legacy_broad ON storage.objects FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
   CREATE TABLE hocalist.media_images(id uuid);
   INSERT INTO storage.buckets VALUES('existing','existing',false,NULL,NULL);
   INSERT INTO storage.objects(bucket_id,name) VALUES('existing','preserved');`);
  const sql=await readFile(new URL('../private_bucket.sql',import.meta.url),'utf8');await db.exec(sql);
  await db.exec("INSERT INTO storage.objects(bucket_id,name) VALUES('hocalist-images','private')");
  for(const role of ['anon','authenticated']){
   const rows=await callAs(db,role,A,'SELECT name FROM storage.objects');assert.deepEqual(rows.map(x=>x.name),['preserved']);
   await assert.rejects(callAs(db,role,A,"INSERT INTO storage.objects(bucket_id,name) VALUES('hocalist-images','forged')"),/row-level security/);
  }
  await assert.rejects(db.exec(sql),/bucket already exists/);await db.exec('ROLLBACK');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM storage.objects')).rows[0].n,2);
 }finally{await db.close();}
});

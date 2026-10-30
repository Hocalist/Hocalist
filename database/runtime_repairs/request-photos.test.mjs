import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,C,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('private request photos preserve request eligibility and atomic receipts',async t=>{
 const db=await setup(false);
 const rpc=async(user,sql,args)=>(await callAs(db,'authenticated',user,sql,args))[0].d;
 const command=(user,op,key,input)=>rpc(user,'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS d',[op,key,JSON.stringify(input)]);
 try {
  for(const p of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql','../outcomes/080_sale_confirmation.sql','./192_confirmed_meeting_coordinates.sql']) await db.exec(await read(p));
  const audit=await read('../audit_repairs/200_audit_reads.sql');
  await db.exec(audit.match(/DO \$metadata\$[\s\S]*?END \$metadata\$;/)[0]);
  const discovery=await read('../discovery_completion/140_discovery_leads.sql');
  await db.exec(discovery.match(/CREATE FUNCTION hocalist.discovery_lead_json\([\s\S]*?\$\$;/)[0]);
  await db.exec(await read('./request-timezone-browser.sql'));
  await db.exec(await read('../media/100_private_images.sql'));
  const media=await read('../account_completion/132_review_evidence.sql');
  await db.exec(media.match(/CREATE OR REPLACE FUNCTION hocalist.media_gateway\([\s\S]*?END \$\$;/)[0]);
  await db.exec(await read('./213_request_photos.sql'));
  const photo='bbbbbbbb-0000-4000-8000-000000000001';
  const foreign='bbbbbbbb-0000-4000-8000-000000000002';
  await db.query(`INSERT INTO hocalist.media_images(id,owner_user_id,intent_key,purpose,state,content_hash)
   VALUES($1,$2,$1,'request','ready',repeat('a',64)),($3,$4,$3,'request','ready',repeat('b',64))`,[photo,A,foreign,C]);
  const input={kind:'product',title:'Synthetic photo request',description:'Synthetic only',condition:'used',quantity:1,use_home_address:false,city:'Chicago',country_code:'US',image_media_ids:[photo]};
  const request=await command(A,'request.create','photo-create',input);
  await t.test('owner, eligible seller and discovery receive IDs; replay is unchanged',async()=>{
   assert.deepEqual(request.image_media_ids,[photo]);
   assert.deepEqual(await command(A,'request.create','photo-create',input),request);
   for(const sql of ['SELECT hocalist.marketplace_request($1) AS d','SELECT hocalist.discovery_lead_json($1) AS d'])
    assert.deepEqual((await rpc(B,sql,[request.id])).image_media_ids,[photo]);
  });
  await t.test('foreign references and duplicates roll back',async()=>{
   await assert.rejects(command(A,'request.create','foreign-photo',{...input,image_media_ids:[foreign]}),/invalid_media_reference/);
   await assert.rejects(command(A,'request.create','duplicate-photo',{...input,image_media_ids:[photo,photo]}),/duplicate_request_photo/);
  });
  await t.test('gateway permits eligible sellers but blocks inactive requests and anonymous calls',async()=>{
   const gateway=async user=>(await db.query(`SELECT hocalist.media_gateway($1,'read',jsonb_build_object('id',$2::text)) AS d`,[user,photo])).rows[0].d;
   assert.equal((await gateway(B)).id,photo);
   await assert.rejects(callAs(db,'anon',null,`SELECT hocalist.media_read_request($1,$2)`,[B,photo]),/permission denied/);
   await db.query(`UPDATE hocalist.requests SET status='closed' WHERE id=$1`,[request.id]);
   await assert.rejects(gateway(B),/media_access_denied/);
   assert.equal((await gateway(A)).id,photo);
   await db.query(`UPDATE hocalist.requests SET status='active' WHERE id=$1`,[request.id]);
  });
  await t.test('request upload requires buyer membership and restricted sellers cannot read',async()=>{
   const key='bbbbbbbb-0000-4000-8000-000000000003';
   const begin=user=>db.query(`SELECT hocalist.media_gateway($1,'begin',jsonb_build_object('key',$2::text,'purpose','request','hash',repeat('c',64))) AS d`,[user,key]);
   await assert.rejects(begin(B),/role|access/i);
   assert.equal((await begin(A)).rows[0].d.state,'pending');
   await db.query(`UPDATE hocalist.memberships SET status='restricted' WHERE user_id=$1`,[B]);
   await assert.rejects(db.query(`SELECT hocalist.media_gateway($1,'read',jsonb_build_object('id',$2::text))`,[B,photo]),/media_access_denied/);
   await db.query(`UPDATE hocalist.memberships SET status='active' WHERE user_id=$1`,[B]);
   const before=(await db.query(`SELECT current_setting('request.jwt.claim.sub',true) AS subject`)).rows[0].subject;
   await db.query(`SELECT hocalist.media_gateway($1,'read',jsonb_build_object('id',$2::text))`,[B,photo]);
   assert.equal((await db.query(`SELECT current_setting('request.jwt.claim.sub',true) AS subject`)).rows[0].subject,before);
  });
  await t.test('legacy edit preserves photos and explicit empty removes seller access',async()=>{
   const {image_media_ids,...legacy}=input;
   const updated=await command(A,'request.update','legacy-edit',{...legacy,request_id:request.id,expected_revision:request.revision});
   assert.deepEqual(updated.image_media_ids,[photo]);
   const removed=await command(A,'request.update','remove-photo',{...input,image_media_ids:[],request_id:request.id,expected_revision:updated.revision});
   assert.deepEqual(removed.image_media_ids,[]);
   await assert.rejects(db.query(`SELECT hocalist.media_gateway($1,'read',jsonb_build_object('id',$2::text))`,[B,photo]),/media_access_denied/);
  });
 }finally{await db.close();}
});

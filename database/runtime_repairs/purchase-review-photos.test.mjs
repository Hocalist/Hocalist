import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,C,acceptedDeal,schedule,propose,respond,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('purchase review photos preserve eligibility, receipts and private media access',async t=>{
 const db=await setup();
 try {
  const discovery=await read('../discovery_completion/140_discovery_leads.sql');
  await db.exec(discovery.match(/CREATE FUNCTION hocalist.discovery_assert_active_member\([\s\S]*?END \$\$;/)[0]);
  await db.exec(await read('../discovery_completion/142_reviews.sql'));
  await db.exec(await read('../media/100_private_images.sql'));
  const media=await read('../account_completion/132_review_evidence.sql');
  await db.exec(media.match(/CREATE OR REPLACE FUNCTION hocalist.media_gateway\([\s\S]*?END \$\$;/)[0].replace("'chat','review','report')","'chat','review','report','request')"));
  await db.exec(`CREATE FUNCTION hocalist.media_referenced(p_image uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN RETURN false; END $$;`);
  await db.exec(await read('./214_purchase_review_photos.sql'));
  const deal=await acceptedDeal(db);
  const pending=(await propose(db,A,deal.conversationId,schedule(),'photo-proposal'))[0].data;
  const meeting=(await respond(db,B,pending.id,true,pending.revision,'photo-accept'))[0].data;
  await db.query("UPDATE hocalist.meetings SET meeting_expires_at=now()+interval '1 day' WHERE id=$1",[meeting.id]);
  const pin=async(user,action,value=null)=>(await callAs(db,'authenticated',user,'SELECT hocalist.sale_pin($1,$2,$3) AS d',[meeting.id,action,value]))[0].d;
  await pin(B,'verify',(await pin(A,'display')).pin);
  const photo='bbbbbbbb-0000-4000-8000-000000000001';
  const other='bbbbbbbb-0000-4000-8000-000000000002';
  const evidence='bbbbbbbb-0000-4000-8000-000000000003';
  for(const [id,owner,purpose] of [[photo,A,'purchase_review'],[other,C,'purchase_review'],[evidence,A,'review']])
   await db.query(`INSERT INTO hocalist.media_images(id,owner_user_id,intent_key,purpose,state,content_hash) VALUES($1,$2,$1,$3,'ready',repeat('a',64))`,[id,owner,purpose]);
  const rpc=async(user,fn,params)=>(await callAs(db,'authenticated',user,`SELECT hocalist.${fn} AS d`,params))[0].d;
  const submit=(key,input,user=A)=>rpc(user,'review_submit($1,$2::jsonb)',[key,JSON.stringify(input)]);
  const input={request_id:deal.requestId,rating:5,body:'Controlled fixture',image_media_ids:[photo]};
  await t.test('rejects foreign, verification evidence, duplicate and oversized attachments',async()=>{
   let attempt=0;
   for(const ids of [[other],[evidence],[photo,photo],[photo,other,evidence,photo,other]])
    await assert.rejects(submit('invalid-'+attempt++,{...input,image_media_ids:ids}),/media_reference|review_photo|check constraint/);
   await assert.rejects(submit('wrong-buyer',input,B),/role|eligible/);
  });
  let saved;
  await t.test('stores photos atomically and unchanged retry returns original receipt',async()=>{
   saved=await submit('photos',input);
   assert.deepEqual(saved.image_media_ids,[photo]);
   assert.equal((await db.query('SELECT hocalist.media_referenced($1) AS linked',[photo])).rows[0].linked,true);
   assert.deepEqual(await submit('photos',input),saved);
   await assert.rejects(submit('photos',{...input,image_media_ids:[]}),/idempotency_conflict/);
  });
  await t.test('published photos read through gateway; removal revokes other-user access',async()=>{
   const gateway=()=>db.query("SELECT hocalist.media_gateway($1,'read',jsonb_build_object('id',$2::text)) AS d",[B,photo]);
   assert.equal((await gateway()).rows[0].d.id,photo);
   const reputation=await rpc(B,'seller_public_reputation($1)',[(await db.query("SELECT id FROM hocalist.memberships WHERE user_id=$1 AND role='seller'",[B])).rows[0].id]);
   assert.deepEqual(reputation.reviews[0].image_media_ids,[photo]);
   const updated=await rpc(A,'review_update($1,$2::jsonb)',['remove',JSON.stringify({review_id:saved.id,expected_revision:saved.revision,rating:5,body:'Controlled fixture',image_media_ids:[]})]);
   assert.deepEqual(updated.image_media_ids,[]);
   assert.equal((await db.query('SELECT hocalist.media_referenced($1) AS linked',[photo])).rows[0].linked,false);
   await assert.rejects(gateway(),/media_access_denied/);
  });
 } finally {await db.close();}
});
